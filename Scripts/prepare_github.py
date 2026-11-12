#!/usr/bin/env python3
"""Audit/stage only deliverable source; never add private local research or credentials."""
import argparse
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ALLOWED = ["Package.swift", "Package.resolved", "README.md", ".gitignore", ".github", "LumaStudio.xcodeproj", "Apps", "Packages", "Resources", "Tests", "Tools", "Scripts", "Documentation", "Training", "Models/manifests", "Vendor/llama-runtime.xcframework", "Vendor/llama-LICENSE.txt", "Vendor/Notices", "Vendor/runtime-provenance.json"]
DENIED = ("work/", "Artifacts/", "Deliverables/", "pixcake-re/", "rea/", "Models/mac/", "ReleaseData/", "DerivedData", "Vendor/llama.xcframework/", "Vendor/build-apple/")
SECRET = re.compile(rb"(?:sk-[A-Za-z0-9_-]{24,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[A-Z0-9]{16}|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----)")

def git(*args, **kwargs):
    return subprocess.run(["git", *args], cwd=ROOT, check=True, **kwargs)

def audit():
    paths = []
    for name in ALLOWED:
        start = ROOT / name
        if not start.exists():
            continue
        paths.extend(start.rglob("*") if start.is_dir() else [start])
    count = size = 0
    for path in paths:
        relative = path.relative_to(ROOT).as_posix()
        if any(p in path.parts for p in (".venv", "__pycache__", "xcuserdata")) or path.suffix in (".pyc", ".gguf", ".pdf", ".docx"):
            continue
        if path.is_symlink():
            if not path.resolve().is_relative_to(ROOT):
                raise RuntimeError("Out-of-workspace source symlink: " + relative)
            continue
        if not path.is_file():
            continue
        length = path.stat().st_size
        if length > 95 * 1024 * 1024:
            raise RuntimeError("File exceeds safe GitHub source limit: " + relative)
        if length < 4 * 1024 * 1024 and path.suffix not in (".png", ".jpg", ".icns", ".car"):
            data = path.read_bytes()
            if SECRET.search(data):
                raise RuntimeError("Potential credential; review before upload: " + relative)
        count += 1
        size += length
    print(f"Source whitelist audit passed: {count} files, {size} bytes. No photo/research/model-weight directories selected.")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", action="store_true")
    args = parser.parse_args()
    audit()
    if not args.stage:
        return
    if not (ROOT / ".git").exists():
        git("init", "-b", "main")
    git("add", "--", *[p for p in ALLOWED if (ROOT / p).exists()])
    names = git("diff", "--cached", "--name-only", "-z", capture_output=True).stdout.decode().split("\0")
    for name in filter(None, names):
        if name.startswith(DENIED) or "/.env" in name or name.startswith(".env") or name.endswith((".gguf", ".pdf", ".docx")):
            raise RuntimeError("Forbidden staged source path: " + name)
    print("Staged source passed directory and credential checks.")

if __name__ == "__main__":
    main()
