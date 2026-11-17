"""Run inside the community container; creates consistent, owner-only DB backups."""
import sqlite3,gzip,os,time
from pathlib import Path
root=Path('/data/backups');root.mkdir(mode=0o700,exist_ok=True)
name='community-'+time.strftime('%Y%m%d-%H%M%S',time.gmtime());temp=root/(name+'.sqlite3')
with sqlite3.connect('file:/data/community.sqlite3?mode=ro',uri=True) as source:
 with sqlite3.connect(temp) as target:source.backup(target)
os.chmod(temp,0o600)
packed=root/(name+'.sqlite3.gz')
with temp.open('rb') as src,gzip.open(packed,'wb') as dest:
 import shutil;shutil.copyfileobj(src,dest)
os.chmod(packed,0o600);temp.unlink()
for stale in sorted(root.glob('community-????????-??????.sqlite3.gz'),reverse=True)[7:]:stale.unlink()
print('Consistent community backup completed')
