from __future__ import annotations
import argparse
from pathlib import Path
from Training.common import digest, read_jsonl, validate_recipe, atomic_json

def run(args):
    import json
    import torch
    from datasets import Dataset
    from transformers import AutoModelForCausalLM, AutoTokenizer
    from peft import PeftModel
    from trl import DPOConfig, DPOTrainer
    if not torch.cuda.is_available():
        raise RuntimeError("DPO is configured for the GPU training server")
    if args.output.exists():
        raise FileExistsError(args.output)
    config=json.loads(args.config.read_text())
    if config.get("training_license_approved") is not True:raise ValueError("Unapproved candidate license")
    rows=[]
    for row in read_jsonl(args.data):
        if row.get("human_review")!="completed" or not row.get("reviewer_id"):
            raise ValueError("DPO requires actual local human preference labels")
        if row.get("rights",{}).get("training_allowed") is not True:raise ValueError("Missing authorization")
        for key in ["chosen","rejected"]:
            validate_recipe(row[key+"_recipe"])
            if digest(Path(row[key+"_image"]))!=row[key+"_sha256"]:raise ValueError("Preference image hash mismatch")
        rows.append({"prompt":row["student_prompt"],"chosen":json.dumps(row["chosen_recipe"],separators=(",",":")),"rejected":json.dumps(row["rejected_recipe"],separators=(",",":"))})
    if not rows:raise ValueError("No human-labeled preference pairs")
    tokenizer=AutoTokenizer.from_pretrained(config["base_model"],local_files_only=not args.allow_download,trust_remote_code=False)
    tokenizer.pad_token=tokenizer.pad_token or tokenizer.eos_token
    model=AutoModelForCausalLM.from_pretrained(config["base_model"],torch_dtype=torch.bfloat16,local_files_only=not args.allow_download,trust_remote_code=False)
    model=PeftModel.from_pretrained(model,args.sft_adapter,is_trainable=True)
    # TRL uses adapter-disabled reference behavior for a PEFT model. Keep an SFT reference adapter
    # so the preference reference is the actual SFT policy, rather than the original base weights.
    model.load_adapter(args.sft_adapter,adapter_name="reference",is_trainable=False)
    trainer=DPOTrainer(model=model,ref_model=None,processing_class=tokenizer,train_dataset=Dataset.from_list(rows),
        args=DPOConfig(output_dir=str(args.output),num_train_epochs=1,per_device_train_batch_size=1,
            gradient_accumulation_steps=8,learning_rate=5e-6,beta=.1,bf16=True,max_length=4096,
            report_to=[],model_adapter_name="default",ref_adapter_name="reference"))
    result=trainer.train();trainer.save_model(str(args.output));tokenizer.save_pretrained(args.output)
    atomic_json(args.output/"preference-report.json",{"status":"completed","pairs":len(rows),"data_sha256":digest(args.data),"metrics":result.metrics,"reference":"frozen SFT reference adapter","human_visual_quality_after_training":"NOT RUN"})

if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--config",type=Path,required=True);p.add_argument("--sft-adapter",required=True);p.add_argument("--data",type=Path,required=True);p.add_argument("--output",type=Path,required=True);p.add_argument("--allow-download",action="store_true")
    run(p.parse_args())
