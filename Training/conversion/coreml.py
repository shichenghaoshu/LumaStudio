import argparse
import json
from pathlib import Path
from Training.common import atomic_json,digest

def convert(args):
    import numpy as np
    import torch
    import coremltools as ct
    if args.role=="editAgent":
        raise ValueError("Generic text LLM conversion is not implemented or certified. Use the native llama.cpp GGUF runner; stateful Core ML needs a model-specific KV-cache export.")
    if args.output.exists():raise FileExistsError(args.output)
    report=json.loads(args.training_report.read_text())
    if report.get("status")!="completed":raise ValueError("A completed specialist training report is required")
    model=torch.jit.load(str(args.model),map_location="cpu").eval()
    if args.role=="evaluator":
        inputs=[ct.TensorType(name="metrics",shape=(1,16),dtype=np.float32)]
        outputs=[ct.TensorType(name="failureProbabilities")]
    else:
        inputs=[ct.ImageType(name="image",shape=(1,3,args.size,args.size),scale=1/255,color_layout=ct.colorlayout.RGB)]
        outputs=[ct.ImageType(name="skinProbability",color_layout=ct.colorlayout.GRAYSCALE_FLOAT16)] if args.role=="beauty" else [ct.TensorType(name="maskProbabilities")]
    # FP16 ML Program is the specialist baseline. Quantization happens only after parity checks.
    converted=ct.convert(model,inputs=inputs,outputs=outputs,convert_to="mlprogram",compute_precision=ct.precision.FLOAT16,
                         minimum_deployment_target=ct.target.macOS14)
    converted.author="LumaStudio";converted.short_description=f"Locally trained {args.role}; inspect accompanying training report"
    converted.save(str(args.output))
    atomic_json(args.output.with_suffix(".conversion.json"),{"status":"converted_not_accepted","role":args.role,"output_schema":"LumaStudio skin-probability v1" if args.role=="beauty" else "specialist runtime adapter pending","training_report_sha256":digest(args.training_report),"source_sha256":digest(args.model),"coremltools":ct.__version__,"precision":"FP16","numerical_parity":"NOT RUN","physical_device_performance":"NOT RUN"})

if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--model",type=Path,required=True);p.add_argument("--training-report",type=Path,required=True);p.add_argument("--role",choices=["editAgent","vision","beauty","evaluator"],required=True);p.add_argument("--output",type=Path,required=True);p.add_argument("--size",type=int,default=256);convert(p.parse_args())
