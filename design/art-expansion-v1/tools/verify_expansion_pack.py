#!/usr/bin/env python3
"""Verify 100% integrity of the staged expansion art & PixelFX package
(design/art-expansion-v1/) and optional compressed archive (.zip).
Does NOT touch any active game files.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from PIL import Image

PACK = Path(__file__).resolve().parents[1]
ROOT = PACK.parents[1]
CORE_JS = ROOT / "native/tools/pixel_baker_core.js"
CHAR_EXP_JS = ROOT / "native/tools/pixel_character_expansion.js"
EXISTING_RECIPES = ROOT / "native/ClassroomProbe/Resources/Assets.xcassets/PixelFXRecipes.dataset/recipes.json"

INJECTION_ANCHOR = "for(const o of Object.keys(So).sort())Me(Je(So[o]),o);"

EXPECTED_BADGES = [
    "ClassBadgeAdventurer", "ClassBadgeRanger", "ClassBadgeSpellblade", "ClassBadgeDragonKnight",
    "ClassBadgeAcolyte", "ClassBadgeScout", "ClassBadgeGuardian", "ClassBadgeElementalist",
    "ClassBadgeBard", "ClassBadgePaladin", "ClassBadgeWindstalker", "ClassBadgeDruid",
    "ClassBadgeArchmage", "ClassBadgeValkyrie",
]

EXPECTED_ITEMS_COMMON = [
    "OakSlingshot", "WoodenStaff", "IronDagger", "WildwoodSpear",
    "TravelerCloak", "StuddedVest", "WildwoodArmor",
    "CloverAmulet", "WoodenWhistle", "SwiftBootsCharm", "WildwoodCharm",
    "BerryTea",
]

EXPECTED_ITEMS_FX = [
    # 13 Rare
    "FrostWand", "KnightHalberd", "GaleLongbow", "OakHammer",
    "ChainmailCoat", "WindrunnerGarb", "GaleArmor", "OakArmor",
    "EagleEyeLens", "GaleCharm", "OakCharm",
    "IronbarkElixir", "HoneySalve",
    # 13 Epic
    "FlameAxe", "ThunderCrossbow", "EmeraldScepter", "ShadowTwinblades", "EmberStaff",
    "MithrilPlate", "ArcaneMantle", "EmberArmor",
    "RubyHeartPendant", "ChronoPocketwatch", "EmberCharm",
    "SuperPotion", "CrystalBarrierFlask",
    # 15 Legendary
    "SunbreakerBlade", "AstralGreatbow", "AegisLance", "AstralCodex",
    "TitanFortressArmor", "PhoenixFeatherRobe", "AegisArmor", "AstralArmor",
    "CrownOfValor", "InfinityHourglass", "AegisCharm", "AstralCharm",
    "PhoenixNectar", "StarlightElixir", "AegisCrystal",
]

EXPECTED_MONSTERS = [
    "MeadowMonsterHopShroom", "MeadowMonsterAcornBandit", "MeadowMonsterBubbleCrab", "MeadowMonsterStingWasp",
    "MeadowMonsterBrambleSprite", "MeadowMonsterGoblinShaman", "MeadowMonsterEmberLizard", "MeadowMonsterShadowOwl",
    "MeadowMonsterRuneKnight", "MeadowMonsterCrystalGolem", "MeadowMonsterFrostAlphaWolf", "MeadowMonsterMushroomKing",
    "MeadowMonsterGoblinWarlord", "MeadowMonsterThornTreant", "MeadowMonsterFrostPhoenix", "MeadowMonsterEclipseBehemoth",
]

EXPECTED_PROJECTILES = [
    "ProjAcorn", "ProjVenomSting", "ProjShamanOrb", "ProjEmberBall",
    "ProjShadowFeather", "ProjBoomBomb", "ProjFrostShard", "ProjEclipseOrb",
]


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def check_white_fringe(im: Image.Image) -> float:
    """Return ratio of opaque boundary pixels that look like unremoved pure white halo."""
    rgba = im.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    edges = 0
    white_edges = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            adj = (y == 0 or px[x, y - 1][3] == 0 or y == h - 1 or px[x, y + 1][3] == 0 or
                   x == 0 or px[x - 1, y][3] == 0 or x == w - 1 or px[x + 1, y][3] == 0)
            if adj:
                edges += 1
                if r > 245 and g > 245 and b > 245 and a < 250:
                    white_edges += 1
    return (white_edges / edges) if edges > 0 else 0.0


def verify_node_wearables() -> tuple[int, int]:
    core = CORE_JS.read_text(encoding="utf-8")
    char_exp = CHAR_EXP_JS.read_text(encoding="utf-8")
    equip_exp = (PACK / "pixel-baker/pixel_equipment_expansion.js").read_text(encoding="utf-8")
    assert INJECTION_ANCHOR in core, "pixel_baker_core.js anchor not found"
    bridge = (
        "\n" + char_exp
        + "\nregisterCharacterExpansion({k,v,ie,Me,ho,Je,ze,We,Ao,i0,J,gt,Mt,Pe,ae,uo,ue,ut,wt,Le,z,mt,Q,V,_t,Et,pt,ct,xa,ma,Sa});\n"
        + "\n" + equip_exp
        + "\nregisterEquipmentExpansion({k,v,Me,J,gt,Mt,Pe,ae,uo,ue,ut,wt,z,Q,V,_t,Et,pt,ct,St,Z,lt,O,ye,jt,At,ko,Ut,xe,te,be,Qe,rt});\n"
    )
    combined = core.replace(INJECTION_ANCHOR, INJECTION_ANCHOR + bridge, 1)
    test_js = r"""
