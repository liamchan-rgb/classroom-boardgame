#!/usr/bin/env python3
"""Generate design/art-expansion-v1/asset-manifest.json (SHA-256 + dimensions)
and build the self-contained compressed archive artifacts/meadow-expansion-art-v1.zip."""
from __future__ import annotations

import hashlib
import json
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image

PACK = Path(__file__).resolve().parents[1]
ROOT = PACK.parents[1]
ZIP_OUT = ROOT / "artifacts/meadow-expansion-art-v1.zip"
ZIP_OUT.parent.mkdir(parents=True, exist_ok=True)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    files_meta = []
    category_counts: dict[str, int] = {}

    for p in sorted(PACK.rglob("*")):
        if p.is_dir() or p.name == "asset-manifest.json" or p.name == ".DS_Store":
            continue
        rel = p.relative_to(PACK).as_posix()
        top = rel.split("/")[0] if "/" in rel else "root"
        category_counts[top] = category_counts.get(top, 0) + 1
        rec: dict = {
            "path": rel,
            "bytes": p.stat().st_size,
            "sha256": sha256_file(p),
        }
        if p.suffix.lower() == ".png":
            with Image.open(p) as im:
                rec["width"] = im.width
                rec["height"] = im.height
                rec["mode"] = im.mode
        files_meta.append(rec)

    manifest = {
        "package": "meadow-expansion-art-v1",
        "version": "1.0.0",
        "specSource": "design/主游戏拓展企划_职业装备怪物_美术交接_v1.txt",
        "baseAppVersion": "v0.32.4/build48",
        "installed": False,
        "builtAtUTC": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "summary": {
            "classBadges": 14,
            "itemIcons": 53,
            "itemIconFX": 41,
            "monsters": 16,
            "monsterSheets": 32,
            "monsterProjectiles": 8,
            "wearableWeapons": 17,
            "wearableArmors": 14,
            "pixelFXPacks": 8,
            "pixelFXClips": 23,
            "pixelFXRecipes": 70,
            "qaPreviews": len(list((PACK / "previews").glob("*.png"))),
            "totalFiles": len(files_meta),
            "totalBytes": sum(f["bytes"] for f in files_meta),
        },
        "categoryFileCounts": category_counts,
        "files": files_meta,
    }
    manifest_path = PACK / "asset-manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # Build deterministic compressed zip archive
    with zipfile.ZipFile(ZIP_OUT, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for p in sorted(PACK.rglob("*")):
            if p.is_dir() or p.name == ".DS_Store":
                continue
            rel = p.relative_to(PACK).as_posix()
            zf.write(p, f"meadow-expansion-art-v1/{rel}")

    print(f"Wrote {manifest_path} ({len(files_meta)} files)")
    print(f"Built {ZIP_OUT} ({ZIP_OUT.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
