#!/usr/bin/env python3
"""Validate resource bindings and shared scheme without requiring Xcode or Pillow."""
import json
import plistlib
import re
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(__file__).resolve().parents[1]
project = root / 'MeadowJourney.xcodeproj'
pbx = (project / 'project.pbxproj').read_text()
plist = plistlib.loads((root / 'Sources/Resources/Info.plist').read_bytes())
assert re.fullmatch(r'[A-Za-z][A-Za-z0-9 -]*', plist['CFBundleDisplayName']), \
    'SideStore App ID registration requires an ASCII-safe display name for this package'
assert plist['UISupportedInterfaceOrientations'] == [
    'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight']
for file in (root / 'Sources').rglob('*.swift'):
    assert str(file.relative_to(root / 'Sources')) in pbx, f'Unbound Swift file: {file}'
for catalog in (root / 'Sources/Resources/Assets.xcassets').rglob('Contents.json'):
    data = json.loads(catalog.read_text())
    for entry in data.get('images', []):
        if 'filename' in entry:
            assert (catalog.parent / entry['filename']).is_file(), f'Missing image: {entry}'
scheme = ET.parse(project / 'xcshareddata/xcschemes/MeadowJourney.xcscheme')
refs = scheme.findall('.//BuildableReference')
assert len(scheme.findall('.//TestableReference')) == 2
for ref in refs:
    assert ref.attrib['BlueprintIdentifier'] in pbx, 'Scheme target ID missing from project'
    assert ref.attrib['ReferencedContainer'] == 'container:MeadowJourney.xcodeproj'
assert 'com.apple.product-type.application' in pbx
assert '"IPHONEOS_DEPLOYMENT_TARGET" = "15.0"' in pbx
definition = json.loads((root / 'Sources/Resources/SceneMap.json').read_text())
assert 'Resources/SceneMap.json' in pbx
assert len(definition['roads']) >= 4
for prop in definition['props']:
    assert (root / 'Sources/Resources/Assets.xcassets' / (prop['asset'] + '.imageset')).is_dir()
assert not (root / 'Sources/Resources/Assets.xcassets/MapBackground.imageset').exists(), 'Flattened scene must not ship'
# 人物部件数据：以文件夹引用打包，每个 JSON 可解析且 id 唯一，眼睛引用的图案都存在
assert 'Resources/CharacterParts' in pbx, 'CharacterParts folder must be bundled'
for path in (root / 'Tests').glob('*.swift'):
    assert path.name in pbx, f'Unbound test file: {path}'
part_ids = set()
for kind in ('hair', 'face'):
    files = sorted((root / 'Sources/Resources/CharacterParts' / kind).glob('*.json'))
    assert files, f'No {kind} data'
    for path in files:
        data = json.loads(path.read_text())
        assert data['id'] not in part_ids, f'Duplicate part id: {data["id"]}'
        part_ids.add(data['id'])
        if kind == 'hair':
            assert len(data['palette']) == 5 and data['locks'] and len(data['hairline']) >= 2, path
        else:
            for view in data['views'].values():
                for name, _, _ in view.get('eyes', []):
                    assert name.rstrip('!') in data['patterns'], f'{path}: unknown eye pattern {name}'
print('Project paths, Swift file references, asset bindings, character parts, orientations and shared test scheme valid.')
