import argparse
import json
import shutil
from pathlib import Path
from Training.common import atomic_json,digest

def package(args):
    metadata=json.loads(args.metadata.read_text())
    required=["id","version","role","displayName","license","licenseURL","source","minimumMemoryGB","precision","inputSchema","outputSchema","trainingStatus","benchmarks"]
    if any(k not in metadata for k in required):raise ValueError("Incomplete model metadata")
    if args.model.suffix not in [".gguf",".mlmodel",".mlpackage"]:raise ValueError("Use GGUF, mlmodel or mlpackage")
    if args.output.exists():raise FileExistsError(args.output)
    if not args.license_file.is_file():raise ValueError("Include the actual model license")
    args.output.mkdir(parents=True)
    filename="agent.gguf" if args.model.suffix==".gguf" else "specialist"+args.model.suffix
    if args.model.is_dir():shutil.copytree(args.model,args.output/filename,symlinks=True)
    else:shutil.copy2(args.model,args.output/filename)
    shutil.copy2(args.license_file,args.output/"LICENSE.txt")
    size=sum(p.stat().st_size for p in args.model.rglob("*") if p.is_file()) if args.model.is_dir() else args.model.stat().st_size
    metadata.update({"filename":filename,"sha256":digest(args.output/filename),"bytes":size,"platform":["macOS"],"format":args.model.suffix[1:]})
    atomic_json(args.output/"manifest.json",metadata)
    print(args.output)

if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--model",type=Path,required=True);p.add_argument("--metadata",type=Path,required=True);p.add_argument("--license-file",type=Path,required=True);p.add_argument("--output",type=Path,required=True);package(p.parse_args())
