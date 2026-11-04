"""PC-only presentation of optional, versioned board telemetry and review receipts."""
from collections import deque
import json
import math
import time

SCHEMA = '30tai-performance-1'
STALE_SECONDS = 5
MAX_REVIEWS = 64


def number(value, minimum=0, maximum=None):
    if type(value) not in (int, float) or not math.isfinite(value) or value < minimum:
        return None
    if maximum is not None and value > maximum:
        return None
    return value


class PerformanceWindow:
    def __init__(self):
        self.session = None
        self.samples = deque(maxlen=120)
        self.received_at = None
        self.frame_changed_at = None
        self.invalid = False

    def ingest(self, telemetry, now=None):
        now = time.time() if now is None else now
        session = telemetry.get('session')
        if session != self.session:
            self.session = session
            self.samples.clear()
            self.received_at = self.frame_changed_at = None
            self.invalid = False
        raw = telemetry.get('performance')
        if not isinstance(raw, dict):
            return
        required = ('sample_seq', 'sample_monotonic_s', 'frame_count', 'elapsed_s')
        if (raw.get('schema_version') != SCHEMA or not session or raw.get('session') != session
                or any(number(raw.get(k)) is None for k in required)
                or type(raw['sample_seq']) is not int or type(raw['frame_count']) is not int):
            self.invalid = True
            return
        last = self.samples[-1] if self.samples else None
        if last and raw['sample_seq'] == last['sample_seq']:
            # Repeated heartbeats carrying an old sample do not refresh it.
            return
        if last and (raw['sample_seq'] < last['sample_seq']
                     or raw['sample_monotonic_s'] <= last['sample_monotonic_s']
                     or raw['frame_count'] < last['frame_count']
                     or raw['elapsed_s'] < last['elapsed_s']):
            self.invalid = True
            return
        self.invalid = False
        sample = {k: raw[k] for k in required}
        sample['sample_age_ms'] = number(raw.get('sample_age_ms')) or 0
        for key in ('detections', 'post_callback_ms', 'roi_draw_ms', 'npu_forward_ms',
                    'capture_ms', 'memory_used_mb', 'memory_total_mb', 'runtime_rss_mb'):
            sample[key] = number(raw.get(key))
        sample['cpu_percent'] = number(raw.get('cpu_percent'), maximum=100)
        sample['qwen_mode'] = raw.get('qwen_mode') if raw.get('qwen_mode') in ('off', 'mock', 'remote') else None
        if last is None or sample['frame_count'] != last['frame_count']:
            self.frame_changed_at = now
        self.samples.append(sample)
        self.received_at = now

    def snapshot(self, online, now=None):
        now = time.time() if now is None else now
        if not self.samples:
            return {'state': 'invalid' if self.invalid else 'awaiting', 'session': self.session,
                    'metrics': {}, 'history': [], 'sample_age_s': None, 'frame_age_s': None}
        last = self.samples[-1]
        age = max(0, now - self.received_at) + last['sample_age_ms'] / 1000
        status = 'invalid' if self.invalid else ('fresh' if online and age <= STALE_SECONDS else 'stale')
        anchors = [s for s in self.samples if 0 < last['sample_monotonic_s'] - s['sample_monotonic_s'] <= 3.5]
        fps = None
        if anchors:
            first = anchors[0]
            span = last['sample_monotonic_s'] - first['sample_monotonic_s']
            if span >= .5:
                fps = (last['frame_count'] - first['frame_count']) / span
        cumulative = ((last['frame_count'] - 1) / last['elapsed_s']
                      if last['frame_count'] > 1 and last['elapsed_s'] > 0 else None)
        metrics = dict(last, fps_window=fps, fps_cumulative=cumulative)
        history = []
        for a, b in zip(list(self.samples), list(self.samples)[1:]):
            history.append({'sample_monotonic_s': b['sample_monotonic_s'],
                            'fps': (b['frame_count'] - a['frame_count']) /
                                   (b['sample_monotonic_s'] - a['sample_monotonic_s'])})
        return {'state': status, 'session': self.session, 'metrics': metrics,
                'history': history[-60:], 'sample_age_s': round(age, 2),
                'frame_age_s': round(max(0, now - self.frame_changed_at), 2)}


