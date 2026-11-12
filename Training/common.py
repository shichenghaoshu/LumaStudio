from __future__ import annotations
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "Packages/PhotoDomain/Sources/Resources/edit-recipe.schema.json"

def read_jsonl(path: Path):
    with path.open(encoding="utf-8") as stream:
        for number, line in enumerate(stream, 1):
            if line.strip():
                try:
                    yield json.loads(line)
                except json.JSONDecodeError as error:
                    raise ValueError(f"{path}:{number}: invalid JSON") from error

def atomic_json(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    temporary.replace(path)

def digest(path: Path):
    if path.is_symlink():
        raise ValueError("Model assets cannot contain symlinks")
    if path.is_dir():
        entries=[]
        for item in path.rglob("*"):
            if item.is_symlink():raise ValueError("Model assets cannot contain symlinks")
            if item.is_file():
                relative=item.relative_to(path).as_posix()
                if "\n" in relative or "\0" in relative:raise ValueError("Invalid model path")
                entries.append(relative+"\0"+str(item.stat().st_size)+"\0"+digest(item)+"\n")
        if not entries or len(entries)>4096:raise ValueError("Empty or oversized model directory")
        return hashlib.sha256("".join(sorted(entries)).encode()).hexdigest()
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def validate_recipe(recipe):
    from jsonschema import Draft202012Validator
    Draft202012Validator(json.loads(SCHEMA.read_text())).validate(recipe)

def check_rights(sample, base: Path):
    identifier = sample.get("sample_id", "")
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", identifier):
        raise ValueError("sample_id must be a safe local identifier")
    rights = sample.get("rights", {})
    if rights.get("training_allowed") is not True or not rights.get("license") or not rights.get("source"):
        raise ValueError("Explicit training authorization, license and source are required")
    if rights.get("private") and not rights.get("consent_record"):
        raise ValueError("Private photos require a local consent record")
    image = (base / sample["image"]).resolve()
    if not image.is_file():
        raise ValueError("Image does not exist")
    if rights.get("sha256") != digest(image):
        raise ValueError("Image does not match the authorized content hash")
    if not isinstance(sample.get("instruction"), str) or not 1 <= len(sample["instruction"]) <= 1000:
        raise ValueError("Instruction must contain 1-1000 characters")
    return image

class NativeRenderer:
    def __init__(self, executable: Path):
        self.executable = executable.resolve()
        if not self.executable.is_file():
            raise ValueError("Build LumaAgentCLI first")

    def call(self, *arguments, timeout=180):
        # Never execute a teacher-provided command. Only fixed CLI commands and positional data.
        result = subprocess.run([str(self.executable), *map(str, arguments)], check=True,
                                capture_output=True, text=True, timeout=timeout,
                                env={**os.environ, "HF_HUB_DISABLE_TELEMETRY": "1"})
        return json.loads(result.stdout)

    def analyze(self, image: Path):
        return self.call("analyze", image)

    def render(self, image: Path, recipe, output: Path, instruction: str):
        validate_recipe(recipe)
        output.mkdir(parents=True, exist_ok=False)
        recipe_path = output / "recipe.json"
        atomic_json(recipe_path, recipe)
        return self.call("render", image, recipe_path, output, instruction)

SYSTEM_PROMPT = (
    "You are LumaStudio's photo editing planner. Return only a valid EditRecipe v1 JSON. "
    "Use the supplied scene metrics, intent and existing recipe. Do not invent tools or models. "
    "Preserve skin texture. Respect the JSON Schema and registered mask capabilities."
)

def training_prompt(row):
    return json.dumps({"instruction": row["instruction"], "analysis": row["analysis"],
                       "current_recipe": row.get("current_recipe"),
                       "preferences": row.get("preferences", {})}, ensure_ascii=False, sort_keys=True)
