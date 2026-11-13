#!/usr/bin/env python3
"""Assemble audited 0.5.0 assets after platform-specific acceptance passes."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import zipfile

from prepare_github import ALLOWED, ROOT, SECRET, audit

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--windows-artifacts',type=Path,required=True)
    parser.add_argument('--ci-receipt',type=Path,default=ROOT/'Artifacts/Performance/final-ci.json')
    args=parser.parse_args()
    head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    if subprocess.check_output(['git','status','--porcelain','--untracked-files=no'],cwd=ROOT).strip():
        raise RuntimeError('Commit the reviewed source before packaging.')
    if subprocess.check_output(['git','ls-files','--others','--exclude-standard','--',*ALLOWED],cwd=ROOT).strip():
        raise RuntimeError('Uncommitted deliverable source remains.')
    audit()
    ci=read(args.ci_receipt)
    if ci['sourceCommit']!=head or not all(run['conclusion']=='success' for run in ci['runs']):
        raise RuntimeError('Successful CI receipt does not match final source.')
    out=ROOT/'Deliverables/Release-0.5.0';out.mkdir(parents=True,exist_ok=True)
    app=out/'LumaStudio.app';info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    if (info['CFBundleShortVersionString'],info['CFBundleVersion'])!=('0.5.0','9'):
        raise RuntimeError('Unexpected Mac application version.')
    ui=read(ROOT/'Artifacts/Performance/mac-final-ui.json')
    if not ui['actualGUI']['libraryRecipeAndReviewUnchangedAfterQA'] or ui['executableSha256']!=sha(app/'Contents/MacOS/LumaStudioMac'):
        raise RuntimeError('Mac acceptance does not match distribution binary.')
    if ui['sourceCodeCommit']!=head:
        raise RuntimeError('Mac acceptance source does not match final commit.')
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    android=read(ROOT/'Artifacts/Performance/android-signed-release-ui.json')
    apk=out/'LumaStudio-0.5.0-Android.apk'
    if not android['success'] or android['apkSha256']!=sha(apk) or android['sourceCommit']!=head:
        raise RuntimeError('Signed Android acceptance does not match distribution APK.')
    windows=next(args.windows_artifacts.rglob('LumaStudio-0.5.0-Windows-x64.zip'))
    win_report=next(args.windows_artifacts.rglob('windows-release-self-test.json'))
    if not read(win_report)['success']:
        raise RuntimeError('Windows Release self-test failed.')
    with zipfile.ZipFile(windows) as archive:
        names=archive.namelist()
        build=json.loads(archive.read(next(n for n in names if n.endswith('/BUILD.json'))).decode('utf-8-sig'))
        if build['sourceCommit']!=head:raise RuntimeError('Windows package source differs from final commit.')
        required={'lumastudio.exe','flutter_windows.dll','luma_native.dll','msvcp140.dll','vcruntime140.dll'}
        if not required.issubset({Path(n).name for n in names}):raise RuntimeError('Windows runtime files missing.')
    shutil.copy2(windows,out/windows.name)
    subprocess.run(['git','archive','--format=zip','--prefix=LumaStudio-0.5.0/',
                    '--output='+str(out/'LumaStudio-0.5.0-Source.zip'),head,'--',*ALLOWED],cwd=ROOT,check=True)
    artifacts=ROOT/'Artifacts/Performance'
    evidence=[artifacts/n for n in [
        'mac-tests-final.log','beauty-enhanced-tests.log','voice-tests-final.log','mac-delivery-build.log','mac-final-ui.json',
        'mac-final-export.json','Before/report.json','After/report.json','native-enhanced-test.log',
        'portable-analyze.log','portable-tests-final.log','portable-raw-formats.json',
        'portable-local-self-test.json','android-signed-release-ui.log',
        'android-signed-release-ui.json','android-release-package.json','final-ci.json',
        'BeautyEnhanced/source.json','BeautyEnhanced/beauty-original.png','BeautyEnhanced/beauty-natural.png',
        'BeautyEnhanced/beauty-studio.png','BeautyEnhanced/beauty-porcelain.png','BeautyEnhanced/beauty-intensive.png',
        'BeautyEnhanced/beauty-reshape.png','FinalUI/mac-editor.png','FinalUI/mac-beauty-intensive.png',
        'FinalUI/mac-beauty-reshape.png','FinalUI/android-release-editor.png','FinalUI/android-release-restarted.png']]
    evidence += [win_report,next(args.windows_artifacts.rglob('windows-editor-ui.png'))]
    with zipfile.ZipFile(out/'LumaStudio-0.5.0-Validation.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for file in evidence:
            if not file.is_file():raise RuntimeError('Required validation artifact missing: '+str(file))
            data=file.read_bytes()
            if file.suffix in ('.json','.txt','.log'):
                if SECRET.search(data):raise RuntimeError('Potential credential in validation artifact: '+str(file))
                data=data.replace(str(ROOT).encode(),b'$PROJECT').replace(str(Path.home()).encode(),b'$HOME')
            name=file.relative_to(artifacts).as_posix() if file.is_relative_to(artifacts) else 'Windows/'+file.name
            archive.writestr(name,data)
    shutil.copy2(ROOT/'Documentation/RELEASE_0.5.0.md',out/'使用说明.md')
    assets={p.name:{'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(out.iterdir())
            if p.is_file() and p.suffix.lower() in ('.zip','.apk','.md')}
    manifest={'version':'0.5.0','build':9,'sourceCommit':head,'ci':ci,
        'platforms':{'macOS':{'minimum':'14.0','architecture':'arm64','signature':'ad-hoc, not notarized',
                             'executableSha256':sha(app/'Contents/MacOS/LumaStudioMac'),'actualGUI':ui['actualGUI']},
                     'Windows':{'minimum':'Windows 10 x64','signature':'unsigned','build':build,
                                'releaseChecks':len(read(win_report)['checks'])},
                     'Android':{'minimumSDK':24,'abis':['arm64-v8a','x86_64'],
                                'certificateSha256':'860dbb1f9bae77289d3ebcf2492ed9bed35cc0e11df25bbc4f33c80a513bcabe',
                                'actualSignedReleaseUI':android}},
        'limits':['No physical Android or user Windows PC acceptance','Mac and Portable recipes are not interoperable',
                  'Portable has 48 numeric controls, Mac 184; face geometry is available only on Mac','No trained commercial beauty or specialist model is bundled',
                  'Engine benchmark is not measured end-to-end UI FPS'],
        'assets':assets}
    (out/'MANIFEST.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    files=[out/name for name in assets]+[out/'MANIFEST.json']
    (out/'SHA256SUMS.txt').write_text(''.join(sha(p)+'  '+p.name+'\n' for p in sorted(files)))
    for file in files:
        if file.suffix=='.zip':
            with zipfile.ZipFile(file) as archive:
                if archive.testzip() is not None:raise RuntimeError('Archive CRC failed: '+str(file))
    print(json.dumps({'version':'0.5.0','sourceCommit':head,'assets':assets},ensure_ascii=False,indent=2))

if __name__=='__main__':main()
