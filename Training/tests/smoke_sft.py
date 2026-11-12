"""Exercise the real SFT entry point on a tiny synthetic model; never a product model."""
import argparse
import json
import subprocess
import sys
from pathlib import Path
from Training.common import atomic_json

def main(args):
    from tokenizers import Tokenizer,models,pre_tokenizers,trainers,decoders
    from transformers import PreTrainedTokenizerFast,Qwen2Config,Qwen2ForCausalLM
    import torch
    if args.output.exists():raise FileExistsError(args.output)
    args.output.mkdir(parents=True)
    base=args.output/"tiny-random-base";base.mkdir()
    prompts=["synthetic unit test brighten", "synthetic unit test darken"]
    completions=['{"version":1,"exposure":0.3}','{"version":1,"exposure":-0.3}']
    tokenizer=Tokenizer(models.BPE(unk_token="[UNK]"));tokenizer.pre_tokenizer=pre_tokenizers.ByteLevel(add_prefix_space=False);tokenizer.decoder=decoders.ByteLevel()
    tokenizer.train_from_iterator(prompts+completions,trainers.BpeTrainer(vocab_size=256,special_tokens=["[UNK]","[PAD]","[EOS]"]))
    fast=PreTrainedTokenizerFast(tokenizer_object=tokenizer,unk_token="[UNK]",pad_token="[PAD]",eos_token="[EOS]")
    fast.save_pretrained(base)
    torch.manual_seed(7)
    config=Qwen2Config(vocab_size=len(fast),hidden_size=32,intermediate_size=64,num_hidden_layers=1,num_attention_heads=4,num_key_value_heads=2,max_position_embeddings=256,
                       eos_token_id=fast.eos_token_id,pad_token_id=fast.pad_token_id)
    Qwen2ForCausalLM(config).save_pretrained(base,safe_serialization=True)
    data=args.output/"synthetic-data";data.mkdir()
    for name in ["train","validation"]:
        rows=[{"sample_id":f"TEST_ONLY_{name}_{i}","image_sha256":name+str(i),"rights":{"training_allowed":True,"license":"synthetic unit-test fixture"},"prompt":prompt,"completion":completions[i]} for i,prompt in enumerate(prompts)]
        (data/f"{name}.jsonl").write_text("".join(json.dumps(r)+"\n" for r in rows))
    settings={"seed":7,"training_license_approved":True,"base_model":str(base),"precision":"no","max_length":256,"batch_size":1,"gradient_accumulation_steps":1,"lora_rank":4,"lora_alpha":8,"target_modules":["q_proj","v_proj"],"learning_rate":.001,"epochs":1,"purpose":"TEST ONLY: randomly initialized tiny model and synthetic text; not a LumaStudio Student"}
    atomic_json(args.output/"config.json",settings)
    subprocess.run([sys.executable,"-m","Training.sft.train","--config",str(args.output/"config.json"),"--data",str(data),"--output",str(args.output/"test-adapter"),"--allow-mps","--max-steps","2"],check=True)
    report=json.loads((args.output/"test-adapter/training-report.json").read_text())
    assert report["optimizer_steps"]==2
    atomic_json(args.output/"SMOKE-RESULT.json",{"status":"passed","purpose":settings["purpose"],"optimizer_steps":2,"device":report["device"],"product_models_trained":0,"professional_quality":"NOT RUN"})
    print(json.dumps(json.loads((args.output/"SMOKE-RESULT.json").read_text()),indent=2))

if __name__=="__main__":
    parser=argparse.ArgumentParser();parser.add_argument("--output",type=Path,required=True);main(parser.parse_args())
