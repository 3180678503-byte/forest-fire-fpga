"""Bound service text logs only; never touch configs, models or command databases."""
from pathlib import Path
ROOT=Path('/home/work/esp32_remote_control_20261028/state')
for name,limit in [('link.jsonl',4*1024*1024),('runtime.log',8*1024*1024)]:
    path=ROOT/name
    if path.exists() and path.stat().st_size>limit:
        # Link log opens per line; runtime supervisor O_APPEND keeps writing after truncate.
        import shutil
        shutil.copyfile(path,path.with_suffix(path.suffix+'.1'))
        with path.open('wb') as stream:stream.truncate(0)
