"""Single UART owner, authenticated polling and queued asynchronous semantic review."""
import argparse,json,os,queue,signal,sys,threading,time,uuid
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from wire import pack,seal,verify,read_body,reply
from agent import Agent
from usb_locator import select_usb,save_selection
from runtime_telemetry import RuntimeTelemetry

def transport_exit_code(error,safe_command_state):
    if not safe_command_state:return 78
    # RX-thread/USB errors are permanent for the current handle; reopen it.
    # Ordinary AT/network deadlines still use the existing Wi-Fi retry path.
    if isinstance(error,OSError) and not isinstance(error,TimeoutError):return 1
    return None

def recover_wifi_or_restart(join_wifi):
    try:join_wifi(20)
    except Exception:
        # ESP power cycling restores its default UART rate. Reopen through
        # UartSession's baud detection instead of retaining the old rate.
        raise SystemExit(1) from None

def main():
    p=argparse.ArgumentParser();p.add_argument('--config',type=Path,required=True);p.add_argument('--state',type=Path,required=True);a=p.parse_args()
    config=json.loads(a.config.read_text());runtime=Path(config['runtime'])
    sys.path[:0]=[str(runtime/'transport'),str(runtime/'transport/vendor'),str(runtime/'python/common')]
    from ch340_usb import Ch340,devices,location
    from uart_session import UartSession,synchronize
    from at_protocol import AtLink
    # Import protocol from the existing validated transport copy.
    from protocol import validate_request,validate_response,strict_loads
    agent=Agent(a.state,runtime,independent_vision=config.get('independent_vision',False));sampler=RuntimeTelemetry(runtime);jobs=queue.Queue(maxsize=1);waiting={};waiting_lock=threading.Lock()
    stop=threading.Event();online={'available':False,'error':None};session_id=str(uuid.uuid4());counter=[0]
    for sig in (signal.SIGTERM,signal.SIGINT):signal.signal(sig,lambda *_:stop.set())
    a.state.mkdir(parents=True,exist_ok=True)
    def log(value):
        with (a.state/'link.jsonl').open('a') as stream:stream.write(json.dumps(dict(value,monotonic=time.monotonic()))+'\n')
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def setup(self):super().setup();self.connection.settimeout(16)
        def do_GET(self):
            if self.path!='/healthz':return reply(self,404,{})
            reply(self,200,dict(online,mode=agent.settings['qwen'],transport='esp32_managed',advisory_only=True))
        def do_POST(self):
            if self.path!='/v1/semantic-review':return reply(self,404,{})
            try:
                task=read_body(self,196608);validate_request(task);identity=task['request_id']
                with waiting_lock:
                    item=waiting.get(identity)
                    if item and pack(item['task'])!=pack(task):raise ValueError('REQUEST_ID_CONFLICT')
                    if not item:
                        item={'task':task,'event':threading.Event(),'deadline':time.monotonic()+14,'result':None,
                              'created_monotonic':time.monotonic(),'vision_session':agent.state().get('session')}
                        jobs.put_nowait(item);waiting[identity]=item
                if not item['event'].wait(14):return reply(self,503,{'error':'REVIEW_TIMEOUT'})
                if item['result'] is None:return reply(self,503,{'error':'TRANSPORT_UNAVAILABLE'})
                reply(self,200,item['result'])
            except (ValueError,KeyError,queue.Full):reply(self,400,{'error':'INVALID_OR_BUSY'})
    server=ThreadingHTTPServer(('127.0.0.1',18765),Handler);server.daemon_threads=True
    threading.Thread(target=server.serve_forever,daemon=True).start()
    report={};current=None
    def telemetry():
        status=agent.state()
        if report.get('usb_selection'):
            status['communication_usb']=report['usb_selection']['selected_path']
            status['usb_selection_mode']=report['usb_selection']['mode']
        try:
            if config.get('performance_telemetry',True):status.update(sampler.collect(status))
        except Exception as exc:status['performance_error']=type(exc).__name__
        return status
    def set_state():
        tmp=a.state/'link.tmp';tmp.write_bytes(pack(dict(online,session=session_id,status=telemetry())));tmp.replace(a.state/'link.json')
    try:
        preferred=config.get('usb_path')
        automatic=config.get('auto_usb',False)
        cached=a.state/'usb_selection.json'
        if automatic and cached.exists():
            try:preferred=json.loads(cached.read_text()).get('selected_path') or preferred
            except (ValueError,OSError):pass
        def probe(device):
            with Ch340(device) as port:
                baud,_=synchronize(port)
                return baud
        device,selection=select_usb(preferred,automatic,[(location(d),d) for d in devices()],probe)
        report['usb_selection']=selection
        log({'state':'usb_selected','usb':selection})
        # Persist only after UartSession confirms the operational baud below.
        with Ch340(device) as uart:
          with UartSession(uart,921600,report) as session:
            save_selection(cached,selection)
            link=AtLink(uart,chunk_size=2048,passive_read=8)
            def command(value,seconds=3):
                link.command(value,time.monotonic()+seconds)
            def exchange(path,fields,seconds=8):
                counter[0]+=1;seq=counter[0]
                message=seal(dict(fields,v=1,device=config['device'],session=session_id,seq=seq),config['key']);body=pack(message)
                packet=('POST '+path+' HTTP/1.0\r\nHost: '+config['host']+'\r\nContent-Type: application/json\r\nContent-Length: '+str(len(body))+'\r\nConnection: close\r\n\r\n').encode()+body
                try:
                    (code,raw),metrics=link.request(config['host'],8769,packet,seconds)
                    if code!=200:raise RuntimeError('PC_HTTP_'+str(code))
                    value=verify(json.loads(raw),config['key'])
                    if value.get('session')!=session_id or value.get('seq')!=seq:raise ValueError('REPLY_IDENTITY')
                    log({'path':path,'elapsed_ms':metrics['total_ms'],'tx_body_bytes':len(body),'rx_body_bytes':len(raw)})
                    return value
                finally:
                    session.safe=link.safe_command_state
                    if session.safe:link.close_connection()
            for value in ('ATE0','AT+CIPMUX=0','AT+CIPMODE=0','AT+CIPRECVMODE=1','AT+CIPDINFO=0'):command(value)
            # Credentials stay in root-only config, echo disabled, never logged.
            quote=lambda s:s.replace('\\','\\\\').replace('"','\\"').replace(',','\\,')
            def join_wifi(seconds):
                uart.drain(.1)
                raw=uart.command('AT+CWJAP="'+quote(config['ssid'])+'","'+quote(config['password'])+'"',seconds)
                # WIFI DISCONNECT is expected during reassociation, not a transfer failure.
                if b'\r\nOK\r\n' not in raw:raise RuntimeError('WIFI_JOIN_FAILED')
                from at_protocol import AtStream
                link.stream=AtStream()
            joined=False
            while not stop.is_set() and not joined:
                try:join_wifi(25);joined=True
                except Exception:
                    online.update(available=False,error='Waiting for configured Wi-Fi hotspot')
                    log({'state':'waiting_wifi'});set_state();stop.wait(5)
            next_poll=0;next_result=0;failures=0
            while not stop.is_set():
                try:
                    now=time.monotonic()
                    if now>=next_poll:
                        response=exchange('/wire/poll',{'status':telemetry(),'results':agent.pending()})
                        agent.acknowledge(response['ack'])
                        if response.get('command'):agent.accept(response['command'])
                        online.update(available=True,error=None);failures=0;next_poll=time.monotonic()+(.05 if response.get('command') else .2);set_state()
                    if current and time.monotonic()>=current['deadline']:
                        current['event'].set();current=None
                    if current is None:
                        try:current=jobs.get_nowait()
                        except queue.Empty:pass
                        if current:
                            if time.monotonic()>=current['deadline']:current['event'].set();current=None;continue
                            response=exchange('/wire/job',{'task':current['task'],'vision_session':current['vision_session'],'expected_mode':'remote' if agent.settings['qwen']=='remote' else 'mock'},min(12,max(1,current['deadline']-time.monotonic())))
                            next_result=time.monotonic()+.2
                    if current and time.monotonic()>=next_result:
                        value=exchange('/wire/result',{'job_id':current['task']['request_id']})
                        if value['state']=='done':
                            validate_response(value['reply'],current['task']);sampler.received(current['task'],current['vision_session'],(time.monotonic()-current['created_monotonic'])*1000);current['result']=value['reply'];current['event'].set();current=None
                        elif value['state'] in ('failed','missing'):current['event'].set();current=None
                        next_result=time.monotonic()+.5
                    # Bounded in-memory completed request cache.
                    with waiting_lock:
                        for identity,item in list(waiting.items()):
                            if item['event'].is_set() and time.monotonic()>item['deadline']+30:del waiting[identity]
                    stop.wait(.03)
                except Exception as exc:
                    failures+=1;online.update(available=False,error=type(exc).__name__+': '+str(exc)[:120]);log({'error':online['error'],'safe':link.safe_command_state});set_state()
                    exit_code=transport_exit_code(exc,link.safe_command_state)
                    if exit_code is not None:
                        session.safe=False
                        log({'fatal':'UNCERTAIN_AT_STATE_REQUIRES_RECOVERY' if exit_code==78 else 'USB_IO_FAILURE_REOPEN_REQUIRED'})
                        raise SystemExit(exit_code)
                    if failures>=3:
                        # Query/rejoin only while command state is known. Never retry an uncertain POST.
                        recover_wifi_or_restart(join_wifi)
                    stop.wait(min(5,failures))
    finally:
        agent.close();online['available']=False
        if current:current['event'].set()
        server.shutdown();server.server_close();set_state()
        (a.state/'uart_session.json').write_bytes(pack(report))
if __name__=='__main__':main()
