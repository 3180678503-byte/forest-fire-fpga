"""Local control UI and authenticated ESP poll/job server, durable SQLite queue."""
import argparse,hashlib,json,re,sqlite3,sys,threading,time,uuid
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from types import SimpleNamespace
from wire import pack,seal,verify,valid_id,read_body,reply
from dashboard import Dashboard

class Store:
    def __init__(self,path,mode='mock'):
        self.mode=mode
        self.lock=threading.RLock();self.db=sqlite3.connect(str(path),check_same_thread=False)
        self.db.row_factory=sqlite3.Row
        self.db.executescript('CREATE TABLE IF NOT EXISTS commands(id TEXT PRIMARY KEY,action TEXT,args TEXT,state TEXT,created REAL,expires REAL,result TEXT,received REAL,completed REAL); CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY,digest TEXT,state TEXT,reply TEXT);')
        self.db.execute("UPDATE jobs SET state='failed',reply=? WHERE state='running'",(json.dumps({'error':'PC_RESTARTED'}),));self.db.commit()
        self.dashboard=Dashboard(self.db)
        self.live={};self.sessions={};self.retired=set()
    def enqueue(self,action,args,ttl=30,identity=None):
        allowed={'status','start','stop','restart','set_config','logs','test_reviews'}
        if action not in allowed or not 1<=ttl<=300:raise ValueError('INVALID_COMMAND')
        identity=valid_id(identity) if identity else str(uuid.uuid4())
        with self.lock:
            old=self.db.execute('SELECT action,args FROM commands WHERE id=?',(identity,)).fetchone()
            if old:
                if old['action']!=action or old['args']!=pack(args).decode():raise ValueError('ID_CONFLICT')
            else:
                now=time.time();self.db.execute('INSERT INTO commands VALUES(?,?,?,?,?,?,?,?,?)',(identity,action,pack(args).decode(),'queued',now,now+ttl,None,None,None));self.db.commit()
        return identity
    def poll(self,message,peer):
        session=valid_id(message['session']);seq=message['seq']
        if not isinstance(seq,int) or seq<1:raise ValueError('SEQUENCE')
        with self.lock:
            old=self.sessions.get(message['device'])
            if (message['device'],session) in self.retired:raise ValueError('RETIRED_SESSION')
            if old and old[0]==session and seq<=old[1]:raise ValueError('REPLAY')
            if old and old[0]!=session:self.retired.add((message['device'],old[0]))
            self.sessions[message['device']]=(session,seq)
            self.live={'last_seen':time.time(),'peer':peer,'session':session,'telemetry':message.get('status',{})}
            self.dashboard.ingest(message.get('status',{}))
            ack=[]
            for result in message.get('results',[])[:1]:
                valid_id(result['id'])
                self.db.execute("UPDATE commands SET state=?,result=?,completed=? WHERE id=? AND state IN ('sent','queued','expired')",('succeeded' if result['ok'] else 'failed',pack(result).decode(),time.time(),result['id']));ack.append(result['id'])
            now=time.time()
            self.db.execute("UPDATE commands SET state='expired' WHERE state IN ('queued','sent') AND expires<?",(now,))
            row=self.db.execute("SELECT * FROM commands WHERE state IN ('queued','sent') ORDER BY created LIMIT 1").fetchone()
            command=None
            if row:
                self.db.execute("UPDATE commands SET state='sent',received=COALESCE(received,?) WHERE id=?",(now,row['id']))
                command={'id':row['id'],'action':row['action'],'args':json.loads(row['args']),'ttl_ms':max(1,int((row['expires']-now)*1000))}
            self.db.commit()
            return {'v':1,'session':session,'seq':seq,'ack':ack,'command':command}
    def snapshot(self):
        with self.lock:
            return {'online':time.time()-self.live.get('last_seen',0)<5,'link':self.live,'commands':[dict(r) for r in self.db.execute('SELECT * FROM commands ORDER BY created DESC LIMIT 60')],'jobs':[dict(r) for r in self.db.execute('SELECT id,state FROM jobs ORDER BY rowid DESC LIMIT 30')],'cloud_mode':self.mode}
    def dashboard_snapshot(self):
        with self.lock:return self.dashboard.snapshot(self.snapshot())

