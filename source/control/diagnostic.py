"""Saved-image NPU/HDMI loop, no camera/ImageMake claims; owned cleanup."""
import argparse,fcntl,json,os,signal,subprocess,sys,time
from pathlib import Path
def main():
    p=argparse.ArgumentParser();p.add_argument('--runtime',type=Path,required=True);p.add_argument('--session',required=True);a=p.parse_args()
    sys.path.insert(0,str(a.runtime));from run_system import occupied,stop
    lock=open('/run/lock/fmql_vision.lock','a');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);occupied()
    out=a.runtime/'outputs'/a.session;out.mkdir();roi=out/'roi';roi.mkdir()
    (out/'session.json').write_text(json.dumps({'mode':'mock','input':'saved_image_cpu_sampling','camera_capture_tested':False}))
    stopping=[False]
    for sig in (signal.SIGTERM,signal.SIGINT):signal.signal(sig,lambda *_:stopping.__setitem__(0,True))
    children=[];streams=[]
    try:
        commands=[('worker',[sys.executable,'-B',str(a.runtime/'python/board/http_worker.py'),'--output',str(roi),'--url','http://127.0.0.1:18765/v1/semantic-review','--max-jobs','0','--idle-timeout','86400','--timeout','15','--ttl','20','--cooldown','0']),
            ('runtime',[str(a.runtime/'hdmi_replay_probe'),str(a.runtime/'configs/hdmi.json'),'--replay-image',str(a.runtime/'fixtures/wire_input.jpg'),'--frames','10000','--profile-out','/dev/null','--roi-output',str(roi)])]
        for name,command in commands:
            stream=(out/(name+'.log')).open('ab');streams.append(stream)
            children.append(subprocess.Popen(command,cwd=a.runtime,stdout=stream,stderr=subprocess.STDOUT,env=dict(os.environ,FMQL_VALIDATE_COUNT='10',FMQL_VALIDATE_STRIDE='30',FMQL_HDMI_VERIFY_COUNT='1')))
        while children[-1].poll() is None and not stopping[0]:time.sleep(.1)
    finally:
        for child in reversed(children):stop(child)
        for stream in streams:stream.close()
    (out/'summary.json').write_text(json.dumps({'runtime_exit':children[-1].returncode,'camera_capture_tested':False}));return 0
if __name__=='__main__':raise SystemExit(main())
