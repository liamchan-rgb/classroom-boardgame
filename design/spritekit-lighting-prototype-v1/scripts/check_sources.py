from pathlib import Path
import hashlib,json,plistlib,xml.etree.ElementTree as ET
from openstep_parser import OpenStepDecoder
from tree_sitter import Language,Parser
import tree_sitter_swift
R=Path(__file__).resolve().parents[1]
parser=Parser(Language(tree_sitter_swift.language()));syntax=[]
for p in sorted((R/'Native').rglob('*.swift')):
    tree=parser.parse(p.read_bytes());errors=[]
    def walk(node):
        if node.type=='ERROR' or node.is_missing:errors.append({'start':list(node.start_point),'kind':node.type})
        for child in node.children:walk(child)
    walk(tree.root_node);assert not errors,(p,errors)
    syntax.append({'file':str(p.relative_to(R)),'syntax':'pass','sdkTypecheck':'not-run'})
project=OpenStepDecoder.ParseFromString((R/'Native/GrassLightingPrototype.xcodeproj/project.pbxproj').read_text());objects=project['objects']
assert project['rootObject'] in objects
for item in objects.values():
    for key in ['fileRef','mainGroup','productReference','productRefGroup','target','targetProxy','buildConfigurationList','containerPortal','remoteGlobalIDString']:
        if key in item:assert item[key] in objects,(key,item[key])
    for key in ['children','buildConfigurations','buildPhases','dependencies','targets','files']:
        for ref in item.get(key,[]):assert ref in objects,(key,ref)
targets=[o for o in objects.values() if o['isa']=='PBXNativeTarget'];assert len(targets)==3
scheme=ET.parse(R/'Native/GrassLightingPrototype.xcodeproj/xcshareddata/xcschemes/GrassLightingPrototype.xcscheme')
for ref in scheme.findall('.//BuildableReference'):assert ref.attrib['BlueprintIdentifier'] in objects
assert len(scheme.findall('.//TestableReference'))==2
with (R/'Native/Resources/Info.plist').open('rb') as f:info=plistlib.load(f)
assert info['CFBundleDisplayName']=='草地光影小样'
manifest=json.loads((R/'Native/Resources/Art/module-manifest.json').read_text())
from PIL import Image
for row in manifest['sceneryAndLandmarks']:
    x,y,w,h=row['sourceRect'];im=Image.open(R/'Native/Resources/Art'/f'{row["kind"]}_atlas.png');assert x>=0 and y>=0 and x+w<=im.width and y+h<=im.height
for row in manifest['adventurerFrames']:
    x,y,w,h=row['sourceRect'];im=Image.open(R/'Native/Resources/Art/adventurer_sheet.png');assert x+w<=im.width and y+h<=im.height
source=R.parent/'ideal-grass-map-slice-v6'
for p in (R/'Native/Resources/Art').glob('*.png'):assert p.read_bytes()==(source/'assets'/p.name).read_bytes()
assert (R/'reference/ideal-effect-user.jpg').read_bytes()==(source/'reference/ideal-effect-user.jpg').read_bytes()
report=dict(status='static-checks-pass',swiftSyntax=syntax,projectObjectGraph='pass',scheme='pass',resourceRects='pass',reusedAssetBytes='pass',userIdealReferenceBytes='pass',nativeBuild='not-run-no-Xcode-or-Apple-SDK',nativeTests='not-run',nativeScreenshots='not-produced',nativePerformance='not-measured',artApproved=False)
(R/'evidence/source-checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))
