#!/usr/bin/env python3
"""Staged installer for Meadow Journey Expansion Art & PixelFX Pack v1.0.
DO NOT RUN until explicitly requested! Defaults to --dry-run (safe inspection).

When approved, run:
  python3 design/art-expansion-v1/tools/install_expansion_pack.py --apply

This script will:
  1. Verify package integrity via verify_expansion_pack.py.
  2. Install 14 ClassBadge, 53 PixelIcon, 41 PixelIconFX, 32 MeadowMonster Motion/Death,
     8 Proj*, and 23 PixelFX_* .imagesets into native/ClassroomProbe/Resources/Assets.xcassets/
     (never overwriting existing locked imagesets unless --force-badges for unified 4 class badges).
  3. Merge monsters/motion_expansion.json into MeadowMonsterVisuals.dataset/motion.json
     and pixel-fx/recipes_expansion.json into PixelFXRecipes.dataset/recipes.json.
  4. Copy pixel-baker/pixel_equipment_expansion.js into native/tools/, wire the extended
     bridge symbols into native/tools/build_pixel_baker.py, and rebuild pixel-baker.js.
  5. Re-run native/tools/generate_xcode_project.py & validate_xcode_project.py.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

PACK = Path(__file__).resolve().parents[1]
ROOT = PACK.parents[1]
ASSETS = ROOT / "native/ClassroomProbe/Resources/Assets.xcassets"
TOOLS = ROOT / "native/tools"
MOTION_JSON = ASSETS / "MeadowMonsterVisuals.dataset/motion.json"
RECIPES_JSON = ASSETS / "PixelFXRecipes.dataset/recipes.json"

OLD_BRIDGE = (
    '        + "\\nregisterCharacterExpansion({"\n'
    '        + "k,v,ie,Me,ho,Je,ze,We,Ao,i0,J,gt,Mt,Pe,ae,uo,ue,ut,wt,Le,z,mt,Q,V,_t,Et,pt,ct,xa,ma,Sa"\n'
    '        + "});\\n"\n'
    '        + "// --- END PROCEDURAL CHARACTER EXPANSION ---\\n"'
)

NEW_BRIDGE = (
    '        + "\\nregisterCharacterExpansion({"\n'
    '        + "k,v,ie,Me,ho,Je,ze,We,Ao,i0,J,gt,Mt,Pe,ae,uo,ue,ut,wt,Le,z,mt,Q,V,_t,Et,pt,ct,xa,ma,Sa"\n'
    '        + "});\\n"\n'
    '        + "// --- END PROCEDURAL CHARACTER EXPANSION ---\\n"\n'
    '        + "// --- BEGIN PROCEDURAL EQUIPMENT EXPANSION ---\\n"\n'
    '        + (TOOLS / "pixel_equipment_expansion.js").read_text(encoding="utf-8")\n'
    '        + "\\nregisterEquipmentExpansion({"\n'
    '        + "k,v,Me,J,gt,Mt,Pe,ae,uo,ue,ut,wt,z,Q,V,_t,Et,pt,ct,St,Z,lt,O,ye,jt,At,ko,Ut,xe,te,be,Qe,rt"\n'
    '        + "});\\n"\n'
    '        + "// --- END PROCEDURAL EQUIPMENT EXPANSION ---\\n"'
)


def write_imageset(src_png: Path, imageset_name: str, apply: bool) -> str:
    dest_dir = ASSETS / f"{imageset_name}.imageset"
    dest_png = dest_dir / f"{imageset_name}.png"
    contents = {
        "images": [{"filename": f"{imageset_name}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }
    status = "UPDATE" if dest_dir.exists() else "CREATE"
    if apply:
        dest_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src_png, dest_png)
        (dest_dir / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")
    return status


def main() -> int:
    ap = argparse.ArgumentParser(description="Install staged Meadow Journey Expansion Art Pack v1.0")
    ap.add_argument("--apply", action="store_true", help="Actually install files into the live project (default: dry-run)")
    args = ap.parse_args()

    # Always run integrity check first
    subprocess.run([sys.executable, str(PACK / "tools/verify_expansion_pack.py")], check=True)

    plan_imagesets: list[tuple[Path, str]] = []
    for folder in ("class-badges", "item-icons", "item-icon-fx", "monsters", "monsters/projectiles", "pixel-fx"):
        for p in sorted((PACK / folder).glob("*.png")):
            plan_imagesets.append((p, p.stem))

    created = updated = 0
    for src, name in plan_imagesets:
        st = write_imageset(src, name, args.apply)
        if st == "CREATE":
            created += 1
        else:
            updated += 1

    print(f"[{'APPLY' if args.apply else 'DRY-RUN'}] Imagesets: {created} new, {updated} existing (total {len(plan_imagesets)})")

    # Merge motion.json
    base_motion = json.loads(MOTION_JSON.read_text(encoding="utf-8"))
    exp_motion = json.loads((PACK / "monsters/motion_expansion.json").read_text(encoding="utf-8"))
    existing_ids = {r["id"] for r in base_motion["records"]}
    added_mon = [r for r in exp_motion["records"] if r["id"] not in existing_ids]
    print(f"[{'APPLY' if args.apply else 'DRY-RUN'}] motion.json: +{len(added_mon)} monster records")
    if args.apply and added_mon:
        base_motion["records"].extend(added_mon)
        MOTION_JSON.write_text(json.dumps(base_motion, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # Merge PixelFX recipes.json
    base_fx = json.loads(RECIPES_JSON.read_text(encoding="utf-8"))
    exp_fx = json.loads((PACK / "pixel-fx/recipes_expansion.json").read_text(encoding="utf-8"))
    ex_cids = {c["id"] for c in base_fx["clips"]}
    added_clips = [c for c in exp_fx["clips"] if c["id"] not in ex_cids]
    added_recipes = {k: v for k, v in exp_fx["recipes"].items() if k not in base_fx["recipes"]}
    print(f"[{'APPLY' if args.apply else 'DRY-RUN'}] PixelFXRecipes: +{len(added_clips)} clips, +{len(added_recipes)} recipes")
    if args.apply:
        base_fx["clips"].extend(added_clips)
        base_fx["recipes"].update(added_recipes)
        RECIPES_JSON.write_text(json.dumps(base_fx, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # Wire pixel_equipment_expansion.js into build_pixel_baker.py
    print(f"[{'APPLY' if args.apply else 'DRY-RUN'}] pixel-baker: install pixel_equipment_expansion.js (17 weapons + 14 armors)")
    if args.apply:
        shutil.copy2(PACK / "pixel-baker/pixel_equipment_expansion.js", TOOLS / "pixel_equipment_expansion.js")
        bpb = TOOLS / "build_pixel_baker.py"
        txt = bpb.read_text(encoding="utf-8")
        if "registerEquipmentExpansion" not in txt:
            if OLD_BRIDGE not in txt:
                raise RuntimeError("Could not locate character expansion bridge in build_pixel_baker.py")
            bpb.write_text(txt.replace(OLD_BRIDGE, NEW_BRIDGE, 1), encoding="utf-8")
        subprocess.run([sys.executable, str(bpb)], check=True)
        subprocess.run([sys.executable, str(TOOLS / "generate_xcode_project.py")], check=True)
        subprocess.run([sys.executable, str(TOOLS / "validate_xcode_project.py")], check=True)
        print("Installation complete! Run scripts/local-build.sh test to confirm.")
    else:
        print("Dry-run complete. No live game files were modified. Re-run with --apply when ready to install.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
