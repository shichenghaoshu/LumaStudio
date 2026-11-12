#!/usr/bin/env python3
"""Package only successful native builds and source/evidence, never photo originals."""
from pathlib import Path
import subprocess,hashlib,zipfile,shutil,re
root=Path(__file__).resolve().parents[1];out=root/'Deliverables';out.mkdir(exist_ok=True)
for name in ['release-mac-build.log','release-pad-simulator-build.log','release-pad-device-build.log']:
    log=(root/'Artifacts'/name).read_text()
    if '** BUILD SUCCEEDED **' not in log or '** BUILD FAILED **' in log: raise SystemExit(f'Build not successful: {name}')
if 'Executed 29 tests, with 0 failures' not in (root/'Artifacts/all-tests.log').read_text(): raise SystemExit('Final core tests not successful')
products=[('ReleaseData/Build/Products/Release/LumaStudioMac.app','LumaStudio.app'),('DerivedDataPad/Build/Products/Release-iphonesimulator/LumaStudioPad.app','LumaStudioPad-simulator.app'),('DerivedDataDevice/Build/Products/Release-iphoneos/LumaStudioPad.app','LumaStudioPad-device-unsigned.app')]
for source,name in products:
    subprocess.run(['ditto',str(root/source),str(out/name)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(out/'LumaStudio.app')],check=True)
subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(out/'LumaStudio.app'),str(out/'LumaStudio-macOS.zip')],check=True)
with zipfile.ZipFile(out/'LumaStudio-source.zip','w',zipfile.ZIP_DEFLATED) as z:
    for item in ['Package.swift','README.md','.gitignore','LumaStudio.xcodeproj','Apps','Packages','Resources','Tests','Tools','Scripts','Documentation']:
        path=root/item
        files=path.rglob('*') if path.is_dir() else [path]
        for file in sorted(files):
            if file.is_file() and '.DS_Store' not in file.parts and 'xcuserdata' not in file.parts: z.write(file,'LumaStudio/'+str(file.relative_to(root)))
evidence=list((root/'Artifacts').glob('*.log'))+[root/'Artifacts/mac-editor.png',root/'Artifacts/mac-batch.png',root/'Artifacts/mac-capture.png',root/'Artifacts/ipad-simulator.png']
for sub in ['RAW-Final/report.json','Portrait/report.json','Stress100/report.json','Stress100/memory.json','Stress100/dimensions-validation.log']:
    evidence.append(root/'Artifacts'/sub)
with zipfile.ZipFile(out/'LumaStudio-validation.zip','w',zipfile.ZIP_DEFLATED) as z:
    for file in evidence:
        if file.exists(): z.write(file,str(file.relative_to(root)))
lines=['LumaStudio 0.1 - local development delivery, 2026-11-10','macOS 14+ arm64; iPadOS 17+','Mac: ad-hoc local signature; iPad device: unsigned, needs your developer Team','Three Release builds: SUCCEEDED; Swift tests: 29 / 0 failures','']
for _,name in products:
    folder=out/name;size=sum(p.stat().st_size for p in folder.rglob('*') if p.is_file())
    lines.append(f'{name}: {size} bytes ({size/1024/1024:.2f} MiB)')
    binaries=list(folder.glob('Contents/MacOS/*')) if name=='LumaStudio.app' else [folder/'LumaStudioPad']
    for binary in binaries:
        if binary.is_file():lines.append(f'  binary SHA256 {hashlib.sha256(binary.read_bytes()).hexdigest()}')
lines.append('')
for file in sorted(out.glob('*.zip')):lines.append(f'{file.name}  {file.stat().st_size} bytes  SHA256 {hashlib.sha256(file.read_bytes()).hexdigest()}')
(out/'MANIFEST.txt').write_text('\n'.join(lines)+'\n')
print('\n'.join(lines))
