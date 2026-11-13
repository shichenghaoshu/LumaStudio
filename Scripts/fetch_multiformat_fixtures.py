#!/usr/bin/env python3
"""Fetch a bounded, CC0-only camera corpus; never use these assets as training data."""
import concurrent.futures
import hashlib
import html
import json
import re
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "work/fixtures/multi-format"
IDS = [131, 4515, 958, 1536, 865, 1051, 753, 1480]
INDEX = "https://raw.pixls.us/json/getrepository.php?set=all"
LICENSE = "https://creativecommons.org/publicdomain/zero/1.0/"


def fetch(entry):
    target = DEST / entry["filename"]
    if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest() != entry["sha256"]:
        request = urllib.request.Request(entry["url"], headers={"User-Agent": "LumaStudio-format-validation/0.4"})
        temporary = target.with_suffix(target.suffix + ".download")
        with urllib.request.urlopen(request, timeout=90) as response, temporary.open("wb") as output:
            total = 0
            while chunk := response.read(1024 * 1024):
                total += len(chunk)
                if total > 80 * 1024 * 1024:
                    raise RuntimeError("Sample exceeds size limit")
                output.write(chunk)
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != entry["sha256"]:
            raise RuntimeError(f"Checksum mismatch: {target.name}")
        temporary.replace(target)
    return {**entry, "bytes": target.stat().st_size}


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(INDEX, timeout=35) as response:
        data = response.read()
    (DEST / "repository-receipt.json").write_bytes(data)
    rows = json.loads(data)["data"]
    entries = []
    for sample_id in IDS:
        row = next(r for r in rows if re.search(rf"getfile.php/{sample_id}/nice/", r[7]))
        if LICENSE not in row[5]:
            raise RuntimeError("Only CC0 entries are allowed")
        link = html.unescape(re.search(r"href='([^']+)'", row[7])[1])
        filename = f"{sample_id}-" + link.rsplit("/", 1)[-1].replace("/", "_")
        checksum = re.search(r"[a-f0-9]{64}", row[7])[0]
        entries.append(dict(id=sample_id, make=row[0], model=row[1], mode=row[2],
                            filename=filename, url=urllib.parse.quote(link, safe=":/"),
                            sha256=checksum, license=LICENSE, repository="https://raw.pixls.us/",
                            purpose="Decode, render and batch validation only; no training"))
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(fetch, entries))
    (DEST / "manifest.json").write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")
    for entry in results:
        print(f"Verified CC0: {entry['make']} {entry['model']} · {entry['filename'].rsplit('.', 1)[-1]} · {entry['bytes']:,} bytes")


if __name__ == "__main__":
    main()
