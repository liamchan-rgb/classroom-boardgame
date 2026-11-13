#!/usr/bin/env python3
"""Extract independently rendered objects and align direction frames for runtime assembly."""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / 'Art/Generated/LivingScene'
CATALOG = ROOT / 'Sources/Resources/Assets.xcassets'
manifest = {}


def save_asset(name, image):
    path = CATALOG / (name + '.imageset')
    path.mkdir(exist_ok=True)
    image.save(path / (name + '.png'), optimize=True)
    (path / 'Contents.json').write_text(json.dumps({
        'info': {'author': 'xcode', 'version': 1},
        'images': [{'filename': name + '.png', 'idiom': 'universal'}]
    }, indent=2) + '\n')
    manifest[name] = {'width': image.width, 'height': image.height,
                      'decodedBytes': image.width * image.height * 4}


save_asset('MeadowGround', Image.open(RAW / 'ground.png').convert('RGB'))

# Regions follow the actual atlas's transparent gutters, rather than assuming equal object widths.
terrain_regions = [
    ('OakA', (0, 0, 535, 580)), ('OakB', (535, 0, 1090, 580)),
    ('Pines', (1090, 0, 1536, 580)), ('RockLow', (0, 580, 550, 1024)),
    ('RockHigh', (550, 580, 1110, 1024)), ('RockSmall', (1110, 580, 1536, 1024))
]
props_regions = [
    ('CampTent', (0, 0, 615, 580)), ('WatchTower', (615, 0, 1000, 580)),
    ('Shrub', (1000, 0, 1536, 580)), ('Fence', (0, 580, 500, 1024)),
    ('Flowers', (500, 580, 1070, 1024)), ('Banner', (1070, 580, 1536, 1024))
]
for source_name, regions in [('terrain-atlas.png', terrain_regions), ('props-atlas.png', props_regions)]:
    source = Image.open(RAW / source_name).convert('RGBA')
    assert source.size == (1536, 1024)
    for name, region in regions:
        cell = source.crop(region)
        bounds = cell.getchannel('A').point(lambda alpha: 255 if alpha > 48 else 0).getbbox()
        if bounds is None:
            raise ValueError('Empty object: ' + name)
        sprite = cell.crop(bounds)
        # Keep native object resolution; a transparent gutter protects shader deformation edges.
        padded = Image.new('RGBA', (sprite.width + 16, sprite.height + 16))
        padded.alpha_composite(sprite, (8, 8))
        save_asset(name, padded)

for hero in range(1, 4):
    source = Image.open(RAW / f'hero{hero}.png').convert('RGBA')
    cells = []
    for row in range(4):
        for column in range(4):
            cell = source.crop((column * source.width // 4, row * source.height // 4,
                                (column + 1) * source.width // 4, (row + 1) * source.height // 4))
            bounds = cell.getchannel('A').point(lambda alpha: 255 if alpha > 80 else 0).getbbox()
            if bounds is None:
                raise ValueError('Empty hero frame')
            cells.append(cell.crop(bounds))
    # One scale per character preserves frame-to-frame body dimensions and stride variation.
    scale = 240 / max(cell.height for cell in cells)
    atlas = Image.new('RGBA', (1536, 1536))
    for index, cell in enumerate(cells):
        width = round(cell.width * scale)
        height = round(cell.height * scale)
        cell = cell.resize((width, height), Image.Resampling.NEAREST)
        row, column = divmod(index, 4)
        atlas.alpha_composite(cell, (column * 384 + (384 - width) // 2, row * 384 + 336 - height))
    save_asset(f'Hero{hero}Directions', atlas)

(ROOT / 'Art/Generated/LivingScene/asset-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Prepared', len(manifest), 'independent assets; decoded texture budget:',
      round(sum(item['decodedBytes'] for item in manifest.values()) / (1024 * 1024), 1), 'MiB')
