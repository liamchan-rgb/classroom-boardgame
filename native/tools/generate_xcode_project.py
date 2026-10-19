#!/usr/bin/env python3
"""Regenerate the small checked-in Xcode project without XcodeGen/Homebrew."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
objects = {}


def identifier(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def add(label, isa, **fields):
    key = identifier(label)
    objects[key] = dict(isa=isa, **fields)
    return key


def encode(value, level=0):
    if isinstance(value, dict):
        body = "\n".join("\t" * (level + 1) + json.dumps(key) + " = " + encode(item, level + 1) + ";"
                         for key, item in value.items())
        return "{\n" + body + "\n" + "\t" * level + "}"
    if isinstance(value, list):
        return "(\n" + "".join("\t" * (level + 1) + encode(item, level + 1) + ",\n" for item in value) + "\t" * level + ")"
    return json.dumps(str(value), ensure_ascii=False)


sources = []
files = []
for name in ("App.swift", "DeckRenderer.swift", "TeacherSession.swift", "Views.swift", "RulesLabView.swift", "PVEAppSession.swift", "PVEStyle.swift", "PVEMapView.swift", "PVEPublicView.swift", "PVEPlayView.swift", "PVESheets.swift", "PVEKeyboard.swift", "PVEArt.swift", "NativeVisualValidation.swift"):
    ref = add("file:" + name, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=name, sourceTree="<group>")
    files.append(ref)
    sources.append(add("build:" + name, "PBXBuildFile", fileRef=ref))
plist = add("info", "PBXFileReference", lastKnownFileType="text.plist.xml", path="Info.plist", sourceTree="<group>")
files.append(plist)
resource_builds = []
for name in ("sample.pptx", "ThirdPartyNotices.txt", "design-tokens.json"):
    ref = add("resource:" + name, "PBXFileReference", lastKnownFileType="file", path="Resources/" + name, sourceTree="<group>")
    files.append(ref)
    resource_builds.append(add("build:" + name, "PBXBuildFile", fileRef=ref))
ref = add("resource:Art", "PBXFileReference", lastKnownFileType="folder", path="Resources/Art", sourceTree="<group>")
files.append(ref)
resource_builds.append(add("build:Art", "PBXBuildFile", fileRef=ref))
product = add("product", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex="0", path="ClassroomProbe.app", sourceTree="BUILT_PRODUCTS_DIR")
app_group = add("app-group", "PBXGroup", children=files, path="ClassroomProbe", sourceTree="<group>")
products_group = add("products-group", "PBXGroup", children=[product], name="Products", sourceTree="<group>")
main_group = add("main-group", "PBXGroup", children=[app_group, products_group], sourceTree="<group>")
package = add("core-package", "XCLocalSwiftPackageReference", relativePath="Packages/ProbeCore")
package_product = add("core-product", "XCSwiftPackageProductDependency", package=package, productName="ClassroomProbeCore")
framework_build = add("build:core", "PBXBuildFile", productRef=package_product)
game_package = add("game-package", "XCLocalSwiftPackageReference", relativePath="Packages/GameCore")
game_product = add("game-product", "XCSwiftPackageProductDependency", package=game_package, productName="ClassroomGameCore")
game_framework = add("build:game", "PBXBuildFile", productRef=game_product)
source_phase = add("sources", "PBXSourcesBuildPhase", buildActionMask="2147483647", files=sources, runOnlyForDeploymentPostprocessing="0")
resource_phase = add("resources", "PBXResourcesBuildPhase", buildActionMask="2147483647", files=resource_builds, runOnlyForDeploymentPostprocessing="0")
framework_phase = add("frameworks", "PBXFrameworksBuildPhase", buildActionMask="2147483647", files=[framework_build, game_framework], runOnlyForDeploymentPostprocessing="0")
project_configs = []
target_configs = []
for name in ("Debug", "Release"):
    project_settings = dict(ALWAYS_SEARCH_USER_PATHS="NO", CLANG_ENABLE_MODULES="YES", CLANG_ENABLE_OBJC_ARC="YES",
                            IPHONEOS_DEPLOYMENT_TARGET="27.0", SDKROOT="iphoneos", SWIFT_VERSION="5.0",
                            SWIFT_OPTIMIZATION_LEVEL="-Onone" if name == "Debug" else "-O",
                            DEBUG_INFORMATION_FORMAT="dwarf" if name == "Debug" else "dwarf-with-dsym",
                            ENABLE_TESTABILITY="YES" if name == "Debug" else "NO")
    if name == "Debug":
        project_settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG $(inherited)"
    project_configs.append(add("project:" + name, "XCBuildConfiguration", name=name, buildSettings=project_settings))
    target_settings = dict(PRODUCT_NAME="$(TARGET_NAME)", PRODUCT_BUNDLE_IDENTIFIER="org.personal.classroom.stage0",
                           INFOPLIST_FILE="ClassroomProbe/Info.plist", GENERATE_INFOPLIST_FILE="NO",
                           CODE_SIGN_STYLE="Manual", CODE_SIGNING_ALLOWED="NO", CODE_SIGNING_REQUIRED="NO",
                           TARGETED_DEVICE_FAMILY="2", SUPPORTED_PLATFORMS="iphoneos iphonesimulator",
                           SUPPORTS_MACCATALYST="NO", SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD="NO",
                           SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD="NO", SWIFT_EMIT_LOC_STRINGS="NO",
                           LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks"],
                           CURRENT_PROJECT_VERSION="11", MARKETING_VERSION="0.11")
    target_configs.append(add("target:" + name, "XCBuildConfiguration", name=name, buildSettings=target_settings))
project_config_list = add("project-config-list", "XCConfigurationList", buildConfigurations=project_configs,
                          defaultConfigurationIsVisible="0", defaultConfigurationName="Release")
target_config_list = add("target-config-list", "XCConfigurationList", buildConfigurations=target_configs,
                         defaultConfigurationIsVisible="0", defaultConfigurationName="Release")
target = add("target", "PBXNativeTarget", name="ClassroomProbe", productName="ClassroomProbe", productReference=product,
             productType="com.apple.product-type.application", buildConfigurationList=target_config_list,
             buildPhases=[source_phase, framework_phase, resource_phase], buildRules=[], dependencies=[],
             packageProductDependencies=[package_product, game_product])
project = add("project", "PBXProject", attributes=dict(LastUpgradeCheck="2700", BuildIndependentTargetsInParallel="YES"),
              buildConfigurationList=project_config_list, compatibilityVersion="Xcode 14.0", developmentRegion="zh-Hans",
              hasScannedForEncodings="0", knownRegions=["zh-Hans", "en", "Base"], mainGroup=main_group,
              productRefGroup=products_group, projectDirPath="", projectRoot="", targets=[target], packageReferences=[package, game_package])
project_path = ROOT / "ClassroomProbe.xcodeproj"
(project_path / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode(dict(archiveVersion="1", classes={}, objectVersion="56",
                                                                            objects=objects, rootObject=project)) + "\n", encoding="utf-8")
scheme_dir = project_path / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / "ClassroomProbe.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="NO" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="ClassroomProbe.app" BlueprintName="ClassroomProbe" ReferencedContainer="container:ClassroomProbe.xcodeproj"/>
      </BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="ClassroomProbe.app" BlueprintName="ClassroomProbe" ReferencedContainer="container:ClassroomProbe.xcodeproj"/>
    </BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''', encoding="utf-8")
print("Generated ClassroomProbe.xcodeproj and shared ClassroomProbe scheme.")
