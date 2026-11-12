from __future__ import annotations
import argparse
import json
import time
from pathlib import Path
from Training.common import NativeRenderer,atomic_json,digest,read_jsonl

def run(args):
    renderer=NativeRenderer(args.renderer);args.output.mkdir(parents=True,exist_ok=False)
    rows=[]
    for i,case in enumerate(read_jsonl(args.cases)):
        image=(args.base/case["image"]).resolve()
        if not image.is_file():raise ValueError("Missing benchmark photograph")
        start=time.monotonic()
        output=renderer.call("run",image,case["instruction"],args.output/f"case-{i:03}",args.model_package or "--rules")
        record={"case":case,"wall_seconds":time.monotonic()-start,"original_sha256":digest(image),"output":output}
        if args.model_package and output["run"]["source"]=="本地规则 + Vision":record["model_execution"]="FALLBACK"
        else:record["model_execution"]="model" if args.model_package else "rules"
        rows.append(record)
    atomic_json(args.output/"benchmark.json",{"device":renderer.call("device"),"cases":rows,"physical_device":"current Mac only","trained_student":"NOT RUN","subjective_quality":"NOT RUN","network_dependency":"native local execution; no network API invoked"})
    print(json.dumps({"cases":len(rows),"fallbacks":sum(r["model_execution"]=="FALLBACK" for r in rows)},ensure_ascii=False))

if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--renderer",type=Path,required=True);p.add_argument("--cases",type=Path,required=True);p.add_argument("--base",type=Path,default=Path.cwd());p.add_argument("--output",type=Path,required=True);p.add_argument("--model-package",type=Path);run(p.parse_args())
