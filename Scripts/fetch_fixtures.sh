#!/bin/zsh
set -eu
cd "${0:A:h}/.."
mkdir -p work/fixtures
curl -L --fail --retry 2 -o work/fixtures/G9-3219.RW2 'https://raw.pixls.us/getfile.php/3219/nice/Panasonic%20-%20DC-G9%20-%204:3.RW2'
curl -L --fail --retry 2 -o work/fixtures/portrait.jpg 'https://images-assets.nasa.gov/image/S99-00858/S99-00858~orig.jpg'
python3 - <<'PY'
import hashlib
from pathlib import Path
expected={'G9-3219.RW2':'cfb015a89d7af92306328868e6d87ac7974c427612608016821dfb336e8e3faa','portrait.jpg':'752846bd7bc6496b66ee4aebf1799635b676ba15b2c06adb6cf7be6da1eb91bb'}
for name,digest in expected.items():
    actual=hashlib.sha256((Path('work/fixtures')/name).read_bytes()).hexdigest()
    if actual != digest: raise SystemExit(f'Checksum mismatch: {name}')
    print('Verified:',name)
PY
