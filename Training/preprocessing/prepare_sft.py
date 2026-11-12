from __future__ import annotations
import argparse
import json
import random
from pathlib import Path
from Training.common import atomic_json, digest, read_jsonl, validate_recipe

def prepare(input_path: Path, output: Path, seed=20261110, validation_fraction=0.2):
    records = []
    for row in read_jsonl(input_path):
        if row.get("accepted") is not True or row.get("eligible_for_student_training") is not True:
            raise ValueError("Only rendered, accepted, authorized teacher samples may enter SFT")
        if row.get("rights", {}).get("training_allowed") is not True:
            raise ValueError("Missing training authorization")
        rendered = Path(row["rendered_result"])
        if not rendered.is_file() or digest(rendered) != row["rendered_sha256"]:
            raise ValueError("Rendered image is missing or modified")
        if not row.get("student_prompt"):
            raise ValueError("Use the exact native student prompt from LumaAgentCLI")
        validate_recipe(row["teacher_recipe"])
        records.append({"sample_id": row["sample_id"], "image_sha256": row["rights"]["sha256"],
                        "prompt": row["student_prompt"],
                        "completion": json.dumps(row["teacher_recipe"], ensure_ascii=False, separators=(",", ":")),
                        "teacher": row["teacher"], "rights": row["rights"]})
    groups = sorted({r["image_sha256"] for r in records})
    if len(groups) < 2:
        raise ValueError("At least two distinct authorized images are required for a disjoint validation split")
    random.Random(seed).shuffle(groups)
    count = min(len(groups) - 1, max(1, round(len(groups) * validation_fraction)))
    validation = set(groups[:count])
    output.mkdir(parents=True, exist_ok=False)
    counts = {}
    for name, wanted in [("train", False), ("validation", True)]:
        rows = [r for r in records if (r["image_sha256"] in validation) == wanted]
        (output / f"{name}.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
        counts[name] = len(rows)
    atomic_json(output / "split.json", {"seed": seed, "group_by": "original_sha256", "distinct_images": len(groups), "counts": counts, "source_sha256": digest(input_path)})
    return counts

if __name__ == "__main__":
    p = argparse.ArgumentParser();p.add_argument("--input", type=Path, required=True);p.add_argument("--output", type=Path, required=True);p.add_argument("--seed", type=int, default=20261110)
    args = p.parse_args();print(prepare(args.input, args.output, args.seed))
