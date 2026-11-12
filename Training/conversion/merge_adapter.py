import argparse
import json
from pathlib import Path
from Training.common import atomic_json,digest

def merge(args):
    import torch
    from transformers import AutoModelForCausalLM,AutoTokenizer
    from peft import PeftModel
    if args.output.exists():raise FileExistsError(args.output)
    report_path=args.adapter/"training-report.json"
    if not report_path.exists():report_path=args.adapter/"preference-report.json"
    report=json.loads(report_path.read_text())
    if report.get("status")!="completed":raise ValueError("Adapter is not from a completed training run")
    model=AutoModelForCausalLM.from_pretrained(args.base,torch_dtype=torch.float16,device_map="cpu",local_files_only=not args.allow_download,trust_remote_code=False)
    model=PeftModel.from_pretrained(model,str(args.adapter));model=model.merge_and_unload(safe_merge=True)
    model.save_pretrained(args.output,safe_serialization=True)
    AutoTokenizer.from_pretrained(str(args.adapter),local_files_only=True).save_pretrained(args.output)
    atomic_json(args.output/"merge-report.json",{"status":"completed","base":args.base,"training_report_sha256":digest(report_path),"precision":"FP16","visual_quality":"NOT RUN"})

if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--base",required=True);p.add_argument("--adapter",type=Path,required=True);p.add_argument("--output",type=Path,required=True);p.add_argument("--allow-download",action="store_true");merge(p.parse_args())
