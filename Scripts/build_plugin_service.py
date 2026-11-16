#!/usr/bin/env python3
"""Build a standalone macOS loopback service using a dedicated packaging Python.

uv venv work/plugin-ecosystem/packaging-venv
uv pip install --python work/plugin-ecosystem/packaging-venv/bin/python -r Tools/PluginCommunity/packaging-requirements.txt
work/plugin-ecosystem/packaging-venv/bin/python Scripts/build_plugin_service.py
"""
import hashlib, importlib.metadata, json, shutil, subprocess, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    if sys.platform!='darwin':raise SystemExit('Build this release helper on macOS')
    out=ROOT/'work/plugin-ecosystem/service-dist'
    args=[sys.executable,'-m','PyInstaller','--noconfirm','--clean','--onedir','--name','LumaCommunity','--distpath',str(out),'--workpath',str(ROOT/'work/plugin-ecosystem/service-build'),'--specpath',str(ROOT/'work/plugin-ecosystem'),
      '--add-data',f'{ROOT}/Tools/PluginCommunity/static:static',
      '--add-data',f'{ROOT}/Resources/Plugins:Resources/Plugins',
      '--add-data',f'{ROOT}/Packages/PhotoDomain/Sources/Resources/edit-recipe.schema.json:Packages/PhotoDomain/Sources/Resources',
      str(ROOT/'Tools/PluginCommunity/server.py')]
    subprocess.run(args,cwd=ROOT,check=True)
    service=out/'LumaCommunity';licenses=service/'LICENSES';licenses.mkdir(exist_ok=True)
    for package in ['pyinstaller','altgraph','macholib','packaging','pyinstaller-hooks-contrib','setuptools']:
        d=importlib.metadata.distribution(package)
        for file in d.files or []:
            if 'license' in str(file).lower() or 'copying' in str(file).lower():
                p=Path(d.locate_file(file))
                if p.is_file():shutil.copy2(p,licenses/(package+'-'+p.name))
    python_license=Path(sys.base_prefix)/'lib/python3.12/LICENSE.txt'
    if not python_license.exists():raise SystemExit('Python distribution license missing: '+str(python_license))
    shutil.copy2(python_license,licenses/'Python-LICENSE.txt')
    provenance={'python':sys.version,'pyinstaller':importlib.metadata.version('pyinstaller'),'platform':sys.platform,'architecture':'arm64','files':[]}
    for p in sorted(service.rglob('*')):
        if p.is_file():provenance['files'].append({'path':str(p.relative_to(service)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
    (service/'build-manifest.json').write_text(json.dumps(provenance,indent=2)+'\n')
    print(service)
if __name__=='__main__':main()
