"""Whitelisted owned-process control; persistent command identities, no shell."""
import base64,hashlib,http.client,json,os,queue,signal,sqlite3,subprocess,sys,threading,time,uuid
from pathlib import Path
from wire import pack,valid_id
class Agent:
    def __init__(self,root,runtime,independent_vision=False):
        self.root=Path(root);self.runtime=Path(runtime);self.lock=threading.RLock();self.tasks=queue.Queue(maxsize=16)
        self.root.mkdir(parents=True,exist_ok=True)
        self.db=sqlite3.connect(str(self.root/'commands.sqlite'),check_same_thread=False);self.db.row_factory=sqlite3.Row
        self.db.execute('CREATE TABLE IF NOT EXISTS commands(id TEXT PRIMARY KEY,state TEXT,result TEXT,acked INTEGER,definition TEXT)')
        self.db.execute("UPDATE commands SET state='done',result=? WHERE state='running'",(json.dumps({'ok':False,'error':'AGENT_RESTARTED_OUTCOME_UNKNOWN'}),));self.db.commit()
        self.child=None;self.stream=None;self.profile=None;self.session=None
        self.vision=None
        if independent_vision:
            from vision_service import VisionService
            self.vision=VisionService(self.root,self.runtime)
        self.review_test={'running':False,'passed':0,'failed':0}
        cfg=self.root/'settings.json';self.settings=dict({'qwen':'mock','cooldown':10,'duration':0,'confidence':.25,'iou':.7,'max_jobs':0},**(json.loads(cfg.read_text()) if cfg.exists() else {}))
        threading.Thread(target=self.work,daemon=True).start()
    def accept(self,cmd):
        identity=valid_id(cmd['id']);definition=pack({'action':cmd['action'],'args':cmd['args']}).decode()
        if not 0<cmd['ttl_ms']<=300000:raise ValueError('COMMAND_TTL')
        with self.lock:
            old=self.db.execute('SELECT * FROM commands WHERE id=?',(identity,)).fetchone()
            if old:
                if old['definition']!=definition:raise ValueError('COMMAND_ID_CONFLICT')
                return
            self.db.execute('INSERT INTO commands VALUES(?,?,?,?,?)',(identity,'running',None,0,definition));self.db.commit()
        self.tasks.put((cmd,time.monotonic()+cmd['ttl_ms']/1000))
    def pending(self):
        with self.lock:
            row=self.db.execute("SELECT id,result FROM commands WHERE state='done' AND acked=0 ORDER BY rowid LIMIT 1").fetchone()
            return [dict(json.loads(row['result']),id=row['id'])] if row else []
    def acknowledge(self,ids):
        with self.lock:
            for identity in ids:self.db.execute('UPDATE commands SET acked=1 WHERE id=?',(identity,))
            self.db.commit()
    def state(self):
        child=self.child
        if self.vision:
            status=self.vision.state();self.profile=status['profile'];self.session=status['session']
        else:
            status={'process':'idle','profile':self.profile,'pid':child.pid if child else None,'session':self.session}
            if child:status.update(process='running' if child.poll() is None else 'exited',exit_code=child.poll())
        if self.review_test.get('running') or self.review_test.get('passed') or self.review_test.get('failed'):status['review_test']=dict(self.review_test)
        try:status['ethernet_state']=Path('/sys/class/net/eth0/operstate').read_text().strip()
        except OSError:status['ethernet_state']='unknown'
        if self.session:
            path=self.runtime/'outputs'/self.session/'session.json'
            if path.exists():
                try:
                    data=json.loads(path.read_text());status.update(runtime_pid=data.get('runtime_pid'),error=data.get('fatal_error'),runtime_exit=data.get('runtime_exit'))
                except (ValueError,OSError):pass
        return status
    def stop(self):
        if self.vision:
            self.vision.stop();return self.state()
        child=self.child
        if child and child.poll() is None:
            child.terminate()
            try:child.wait(timeout=25)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid,signal.SIGKILL);child.wait(timeout=3)
        if self.stream:self.stream.close();self.stream=None
        return self.state()
    def close(self):
        # A communication process exiting must not stop the independent unit.
        if not self.vision:self.stop()
        if self.stream:self.stream.close();self.stream=None
    def start(self,args):
        profile=args.get('profile','live')
        if set(args)-{'profile'} or profile not in ('live','offline','diagnostic'):raise ValueError('INVALID_PROFILE')
        if self.vision:
            current=self.state()
            if current['process']=='running':return {'already_running':True,**current}
        if self.child and self.child.poll() is None:return {'already_running':True,**self.state()}
        # Check all existing vision owners; do not terminate another conversation's process.
        sys.path.insert(0,str(self.runtime))
        from run_system import occupied
        occupied()
        session='wire_'+str(time.time_ns());self.session=session;self.profile=profile
        if self.stream:self.stream.close()
        if not self.vision:self.stream=(self.root/'runtime.log').open('ab')
        if profile=='diagnostic':
            command=[sys.executable,'-B',str(Path(__file__).parent/'diagnostic.py'),'--runtime',str(self.runtime),'--session',session]
        else:
            command=[sys.executable,'-B','-u',str(Path(__file__).parent/'supervisor_adapter.py'),'--runtime',str(self.runtime),
                '--confidence',str(self.settings['confidence']),'--iou',str(self.settings['iou']),
                '--session',session,'--mode',('remote' if self.settings['qwen']=='remote' else 'mock'),'--output','hdmi',
                '--duration',str(self.settings['duration']),'--review-transport',('managed' if self.settings['qwen']=='remote' else 'http'),'--review-http-url','http://127.0.0.1:18765/v1/semantic-review',
                '--cooldown',str(self.settings['cooldown']),'--max-jobs',str(self.settings['max_jobs'])]
            if profile=='offline':command+=['--input','offline','--image',str(self.runtime/'fixtures/wire_input.jpg')]
            if self.settings['qwen']=='off':command+=['--qwen-off']
        if self.vision:return self.vision.start(command,session,profile)
        self.child=subprocess.Popen(command,cwd=self.runtime,stdout=self.stream,stderr=subprocess.STDOUT,start_new_session=True)
        return {'starting':True,**self.state()}
    def execute(self,action,args):
        if action=='status':return {'status':self.state(),'settings':self.settings}
        if action=='start':return self.start(args)
        if action=='stop':
            if args:raise ValueError('INVALID_ARGS')
            return self.stop()
        if action=='restart':self.stop();return self.start(args)
        if action=='logs':
            if args:raise ValueError('INVALID_ARGS')
            paths=[self.root/'runtime.log']
            if self.session:paths+=[self.runtime/'outputs'/self.session/'camera_init.log',self.runtime/'outputs'/self.session/'runtime.log']
            value={}
            for path in paths:
                if path.exists():
                    with path.open('rb') as stream:
                        stream.seek(max(0,path.stat().st_size-700));value[path.name]=stream.read(700).decode(errors='replace')
            return {'logs':value}
        if action=='set_config':
            if set(args)-{'qwen','cooldown','duration','confidence','iou','max_jobs'}:raise ValueError('UNSUPPORTED_CONFIG')
            new=dict(self.settings,**args)
            if new['qwen'] not in ('mock','remote','off') or type(new['cooldown']) not in (int,float) or not 0<=new['cooldown']<=3600 or type(new['duration']) not in (int,float) or not 0<=new['duration']<=86400:raise ValueError('INVALID_CONFIG')
            if any(type(new[k]) not in (int,float) or not 0<=new[k]<=1 for k in ('confidence','iou')) or type(new['max_jobs']) is not int or not 0<=new['max_jobs']<=1000000:raise ValueError('INVALID_CONFIG')
            if new['qwen']=='remote' and not (self.runtime/'qwen_release.json').is_file():raise ValueError('RUNTIME_HAS_NO_MANAGED_QWEN')
            tmp=self.root/'settings.tmp';tmp.write_bytes(pack(new));tmp.replace(self.root/'settings.json');self.settings=new
            return {'settings':new,'effective':'next_start'}
        if action=='test_reviews':
            if set(args)-{'count','interval'} or type(args.get('count',5)) is not int or not 1<=args.get('count',5)<=100 or type(args.get('interval',1)) not in (int,float) or not 0<=args.get('interval',1)<=120:raise ValueError('INVALID_TEST_LIMITS')
            if self.review_test['running']:return {'already_running':True}
            self.review_test={'running':True,'passed':0,'failed':0}
            threading.Thread(target=self.run_review_test,args=(args.get('count',5),args.get('interval',1)),daemon=True).start()
            return {'started':True,'synthetic_only':True,'mode':'mock'}
        raise ValueError('ACTION_NOT_ALLOWED')
    def run_review_test(self,count,interval):
        from datetime import datetime,timezone
        fixtures=[json.loads((self.runtime/'fixtures/synthetic.json').read_text()),json.loads((self.runtime/'fixtures/wire_large.json').read_text())]
        logfile=self.root/('review_test_'+str(time.time_ns())+'.jsonl')
        for index in range(count):
            fixture=fixtures[index%2];identity=str(uuid.uuid4())
            task={'schema_version':'fire-semantic-review-1.0','request_id':identity,'event_id':'control-test:'+identity,'frame_id':index+1,
                'timestamp_utc':datetime.now(timezone.utc).isoformat(),'detector':fixture['detector'],
                'evidence':{'image_mime':'image/jpeg','image_encoding':'base64','image_base64':fixture['jpeg_base64'],'image_role':'target_crop'},
                'context':{'gate_state':'CONFIRMED','consecutive_hits':5,'class_consistent':True,'bbox_iou_stability':None,'score_trend':'stable'}}
            client=http.client.HTTPConnection('127.0.0.1',18765,timeout=16);begin=time.monotonic()
            result={'request_id':identity,'jpeg_sha256':fixture['jpeg_sha256'],'jpeg_bytes':len(base64.b64decode(fixture['jpeg_base64']))}
            try:
                client.request('POST','/v1/semantic-review',body=pack(task),headers={'Content-Type':'application/json'})
                response=client.getresponse();value=json.loads(response.read(65536))
                if response.status!=200 or value.get('request_id')!=identity or not value.get('meta',{}).get('is_mock'):raise ValueError('INVALID_MOCK_RESULT')
                result.update(ok=True,reply=value);self.review_test['passed']+=1
            except Exception as exc:result.update(ok=False,error=str(exc)[:120]);self.review_test['failed']+=1
            finally:client.close()
            result['elapsed_ms']=round((time.monotonic()-begin)*1000,3)
            with logfile.open('a') as stream:stream.write(json.dumps(result)+'\n')
            if index+1<count:time.sleep(interval)
        self.review_test['running']=False
    def work(self):
        while True:
            cmd,deadline=self.tasks.get();begin=time.monotonic()
            try:
                if begin>deadline:raise ValueError('EXPIRED_BEFORE_EXECUTION')
                result={'ok':True,'result':self.execute(cmd['action'],cmd['args'])}
            except Exception as exc:result={'ok':False,'error':type(exc).__name__+': '+str(exc)[:180]}
            result['execution_ms']=round((time.monotonic()-begin)*1000,3)
            with self.lock:
                self.db.execute("UPDATE commands SET state='done',result=? WHERE id=?",(pack(result).decode(),cmd['id']));self.db.commit()
