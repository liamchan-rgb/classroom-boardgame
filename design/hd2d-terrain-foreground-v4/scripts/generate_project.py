from pathlib import Path
import hashlib,json,plistlib
from xml.sax.saxutils import escape
R=Path(__file__).resolve().parents[1]
N=R/'Native';P=N/'GrassLightingPrototype.xcodeproj';P.mkdir(exist_ok=True)
objects={}
def ident(name):return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def obj(object_key,isa,**kwargs):
    key=ident(object_key);objects[key]=dict(isa=isa,**kwargs);return key
def file(name,path,kind,sourceTree='<group>'):
    return obj(name,'PBXFileReference',path=path,lastKnownFileType=kind,sourceTree=sourceTree)
def sources(group,directory):
    refs=[];builds=[]
    for p in sorted((N/directory).glob('*.swift')):
        ref=file(directory+p.name,p.name,'sourcecode.swift');refs.append(ref);builds.append(obj('build'+directory+p.name,'PBXBuildFile',fileRef=ref))
    return obj(group,'PBXGroup',path=directory,sourceTree='<group>',children=refs),builds
sourceGroup,sourceBuilds=sources('sources','Sources');testGroup,testBuilds=sources('tests','Tests')
art=file('art','Resources/Art','folder');artBuild=obj('artBuild','PBXBuildFile',fileRef=art)
info=file('info','Resources/Info.plist','text.plist.xml')
appProduct=file('appProduct','GrassLightingPrototype.app','wrapper.application','BUILT_PRODUCTS_DIR')
testProduct=file('testProduct','DisplayGeometryTests.xctest','wrapper.cfbundle','BUILT_PRODUCTS_DIR')
productGroup=obj('products','PBXGroup',name='Products',sourceTree='<group>',children=[appProduct,testProduct])
mainGroup=obj('main','PBXGroup',sourceTree='<group>',children=[sourceGroup,testGroup,art,info,productGroup])
projectID=ident('project');appID=ident('appTarget')
def configurations(name,extra):
    ids=[]
    for mode in ['Debug','Release']:
        settings=dict(SWIFT_VERSION='5.0',IPHONEOS_DEPLOYMENT_TARGET='17.0',SDKROOT='iphoneos',SUPPORTED_PLATFORMS='iphoneos iphonesimulator',TARGETED_DEVICE_FAMILY='2',CLANG_ENABLE_MODULES='YES',SWIFT_OPTIMIZATION_LEVEL='-Onone' if mode=='Debug' else '-O',DEBUG_INFORMATION_FORMAT='dwarf' if mode=='Debug' else 'dwarf-with-dsym',ENABLE_TESTABILITY='YES' if mode=='Debug' else 'NO')
        settings.update(extra)
        if mode=='Debug':settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG $(inherited)'
        ids.append(obj(name+mode,'XCBuildConfiguration',name=mode,buildSettings=settings))
    return obj(name+'configList','XCConfigurationList',buildConfigurations=ids,defaultConfigurationName='Release',defaultConfigurationIsVisible=0)
