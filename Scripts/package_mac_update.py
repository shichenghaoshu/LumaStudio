#!/usr/bin/env python3
"""Package a Mac-only update after matching local, GUI and CI acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import zipfile

from prepare_github import ALLOWED, ROOT, SECRET, audit


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    app, evidence = args.app.resolve(), args.evidence.resolve()
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT).strip():
        raise RuntimeError("Commit reviewed source before packaging.")
    if subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard", "--", *ALLOWED], cwd=ROOT).strip():
        raise RuntimeError("Uncommitted deliverable source remains.")
    audit()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    if (version, build) != ("0.5.1", "15"):
        raise RuntimeError("Unexpected update version.")
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    ui, ci = read(evidence / "mac-final-ui.json"), read(evidence / "final-ci.json")
    if ui["sourceCommit"] != head or ui["executableSHA256"] != sha(executable):
        raise RuntimeError("GUI receipt does not match this source and executable.")
    required = {"singleLabel", "batchLabels", "combinedFilter", "clearLabel", "restartRestoresLabel",
                "compactLayout", "interactivePreview", "refinedPreview", "exportOriginalResolution", "userLibraryUnchanged"}
    if not all(ui["checks"].get(k) is True for k in required):
        raise RuntimeError("Actual GUI acceptance remains incomplete.")
    if ci["sourceCommit"] != head or not ci["runs"] or not all(r["conclusion"] == "success" for r in ci["runs"]):
        raise RuntimeError("Successful CI receipt does not match this source.")
    if "Test Suite 'All tests' passed" not in (evidence / "all-tests.log").read_text():
        raise RuntimeError("Local full regression did not pass.")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    out = ROOT / "Deliverables" / ("Release-" + version)
    out.mkdir(parents=True, exist_ok=True)
    target = out / "LumaStudio.app"
    if target.exists() and sha(target / "Contents/MacOS" / info["CFBundleExecutable"]) != sha(executable):
        raise RuntimeError("A different application already occupies this release directory.")
    if not target.exists():
        subprocess.run(["ditto", str(app), str(target)], check=True)
    mac = out / f"LumaStudio-{version}-macOS-AppleSilicon.zip"
    subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(target), str(mac)], check=True)
    with tempfile.TemporaryDirectory(prefix="luma-mac-verify-") as temp:
        subprocess.run(["ditto", "-x", "-k", str(mac), temp], check=True)
        unpacked = Path(temp) / "LumaStudio.app"
        if sha(unpacked / "Contents/MacOS" / info["CFBundleExecutable"]) != sha(executable):
            raise RuntimeError("Unpacked executable differs.")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(unpacked)], check=True)
    source = out / f"LumaStudio-{version}-Source.zip"
    subprocess.run(["git", "archive", "--format=zip", f"--prefix=LumaStudio-{version}/",
                    "--output=" + str(source), head, "--", *ALLOWED], cwd=ROOT, check=True)
    selected = ["all-tests.log", "targeted-tests.log", "voice-tests.log", "mac-release-build.log",
                "mac-final-ui.json", "final-ci.json", "export.json", "comparison.json",
                "Baseline/report.json", "After/report.json", "source.json",
                "UI/color-labels.png", "UI/compact.png", "UI/portrait.png"]
    validation = out / f"LumaStudio-{version}-Validation.zip"
    with zipfile.ZipFile(validation, "w", zipfile.ZIP_DEFLATED) as archive:
        for name in selected:
            file = evidence / name
            data = file.read_bytes()
            if file.suffix in (".json", ".log", ".txt"):
                if SECRET.search(data):
                    raise RuntimeError("Potential credential in evidence: " + name)
                data = data.replace(str(ROOT).encode(), b"$PROJECT").replace(str(Path.home()).encode(), b"$HOME")
            archive.writestr(name, data)
    guide = out / f"LumaStudio-{version}-Guide.md"
    shutil.copy2(ROOT / f"Documentation/RELEASE_{version}.md", guide)
    files = [mac, source, validation, guide]
    assets = {p.name: {"bytes": p.stat().st_size, "sha256": sha(p)} for p in files}
    manifest = {"version": version, "build": int(build), "sourceCommit": head, "platform": "macOS arm64",
                "signature": "ad-hoc; not notarized", "executableSHA256": sha(executable),
                "actualGUI": ui["checks"], "ci": ci, "assets": assets,
                "otherPlatforms": {"Windows": "0.5.0", "Android": "0.5.0"},
                "limits": ["Engine timing is not end-to-end UI FPS", "No newly trained portrait model"]}
    manifest_file = out / "MANIFEST.json"
    manifest_file.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    files.append(manifest_file)
    (out / "SHA256SUMS.txt").write_text("".join(sha(p) + "  " + p.name + "\n" for p in sorted(files)))
    for file in (mac, source, validation):
        with zipfile.ZipFile(file) as archive:
            if archive.testzip() is not None:
                raise RuntimeError("Archive CRC failed: " + file.name)
    print(json.dumps({"version": version, "sourceCommit": head, "assets": assets}, indent=2))


if __name__ == "__main__":
    main()
