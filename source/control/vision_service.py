"""A fixed, independently owned systemd unit for the vision supervisor."""
import json
import os
from pathlib import Path
import re
import subprocess
import threading

UNIT='fmql-vision-esp32.service'
DESCRIPTION='30TAI independent vision '
PROPERTIES=('LoadState','ActiveState','SubState','MainPID','ExecMainStatus','Description','ControlGroup')

class VisionService:
    def __init__(self,root,runtime,runner=None):
        self.root=Path(root);self.runtime=Path(runtime).resolve()
        self.metadata=self.root/'vision_owner.json'
        self.runner=runner or subprocess.run
        self.lock=threading.RLock()

    def _run(self,args,timeout=12):
        return self.runner(args,capture_output=True,text=True,timeout=timeout)

    def _owner(self):
        if not self.metadata.exists():return None
        value=json.loads(self.metadata.read_text())
        if (value.get('unit')!=UNIT or value.get('runtime')!=str(self.runtime)
            or not re.fullmatch(r'wire_[0-9]+',value.get('session',''))
            or value.get('profile') not in ('live','offline','diagnostic')):
            raise RuntimeError('VISION_OWNER_INVALID')
        return value

    def _properties(self):
        result=self._run(['systemctl','show',UNIT,'--no-pager']+['--property='+x for x in PROPERTIES])
        return dict(line.split('=',1) for line in result.stdout.splitlines() if '=' in line)

    def _save(self,value):
        temporary=self.metadata.with_suffix('.tmp')
        temporary.write_text(json.dumps(value,sort_keys=True))
        os.chmod(str(temporary),0o600);temporary.replace(self.metadata)

    def state(self):
        with self.lock:
            owner=self._owner();properties=self._properties()
            active=properties.get('ActiveState') in ('activating','active','reloading','deactivating')
            if active and (not owner or properties.get('Description')!=DESCRIPTION+owner['session']):
                raise RuntimeError('VISION_UNIT_OWNERSHIP_MISMATCH')
            value={'process':'idle' if not owner else 'exited','profile':owner['profile'] if owner else None,
                   'session':owner['session'] if owner else None,'pid':None,'manager':'systemd','unit':UNIT,
                   'control_group':properties.get('ControlGroup','')}
            if active:
                value.update(process='running',pid=int(properties.get('MainPID') or 0) or None,exit_code=None)
            elif owner:
                value['exit_code']=owner.get('exit_code')
                record=self.runtime/'outputs'/owner['session']/'session.json'
                if record.exists():
                    try:
                        data=json.loads(record.read_text());value['exit_code']=data.get('runtime_exit')
                    except (ValueError,OSError):pass
            return value

    def start(self,command,session,profile):
        with self.lock:
            old=self.state()
            if old['process']=='running':return {'already_running':True,**old}
            if not re.fullmatch(r'wire_[0-9]+',session) or profile not in ('live','offline','diagnostic'):
                raise ValueError('INVALID_VISION_IDENTITY')
            # An active foreign unit cannot be controlled; a retained failed unit
            # also needs its ownership checked before clearing its failed state.
            props=self._properties();owner=self._owner()
            if props.get('LoadState')=='loaded' and props.get('Description')!=DESCRIPTION+(owner['session'] if owner else ''):
                raise RuntimeError('VISION_UNIT_OWNERSHIP_MISMATCH')
            if props.get('ActiveState')=='failed':self._run(['systemctl','reset-failed',UNIT])
            value={'version':1,'unit':UNIT,'runtime':str(self.runtime),'session':session,'profile':profile}
            self._save(value)
            log=str(self.root/'runtime.log')
            args=['systemd-run','--quiet','--collect','--unit='+UNIT,'--description='+DESCRIPTION+session,
                '--property=Type=simple','--property=Restart=no','--property=KillMode=control-group',
                '--property=TimeoutStopSec=45','--property=WorkingDirectory='+str(self.runtime),
                '--property=UMask=0077','--property=StandardOutput=append:'+log,
                '--property=StandardError=append:'+log,'--']+list(command)
            result=self._run(args,20)
            if result.returncode:
                value['exit_code']=1;value['start_error']='SYSTEMD_START_FAILED';self._save(value)
                raise RuntimeError('VISION_SYSTEMD_START_FAILED')
            return {'starting':True,**self.state()}

    def stop(self):
        with self.lock:
            value=self.state()  # Verify ownership before issuing any stop.
            if value['process']=='running':
                result=self._run(['systemctl','stop',UNIT],60)
                if result.returncode:raise RuntimeError('VISION_SYSTEMD_STOP_FAILED')
            owner=self._owner()
            if owner:
                owner['exit_code']=0;self._save(owner)
            return self.state()
