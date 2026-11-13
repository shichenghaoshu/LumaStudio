#!/usr/bin/env python3
"""Package the Mac release whose binary has passed native UI acceptance.

Source and evidence stay separate. Replacing the current delivery preserves it in
Legacy-VERSION; no user library, credentials, photographs or model weights enter source.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import plistlib
import re
import shutil
import stat
import subprocess
import zipfile

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'Deliverables'

def sha(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def run(*args):
    subprocess.run(list(map(str,args)),check=True,stdout=subprocess.DEVNULL)

def archive_source(destination):
    spec=importlib.util.spec_from_file_location('source_audit',ROOT/'Scripts/prepare_github.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);module.audit()
    excluded={'.venv','__pycache__','.DS_Store','xcuserdata'}
    with zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for name in module.ALLOWED:
            start=ROOT/name
            for path in sorted(start.rglob('*') if start.is_dir() else [start]):
                if excluded.intersection(path.parts) or path.suffix in ('.pyc','.gguf','.pdf','.docx') or path.name.startswith('.env') or any(p in {'data','outputs'} for p in path.relative_to(ROOT).parts[:2]):continue
                relative='LumaStudio/'+path.relative_to(ROOT).as_posix()
                if path.is_symlink():
                    if not path.resolve().is_relative_to(ROOT):raise RuntimeError('Out-of-workspace symlink')
                    info=zipfile.ZipInfo(relative);info.create_system=3;info.external_attr=(stat.S_IFLNK|0o777)<<16
                    archive.writestr(info,os.readlink(path))
                elif path.is_file():archive.write(path,relative)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--app',type=Path,default=ROOT/'work/WorkflowReleaseData/Build/Products/Release/LumaStudioMac.app')
    args=parser.parse_args()
    source=args.app.resolve()
    info=plistlib.loads((source/'Contents/Info.plist').read_bytes())
    configured=plistlib.loads((ROOT/'Apps/LumaStudioMac/Info.plist').read_bytes())
    if any(info[k]!=configured[k] for k in ('CFBundleShortVersionString','CFBundleVersion')):raise RuntimeError('Built application version differs from source')
    version=info['CFBundleShortVersionString'];binary=source/'Contents/MacOS/LumaStudioMac'
    acceptance=json.loads((ROOT/'Artifacts/final-acceptance.json').read_text())
    if acceptance.get('status')!='passed' or acceptance.get('version')!=version or acceptance.get('executable_sha256')!=sha(binary):raise RuntimeError('UI acceptance does not match this binary')
    build=(ROOT/'Artifacts/final-mac-build.log').read_text()
    tests=(ROOT/'Artifacts/final-all-tests.log').read_text()
    if '** BUILD SUCCEEDED **' not in build or '** BUILD FAILED **' in build:raise RuntimeError('Release build not passed')
    summaries=re.findall(r'Executed (\d+) tests, with (\d+) tests skipped and (\d+) failures|Executed (\d+) tests, with (\d+) failures',tests)
    if not summaries or any(s in tests for s in ('unexpected signal','Test Suite \'All tests\' failed','error:')):raise RuntimeError('Shared tests not passed')
    last=summaries[-1];executed=int(last[0] or last[3]);skipped=int(last[1] or 0);failures=int(last[2] or last[4])
    if executed<89 or failures:raise RuntimeError('Incomplete shared test suite')
    if skipped:
        supplemental=(ROOT/'Artifacts/final-legacy-test.log').read_text()
        if skipped!=1 or 'testPreReviewDatabaseMigratesWithoutLosingPhotoOrRecipe' not in supplemental or 'Executed 1 test, with 0 failures' not in supplemental:raise RuntimeError('Skipped fixture check needs a passing supplemental run')
    stdio=(ROOT/'Artifacts/pro-stdio-tests.log').read_text()
    training=(ROOT/'Artifacts/pro-training-regression.log').read_text()
    if 'Ran 3 tests' not in stdio or not stdio.rstrip().endswith('OK'):raise RuntimeError('Voice stdio tests not passed')
    if 'Ran 6 tests' not in training or not training.rstrip().endswith('OK'):raise RuntimeError('Training pipeline regression not passed')
    intent=(ROOT/'Artifacts/final-intent-test.log').read_text()
    if "Test Case '-[AgentTests.AgentTests testInstructionNegationAndLocalIntent]' passed" not in intent:raise RuntimeError('Final instruction parser regression not passed')
    stage=ROOT/'work/final-delivery-stage'
    if stage.exists():shutil.rmtree(stage)
    stage.mkdir(parents=True)
    app=stage/'LumaStudio.app';run('ditto',source,app);run('codesign','--verify','--deep','--strict',app)
    run('ditto','-c','-k','--sequesterRsrc','--keepParent',app,stage/'LumaStudio-macOS.zip')
    archive_source(stage/'LumaStudio-source.zip')
    evidence=[ROOT/'Artifacts'/name for name in ('final-mac-build.log','final-all-tests.log','final-legacy-test.log','final-postfix-tests.log','final-intent-test.log','final-acceptance.json','final-source-audit.log','pro-stdio-tests.log','pro-training-regression.log')]
    for folder in ('FinalRelease','ProEditor'):
        evidence += [p for p in (ROOT/'Artifacts'/folder).rglob('*') if p.is_file() and p.suffix.lower() in ('.json','.png','.jpg','.jpeg','.txt','.log')]
    with zipfile.ZipFile(stage/'LumaStudio-validation.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(set(evidence)):
            if path.is_file():archive.write(path,'Artifacts/'+path.relative_to(ROOT/'Artifacts').as_posix())
    manual=(ROOT/'Documentation/RELEASE_0.4.2.md').read_text()
    (stage/'使用说明.md').write_text(manual)
    manifest={'version':version,'build':info['CFBundleVersion'],'platform':'macOS 14+, Apple Silicon arm64','signature':'local ad-hoc; no Developer ID notarization','executable_sha256':sha(app/'Contents/MacOS/LumaStudioMac'),'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'ui_acceptance':acceptance,'shared_tests':{'executed':executed,'failures':failures,'skipped_in_full_run':skipped,'supplemental_legacy_fixture_passed':bool(skipped)},'voice_stdio_tests':3,'training_pipeline_regression_tests':6,'trained_product_models':0,'archives':{p.name:{'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(stage.glob('*.zip'))}}
    check=ROOT/'work/final-delivery-extraction'
    if check.exists():shutil.rmtree(check)
    check.mkdir(parents=True)
    run('ditto','-x','-k',stage/'LumaStudio-macOS.zip',check)
    extracted=check/'LumaStudio.app';run('codesign','--verify','--deep','--strict',extracted)
    if sha(extracted/'Contents/MacOS/LumaStudioMac')!=manifest['executable_sha256']:raise RuntimeError('Extracted application differs')
    manifest['extracted_signature_and_binary_match']=True
    (stage/'MANIFEST.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    OUT.mkdir(exist_ok=True)
    old=OUT/'LumaStudio.app/Contents/Info.plist'
    old_version=plistlib.loads(old.read_bytes())['CFBundleShortVersionString'] if old.exists() else 'previous'
    legacy=OUT/('Legacy-'+old_version)
    if any((OUT/p.name).exists() for p in stage.iterdir()):legacy.mkdir(exist_ok=True)
    old_manifest=OUT/'MANIFEST.txt'
    if old_manifest.exists():
        legacy.mkdir(exist_ok=True)
        if (legacy/old_manifest.name).exists():raise RuntimeError('Preserved manifest already exists')
        old_manifest.rename(legacy/old_manifest.name)
    for p in stage.iterdir():
        destination=OUT/p.name
        if destination.exists():
            saved=legacy/p.name
            if saved.exists():raise RuntimeError('Preserved delivery already exists: '+str(saved))
            destination.rename(saved)
        p.rename(destination)
    print(json.dumps({k:manifest[k] for k in ('version','build','executable_sha256','source_commit','archives','extracted_signature_and_binary_match')},ensure_ascii=False,indent=2))

if __name__=='__main__':main()