const fs = require("fs");
eval(fs.readFileSync(process.argv[2], "utf8"));
const info = JSON.parse(globalThis.PixelBaker.info());
const newWeapons = [
  ["weapon_oak_slingshot","oakSlingshot","bow",false],
  ["weapon_wooden_staff","woodenStaff","up",false],
  ["weapon_iron_dagger","ironDagger","down",false],
  ["weapon_frost_wand","frostWand","up",false],
  ["weapon_knight_halberd","knightHalberd","shoulder",false],
  ["weapon_flame_axe","flameAxe","shoulder",true],
  ["weapon_thunder_crossbow","thunderCrossbow","bow",true],
  ["weapon_emerald_scepter","emeraldScepter","up",true],
  ["weapon_shadow_twinblades","shadowTwinblades","down",true],
  ["weapon_sunbreaker_blade","sunbreakerBlade","shoulder",true],
  ["weapon_astral_greatbow","astralGreatbow","bow",true],
  ["weapon_wildwood_spear","wildwoodSpear","down",false],
  ["weapon_gale_longbow","galeLongbow","bow",false],
  ["weapon_oak_hammer","oakHammer","shoulder",false],
  ["weapon_ember_staff","emberStaff","up",true],
  ["weapon_aegis_lance","aegisLance","shoulder",true],
  ["weapon_astral_codex","astralCodex","up",true]
];
const newArmors = [
  ["top_traveler_cloak","travelerCloak",false],
  ["top_studded_vest","studdedVest",false],
  ["top_chainmail_coat","chainmailCoat",false],
  ["top_windrunner_garb","windrunnerGarb",false],
  ["top_mithril_plate","mithrilPlate",true],
  ["top_arcane_mantle","arcaneMantle",true],
  ["top_titan_fortress_armor","titanFortressArmor",true],
  ["top_phoenix_feather_robe","phoenixFeatherRobe",true],
  ["top_wildwood_armor","wildwoodArmor",false],
  ["top_gale_armor","galeArmor",false],
  ["top_oak_armor","oakArmor",false],
  ["top_ember_armor","emberArmor",true],
  ["top_aegis_armor","aegisArmor",true],
  ["top_astral_armor","astralArmor",true]
];
const wMap = new Map(info.items.weapon_main.map(x => [x.id, x]));
const tMap = new Map(info.items.top.map(x => [x.id, x]));
const hasPx = b => { for (let i = 3; i < b.length; i += 4) if (b[i] > 0) return true; return false; };
for (const [id, gi, hold, fx] of newWeapons) {
  const r = wMap.get(id);
  if (!r || r.gameItem !== gi || r.hold !== hold) throw new Error("Weapon mismatch: " + id);
  const spec = { skin:"fair", slots:{ hair:"hair_spiky", face:"face_round", top:"top_leather_armor", bottom:"bottom_trousers", shoes:"shoes_boots", weapon_main:id }, dirs:["S","SE","E","NE","N"], frames:[0] };
  if (!hasPx(globalThis.PixelBaker.bake(JSON.stringify(spec)))) throw new Error("Blank weapon bake: " + id);
  const fxBuf = globalThis.PixelBaker.bakeFx(JSON.stringify({ ...spec, dirs:["S","SE","E"], frames:[0, 8] }));
  if (fx && !hasPx(fxBuf)) throw new Error("Missing weapon bakeFx: " + id);
}
for (const [id, gi, fx] of newArmors) {
  const r = tMap.get(id);
  if (!r || r.gameItem !== gi) throw new Error("Armor mismatch: " + id);
  const spec = { skin:"fair", slots:{ hair:"hair_twintails", face:"face_round", top:id, bottom:"bottom_trousers", shoes:"shoes_boots" }, dirs:["S","SE","E","NE","N"], frames:[0] };
  if (!hasPx(globalThis.PixelBaker.bake(JSON.stringify(spec)))) throw new Error("Blank armor bake: " + id);
  const fxBuf = globalThis.PixelBaker.bakeFx(JSON.stringify({ ...spec, dirs:["S"], frames:[0] }));
  if (fx && !hasPx(fxBuf)) throw new Error("Missing armor bakeFx: " + id);
}
console.log(JSON.stringify({ weapons: newWeapons.length, armors: newArmors.length }));
"""
    with tempfile.TemporaryDirectory() as td:
        bp = Path(td) / "baker.js"
        tp = Path(td) / "test.js"
        bp.write_text(combined, encoding="utf-8")
        tp.write_text(test_js, encoding="utf-8")
        proc = subprocess.run(["node", str(tp), str(bp)], capture_output=True, text=True, check=True)
        out = json.loads(proc.stdout)
        return out["weapons"], out["armors"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--zip", dest="zip_path", default=None, help="Optional path to .zip archive to verify")
    args = ap.parse_args()

    errors: list[str] = []

    # 1. Class Badges (14 x 256x256)
    badge_files = sorted((PACK / "class-badges").glob("*.png"))
    if len(badge_files) != 14:
        errors.append(f"Expected 14 class badges, found {len(badge_files)}")
    for b in EXPECTED_BADGES:
        p = PACK / "class-badges" / f"{b}.png"
        if not p.exists():
            errors.append(f"Missing {p.name}")
            continue
        im = Image.open(p)
        if im.size != (256, 256):
            errors.append(f"{p.name}: size {im.size} != (256, 256)")
        if check_white_fringe(im) > 0.02:
            errors.append(f"{p.name}: semi-transparent white fringe detected")

    # 2. Item Static Icons (53 x 512x512) & FX Strips (41 x 4608x192)
    all_items = EXPECTED_ITEMS_COMMON + EXPECTED_ITEMS_FX
    assert len(all_items) == 53 and len(EXPECTED_ITEMS_FX) == 41
    icon_files = sorted((PACK / "item-icons").glob("*.png"))
    fx_files = sorted((PACK / "item-icon-fx").glob("*.png"))
    if len(icon_files) != 53:
        errors.append(f"Expected 53 item icons, found {len(icon_files)}")
    if len(fx_files) != 41:
        errors.append(f"Expected 41 item FX strips, found {len(fx_files)}")
    for name in all_items:
        p = PACK / "item-icons" / f"PixelIcon{name}.png"
        if not p.exists():
            errors.append(f"Missing {p.name}")
        else:
            im = Image.open(p)
            if im.size != (512, 512):
                errors.append(f"{p.name}: size {im.size} != (512, 512)")
            if check_white_fringe(im) > 0.01:
                errors.append(f"{p.name}: white fringe detected")
    for name in EXPECTED_ITEMS_FX:
        p = PACK / "item-icon-fx" / f"PixelIconFX{name}.png"
        if not p.exists():
            errors.append(f"Missing {p.name}")
        else:
            im = Image.open(p)
            if im.size != (4608, 192):
                errors.append(f"{p.name}: size {im.size} != (4608, 192)")

    # 3. 16 Monsters (32 sheets + motion_expansion.json + 8 projectiles)
    for asset in EXPECTED_MONSTERS:
        mp = PACK / "monsters" / f"{asset}Motion.png"
        dp = PACK / "monsters" / f"{asset}Death.png"
        for p, exp_sz in ((mp, (3072, 1792)), (dp, (4096, 1600))):
            if not p.exists():
                errors.append(f"Missing {p.name}")
                continue
            im = Image.open(p)
            if im.size != exp_sz:
                errors.append(f"{p.name}: size {im.size} != {exp_sz}")
            if im.mode != "P" or im.info.get("transparency") != 0:
                errors.append(f"{p.name}: expected crisp mode='P' with transparency=0, got mode={im.mode}")
        if dp.exists():
            dim = Image.open(dp).convert("RGBA")
            # Frame 39 (col 7, row 4) must end cleanly 100% transparent!
            f39 = dim.crop((7 * 512, 4 * 320, 8 * 512, 5 * 320))
            if f39.getbbox() is not None:
                errors.append(f"{dp.name}: terminal frame 39 is not fully transparent")

    motion_doc = json.loads((PACK / "monsters/motion_expansion.json").read_text(encoding="utf-8"))
    if len(motion_doc.get("records", [])) != 16:
        errors.append(f"motion_expansion.json: expected 16 records, found {len(motion_doc.get('records', []))}")

    for proj in EXPECTED_PROJECTILES:
        pp = PACK / "monsters/projectiles" / f"{proj}.png"
        if not pp.exists():
            errors.append(f"Missing {pp.name}")
        else:
            im = Image.open(pp)
            if im.size not in ((64, 64), (128, 64)):
                errors.append(f"{pp.name}: size {im.size} not in (64x64, 128x64)")

    # 4. PixelFX 8 Packs (23 clips) + recipes_expansion.json (70 recipes)
    existing_fx = json.loads(EXISTING_RECIPES.read_text(encoding="utf-8"))
    existing_clip_ids = {c["id"] for c in existing_fx["clips"]}
    fx_doc = json.loads((PACK / "pixel-fx/recipes_expansion.json").read_text(encoding="utf-8"))
    new_clips = fx_doc.get("clips", [])
    if fx_doc.get("fps") != 20 or fx_doc.get("packs") != 8 or len(new_clips) != 23:
        errors.append(f"recipes_expansion.json: expected fps=20, packs=8, 23 clips; got {len(new_clips)}")
    new_clip_ids = set()
    for c in new_clips:
        cid = c["id"]
        new_clip_ids.add(cid)
        fp = PACK / "pixel-fx" / f"PixelFX_{cid}.png"
        if not fp.exists():
            errors.append(f"Missing {fp.name}")
            continue
        im = Image.open(fp)
        layers = (1 if c["back"] else 0) + (1 if c["front"] else 0)
        total = c["n"] * layers
        rows = math.ceil(total / c["cols"])
        exp_sz = (c["cols"] * c["w"], rows * c["h"])
        if im.size != exp_sz:
            errors.append(f"{fp.name}: size {im.size} != {exp_sz}")
        if not c.get("loop"):
            # Verify terminal frame of last layer is transparent
            k = total - 1
            gx, gy = (k % c["cols"]) * c["w"], (k // c["cols"]) * c["h"]
            if im.crop((gx, gy, gx + c["w"], gy + c["h"])).getbbox() is not None:
                errors.append(f"{fp.name}: non-looping terminal frame is not transparent")
    valid_clip_ids = existing_clip_ids | new_clip_ids
    for rname, events in fx_doc.get("recipes", {}).items():
        for ev in events:
            if ev["clip"] not in valid_clip_ids:
                errors.append(f"Recipe {rname} references unknown clip {ev['clip']}")

    # 5. Pixel-Baker 31 Wearables Headless Node.js Verification
    try:
        w_cnt, a_cnt = verify_node_wearables()
    except Exception as e:
        errors.append(f"Node wearable verification failed: {e}")
        w_cnt, a_cnt = 0, 0

    # 6. Asset Manifest SHA-256 Verification
    manifest_path = PACK / "asset-manifest.json"
    if not manifest_path.exists():
        errors.append("Missing asset-manifest.json")
        manifest = None
    else:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for entry in manifest.get("files", []):
            fp = PACK / entry["path"]
            if not fp.exists():
                errors.append(f"Manifest file missing: {entry['path']}")
            else:
                if fp.stat().st_size != entry["bytes"]:
                    errors.append(f"Size mismatch for {entry['path']}")
                if sha256_file(fp) != entry["sha256"]:
                    errors.append(f"SHA-256 mismatch for {entry['path']}")

    # 7. Optional ZIP Archive Integrity Check
    if args.zip_path:
        zp = Path(args.zip_path)
        if not zp.exists():
            errors.append(f"Missing zip archive: {zp}")
        else:
            with zipfile.ZipFile(zp, "r") as zf:
                bad = zf.testzip()
                if bad is not None:
                    errors.append(f"Corrupt zip entry: {bad}")
                names = set(zf.namelist())
                if manifest:
                    for entry in manifest["files"]:
                        zname = f"meadow-expansion-art-v1/{entry['path']}"
                        if zname not in names:
                            errors.append(f"Missing from zip: {zname}")

    if errors:
        print("VERIFICATION FAILED:")
        for e in errors:
            print("  -", e)
        return 1

    print(
        f"VERIFICATION PASSED: 14 badges, 53 item icons, 41 item FX strips, "
        f"16 monsters (32 sheets + 8 projectiles), {w_cnt} weapons + {a_cnt} armors (pixel-baker), "
        f"8 PixelFX packs ({len(new_clips)} clips, {len(fx_doc['recipes'])} recipes), "
        f"manifest ({len(manifest['files'])} files SHA-256 OK)"
        + (f", zip OK ({args.zip_path})" if args.zip_path else "")
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
