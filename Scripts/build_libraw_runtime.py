#!/usr/bin/env python3
"""Build a relocatable arm64 Mac fallback from pinned, unmodified official source."""
import hashlib
import json
import os
import shutil
import subprocess
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.22.3"
SHA256 = "789f3c33466210a1a0907f747a97c715d21bbf4af712f257fcbbd90111b227e4"
URL = f"https://www.libraw.org/data/LibRaw-{VERSION}.tar.gz"
OUT = ROOT / "Vendor/libraw-runtime"
WORK = ROOT / "work/libraw-build"


def run(*args, cwd=None, env=None):
    subprocess.run(list(map(str, args)), cwd=cwd, env=env, check=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    archive = OUT / f"LibRaw-{VERSION}-source.tar.gz"
    if not archive.exists():
        cached = ROOT / f"work/LibRaw-{VERSION}.tar.gz"
        if cached.exists():
            shutil.copy2(cached, archive)
        else:
            urllib.request.urlretrieve(URL, archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise RuntimeError("LibRaw source checksum mismatch")
    source = WORK / f"LibRaw-{VERSION}"
    if not source.exists():
        with tarfile.open(archive) as tar:
            tar.extractall(WORK, filter="data")
    prefix = WORK / "install"
    environment = {**os.environ, "MACOSX_DEPLOYMENT_TARGET": "14.0", "CFLAGS": "-O2 -arch arm64", "CXXFLAGS": "-O2 -arch arm64"}
    # No external codec/color/OpenMP dependencies; Apple stays the primary decoder.
    # Lossy-DNG JPEG fallback is unavailable in this minimal secondary runtime.
    run(source / "configure", f"--prefix={prefix}", "--disable-static", "--disable-examples", "--disable-openmp", "--disable-lcms", "--disable-jpeg", cwd=source, env=environment)
    run("make", "-j4", cwd=source, env=environment)
    library = next((source / "lib/.libs").glob("libraw.*.dylib"))
    target = OUT / "libraw.dylib"
    shutil.copy2(library.resolve(), target)
    run("install_name_tool", "-id", "@loader_path/libraw.dylib", target)
    executable = OUT / "luma-raw-decode"
    run("xcrun", "clang++", "-O2", "-arch", "arm64", "-mmacosx-version-min=14.0", "-std=c++17", "-I", source, ROOT / "Tools/LibRawDecoder/luma_raw_decode.cpp", "-L", OUT, "-lraw", "-o", executable)
    run("codesign", "--force", "--sign", "-", target)
    run("codesign", "--force", "--sign", "-", executable)
    for name in ["LICENSE.CDDL", "LICENSE.LGPL", "COPYRIGHT"]:
        if (source / name).exists():
            shutil.copy2(source / name, OUT / name)
    provenance = dict(version=VERSION, sourceURL=URL, sourceSHA256=SHA256, licenseChoice="CDDL-1.0", architecture="arm64", minimumMacOS="14.0", sourceModified=False, externalDependencies=False, limitations=["No LibRaw JPEG-lossy-DNG extension; native Apple decoding remains available", "Fallback exposes exposure and camera white balance; Apple-specific RAW controls unavailable"], files={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [target, executable]})
    (OUT / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    run(executable, "--version")
    run("otool", "-L", executable)
    run("otool", "-L", target)


if __name__ == "__main__":
    main()
