import argparse
import json
import subprocess
import sys
from pathlib import Path
from Training.common import atomic_json,digest

def convert(args):
    if args.output.exists():raise FileExistsError(args.output)
    args.output.mkdir(parents=True)
    converter=args.llama_cpp/"convert_hf_to_gguf.py"
    if not converter.is_file() or not (args.model/"merge-report.json").is_file():
        raise ValueError("Provide llama.cpp source and a merged trained model")
    outputs=[]
    for precision in ["f16","bf16"]:
        target=args.output/(precision+".gguf")
        subprocess.run([sys.executable,str(converter),str(args.model),"--outfile",str(target),"--outtype",precision],check=True)
        outputs.append({"precision":precision,"path":str(target),"bytes":target.stat().st_size,"sha256":digest(target)})
    for precision in ["Q8_0","Q4_K_M"]:
        target=args.output/(precision+".gguf")
        subprocess.run([str(args.quantizer),str(args.output/"f16.gguf"),str(target),precision],check=True)
        outputs.append({"precision":precision,"path":str(target),"bytes":target.stat().st_size,"sha256":digest(target)})
    atomic_json(args.output/"quantization-report.json",{"status":"completed","models":outputs,"parameter_accuracy":"NOT RUN","memory_and_latency":"NOT RUN","visual_quality":"NOT RUN","selection":"Not selected until measured on the same held-out tasks"})

if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--model",type=Path,required=True);p.add_argument("--llama-cpp",type=Path,required=True);p.add_argument("--quantizer",type=Path,required=True);p.add_argument("--output",type=Path,required=True);convert(p.parse_args())
