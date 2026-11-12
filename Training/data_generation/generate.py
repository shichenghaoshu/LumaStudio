from __future__ import annotations
import argparse
import json
from pathlib import Path
from Training.common import ROOT, NativeRenderer, atomic_json, check_rights, digest, read_jsonl
from Training.preprocessing.images import prepare_image
from Training.teachers.provider import NativeBaselineTeacher, HuggingFaceVisionTeacher

def generate(args):
    renderer = NativeRenderer(args.renderer)
    if args.teacher == "qwen-vl":
        teacher = HuggingFaceVisionTeacher(args.teacher_model, args.allow_download)
    elif args.teacher == "remote-vision":
        from Training.teachers.remote import RemoteVisionTeacher
        if not args.teacher_endpoint:raise ValueError("Provide an explicit training teacher endpoint")
        teacher=RemoteVisionTeacher(args.teacher_endpoint)
    else:
        teacher = NativeBaselineTeacher(renderer, args.model_package)
    args.output.mkdir(parents=True, exist_ok=False)
    records, failures = [], []
    for sample in read_jsonl(args.input):
        identifier = sample.get("sample_id", "invalid")
        try:
            image = check_rights(sample, args.base)
            analysis = renderer.analyze(image)
            student_prompt = renderer.call("prompt", image, sample["instruction"])["prompt"]
            directory = args.output / identifier
            prepared = prepare_image(image, directory / "preprocessed", renderer)
            recipe = teacher.propose(prepared, sample["instruction"], analysis)
            rounds = []
            for index in range(3):
                result = renderer.render(image, recipe, directory / f"round-{index}", sample["instruction"])
                rounds.append({"recipe": recipe, "result": result})
                if not result["evaluation"]["issues"] or index == 2:
                    break
                corrected = teacher.correct(recipe, result)
                if corrected == recipe:
                    break
                recipe = corrected
            chosen = rounds[-1]["result"]
            issues = chosen["evaluation"]["issues"]
            # This is a strict metric gate; aesthetics and human preference are never fabricated.
            accepted = not issues and chosen["originalPreserved"] is True
            record = {**sample, "image": str(image), "analysis": analysis, "scene": analysis["scene"], "student_prompt": student_prompt,
                      "teacher": teacher.name, "teacher_source": getattr(teacher, "last_source", teacher.name),
                      "teacher_fallback_reason": getattr(teacher, "last_fallback_reason", None),
                      "teacher_recipe": recipe, "rendered_result": chosen["renderedResult"],
                      "rendered_sha256": digest(Path(chosen["renderedResult"])),
                      "evaluation": teacher.evaluate(image, Path(chosen["renderedResult"]), chosen["evaluation"]),
                      "quality_tier": teacher.quality_tier, "accepted": accepted,
                      "eligible_for_student_training": bool(accepted and teacher.training_authorized),
                      "human_review": "NOT RUN", "user_preference": None, "rounds": rounds}
            atomic_json(directory / "sample.json", record)
            records.append(record)
        except Exception as error:
            failures.append({"sample_id": identifier, "error": str(error), "accepted": False})
    for filename, rows in [("records.jsonl", records), ("rejected.jsonl", [r for r in records if not r["accepted"]] + failures),
                           ("accepted-training.jsonl", [r for r in records if r["eligible_for_student_training"]])]:
        with (args.output / filename).open("w", encoding="utf-8") as stream:
            for row in rows:
                stream.write(json.dumps(row, ensure_ascii=False, allow_nan=False) + "\n")
    summary = {"teacher": teacher.name, "rendered_samples": len(records), "failed_samples": len(failures),
               "metric_gate_passed": sum(r["accepted"] for r in records),
               "eligible_training_samples": sum(r["eligible_for_student_training"] for r in records),
               "human_preference_labels": 0, "status": "completed"}
    atomic_json(args.output / "summary.json", summary)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 1 if failures else 0

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--input", type=Path, required=True)
    p.add_argument("--base", type=Path, default=ROOT)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--renderer", type=Path, default=ROOT / ".build/release/LumaAgentCLI")
    p.add_argument("--teacher", choices=["native-baseline", "qwen-vl", "remote-vision"], default="native-baseline")
    p.add_argument("--teacher-endpoint")
    p.add_argument("--model-package", type=Path)
    p.add_argument("--teacher-model", default="Qwen/Qwen2.5-VL-7B-Instruct")
    p.add_argument("--allow-download", action="store_true")
    raise SystemExit(generate(p.parse_args()))
if __name__ == "__main__":
    main()
