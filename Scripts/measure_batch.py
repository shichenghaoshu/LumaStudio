#!/usr/bin/env python3
"""Development-only runner; the application has no Python dependency."""
import subprocess, time, json, sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
out=root/'Artifacts'/'Stress100';out.mkdir(parents=True,exist_ok=True)
with (out/'run.log').open('w') as log:
    p=subprocess.Popen([str(root/'.build/release/LumaDiagnostics'),'benchmark',str(root/'work/fixtures/G9-3219.RW2'),str(out),'100'],stdout=log,stderr=subprocess.STDOUT)
    samples=[];start=time.monotonic()
    while p.poll() is None:
        r=subprocess.run(['ps','-o','rss=','-p',str(p.pid)],capture_output=True,text=True)
        try: samples.append({'seconds':round(time.monotonic()-start,2),'rssMB':int(r.stdout.strip())/1024})
        except ValueError: pass
        time.sleep(1)
    (out/'memory.json').write_text(json.dumps({'exitCode':p.returncode,'samples':samples},indent=2))
    print('batch exit',p.returncode,'elapsed',round(time.monotonic()-start,2),'samples',len(samples),'peak RSS MB',round(max((v['rssMB'] for v in samples),default=0),2))
    sys.exit(p.returncode)