projectConfig=configurations('project',{})
appConfig=configurations('app',dict(PRODUCT_NAME='$(TARGET_NAME)',PRODUCT_BUNDLE_IDENTIFIER='com.classroomboardgame.design.grasshd2dv3',INFOPLIST_FILE='Resources/Info.plist',GENERATE_INFOPLIST_FILE='NO',CODE_SIGN_STYLE='Automatic',SUPPORTS_MACCATALYST='NO',LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/Frameworks',MARKETING_VERSION='0.4',CURRENT_PROJECT_VERSION='4'))
def phase(name,isa,files):return obj(name,isa,buildActionMask=2147483647,files=files,runOnlyForDeploymentPostprocessing=0)
appSources=phase('appSources','PBXSourcesBuildPhase',sourceBuilds);appResources=phase('appResources','PBXResourcesBuildPhase',[artBuild]);appFrameworks=phase('appFrameworks','PBXFrameworksBuildPhase',[])
obj('appTarget','PBXNativeTarget',name='GrassLightingPrototype',productName='GrassLightingPrototype',productReference=appProduct,productType='com.apple.product-type.application',buildConfigurationList=appConfig,buildPhases=[appSources,appFrameworks,appResources],buildRules=[],dependencies=[])
testIDs=[]
for key,name,product,builds,ui in [('unit','DisplayGeometryTests',testProduct,testBuilds,False)]:
    extra=dict(PRODUCT_NAME='$(TARGET_NAME)',PRODUCT_BUNDLE_IDENTIFIER='com.classroomboardgame.design.hd2dv4.'+key+'tests',GENERATE_INFOPLIST_FILE='YES',CODE_SIGN_STYLE='Automatic',LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/Frameworks @loader_path/Frameworks')
    if ui:extra['TEST_TARGET_NAME']='GrassLightingPrototype'
    else:extra.update(TEST_HOST='$(BUILT_PRODUCTS_DIR)/GrassLightingPrototype.app/GrassLightingPrototype',BUNDLE_LOADER='$(TEST_HOST)')
    config=configurations(key,extra)
    proxy=obj(key+'proxy','PBXContainerItemProxy',containerPortal=projectID,proxyType=1,remoteGlobalIDString=appID,remoteInfo='GrassLightingPrototype')
    dependency=obj(key+'dependency','PBXTargetDependency',target=appID,targetProxy=proxy)
    target=obj(key+'Target','PBXNativeTarget',name=name,productName=name,productReference=product,productType='com.apple.product-type.bundle.ui-testing' if ui else 'com.apple.product-type.bundle.unit-test',buildConfigurationList=config,buildPhases=[phase(key+'Sources','PBXSourcesBuildPhase',builds),phase(key+'Frameworks','PBXFrameworksBuildPhase',[]),phase(key+'Resources','PBXResourcesBuildPhase',[])],buildRules=[],dependencies=[dependency]);testIDs.append((target,name))
obj('project','PBXProject',attributes=dict(LastUpgradeCheck='1600',TargetAttributes={appID:dict(CreatedOnToolsVersion='16.0',ProvisioningStyle='Automatic'),**{key:dict(CreatedOnToolsVersion='16.0',TestTargetID=appID) for key,_ in testIDs}}),buildConfigurationList=projectConfig,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=mainGroup,productRefGroup=productGroup,projectDirPath='',projectRoot='',targets=[appID]+[key for key,_ in testIDs])
def encode(value):
    if isinstance(value,dict):return '{\n'+''.join(json.dumps(str(k))+ ' = '+encode(v)+';\n' for k,v in value.items())+'}'
    if isinstance(value,list):return '('+','.join(encode(v) for v in value)+')'
    if isinstance(value,int):return str(value)
    return json.dumps(value,ensure_ascii=False)
(P/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode(dict(archiveVersion=1,classes={},objectVersion=56,objects=objects,rootObject=projectID))+'\n')
scheme=P/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
def ref(key,name,ext):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{key}" BuildableName="{escape(name)}.{ext}" BlueprintName="{escape(name)}" ReferencedContainer="container:GrassLightingPrototype.xcodeproj"/>'
build=''.join('<BuildActionEntry buildForTesting="YES" buildForRunning="'+('YES' if key==appID else 'NO')+'" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">'+ref(key,name,'app' if key==appID else 'xctest')+'</BuildActionEntry>' for key,name in [(appID,'GrassLightingPrototype')]+testIDs)
tests=''.join('<TestableReference skipped="NO">'+ref(key,name,'xctest')+'</TestableReference>' for key,name in testIDs)
(scheme/'GrassLightingPrototype.xcscheme').write_text('<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>'+build+'</BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>'+tests+'</Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">'+ref(appID,'GrassLightingPrototype','app')+'</BuildableProductRunnable></LaunchAction><AnalyzeAction buildConfiguration="Debug"/></Scheme>\n')
plist=dict(CFBundleDisplayName='GrassHD2D',CFBundleExecutable='$(EXECUTABLE_NAME)',CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)',CFBundleName='$(PRODUCT_NAME)',CFBundlePackageType='APPL',CFBundleInfoDictionaryVersion='6.0',CFBundleShortVersionString='0.4',CFBundleVersion='4',LSRequiresIPhoneOS=True,UIRequiresFullScreen=True,UILaunchScreen={},UIApplicationSceneManifest=dict(UIApplicationSupportsMultipleScenes=False,UISceneConfigurations={}),UISupportedInterfaceOrientations=['UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'])
with (N/'Resources/Info.plist').open('wb') as out:plistlib.dump(plist,out)
print('Independent project generated:',P)
