from __future__ import annotations
import argparse
import json
import time
from pathlib import Path
from Training.common import atomic_json, digest, read_jsonl

def run(args):
    import torch
    from torch.utils.data import DataLoader, Dataset
    from accelerate import Accelerator
    from peft import LoraConfig, get_peft_model, PeftModel
    from transformers import AutoModelForCausalLM, AutoTokenizer, set_seed
    from Training.distillation.losses import masked_logit_distillation, FeatureProjection
    config = json.loads(args.config.read_text())
    if config.get("training_license_approved") is not True:
        raise ValueError("The selected candidate's training license has not been approved")
    if not torch.cuda.is_available() and not args.allow_mps:
        raise RuntimeError("No CUDA GPU detected. Use a GPU server; --allow-mps is an explicit research experiment")
    if args.allow_mps and not torch.cuda.is_available() and not torch.backends.mps.is_available():
        raise RuntimeError("Neither CUDA nor MPS is available")
    if args.output.exists():
        raise FileExistsError("Use a new output directory; existing checkpoints are preserved")
    set_seed(config["seed"])
    local_only = not args.allow_download
    tokenizer = AutoTokenizer.from_pretrained(config["base_model"], local_files_only=local_only, trust_remote_code=False)
    tokenizer.pad_token = tokenizer.pad_token or tokenizer.eos_token
    class CompletionDataset(Dataset):
        def __init__(self, path):
            self.rows = list(read_jsonl(path))
            if not self.rows:
                raise ValueError("Training/validation dataset is empty")
            if any(r.get("rights", {}).get("training_allowed") is not True for r in self.rows):
                raise ValueError("Dataset lacks image training authorization")
        def __len__(self): return len(self.rows)
        def __getitem__(self, index):
            row = self.rows[index]
            prefix = tokenizer.encode(row["prompt"], add_special_tokens=False)
            target = tokenizer.encode(row["completion"] + tokenizer.eos_token, add_special_tokens=False)
            if len(prefix) + len(target) > config["max_length"]:
                raise ValueError("Sample exceeds context budget; never truncate a structured JSON target")
            return {"input_ids": prefix + target, "labels": [-100] * len(prefix) + target}
    def collate(rows):
        length = max(len(r["input_ids"]) for r in rows)
        ids = [r["input_ids"] + [tokenizer.pad_token_id] * (length-len(r["input_ids"])) for r in rows]
        labels = [r["labels"] + [-100] * (length-len(r["labels"])) for r in rows]
        attention = [[1] * len(r["input_ids"]) + [0] * (length-len(r["input_ids"])) for r in rows]
        return {"input_ids":torch.tensor(ids), "labels":torch.tensor(labels), "attention_mask":torch.tensor(attention)}
    train = CompletionDataset(args.data / "train.jsonl");validation = CompletionDataset(args.data / "validation.jsonl")
    if {r["image_sha256"] for r in train.rows} & {r["image_sha256"] for r in validation.rows}:
        raise ValueError("The same original appears in training and validation")
    precision = config["precision"] if torch.cuda.is_available() else "no"
    accelerator = Accelerator(gradient_accumulation_steps=config["gradient_accumulation_steps"], mixed_precision=precision, log_with=None)
    dtype = torch.bfloat16 if precision=="bf16" else torch.float16 if precision=="fp16" else torch.float32
    model = AutoModelForCausalLM.from_pretrained(config["base_model"], torch_dtype=dtype, local_files_only=local_only, trust_remote_code=False)
    model.config.use_cache = False
    if args.resume:
        model = PeftModel.from_pretrained(model, args.resume, is_trainable=True)
    else:
        model = get_peft_model(model, LoraConfig(r=config["lora_rank"], lora_alpha=config["lora_alpha"], lora_dropout=0.05,
                    target_modules=config["target_modules"], task_type="CAUSAL_LM"))
    model.enable_input_require_grads();model.gradient_checkpointing_enable()
    teacher = projection = None
    if args.teacher:
        if not torch.cuda.is_available():
            raise RuntimeError("Online logit/feature distillation requires the configured CUDA server budget")
        teacher_tokenizer = AutoTokenizer.from_pretrained(args.teacher, local_files_only=local_only, trust_remote_code=False)
        if teacher_tokenizer.get_vocab() != tokenizer.get_vocab():
            raise ValueError("Different vocabularies: use response/tool trajectory distillation instead of logit alignment")
        teacher = AutoModelForCausalLM.from_pretrained(args.teacher, torch_dtype=dtype, local_files_only=local_only, trust_remote_code=False).eval()
        teacher.requires_grad_(False)
        teacher = accelerator.prepare_model(teacher, evaluation_mode=True)
        if args.feature_weight:
            projection = FeatureProjection(model.config.hidden_size, teacher.config.hidden_size)
    parameters = [p for p in model.parameters() if p.requires_grad] + (list(projection.parameters()) if projection else [])
    optimizer = torch.optim.AdamW(parameters, lr=config["learning_rate"])
    loader = DataLoader(train, batch_size=config["batch_size"], shuffle=True, collate_fn=collate)
    val_loader = DataLoader(validation, batch_size=1, collate_fn=collate)
    if projection:
        model, projection, optimizer, loader, val_loader = accelerator.prepare(model, projection, optimizer, loader, val_loader)
    else:
        model, optimizer, loader, val_loader = accelerator.prepare(model, optimizer, loader, val_loader)
    start=time.monotonic();steps=0;losses=[]
    model.train();optimizer.zero_grad()
    for epoch in range(config["epochs"]):
        for batch in loader:
            with accelerator.accumulate(model, *([projection] if projection else [])):
                outputs=model(**batch, output_hidden_states=bool(projection))
                loss=outputs.loss
                if teacher:
                    with torch.no_grad(): reference=teacher(input_ids=batch["input_ids"],attention_mask=batch["attention_mask"],output_hidden_states=bool(projection))
                    loss=loss+args.logit_weight*masked_logit_distillation(outputs.logits,reference.logits,batch["labels"])
                    if projection: loss=loss+args.feature_weight*projection(outputs.hidden_states[-1],reference.hidden_states[-1],batch["labels"])
                if not torch.isfinite(loss): raise RuntimeError("Non-finite loss; checkpoint was not published")
                accelerator.backward(loss)
                if accelerator.sync_gradients: accelerator.clip_grad_norm_(parameters,1.0)
                optimizer.step();optimizer.zero_grad()
            losses.append(float(loss.detach()));steps += int(accelerator.sync_gradients)
            if args.max_steps and steps>=args.max_steps:break
        if args.max_steps and steps>=args.max_steps:break
    if steps<1:raise RuntimeError("No optimizer step completed")
    model.eval();validation_losses=[]
    with torch.inference_mode():
        for batch in val_loader:
            validation_losses.append(accelerator.gather_for_metrics(model(**batch).loss.detach().reshape(1)))
    accelerator.wait_for_everyone()
    if accelerator.is_main_process:
        args.output.mkdir(parents=True,exist_ok=False)
        accelerator.unwrap_model(model).save_pretrained(args.output,safe_serialization=True)
        tokenizer.save_pretrained(args.output)
        if projection:torch.save(accelerator.unwrap_model(projection).state_dict(),args.output/"feature-projection.pt")
        atomic_json(args.output/"training-report.json",{"status":"completed","config":config,"optimizer_steps":steps,
                    "train_loss_last":losses[-1],"validation_loss":float(torch.cat(validation_losses).mean()),
                    "elapsed_seconds":time.monotonic()-start,"device":str(accelerator.device),"train_sha256":digest(args.data/"train.jsonl"),
                    "validation_sha256":digest(args.data/"validation.jsonl"),"torch_version":torch.__version__,
                    "peak_cuda_bytes":torch.cuda.max_memory_allocated() if torch.cuda.is_available() else None,
                    "online_distillation_teacher":args.teacher,"human_visual_quality":"NOT RUN"})

if __name__ == "__main__":
    p=argparse.ArgumentParser();p.add_argument("--config",type=Path,required=True);p.add_argument("--data",type=Path,required=True);p.add_argument("--output",type=Path,required=True)
    p.add_argument("--resume");p.add_argument("--teacher");p.add_argument("--logit-weight",type=float,default=.5);p.add_argument("--feature-weight",type=float,default=0)
    p.add_argument("--allow-download",action="store_true");p.add_argument("--allow-mps",action="store_true");p.add_argument("--max-steps",type=int)
    run(p.parse_args())
