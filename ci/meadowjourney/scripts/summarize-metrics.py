#!/usr/bin/env python3
import json
import statistics
import sys
from pathlib import Path

samples = json.loads(Path(sys.argv[1]).read_text())
assert len(samples) >= 8, 'Expected multiple measured running frames'
assert all(sample['independentProps'] > 140 for sample in samples)
assert all(sample['roads'] == 4 for sample in samples)
fps = [sample['fps'] for sample in samples if sample['fps'] > 0]
assert fps
print(json.dumps({
    'environment': 'GitHub macOS iPad Simulator (not a physical iPad benchmark)',
    'samples': len(samples), 'averageFPS': round(statistics.mean(fps), 2),
    'minimumFPS': round(min(fps), 2),
    'maximumResidentMiB': round(max(sample['residentMemoryMiB'] for sample in samples), 2),
    'decodedTextureMiB': samples[-1]['textureBudgetMiB'],
    'independentProps': samples[-1]['independentProps'],
    'discovered': samples[-1]['discoveries']
}, ensure_ascii=False, indent=2))
