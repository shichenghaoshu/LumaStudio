from __future__ import annotations
import argparse
from pathlib import Path
from Training.common import atomic_json,digest,read_jsonl

def run(args):
    import torch
    from torch import nn
    rows=list(read_jsonl(args.data))
    if not rows or any(r.get("human_review")!="completed" for r in rows):raise ValueError("Evaluator training requires real human quality labels")
    if args.output.exists():raise FileExistsError(args.output)
    features=torch.tensor([r["features"] for r in rows],dtype=torch.float32)
    targets=torch.tensor([r["failure_labels"] for r in rows],dtype=torch.float32)
    if features.ndim!=2 or features.shape[1]!=16 or targets.shape!=(len(rows),5):raise ValueError("Expected 16 deterministic features and 5 human failure labels")
    if not torch.isfinite(features).all() or not ((targets>=0)&(targets<=1)).all():raise ValueError("Invalid evaluator training data")
    torch.manual_seed(20261110);model=nn.Sequential(nn.Linear(16,64),nn.SiLU(),nn.Linear(64,32),nn.SiLU(),nn.Linear(32,5));optimizer=torch.optim.AdamW(model.parameters(),lr=1e-3)
    for _ in range(args.steps):
        loss=torch.nn.functional.binary_cross_entropy_with_logits(model(features),targets);optimizer.zero_grad();loss.backward();optimizer.step()
    if args.steps<1:raise ValueError("No optimizer steps requested")
    args.output.mkdir(parents=True);model.eval()
    torch.save(model.state_dict(),args.output/"weights.pt")
    torch.jit.trace(nn.Sequential(model,nn.Sigmoid()),torch.zeros(1,16)).save(str(args.output/"model.ts"))
    atomic_json(args.output/"training-report.json",{"status":"completed","rows":len(rows),"steps":args.steps,"last_loss":float(loss.detach()),"data_sha256":digest(args.data),"held_out_accuracy":"NOT RUN","role":"evaluator","failure_labels":["exposure","skin_color","over_smoothing","edge_artifact","instruction_mismatch"]})

if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--data",type=Path,required=True);p.add_argument("--output",type=Path,required=True);p.add_argument("--steps",type=int,default=300);run(p.parse_args())