def review_mode(service_mode, requested):
    if requested not in ('mock','remote') or (service_mode!='auto' and requested!=service_mode):
        raise ValueError('REVIEW_MODE_MISMATCH')
    return requested

def serve(config,state_dir,ui_port=8770,mode='mock',cloud_budget=1):
    state_dir.mkdir(parents=True,exist_ok=True);store=Store(state_dir/'control.sqlite',mode)
    base=Path(config['host_project']);sys.path[:0]=[str(base/'source/host'),str(base/'source/common')]
    import host_bridge
    from protocol import validate_request
    bridges={}
    for selected in (('mock','remote') if mode=='auto' else (mode,)):
        bridges[selected]=host_bridge.Bridge(SimpleNamespace(mode=selected,max_requests=1000000 if selected=='mock' else cloud_budget,
            key_file=config.get('cloud_key_file',''),
            endpoint=config.get('cloud_endpoint','https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions'),model=config.get('cloud_model','qwen3.8-flash'),cloud_timeout=8,
            log=str(state_dir/('mock_review.jsonl' if selected=='mock' else 'remote_review.jsonl'))))
    if mode=='remote' and not bridges['remote'].key:raise RuntimeError('MISSING_CLOUD_KEY')
    def background(identity,task,jpeg,selected):
        started=time.monotonic()
        try:
            code,result=bridges[selected].review(task,jpeg)
            if code!=200:raise RuntimeError('review status '+str(code))
            state='done'
        except Exception as exc:state='failed';result={'error':str(exc)[:120]}
        with store.lock:
            store.db.execute('UPDATE jobs SET state=?,reply=? WHERE id=?',(state,pack(result).decode(),identity));store.db.commit()
            store.dashboard.finish_review(identity,result,state=='failed',(time.monotonic()-started)*1000);store.db.commit()
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def setup(self):super().setup();self.connection.settimeout(5)
        def do_GET(self):
            if self.server.kind!='ui':return reply(self,404,{'error':'NOT_FOUND'})
            if self.path=='/api/state':return reply(self,200,store.snapshot())
            if self.path=='/api/dashboard':return reply(self,200,store.dashboard_snapshot())
            match=re.fullmatch(r'/api/reviews/([0-9a-f-]{36})/image',self.path)
            if match:
                try:identity=valid_id(match.group(1))
                except ValueError:return reply(self,404,{'error':'NOT_FOUND'})
                with store.lock:jpeg=store.dashboard.image(identity)
                if jpeg is None:return reply(self,404,{'error':'IMAGE_EXPIRED'})
                self.send_response(200);self.send_header('Content-Type','image/jpeg');self.send_header('Content-Length',str(len(jpeg)));self.send_header('Cache-Control','no-store');self.send_header('X-Content-Type-Options','nosniff');self.end_headers();self.wfile.write(jpeg);return
            if self.path!='/':return reply(self,404,{})
            page=Path(__file__).parent/'dashboard_panel.html'
            raw=(page if page.exists() else Path(__file__).parent/'panel.html').read_bytes()
            self.send_response(200);self.send_header('Content-Type','text/html; charset=utf-8');self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
        def do_POST(self):
            try:
                message=read_body(self)
                if self.server.kind=='ui':
                    if self.path!='/api/command' or self.headers.get('X-Control-Local')!='1':raise ValueError('LOCAL_API_ONLY')
                    origin=self.headers.get('Origin')
                    if origin and origin not in ('http://127.0.0.1:'+str(ui_port),'http://localhost:'+str(ui_port)):raise ValueError('ORIGIN')
                    identity=store.enqueue(message['action'],message.get('args',{}),message.get('ttl',30),message.get('id'))
                    return reply(self,200,{'id':identity})
                value=verify(message,config['key'])
                if value.get('device')!=config['device']:raise ValueError('DEVICE')
                if self.path=='/wire/poll':result=store.poll(value,self.client_address[0])
                elif self.path=='/wire/job':
                    selected=review_mode(mode,value.get('expected_mode',mode))
                    task=value['task'];jpeg=validate_request(task);identity=valid_id(task['request_id']);digest=hashlib.sha256(pack(task)).hexdigest()
                    if mode=='auto':digest=hashlib.sha256(pack({'mode':selected,'task':task})).hexdigest()
                    if selected=='remote' and task['detector']['model'].startswith('transport_test_'):raise ValueError('SYNTHETIC_TEST_REQUIRES_MOCK')
                    import io
                    from PIL import Image
                    if len(jpeg)>128*1024:raise ValueError('JPEG_LIMIT')
                    with Image.open(io.BytesIO(jpeg)) as image:
                        if image.format!='JPEG' or max(image.size)>640:raise ValueError('JPEG_FORMAT')
                        image.load()
                    with store.lock:
                        old=store.db.execute('SELECT digest FROM jobs WHERE id=?',(identity,)).fetchone()
                        if old and old['digest']!=digest:raise ValueError('JOB_ID_CONFLICT')
                        if not old:
                            explicit_session=value.get('vision_session')
                            if explicit_session is not None and (not isinstance(explicit_session,str) or not re.fullmatch(r'wire_[0-9]+',explicit_session)):raise ValueError('VISION_SESSION')
                            runtime_session=explicit_session or (store.live.get('telemetry',{}).get('session') if store.live.get('session')==value['session'] else None)
                            store.dashboard.begin_review(task,jpeg,selected,runtime_session)
                            store.db.execute('INSERT INTO jobs VALUES(?,?,?,?)',(identity,digest,'running',None));store.db.commit()
                            threading.Thread(target=background,args=(identity,task,jpeg,selected),daemon=True).start()
                    result={'v':1,'session':value['session'],'seq':value['seq'],'job_id':identity,'accepted':True}
                elif self.path=='/wire/result':
                    with store.lock:row=store.db.execute('SELECT state,reply FROM jobs WHERE id=?',(valid_id(value['job_id']),)).fetchone()
                    result={'v':1,'session':value['session'],'seq':value['seq'],'state':row['state'] if row else 'missing','reply':json.loads(row['reply']) if row and row['reply'] else None}
                else:raise ValueError('NOT_FOUND')
                reply(self,200,seal(result,config['key']))
            except (ValueError,KeyError,TypeError) as exc:reply(self,400,{'error':str(exc)[:120]})
            except Exception:reply(self,503,{'error':'INTERNAL_ERROR'})
    servers=[]
    for kind,address in [('wire',(config['host'],8769)),('ui',('127.0.0.1',ui_port))]:
        server=ThreadingHTTPServer(address,Handler);server.kind=kind;server.daemon_threads=True;servers.append(server)
        threading.Thread(target=server.serve_forever,daemon=True).start()
    print(json.dumps({'ready':True,'ui':'http://127.0.0.1:'+str(ui_port),'wire_host':config['host'],'mode':mode}),flush=True)
    try:
        while True:time.sleep(1)
    except KeyboardInterrupt:pass
    finally:
        for server in servers:server.shutdown();server.server_close()
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--config',type=Path,required=True);p.add_argument('--state',type=Path,required=True)
    p.add_argument('--mode',choices=('mock','remote','auto'),default='mock');p.add_argument('--allow-live-upload',action='store_true');p.add_argument('--cloud-budget',type=int,default=1)
    a=p.parse_args()
    if a.mode in ('remote','auto') and not a.allow_live_upload:p.error('Real cloud mode requires explicit --allow-live-upload')
    if not 1<=a.cloud_budget<=100000:p.error('Invalid cloud budget')
    serve(json.loads(a.config.read_text(encoding='utf-8')),a.state,mode=a.mode,cloud_budget=a.cloud_budget)
