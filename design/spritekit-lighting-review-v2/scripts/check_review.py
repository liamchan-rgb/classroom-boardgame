"""Check new review configuration and immutable source assets without Apple SDK."""
from pathlib import Path
import hashlib
import json
import shutil
import struct
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
provenance = json.loads((root / "asset-provenance.json").read_text())
for name, digest in provenance["assets"].items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
assert hashlib.sha256((root / "reference/ideal-effect-user.jpg").read_bytes()).hexdigest() == provenance["userIdealReferenceSHA256"]
with tempfile.TemporaryDirectory() as directory:
    copy = Path(directory)
    (copy / "scripts").mkdir()
    (copy / "Native/Resources").mkdir(parents=True)
    for name in ("Sources", "Tests", "UITests"):
        shutil.copytree(root / "Native" / name, copy / "Native" / name)
    script = copy / "scripts/generate_project.py"
    shutil.copyfile(root / "scripts/generate_project.py", script)
    subprocess.run([sys.executable, str(script)], check=True)
    for name in ("Native/GrassLightingPrototype.xcodeproj/project.pbxproj",
                 "Native/GrassLightingPrototype.xcodeproj/xcshareddata/xcschemes/GrassLightingPrototype.xcscheme",
                 "Native/Resources/Info.plist"):
        assert (root / name).read_bytes() == (copy / name).read_bytes(), "Regenerate project: " + name
art = root / "Native/Resources/Art"
manifest = json.loads((art / "module-manifest.json").read_text())
dimensions = {}
for image in art.glob("*.png"):
    header = image.read_bytes()[:24]
    assert header[:8] == b"\x89PNG\r\n\x1a\n"
    dimensions[image.stem] = struct.unpack(">II", header[16:24])
for group, source in (("terrain", "terrain_atlas"), ("sceneryAndLandmarks", None), ("adventurerFrames", "adventurer_sheet")):
    for row in manifest[group]:
        width, height = dimensions[source or row["kind"] + "_atlas"]
        x, y, w, h = row["sourceRect"]
        assert 0 <= x < x + w <= width and 0 <= y < y + h <= height, row
        anchor = row.get("anchorPx")
        if anchor:
            assert 0 <= anchor[0] <= w and 0 <= anchor[1] <= h, row
print("PASS: regenerated project/scheme/Info.plist, original asset bytes, ideal reference and atlas rectangles.")
print("SDK compilation, native tests and visual judgement are separate CI/review steps.")
