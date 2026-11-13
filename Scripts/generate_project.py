#!/usr/bin/env python3
"""Generate the native two-target project without a build-time third-party tool."""
from pathlib import Path
import hashlib, plistlib
ROOT = Path(__file__).resolve().parents[1]
objects = {}
def ident(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def add(key, text):
    i=ident(key); objects[i]=text; return i
def quoted(s): return '"'+str(s).replace('\\','\\\\').replace('"','\\"')+'"'
def array(values): return '('+','.join(values)+',)'
def cfg_list(key, settings):
    cs=[]
    for mode in ['Debug','Release']:
        s=dict(settings)
        s.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O', 'DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym'})
        cs.append(add(key+mode, 'isa = XCBuildConfiguration; buildSettings = {'+''.join(k+' = '+quoted(v)+';' for k,v in s.items())+'}; name = '+mode+';'))
    return add(key+'configs','isa = XCConfigurationList; buildConfigurations = '+array(cs)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
rootid=ident('project')
package=add('package','isa = XCLocalSwiftPackageReference; relativePath = .;')
refs=[]; prods=[]; targets=[]
for platform, target, mainDir, sdk, minimum in [('Mac','LumaStudioMac','LumaStudioMac','macosx','14.0'),('Pad','LumaStudioPad','LumaStudioPad','iphoneos','17.0')]:
    sourcebuild=[]
    files=sorted((ROOT/'Apps'/mainDir).glob('*.swift'))+sorted((ROOT/'Apps'/'Shared').glob('*.swift'))
    for file in files:
        path=str(file.relative_to(ROOT)); ref=add('ref'+path,'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = '+quoted(path)+'; sourceTree = "<group>";')
        if ref not in refs: refs.append(ref)
        sourcebuild.append(add(target+path,'isa = PBXBuildFile; fileRef = '+ref+';'))
    product=add(target+'app','isa = PBXFileReference; explicitFileType = wrapper.application; path = '+target+'.app; sourceTree = BUILT_PRODUCTS_DIR;'); prods.append(product)
    dep=add(target+'packageproduct','isa = XCSwiftPackageProductDependency; package = '+package+'; productName = PhotoCore;')
    depbuild=add(target+'link','isa = PBXBuildFile; productRef = '+dep+';')
    phases=[add(target+'src','isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+array(sourcebuild)+'; runOnlyForDeploymentPostprocessing = 0;'), add(target+'fw','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = '+array([depbuild])+'; runOnlyForDeploymentPostprocessing = 0;')]
    asset=add('assets','isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "Resources/Assets.xcassets"; sourceTree = "<group>";')
    if asset not in refs: refs.append(asset)
    assetbuild=add(target+'assetbuild','isa = PBXBuildFile; fileRef = '+asset+';')
    notice=add('notices','isa = PBXFileReference; lastKnownFileType = text; path = "Resources/ThirdPartyNotices.txt"; sourceTree = "<group>";')
    if notice not in refs: refs.append(notice)
    noticebuild=add(target+'noticebuild','isa = PBXBuildFile; fileRef = '+notice+';')
    resourcebuilds=[assetbuild,noticebuild]
    if platform=='Mac':
        runtime=add('libraw-runtime','isa = PBXFileReference; lastKnownFileType = folder; path = "Vendor/libraw-runtime"; sourceTree = "<group>";')
        if runtime not in refs: refs.append(runtime)
        resourcebuilds.append(add(target+'libraw-build','isa = PBXBuildFile; fileRef = '+runtime+';'))
    phases.append(add(target+'res','isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = '+array(resourcebuilds)+'; runOnlyForDeploymentPostprocessing = 0;'))
    # Local ad-hoc builds have no Team ID, so hardened library validation cannot
    # authenticate a separately signed llama.framework. A Developer ID distribution
    # must override this to YES and sign the app/framework with that same team.
    cfg={'PRODUCT_NAME':target,'PRODUCT_BUNDLE_IDENTIFIER':'studio.luma.'+platform.lower(),'INFOPLIST_FILE':'Apps/'+mainDir+'/Info.plist','SDKROOT':sdk,'SWIFT_VERSION':'5.0','CODE_SIGN_STYLE':'Automatic','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ENABLE_HARDENED_RUNTIME':'NO','GENERATE_INFOPLIST_FILE':'NO','SUPPORTED_PLATFORMS':'macosx' if platform=='Mac' else 'iphoneos iphonesimulator','SWIFT_EMIT_LOC_STRINGS':'YES','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks' if platform=='Mac' else '$(inherited) @executable_path/Frameworks'}
    cfg['MACOSX_DEPLOYMENT_TARGET' if platform=='Mac' else 'IPHONEOS_DEPLOYMENT_TARGET']=minimum
    if platform=='Pad': cfg.update({'TARGETED_DEVICE_FAMILY':'2','SUPPORTS_MACCATALYST':'NO'})
    else: cfg.update({'ARCHS':'arm64','CODE_SIGN_ENTITLEMENTS':'Apps/LumaStudioMac/LumaStudioMac.entitlements'})
    cl=cfg_list(target,cfg)
    tid=add(target,'isa = PBXNativeTarget; buildConfigurationList = '+cl+'; buildPhases = '+array(phases)+'; buildRules = (); dependencies = (); name = '+target+'; packageProductDependencies = '+array([dep])+'; productName = '+target+'; productReference = '+product+'; productType = "com.apple.product-type.application";'); targets.append(tid)
    info={'CFBundleDevelopmentRegion':'zh_CN','CFBundleDisplayName':'LumaStudio','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleURLTypes':[{'CFBundleURLName':'studio.luma.pairing','CFBundleURLSchemes':['lumastudio']}],'CFBundleName':'LumaStudio','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.4.2' if platform=='Mac' else '0.1.0','CFBundleVersion':'8' if platform=='Mac' else '1','LSMinimumSystemVersion':minimum,'NSCameraUsageDescription':'发现已连接的 G9 并验证 USB 联机拍摄能力。','NSLocalNetworkUsageDescription':'在本地网络与经过配对的 Mac 或 iPad 传输照片。','NSBonjourServices':['_lumastudio._tcp']}
    if platform=='Mac': info.update({'NSMicrophoneUsageDescription':'将你主动输入的语音转换成修图要求。','NSSpeechRecognitionUsageDescription':'把语音转写到修图输入框，默认使用设备端识别。'})
    if platform=='Pad': info.update({'UILaunchScreen':{},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':True},'UISupportedInterfaceOrientations':['UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight','UIInterfaceOrientationPortrait','UIInterfaceOrientationPortraitUpsideDown'],'LSSupportsOpeningDocumentsInPlace':True,'UIFileSharingEnabled':True})
    (ROOT/'Apps'/mainDir/'Info.plist').write_bytes(plistlib.dumps(info))
    sd=ROOT/'LumaStudio.xcodeproj'/'xcshareddata'/'xcschemes';sd.mkdir(parents=True,exist_ok=True)
    (sd/(target+'.xcscheme')).write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1640" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{tid}" BuildableName="{target}.app" BlueprintName="{target}" ReferencedContainer="container:LumaStudio.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug"/><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{tid}" BuildableName="{target}.app" BlueprintName="{target}" ReferencedContainer="container:LumaStudio.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{tid}" BuildableName="{target}.app" BlueprintName="{target}" ReferencedContainer="container:LumaStudio.xcodeproj"/></BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
products=add('products','isa = PBXGroup; children = '+array(prods)+'; name = Products; sourceTree = "<group>";')
group=add('group','isa = PBXGroup; children = '+array(refs+[products])+'; sourceTree = "<group>";')
cl=cfg_list('project',{'CLANG_ENABLE_MODULES':'YES','SWIFT_VERSION':'5.0','DEAD_CODE_STRIPPING':'YES','ENABLE_USER_SCRIPT_SANDBOXING':'YES'})
add('project','isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1640;}; buildConfigurationList = '+cl+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (en,zh_CN,Base,); mainGroup = '+group+'; packageReferences = '+array([package])+'; productRefGroup = '+products+'; projectDirPath = ""; projectRoot = ""; targets = '+array(targets)+';')
p=ROOT/'LumaStudio.xcodeproj'/'project.pbxproj'; p.parent.mkdir(exist_ok=True)
p.write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+''.join(i+' = {'+t+'};\n' for i,t in objects.items())+'}; rootObject = '+rootid+';}\n')
print(p)
