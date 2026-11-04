"""Bounded 1 Hz log/proc sampler, independent of the camera and device locks."""
from collections import deque
import json
import math
from pathlib import Path
import re
import threading
import time

THROUGHPUT=re.compile(r'\[THROUGHPUT\] frames=(\d+), elapsed_since_first_s=([\d.]+), fps=([\d.]+)')
POST=re.compile(r'\[YOLOv8\]\[frame=(\d+)\] dfl_sigmoid_nms_ms=([\d.]+), convert_draw_ms=([\d.]+), detections=(\d+)')
SESSION=re.compile(r'wire_[0-9]+\Z')


def read_json(path):
    try:
        with path.open('rb') as stream:data=stream.read(65537)
        value=json.loads(data) if len(data)<=65536 else {}
        return value if isinstance(value,dict) else {}
    except (OSError,ValueError):return {}


class RuntimeTelemetry:
    def __init__(self,runtime,clock=None,proc='/proc'):
        self.runtime=Path(runtime);self.clock=clock or time.monotonic;self.proc=Path(proc)
        self.lock=threading.RLock();self.session=None;self.receipts=deque(maxlen=8)
        self.last_sample=-float('inf');self.offset=0;self.inode=None;self.partial=''
        self.count=None;self.elapsed=None;self.post=None;self.metric=None
        self.cpu_previous=None;self.seen_files={};self.sample_cost_ms=None

    def _reset(self,session):
        self.session=session;self.last_sample=-float('inf');self.offset=0;self.inode=None;self.partial=''
        self.count=self.elapsed=self.post=self.metric=None;self.receipts.clear();self.seen_files={}

    def received(self,task,session,elapsed_ms):
        with self.lock:
            if not session or not SESSION.fullmatch(session):return
            if session!=self.session:self._reset(session)
            identity=task.get('request_id')
            if (not identity or type(task.get('frame_id')) is not int
                or type(elapsed_ms) not in (int,float) or not math.isfinite(elapsed_ms) or elapsed_ms<0
                or any(r['request_id']==identity for r in self.receipts)):return
            self.receipts.append({'request_id':identity,'frame_id':task['frame_id'],
                                  'state':'received','roundtrip_ms':round(elapsed_ms,3)})

    def _read_log(self,path):
        try:
            stat=path.stat()
            if self.inode!=stat.st_ino or stat.st_size<self.offset:
                self.inode=stat.st_ino;self.offset=max(0,stat.st_size-262144);self.partial=''
            if stat.st_size-self.offset>262144:
                self.offset=stat.st_size-262144;self.partial=''
            with path.open('rb') as stream:
                stream.seek(self.offset);data=stream.read(262144);self.offset=stream.tell()
        except OSError:return
        lines=(self.partial+data.decode(errors='replace')).split('\n');self.partial=lines.pop()[-4096:]
        for line in lines:
            match=POST.search(line)
            if match:self.post=(int(match[1]),float(match[2]),float(match[3]),int(match[4]))
            match=THROUGHPUT.search(line)
            if match and math.isfinite(float(match[2])):self.count=int(match[1]);self.elapsed=float(match[2])

    def _resources(self,pid):
        value={}
        try:
            fields=[int(x) for x in (self.proc/'stat').read_text().splitlines()[0].split()[1:9]]
            current=(sum(fields),fields[3]+fields[4])
            if self.cpu_previous:
                total=current[0]-self.cpu_previous[0];idle=current[1]-self.cpu_previous[1]
                if total>0:value['cpu_percent']=round(max(0,min(100,100*(total-idle)/total)),2)
            self.cpu_previous=current
        except (OSError,ValueError,IndexError):pass
        try:
            fields={line.split(':',1)[0]:int(line.split()[1])*1024 for line in (self.proc/'meminfo').read_text().splitlines() if ':' in line}
            value['memory_total_mb']=round(fields['MemTotal']/1e6,3)
            value['memory_used_mb']=round((fields['MemTotal']-fields['MemAvailable'])/1e6,3)
        except (OSError,ValueError,KeyError,IndexError):pass
        if type(pid) is int and pid>0:
            try:
                process=self.proc/str(pid)
                if str(self.runtime/'yolo_qwen_esp32_hdmi').encode() in (process/'cmdline').read_bytes():
                    match=re.search(r'^VmRSS:\s+(\d+) kB', (process/'status').read_text(),re.M)
                    if match:value['runtime_rss_mb']=round(int(match[1])*1024/1e6,3)
            except OSError:pass
        return value

    def _review_files(self,out):
        try:files=sorted((out/'roi/reviews').glob('event_*_frame_*.json'),key=lambda p:p.stat().st_mtime_ns,reverse=True)[:8]
        except OSError:return
        for path in reversed(files):
            try:signature=(path.stat().st_mtime_ns,path.stat().st_size)
            except OSError:continue
            if self.seen_files.get(path.name)==signature:continue
            item=read_json(path)
            if item.get('transport_status')=='ok' and item.get('request_id') and type(item.get('frame')) is int:
                self.received({'request_id':item['request_id'],'frame_id':item['frame']},self.session,item.get('end_to_end_ms',0))
            self.seen_files[path.name]=signature
        if len(self.seen_files)>64:self.seen_files={p.name:self.seen_files.get(p.name) for p in files}

    def collect(self,status):
        with self.lock:
            session=status.get('session');now=self.clock()
            if not isinstance(session,str) or not SESSION.fullmatch(session):return {}
            if session!=self.session:self._reset(session)
            if now-self.last_sample>=1:
                start=self.clock();self.last_sample=now
                out=self.runtime/'outputs'/session
                self._review_files(out)
                if status.get('process')=='running':
                    self._read_log(out/'runtime.log')
                    if self.count is not None:
                        self.metric={'schema_version':'30tai-performance-1','session':session,
                                     'sample_seq':int(now*1000),'sample_monotonic_s':now,
                                     'frame_count':self.count,'elapsed_s':self.elapsed}
                        if self.post and self.post[0]==self.count:
                            self.metric.update(post_callback_ms=self.post[1],roi_draw_ms=self.post[2],detections=self.post[3])
                        mode=read_json(out/'session.json').get('mode')
                        if mode in ('off','mock','remote'):self.metric['qwen_mode']=mode
                        self.metric.update(self._resources(status.get('runtime_pid')))
                self.sample_cost_ms=round((self.clock()-start)*1000,3)
            result={'review_receipts':list(self.receipts)}
            if self.metric and status.get('process')=='running':
                result['performance']=dict(self.metric,sample_age_ms=round(max(0,now-self.last_sample)*1000,3),
                                           sampler_ms=self.sample_cost_ms)
            return result
