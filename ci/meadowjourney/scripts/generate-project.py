#!/usr/bin/env python3
"""Emit a native, dependency-free Xcode project and shared scheme deterministically."""
import hashlib
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'MeadowJourney.xcodeproj'
PROJECT.mkdir(exist_ok=True)
objects = {}


def ident(key):
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()


def obj(key, isa, **values):
    objects[ident(key)] = {'isa': isa, **values}
    return ident(key)


def ref(key):
    return ident(key)


def file(key, path, kind, tree='<group>'):
    return obj(key, 'PBXFileReference', lastKnownFileType=kind, path=path, sourceTree=tree)


def build_file(key, file_ref):
    return obj(key, 'PBXBuildFile', fileRef=file_ref)


source_refs, source_builds = [], []
for path in sorted((ROOT / 'Sources').rglob('*.swift')):
    relative = str(path.relative_to(ROOT / 'Sources'))
    source_ref = file('file:' + relative, relative, 'sourcecode.swift')
    source_refs.append(source_ref)
    source_builds.append(build_file('build:' + relative, source_ref))
assets = file('assets', 'Resources/Assets.xcassets', 'folder.assetcatalog')
info = file('info', 'Resources/Info.plist', 'text.plist.xml')
scene_map = file('scene-map', 'Resources/SceneMap.json', 'text.json')
# 人物部件数据（发型、五官 JSON），以文件夹引用整体打包，网页制作工具读同一份
character_parts = file('character-parts', 'Resources/CharacterParts', 'folder')
source_refs += [assets, info, scene_map, character_parts]
app = obj('app-product', 'PBXFileReference', explicitFileType='wrapper.application',
          path='MeadowJourney.app', sourceTree='BUILT_PRODUCTS_DIR', includeInIndex=0)
unit = obj('unit-product', 'PBXFileReference', explicitFileType='wrapper.cfbundle',
           path='MeadowJourneyTests.xctest', sourceTree='BUILT_PRODUCTS_DIR', includeInIndex=0)
ui = obj('ui-product', 'PBXFileReference', explicitFileType='wrapper.cfbundle',
         path='MeadowJourneyUITests.xctest', sourceTree='BUILT_PRODUCTS_DIR', includeInIndex=0)
unit_ref = file('unit-source', 'TrailTests.swift', 'sourcecode.swift')
unit_refs = [unit_ref] + [file('unit-source:' + path.name, path.name, 'sourcecode.swift')
                          for path in sorted((ROOT / 'Tests').glob('*.swift')) if path.name != 'TrailTests.swift']
ui_ref = file('ui-source', 'JourneyUITests.swift', 'sourcecode.swift')
sources_group = obj('sources-group', 'PBXGroup', path='Sources', sourceTree='<group>', children=source_refs)
tests_group = obj('tests-group', 'PBXGroup', path='Tests', sourceTree='<group>', children=unit_refs)
ui_group = obj('ui-group', 'PBXGroup', path='UITests', sourceTree='<group>', children=[ui_ref])
products_group = obj('products-group', 'PBXGroup', name='Products', sourceTree='<group>', children=[app, unit, ui])
main_group = obj('main-group', 'PBXGroup', sourceTree='<group>', children=[sources_group, tests_group, ui_group, products_group])


def phase(key, isa, files):
    return obj(key, isa, buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0)


project_settings = {
    'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES',
    'IPHONEOS_DEPLOYMENT_TARGET': '15.0', 'SDKROOT': 'iphoneos',
    'SWIFT_VERSION': '5.0', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES',
    'CLANG_WARN_DOCUMENTATION_COMMENTS': 'YES', 'GCC_WARN_UNUSED_VARIABLE': 'YES',
    'CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER': 'YES',
}
app_settings = {
    'PRODUCT_NAME': '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.liamchan.experiment.meadow',
    'INFOPLIST_FILE': 'Sources/Resources/Info.plist', 'GENERATE_INFOPLIST_FILE': 'NO',
    'TARGETED_DEVICE_FAMILY': '1,2', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator',
    'CODE_SIGN_STYLE': 'Automatic', 'MARKETING_VERSION': '1.2.0', 'CURRENT_PROJECT_VERSION': '4',
    'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon',
    'LD_RUNPATH_SEARCH_PATHS': ['$(inherited)', '@executable_path/Frameworks'],
    'SWIFT_EMIT_LOC_STRINGS': 'YES', 'ENABLE_PREVIEWS': 'NO',
}


def configurations(key, settings):
    config_ids = []
    for name in ['Debug', 'Release']:
        value = dict(settings)
        value.update({'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if name == 'Debug' else '-O',
                      'DEBUG_INFORMATION_FORMAT': 'dwarf' if name == 'Debug' else 'dwarf-with-dsym'})
        if name == 'Debug':
            value.update({'ENABLE_TESTABILITY': 'YES', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG $(inherited)',
                          'ONLY_ACTIVE_ARCH': 'YES'})
        config_ids.append(obj(f'{key}:{name}', 'XCBuildConfiguration', name=name, buildSettings=value))
    return obj(key + ':configs', 'XCConfigurationList', buildConfigurations=config_ids,
               defaultConfigurationIsVisible=0, defaultConfigurationName='Release')