class Dashboard:
    """Uses the Store's existing lock and database; never issues control/cloud calls."""
    def __init__(self, connection):
        self.db = connection
        self.performance = PerformanceWindow()
        self.db.execute('''CREATE TABLE IF NOT EXISTS dashboard_reviews
            (id TEXT PRIMARY KEY, session TEXT, created REAL, updated REAL, card TEXT, jpeg BLOB)''')
        # An interrupted PC job must not look like an ongoing cloud request forever.
        for row in self.db.execute('SELECT id,card FROM dashboard_reviews').fetchall():
            card = json.loads(row['card'])
            if card['state'] == 'processing':
                card.update(state='failed', error_code='PC_RESTARTED')
                self.db.execute('UPDATE dashboard_reviews SET card=? WHERE id=?', (json.dumps(card), row['id']))
        self.db.commit()

    def ingest(self, telemetry, now=None):
        if not isinstance(telemetry, dict):
            return
        self.performance.ingest(telemetry, now)
        receipts = telemetry.get('review_receipts', [])
        if not isinstance(receipts, list):
            return
        for receipt in receipts[:8]:
            if not isinstance(receipt, dict) or receipt.get('state') != 'received':
                continue
            row = self.db.execute('SELECT card,session FROM dashboard_reviews WHERE id=?',
                                  (str(receipt.get('request_id', '')),)).fetchone()
            if not row or not telemetry.get('session') or row['session'] != telemetry['session']:
                continue
            card = json.loads(row['card'])
            if type(receipt.get('frame_id')) is not int or receipt['frame_id'] != card['frame_id']:
                continue
            if card.get('board_received'):
                continue
            card.update(board_received=True, board_received_at=time.time() if now is None else now,
                        roundtrip_ms=number(receipt.get('roundtrip_ms')))
            self._update(card)

    def _update(self, card):
        self.db.execute('UPDATE dashboard_reviews SET card=?,updated=? WHERE id=?',
                        (json.dumps(card), time.time(), card['request_id']))

    def begin_review(self, task, jpeg, mode, session):
        identity = task['request_id']
        if self.db.execute('SELECT id FROM dashboard_reviews WHERE id=?', (identity,)).fetchone():
            return
        now = time.time()
        d = task['detector']
        card = {'request_id': identity, 'event_id': task['event_id'], 'frame_id': task['frame_id'],
                'session': session, 'mode': mode, 'state': 'processing', 'created_at': now,
                'detector': {k: d[k] for k in ('class_name', 'class_id', 'score', 'bbox_xyxy', 'model')},
                'semantic': None, 'provider': None, 'host_latency_ms': None,
                'roundtrip_ms': None, 'board_received': False,
                'image_url': '/api/reviews/' + identity + '/image'}
        self.db.execute('INSERT INTO dashboard_reviews VALUES(?,?,?,?,?,?)',
                        (identity, session, now, now, json.dumps(card), jpeg))
        self.db.execute('DELETE FROM dashboard_reviews WHERE id NOT IN '
                        '(SELECT id FROM dashboard_reviews ORDER BY created DESC,rowid DESC LIMIT ?)', (MAX_REVIEWS,))

    def finish_review(self, identity, result, failed, elapsed_ms):
        row = self.db.execute('SELECT card FROM dashboard_reviews WHERE id=?', (identity,)).fetchone()
        if not row:
            return
        card = json.loads(row['card'])
        meta = result.get('meta', {}) if isinstance(result, dict) else {}
        meta = meta if isinstance(meta, dict) else {}
        semantic = result.get('semantic', {}) if isinstance(result, dict) else {}
        semantic = semantic if isinstance(semantic, dict) else {}
        card.update(state='failed' if failed else ('fallback' if meta.get('request_status') == 'fallback' else 'completed'),
                    host_latency_ms=round(elapsed_ms, 3), host_completed_at=time.time(),
                    provider=meta.get('provider') if meta.get('provider') in ('mock', 'qwen_api') else None,
                    request_status=str(meta.get('request_status', 'unknown'))[:32],
                    request_attempted=meta.get('request_attempted') is True,
                    error_code='REVIEW_FAILED' if failed else str(meta.get('error_code', ''))[:64],
                    semantic={k: semantic.get(k) for k in ('verdict', 'reason_code', 'confidence', 'evidence')} if semantic else None)
        self._update(card)

    def image(self, identity):
        row = self.db.execute('SELECT jpeg FROM dashboard_reviews WHERE id=?', (identity,)).fetchone()
        return bytes(row['jpeg']) if row else None

    def snapshot(self, control, now=None):
        now = time.time() if now is None else now
        telemetry = control.get('link', {}).get('telemetry', {})
        telemetry = telemetry if isinstance(telemetry, dict) else {}
        session = telemetry.get('session')
        rows = self.db.execute('SELECT card FROM dashboard_reviews WHERE session IS ? '
                               'ORDER BY created DESC,rowid DESC LIMIT 5', (session,)).fetchall()
        reviews = [json.loads(row['card']) for row in rows]
        performance = self.performance.snapshot(control['online'], now)
        if telemetry.get('process') == 'exited' and performance['state'] == 'fresh':
            performance['state'] = 'stopped'
        return {'api_version': '30tai-dashboard-1', 'server_time': now, 'preview': False,
                'control': control, 'performance': performance,
                'reviews': reviews, 'review_scope': 'current_session' if session else 'unassigned',
                'review_cache_limit': MAX_REVIEWS,
                'definitions': {'fps_window': '处理吞吐率，近3秒滑动平均',
                                'post_callback_ms': '后处理回调，包含DFL/NMS与动作更新',
                                'roi_draw_ms': 'ROI/绘制旁路',
                                'cpu_percent': '整板CPU，0–100%',
                                'host_latency_ms': '主机复核处理耗时',
                                'roundtrip_ms': '板端发起至收回复核结果'}}
