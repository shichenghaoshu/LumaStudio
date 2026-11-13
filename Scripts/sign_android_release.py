#!/usr/bin/env python3
"""Sign a release APK with a persistent local key; never expose its password.

The keystore is outside the repository. The password travels only through
captured pipes and macOS Keychain, never files, environment variables or argv.
"""
import argparse
import os
from pathlib import Path
import secrets
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]

def run(args, **kwargs):
    return subprocess.run(list(map(str,args)),check=True,**kwargs)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('apk',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--sdk',type=Path,required=True)
    parser.add_argument('--java',type=Path,required=True)
    args=parser.parse_args()
    helper=ROOT/'work/release-tools/release-keychain'
    helper.parent.mkdir(parents=True,exist_ok=True)
    if not helper.exists():
        run(['xcrun','swiftc',ROOT/'Tools/ReleaseKeychain/main.swift','-o',helper],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        run(['codesign','--force','--sign','-',helper],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    result=subprocess.run([str(helper),'read'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    keyroot=Path.home()/'Library/Application Support/LumaStudioRelease'
    keyroot.mkdir(mode=0o700,parents=True,exist_ok=True)
    keystore=keyroot/'android-release.p12'
    if result.returncode==2:
        if keystore.exists():
            raise RuntimeError('Existing keystore has no matching accessible credential; preserving it')
        password=secrets.token_urlsafe(48).encode()
        run([helper,'create'],input=password,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    elif result.returncode==0:
        password=result.stdout
    else:
        raise RuntimeError('macOS Keychain did not allow reading the release credential')
    if not keystore.exists():
        temporary=keyroot/'android-release.new.p12'
        try:
            run([args.java/'bin/keytool','-genkeypair','-keystore',temporary,'-storetype','PKCS12','-alias','lumastudio','-keyalg','RSA','-keysize','3072','-validity','10000','-dname','CN=LumaStudio Release'],input=password+b'\n'+password+b'\n',stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            temporary.chmod(0o600);temporary.replace(keystore)
        except subprocess.CalledProcessError:
            raise RuntimeError('Key generation failed; no signing material was printed') from None
    buildtools=sorted((args.sdk/'build-tools').iterdir(),key=lambda p:tuple(int(x) for x in p.name.split('.') if x.isdigit()))[-1]
    signer=buildtools/'apksigner'
    args.output.parent.mkdir(parents=True,exist_ok=True)
    env={**os.environ,'JAVA_HOME':str(args.java)}
    try:
        run([signer,'sign','--ks',keystore,'--ks-key-alias','lumastudio','--ks-pass','stdin','--key-pass','stdin','--out',args.output,args.apk],input=password+b'\n'+password+b'\n',stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
    except subprocess.CalledProcessError:
        raise RuntimeError('APK signing failed; no signing material was printed') from None
    # Certificate identity and digests are public; passwords are never logged.
    run([signer,'verify','--verbose','--print-certs',args.output],env=env)
    print('Release APK signed; private keystore retained outside source:',keystore)

if __name__=='__main__':main()