def target(key, name, product, sources, product_type, resources=None, settings=None, dependencies=None):
    return obj(key, 'PBXNativeTarget', name=name, productName=name, productReference=product,
               productType=product_type, buildConfigurationList=configurations(key, settings or {}),
               buildPhases=[phase(key + ':sources', 'PBXSourcesBuildPhase', sources),
                            phase(key + ':frameworks', 'PBXFrameworksBuildPhase', []),
                            phase(key + ':resources', 'PBXResourcesBuildPhase', resources or [])],
               buildRules=[], dependencies=dependencies or [])


target('app-target', 'MeadowJourney', app, source_builds, 'com.apple.product-type.application',
       resources=[build_file('assets-build', assets), build_file('scene-map-build', scene_map),
                  build_file('character-parts-build', character_parts)], settings=app_settings)
for key, name, product, sources, kind in [
    ('unit-target', 'MeadowJourneyTests', unit, unit_refs, 'unit-test'),
    ('ui-target', 'MeadowJourneyUITests', ui, [ui_ref], 'ui-testing')
]:
    proxy = obj(key + ':proxy', 'PBXContainerItemProxy', containerPortal=ref('project'), proxyType=1,
                remoteGlobalIDString=ref('app-target'), remoteInfo='MeadowJourney')
    dependency = obj(key + ':dependency', 'PBXTargetDependency', target=ref('app-target'), targetProxy=proxy)
    settings = {'PRODUCT_NAME': '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.liamchan.experiment.' + name,
                'GENERATE_INFOPLIST_FILE': 'YES', 'TARGETED_DEVICE_FAMILY': '1,2', 'CODE_SIGN_STYLE': 'Automatic',
                'LD_RUNPATH_SEARCH_PATHS': ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']}
    if kind == 'unit-test':
        settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/MeadowJourney.app/MeadowJourney'
        settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
    else:
        settings['TEST_TARGET_NAME'] = 'MeadowJourney'
    builds = [build_file(key + ':build', sources[0])] + [
        build_file(key + ':build:' + str(i), source) for i, source in enumerate(sources[1:], 1)]
    target(key, name, product, builds, 'com.apple.product-type.bundle.' + kind,
           settings=settings, dependencies=[dependency])

obj('project', 'PBXProject', attributes={'LastUpgradeCheck': '1640',
    'TargetAttributes': {ref('app-target'): {'CreatedOnToolsVersion': '16.4'},
                         ref('unit-target'): {'CreatedOnToolsVersion': '16.4', 'TestTargetID': ref('app-target')},
                         ref('ui-target'): {'CreatedOnToolsVersion': '16.4', 'TestTargetID': ref('app-target')}}},
    buildConfigurationList=configurations('project', project_settings), compatibilityVersion='Xcode 14.0',
    developmentRegion='zh_CN', hasScannedForEncodings=0, knownRegions=['en', 'zh_CN', 'Base'],
    mainGroup=main_group, productRefGroup=products_group, projectDirPath='', projectRoot='',
    targets=[ref('app-target'), ref('unit-target'), ref('ui-target')])


def serialize(value, level=0):
    if isinstance(value, dict):
        return '{\n' + ''.join('\t' * (level + 1) + serialize(k) + ' = ' + serialize(v, level + 1) + ';\n'
                              for k, v in value.items()) + '\t' * level + '}'
    if isinstance(value, list):
        return '(\n' + ''.join('\t' * (level + 1) + serialize(v, level + 1) + ',\n' for v in value) + '\t' * level + ')'
    if isinstance(value, int):
        return str(value)
    if len(value) == 24 and all(c in '0123456789ABCDEF' for c in value):
        return value
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


data = {'archiveVersion': 1, 'classes': {}, 'objectVersion': 56, 'objects': objects, 'rootObject': ref('project')}
(PROJECT / 'project.pbxproj').write_text('// !$*UTF8*$!\n' + serialize(data) + '\n')


def buildable(key, name, product):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref(key)}" BuildableName="{escape(product)}" BlueprintName="{name}" ReferencedContainer="container:MeadowJourney.xcodeproj"/>'


app_buildable = buildable('app-target', 'MeadowJourney', 'MeadowJourney.app')
testables = ''.join('<TestableReference skipped="NO">' + buildable(key, name, name + '.xctest') + '</TestableReference>'
                    for key, name in [('unit-target', 'MeadowJourneyTests'), ('ui-target', 'MeadowJourneyUITests')])
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1640" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_buildable}</BuildActionEntry></BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables>{testables}</Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{app_buildable}</BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{app_buildable}</BuildableProductRunnable>
  </ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_dir = PROJECT / 'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / 'MeadowJourney.xcscheme').write_text(scheme)
print('Generated MeadowJourney.xcodeproj and shared app/test scheme.')
