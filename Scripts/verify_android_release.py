#!/usr/bin/env python3
"""Build, sign and instrument the real minified APK on a disposable emulator."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--java', type=Path, required=True)
    args = parser.parse_args()
    adb = shutil.which('adb') or str(args.sdk/'platform-tools/adb')
    device = [adb, '-s', args.device]
    if subprocess.check_output(device+['shell','getprop','ro.kernel.qemu'],text=True).strip() != '1':
        raise RuntimeError('ReleaseSmokeTest requires a disposable emulator with no personal library.')
    evidence = ROOT/'Artifacts/Performance'
    evidence.mkdir(parents=True,exist_ok=True)
    app = ROOT/'Apps/LumaStudioCross'
    env = dict(os.environ, JAVA_HOME=str(args.java), ANDROID_HOME=str(args.sdk))
    with (evidence/'android-release-test-build.log').open('w') as log:
        subprocess.run(['./gradlew',':app:assembleRelease',':app:assembleReleaseAndroidTest',
                        '-Ptarget-platform=android-arm64,android-x64'],cwd=app/'android',env=env,
                       stdout=log,stderr=subprocess.STDOUT,check=True)
    output = ROOT/'Deliverables/Release-0.5.0/LumaStudio-0.5.0-Android.apk'
    test = ROOT/'work/release-tools/android-release-qa.apk'
    sign = [sys.executable,str(ROOT/'Scripts/sign_android_release.py')]
    for source,destination,name in [
        (app/'build/app/outputs/apk/release/app-release-unsigned.apk',output,'android-signing.log'),
        (app/'build/app/outputs/apk/androidTest/release/app-release-androidTest.apk',test,'android-release-test-signing.log')]:
        with (evidence/name).open('w') as log:
            subprocess.run(sign+[str(source),str(destination),'--sdk',str(args.sdk),'--java',str(args.java)],
                           stdout=log,stderr=subprocess.STDOUT,check=True,cwd=ROOT)
        subprocess.run(device+['install','-r',str(destination)],check=True)
    fixture=ROOT/'work/release-tools/LumaStudio-QA-import.jpg'
    fixture.write_bytes((app/'assets/demo.jpg').read_bytes()+b'\nLuma release import QA '+uuid.uuid4().hex.encode())
    subprocess.run(device+['push',str(fixture),'/sdcard/Download/LumaStudio-QA-import.jpg'],check=True)
    result = subprocess.run(device+['shell','am','instrument','-w','-r','-e','class',
        'studio.luma.lumastudio.ReleaseSmokeTest',
        'studio.luma.lumastudio.test/androidx.test.runner.AndroidJUnitRunner'],
        capture_output=True,text=True,timeout=180)
    log = result.stdout+result.stderr
    (evidence/'android-signed-release-ui.log').write_text(log)
    screenshots = evidence/'FinalUI'
    screenshots.mkdir(exist_ok=True)
    subprocess.run(device+['pull','/sdcard/Android/data/studio.luma.lumastudio/files/release-qa/.',
                           str(screenshots)],check=False)
    passed = result.returncode == 0 and 'OK (1 test)' in log and 'FAILURES' not in log
    report = {'success':passed,'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
              'apkSha256':hashlib.sha256(output.read_bytes()).hexdigest(),
              'target':'actual signed non-debuggable distribution APK, lib/main.dart entry point',
              'device':args.device,'androidSDK':subprocess.check_output(device+['shell','getprop','ro.build.version.sdk'],text=True).strip(),
              'checks':['offline demo import','accessible slider drag changes persisted recipe','high-strength beauty preset persists real controls',
                        'system save picker and completion','valid original-resolution JPEG export with actual brighter pixels',
                        'original SHA256 unchanged','restart restores visible decoded preview and edits',
                        'system file picker imports an external JPEG'],
              'physicalDeviceAcceptance':False}
    (evidence/'android-signed-release-ui.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    if not passed:
        print(log[-8000:])
        raise SystemExit(1)
    build_tools=sorted((args.sdk/'build-tools').iterdir(),key=lambda p:p.name)[-1]
    subprocess.run([str(build_tools/'zipalign'),'-c','-P','16','4',str(output)],check=True)
    with zipfile.ZipFile(output) as archive:
        abis=sorted({name.split('/')[1] for name in archive.namelist() if name.startswith('lib/') and name.endswith('.so')})
    assert abis==['arm64-v8a','x86_64'],abis
    package={'version':'0.5.0','versionCode':9,'minimumSDK':24,'debuggable':False,
             'abis':abis,'zipalign16KB':True,'sha256':report['apkSha256'],
             'signatureV2andV3Verified':True,'releaseInstrumentationPassed':True}
    (evidence/'android-release-package.json').write_text(json.dumps(package,indent=2)+'\n')

if __name__ == '__main__':
    main()
