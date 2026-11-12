from __future__ import annotations
from abc import ABC, abstractmethod
import json
from pathlib import Path
from Training.common import NativeRenderer, SCHEMA, validate_recipe

class TeacherProvider(ABC):
    name: str
    training_authorized: bool = False
    quality_tier: str = "unreviewed"

    @abstractmethod
    def propose(self, image: Path, instruction: str, analysis: dict) -> dict:
        """Return EditRecipe parameters. The teacher never executes pixels."""

    def evaluate(self, original: Path, rendered: Path, report: dict) -> dict:
        return {"native_metrics": report, "semantic_evaluation": "NOT RUN"}

    def correct(self, recipe: dict, report: dict) -> dict:
        return report["correctedRecipe"]

class NativeBaselineTeacher(TeacherProvider):
    """A reproducible workflow baseline, explicitly ineligible as professional distillation data."""
    quality_tier = "workflow_baseline"
    def __init__(self, renderer: NativeRenderer, model_package: Path | None = None):
        self.renderer = renderer
        self.package = model_package
        self.name = "native-base-model" if model_package else "native-rule-baseline"

    def propose(self, image, instruction, analysis):
        result = self.renderer.call("plan", image, instruction, self.package or "--rules")
        self.last_source = result["source"]
        self.last_fallback_reason = result.get("fallbackReason")
        return result["recipe"]

class HuggingFaceVisionTeacher(TeacherProvider):
    name = "qwen25-vl-7b"
    training_authorized = True
    quality_tier = "teacher_candidate"
    def __init__(self, model_path: str, allow_download: bool = False):
        import torch
        from transformers import AutoProcessor, Qwen2_5_VLForConditionalGeneration
        # This adapter is for the Apache-2.0 Qwen VL teacher; no JarvisArt weights/code/output.
        if model_path != "Qwen/Qwen2.5-VL-7B-Instruct" and not Path(model_path).is_dir():
            raise ValueError("Use the documented Qwen teacher or an audited local model directory")
        self.processor = AutoProcessor.from_pretrained(model_path, local_files_only=not allow_download, trust_remote_code=False)
        self.model = Qwen2_5_VLForConditionalGeneration.from_pretrained(
            model_path, torch_dtype="auto", device_map="auto", local_files_only=not allow_download,
            trust_remote_code=False).eval()

    def propose(self, image, instruction, analysis):
        import torch
        from PIL import Image
        prompt = "Generate only EditRecipe v1 JSON. No markdown. Available masks: face,skin,subject,background.\n" + SCHEMA.read_text() + "\nScene metrics:" + json.dumps(analysis) + "\nInstruction:" + instruction
        messages = [{"role": "user", "content": [{"type": "image", "image": str(image)}, {"type": "text", "text": prompt}]}]
        text = self.processor.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
        with Image.open(image) as opened:
            inputs = self.processor(text=[text], images=[opened.convert("RGB")], return_tensors="pt").to(self.model.device)
        with torch.inference_mode():
            output = self.model.generate(**inputs, max_new_tokens=1400, do_sample=False)
        completion = self.processor.batch_decode(output[:, inputs.input_ids.shape[1]:], skip_special_tokens=True)[0].strip()
        recipe = json.loads(completion)
        validate_recipe(recipe)
        return recipe
