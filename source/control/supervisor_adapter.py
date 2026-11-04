"""Reuse the deployed HDMI supervisor unchanged; override generated config only."""
import argparse,importlib.util,sys
from pathlib import Path
def main():
    p=argparse.ArgumentParser(add_help=False);p.add_argument('--runtime',type=Path,required=True)
    p.add_argument('--confidence',type=float,default=.25);p.add_argument('--iou',type=float,default=.7)
    a,remaining=p.parse_known_args()
    if not 0<=a.confidence<=1 or not 0<=a.iou<=1:raise ValueError('INVALID_THRESHOLD')
    sys.path.insert(0,str(a.runtime))
    spec=importlib.util.spec_from_file_location('hdmi_supervisor',a.runtime/'run_system.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);original=module.atomic
    def atomic(path,value):
        if path.name=='config.json':
            if 'pipeline' in value:value['pipeline']['icore'].update(conf=a.confidence,iou_thresh=a.iou)
            elif 'model' in value:value['model'].update(conf=a.confidence,iou=a.iou)
        return original(path,value)
    module.atomic=atomic;sys.argv=[str(a.runtime/'run_system.py')]+remaining
    return module.main()
if __name__=='__main__':raise SystemExit(main())
