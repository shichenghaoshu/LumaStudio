from __future__ import annotations
import argparse
from pathlib import Path
from Training.common import check_rights, read_jsonl, atomic_json, digest

def run(args):
    import numpy as np
    import torch
    from PIL import Image
    from torch.utils.data import Dataset,DataLoader
    from Training.vision.models import SegmentationUNet,ProbabilityOutput
    if args.output.exists():raise FileExistsError(args.output)
    rows=list(read_jsonl(args.data))
    if not rows:raise ValueError("No authorized, manually labeled mask data")
    kinds=["skin"] if args.role=="beauty" else ["skin","hair","sky","subject"]
    # Vision and beauty models are trained independently; no random model is published.
    class Masks(Dataset):
        def __len__(self):return len(rows)
        def __getitem__(self,i):
            row=rows[i];path=check_rights(row,args.base)
            with Image.open(path) as opened:image=np.array(opened.convert("RGB").resize((args.size,args.size)),dtype=np.float32)/255
            masks=[]
            for kind in kinds:
                annotation=row.get("masks",{}).get(kind)
                if not annotation or annotation.get("human_verified") is not True:raise ValueError("Each specialist channel requires a verified annotation")
                mask=(args.base/annotation["path"]).resolve()
                if digest(mask)!=annotation["sha256"]:raise ValueError("Mask annotation changed")
                with Image.open(mask) as opened:masks.append(np.array(opened.convert("L").resize((args.size,args.size),Image.Resampling.NEAREST),dtype=np.float32)/255)
            return torch.from_numpy(image.transpose(2,0,1)),torch.from_numpy(np.stack(masks))
    torch.manual_seed(20261110)
    device="cuda" if torch.cuda.is_available() else "mps" if args.allow_mps and torch.backends.mps.is_available() else "cpu"
    if device=="cpu" and not args.allow_cpu:raise RuntimeError("No GPU available; pass --allow-cpu for a deliberate small research run")
    model=SegmentationUNet(channels=len(kinds)).to(device);optimizer=torch.optim.AdamW(model.parameters(),lr=1e-4)
    losses=[];model.train()
    for epoch in range(args.epochs):
        for image,target in DataLoader(Masks(),batch_size=1,shuffle=True):
            image,target=image.to(device),target.to(device);logits=model(image)
            loss=torch.nn.functional.binary_cross_entropy_with_logits(logits,target)
            if not torch.isfinite(loss):raise RuntimeError("Non-finite segmentation loss")
            optimizer.zero_grad();loss.backward();optimizer.step();losses.append(float(loss.detach()))
    if not losses:raise RuntimeError("No training step executed")
    args.output.mkdir(parents=True)
    torch.save(model.cpu().state_dict(),args.output/"weights.pt")
    model.eval();torch.jit.trace(ProbabilityOutput(model),torch.zeros(1,3,args.size,args.size)).save(str(args.output/"model.ts"))
    atomic_json(args.output/"training-report.json",{"status":"completed","role":args.role,"channels":kinds,"steps":len(losses),"last_loss":losses[-1],"device":device,"data_sha256":digest(args.data),"parameters":sum(p.numel() for p in model.parameters()),"held_out_accuracy":"NOT RUN","visual_quality":"NOT RUN"})

if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--data",type=Path,required=True);p.add_argument("--base",type=Path,required=True);p.add_argument("--output",type=Path,required=True);p.add_argument("--role",choices=["vision","beauty"],required=True);p.add_argument("--epochs",type=int,default=10);p.add_argument("--size",type=int,default=256);p.add_argument("--allow-mps",action="store_true");p.add_argument("--allow-cpu",action="store_true")
    run(p.parse_args())
