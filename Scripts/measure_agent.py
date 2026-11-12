#!/usr/bin/env python3
"""Measure an actual native Agent run with per-process network denied and RSS samples."""
import argparse
import json
import subprocess
import time
from pathlib import Path

def main(args):
    args.output.mkdir(parents=True,exist_ok=False)
    command=[str(args.executable.resolve()),"run",str(args.image.resolve()),args.instruction,str((args.output/"render").resolve()),str(args.model_package.resolve())]
    isolated=["/usr/bin/sandbox-exec","-p","(version 1) (allow default) (deny network*)",*command]
    started=time.monotonic();samples=[]
    with (args.output/"stdout.json").open("w") as stdout,(args.output/"stderr.log").open("w") as stderr:
        process=subprocess.Popen(isolated,stdout=stdout,stderr=stderr)
        while process.poll() is None:
            status=subprocess.run(["/bin/ps","-o","rss=","-p",str(process.pid)],capture_output=True,text=True)
            if status.returncode==0 and status.stdout.strip():samples.append({"seconds":time.monotonic()-started,"rss_bytes":int(status.stdout.strip())*1024})
            time.sleep(.2)
    report={"exit_code":process.returncode,"wall_seconds":time.monotonic()-started,"network_policy":"deny network* for the native process", "peak_sampled_rss_bytes":max((r["rss_bytes"] for r in samples),default=None),"rss_samples":samples,"gpu_utilization":"NOT MEASURED","ane_utilization":"NOT MEASURED"}
    if process.returncode==0:
        result=json.loads((args.output/"stdout.json").read_text());run=result["run"]
        selected=run["rounds"][run["selectedRound"]]
        report.update(source=run["source"],fallback_reason=run.get("fallbackReason"),planning_milliseconds=run["planningMilliseconds"],rounds=len(run["rounds"]),selected_round=run["selectedRound"],selected_evaluation=selected["evaluation"],selected_recipe=selected["recipe"],original_preserved=result["originalPreserved"])
    (args.output/"measurement.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
    print(json.dumps({k:v for k,v in report.items() if k not in ["rss_samples","selected_evaluation","selected_recipe"]},ensure_ascii=False,indent=2))
    raise SystemExit(process.returncode)

if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--executable",type=Path,required=True);p.add_argument("--image",type=Path,required=True);p.add_argument("--instruction",required=True);p.add_argument("--model-package",type=Path,required=True);p.add_argument("--output",type=Path,required=True);main(p.parse_args())
