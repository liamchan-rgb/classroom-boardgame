#!/usr/bin/env python3
"""Build native/ClassroomProbe/Resources/pixel-baker.js from pixel_baker_core.js
and pixel_character_expansion.js, run automated headless verification across all
expanded hairstyles, hair colors, eye colors, and non-equipment costumes, and
optionally render high-res visual review contact sheets.

Usage:
  python3 native/tools/build_pixel_baker.py
  python3 native/tools/build_pixel_baker.py --render-review <out_dir>
"""
from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "native/tools"
CORE_PATH = TOOLS / "pixel_baker_core.js"
EXPANSION_PATH = TOOLS / "pixel_character_expansion.js"
OUT_PATH = ROOT / "native/ClassroomProbe/Resources/pixel-baker.js"

INJECTION_ANCHOR = "for(const o of Object.keys(So).sort())Me(Je(So[o]),o);"


def build() -> None:
    core = CORE_PATH.read_text(encoding="utf-8")
    expansion = EXPANSION_PATH.read_text(encoding="utf-8")
    if INJECTION_ANCHOR not in core:
        raise RuntimeError(f"Could not find injection anchor in {CORE_PATH}")
    bridge = (
        "\n// --- BEGIN PROCEDURAL CHARACTER EXPANSION ---\n"
        + expansion
        + "\nregisterCharacterExpansion({"
        + "k,v,ie,Me,ho,Je,ze,We,Ao,i0,J,gt,Mt,Pe,ae,uo,ue,ut,wt,Le,z,mt,Q,V,_t,Et,pt,ct,xa,ma,Sa"
        + "});\n"
        + "// --- END PROCEDURAL CHARACTER EXPANSION ---\n"
        + "// --- BEGIN PROCEDURAL EQUIPMENT EXPANSION ---\n"
        + (TOOLS / "pixel_equipment_expansion.js").read_text(encoding="utf-8")
        + "\nregisterEquipmentExpansion({"
        + "k,v,Me,J,gt,Mt,Pe,ae,uo,ue,ut,wt,z,Q,V,_t,Et,pt,ct,St,Z,lt,O,ye,jt,At,ko,Ut,xe,te,be,Qe,rt"
        + "});\n"
        + "// --- END PROCEDURAL EQUIPMENT EXPANSION ---\n"
    )
    combined = core.replace(INJECTION_ANCHOR, INJECTION_ANCHOR + bridge, 1)
    OUT_PATH.write_text(combined, encoding="utf-8")
    print(f"Built {OUT_PATH} ({len(combined):,} bytes)")


def verify() -> dict:
    script = r"""
const fs = require("fs");
eval(fs.readFileSync(process.argv[1], "utf8"));
const info = JSON.parse(globalThis.PixelBaker.info());
const summary = {
  sprW: info.sprW,
  sprH: info.sprH,
  hairs: info.items.hair.length,
  hairColors: info.items.hair[0].variants.length,
  faces: info.items.face.length,
  faceRoundEyes: info.items.face.find(f => f.id === "face_round").variants.length,
  tops: info.items.top.length,
  costumes: info.items.top.filter(t => t.id.startsWith("top_costume_")).length,
  bottoms: info.items.bottom.length,
  shoes: info.items.shoes.length,
};
// Ensure every hairstyle has all 20 hair colors
for (const h of info.items.hair) {
  if (h.variants.length < 20) throw new Error(`Hair ${h.id} has only ${h.variants.length} colors`);
}
// Smoke bake EVERY hairstyle across 5 dirs + idle/walk/ready/slash
function checkNonEmpty(label, bytes) {
  let opaque = 0;
  for (let i = 3; i < bytes.length; i += 4) if (bytes[i] > 0) opaque++;
  if (opaque < 100) throw new Error(`${label} produced almost empty sprite (${opaque} opaque px)`);
}
for (const h of info.items.hair) {
  const bytes = globalThis.PixelBaker.bake(JSON.stringify({
    slots: { hair: h.id, face: "face_round", top: "top_costume_academy", bottom: "bottom_trousers", shoes: "shoes_boots" },
    variants: { hair: h.variants[0].id, face: "blue", bottom: "slate", shoes: "black" },
    skin: "fair", dirs: ["S", "SE", "E", "NE", "N"], frames: [0, 100]
  }));
  checkNonEmpty("hair:" + h.id, bytes);
}
// Smoke bake EVERY hair color
for (const c of info.items.hair[0].variants) {
  const bytes = globalThis.PixelBaker.bake(JSON.stringify({
    slots: { hair: "hair_twintails", face: "face_round", top: "top_costume_sailor", bottom: "bottom_pleated_skirt", shoes: "shoes_boots" },
    variants: { hair: c.id, face: "blue", bottom: "navy", shoes: "navy" },
    skin: "fair", dirs: ["S"], frames: [0]
  }));
  checkNonEmpty("hairColor:" + c.id, bytes);
}
// Smoke bake EVERY eye option (face_round variants + hetero faces)
for (const e of info.items.face.find(f => f.id === "face_round").variants) {
  const bytes = globalThis.PixelBaker.bake(JSON.stringify({
    slots: { hair: "hair_messy", face: "face_round", top: "top_traveler", bottom: "bottom_trousers", shoes: "shoes_boots" },
    variants: { hair: "black", face: e.id, top: "blue", bottom: "dark", shoes: "brown" },
    skin: "fair", dirs: ["S", "SE", "E"], frames: [0]
  }));
  checkNonEmpty("eye:" + e.id, bytes);
}
for (const fid of ["face_hetero_gold_blue", "face_hetero_crimson_cyan"]) {
  const bytes = globalThis.PixelBaker.bake(JSON.stringify({
    slots: { hair: "hair_messy", face: fid, top: "top_traveler", bottom: "bottom_trousers", shoes: "shoes_boots" },
    variants: { hair: "silver", top: "blue", bottom: "dark", shoes: "brown" },
    skin: "fair", dirs: ["S", "SE", "E"], frames: [0]
  }));
  checkNonEmpty("face:" + fid, bytes);
}
// Smoke bake EVERY costume across 5 dirs + idle/walk/slash/shoot/cast with weapons
const costumes = info.items.top.filter(t => t.id.startsWith("top_costume_"));
for (const cst of costumes) {
  const bytes = globalThis.PixelBaker.bake(JSON.stringify({
    slots: { hair: "hair_curtain", face: "face_round", top: cst.id, bottom: "bottom_trousers", shoes: "shoes_boots", weapon_main: "weapon_training_sword" },
    variants: { hair: "brown", face: "blue", bottom: "dark", shoes: "black" },
    skin: "fair", dirs: ["S", "SE", "E", "NE", "N"], frames: [0, 100, 10, 26]
  }));
  checkNonEmpty("costume:" + cst.id, bytes);
}
process.stdout.write(JSON.stringify(summary));
"""
    raw = subprocess.check_output(["node", "-e", script, str(OUT_PATH)], text=True)
    summary = json.loads(raw)
    print("PASS headless Node verification:", json.dumps(summary, ensure_ascii=False))
    return summary


def render_review(out_dir: Path) -> None:
    from PIL import Image, ImageDraw

    out_dir.mkdir(parents=True, exist_ok=True)
    baker_js = r"""
const fs = require("fs");
eval(fs.readFileSync(process.argv[1], "utf8"));
const specs = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const info = JSON.parse(globalThis.PixelBaker.info());
const imgs = specs.map(s => Buffer.from(globalThis.PixelBaker.bake(JSON.stringify(s))).toString("base64"));
process.stdout.write(JSON.stringify({ w: info.sprW, h: info.sprH, imgs }));
"""

    def bake_batch(specs):
        tmp = out_dir / "_specs.json"
        tmp.write_text(json.dumps(specs), encoding="utf-8")
        res = json.loads(subprocess.check_output(["node", "-e", baker_js, str(OUT_PATH), str(tmp)], text=True))
        tmp.unlink(missing_ok=True)
        return res["w"], res["h"], [base64.b64decode(b) for b in res["imgs"]]

    # Sheet 1: All 12 NEW hairstyles across all 5 directions (S SE E NE N)
    new_hairs = [
        ("hair_twintails", "pink"),
        ("hair_twin_buns", "black"),
        ("hair_bob_cut", "brown"),
        ("hair_spiky", "blonde"),
        ("hair_wolf_cut", "navy"),
        ("hair_hime_cut", "midnight"),
        ("hair_wavy_long", "caramel"),
        ("hair_half_up", "cream"),
        ("hair_curtain", "ash"),
        ("hair_fluffy_curl", "brown"),
        ("hair_side_braid", "chestnut"),
        ("hair_quiff", "silver"),
    ]
    specs = [
        {
            "slots": {"hair": hid, "face": "face_round", "top": "top_costume_academy", "bottom": "bottom_trousers", "shoes": "shoes_boots"},
            "variants": {"hair": col, "face": "blue", "bottom": "slate", "shoes": "black"},
            "skin": "fair", "dirs": ["S", "SE", "E", "NE", "N"], "frames": [0]
        }
        for hid, col in new_hairs
    ]
    w, h, imgs = bake_batch(specs)
    zoom = 3
    cw, ch = w * zoom, h * zoom
    sheet = Image.new("RGBA", (5 * cw + 170, len(new_hairs) * ch + 24), (36, 54, 42, 255))
    dr = ImageDraw.Draw(sheet)
    for r, ((hid, col), raw) in enumerate(zip(new_hairs, imgs)):
        im = Image.frombytes("RGBA", (w, h * 5), raw)
        dr.text((10, 12 + r * ch + ch // 2 - 6), f"{hid}\n({col})", fill=(248, 242, 224, 255))
        for c in range(5):
            cell = im.crop((0, c * h, w, (c + 1) * h)).resize((cw, ch), Image.NEAREST)
            sheet.alpha_composite(cell, (160 + c * cw, 12 + r * ch))
    sheet.save(out_dir / "review_new_hairstyles.png")

    # Sheet 2: All 20 hair colors + all 18 eye colors (front zoomed head/body grid)
    hair_colors = [
        "black", "brown", "chestnut", "blonde", "cream", "caramel", "red", "wine", "pink", "coral",
        "violet", "lavender", "navy", "sky", "teal", "mint", "emerald", "ash", "silver", "midnight"
    ]
    eye_specs_meta = [
        ("blue", "face_round", "blue"), ("amber", "face_round", "amber"), ("green", "face_round", "green"),
        ("violet", "face_round", "violet"), ("teal", "face_round", "teal"), ("ruby", "face_round", "ruby"),
        ("sakura", "face_round", "sakura"), ("gold", "face_round", "gold"), ("ice", "face_round", "ice"),
        ("obsidian", "face_round", "obsidian"), ("hazel", "face_round", "hazel"), ("emerald", "face_round", "emerald"),
        ("orange", "face_round", "orange"), ("silver", "face_round", "silver"), ("indigo", "face_round", "indigo"),
        ("magenta", "face_round", "magenta"),
        ("hetero_gold_blue", "face_hetero_gold_blue", ""),
        ("hetero_crimson_cyan", "face_hetero_crimson_cyan", ""),
    ]
    hc_specs = [
        {
            "slots": {"hair": "hair_long", "face": "face_round", "top": "top_costume_academy", "bottom": "bottom_trousers", "shoes": "shoes_boots"},
            "variants": {"hair": col, "face": "blue", "bottom": "slate", "shoes": "black"},
            "skin": "fair", "dirs": ["S"], "frames": [0]
        }
        for col in hair_colors
    ]
    eye_specs = [
        {
            "slots": {"hair": "hair_curtain", "face": fid, "top": "top_costume_academy", "bottom": "bottom_trousers", "shoes": "shoes_boots"},
            "variants": {"hair": "silver", "face": fv, "bottom": "slate", "shoes": "black"},
            "skin": "fair", "dirs": ["S"], "frames": [0]
        }
        for _, fid, fv in eye_specs_meta
    ]
    w, h, hc_imgs = bake_batch(hc_specs)
    _, _, eye_imgs = bake_batch(eye_specs)
    cols = 5
    box_w, box_h = 150, 190
    c_sheet = Image.new("RGBA", (cols * box_w + 20, 8 * box_h + 60), (34, 48, 40, 255))
    dr = ImageDraw.Draw(c_sheet)
    dr.text((14, 10), "20 HAIR COLORS (hair_long)", fill=(255, 232, 168, 255))
    for i, (col, raw) in enumerate(zip(hair_colors, hc_imgs)):
        r, c = divmod(i, cols)
        im = Image.frombytes("RGBA", (w, h), raw).crop((5, 8, 37, 40)).resize((128, 128), Image.NEAREST)
        x0, y0 = 10 + c * box_w, 34 + r * box_h
        c_sheet.alpha_composite(im, (x0 + 11, y0 + 10))
        dr.text((x0 + 16, y0 + 146), col, fill=(245, 240, 224, 255))
    eye_top = 34 + 4 * box_h + 18
    dr.text((14, eye_top - 22), "18 EYE COLORS (head close-up 5x)", fill=(255, 232, 168, 255))
    for i, ((ename, _, _), raw) in enumerate(zip(eye_specs_meta, eye_imgs)):
        r, c = divmod(i, cols)
        im = Image.frombytes("RGBA", (w, h), raw).crop((10, 14, 32, 36)).resize((110, 110), Image.NEAREST)
        x0, y0 = 10 + c * box_w, eye_top + r * box_h
        c_sheet.alpha_composite(im, (x0 + 20, y0 + 14))
        dr.text((x0 + 12, y0 + 134), ename, fill=(245, 240, 224, 255))
    c_sheet.save(out_dir / "review_colors_and_eyes.png")

    # Sheet 3: All 16 BRAND-NEW COSTUMES across 5 dirs + battle ready pose (with coordinated bottom & shoes!)
    costume_combos = [
        ("costume_academy",     "top_costume_academy",     "navy",      "bottom_trousers",      "slate",   "shoes_boots", "black",   "hair_curtain",     "black",    "blue"),
        ("costume_sailor",      "top_costume_sailor",      "navy",      "bottom_pleated_skirt", "navy",    "shoes_boots", "navy",    "hair_twintails",   "blonde",   "sky" if False else "blue"),
        ("costume_mage_robe",   "top_costume_mage_robe",   "indigo",    "bottom_trousers",      "indigo",  "shoes_boots", "black",   "hair_hime_cut",    "midnight", "violet"),
        ("costume_hoodie",      "top_costume_hoodie",      "coral",     "bottom_trousers",      "denim",   "shoes_boots", "white",   "hair_spiky",       "caramel",  "amber"),
        ("costume_overalls",    "top_costume_overalls",    "denim",     "bottom_trousers",      "denim",   "shoes_boots", "brown",   "hair_fluffy_curl", "brown",    "green"),
        ("costume_kimono",      "top_costume_kimono",      "sakura",    "bottom_hakama",        "crimson", "shoes_boots", "cream",   "hair_twin_buns",   "black",    "sakura"),
        ("costume_hanfu",       "top_costume_hanfu",       "jade",      "bottom_hakama",        "ivory",   "shoes_boots", "black",   "hair_half_up",     "silver",   "teal"),
        ("costume_noble",       "top_costume_noble",       "wine",      "bottom_trousers",      "white",   "shoes_boots", "black",   "hair_quiff",       "wine",     "gold"),
        ("costume_sundress",    "top_costume_sundress",    "sunflower", "bottom_shorts_socks",  "white",   "shoes_boots", "brown",   "hair_side_braid",  "chestnut", "emerald"),
        ("costume_captain",     "top_costume_captain",     "crimson",   "bottom_trousers",      "white",   "shoes_boots", "black",   "hair_wolf_cut",    "navy",     "ruby"),
        ("costume_bard",        "top_costume_bard",        "emerald",   "bottom_trousers",      "brown",   "shoes_boots", "brown",   "hair_swept",       "blonde",   "green"),
        ("costume_winter_coat", "top_costume_winter_coat", "glacier",   "bottom_trousers",      "navy",    "shoes_boots", "cream",   "hair_bob_cut",     "cream",    "ice"),
        ("costume_explorer",    "top_costume_explorer",    "khaki",     "bottom_trousers",      "khaki",   "shoes_boots", "brown",   "hair_messy",       "brown",    "hazel"),
        ("costume_phantom",     "top_costume_phantom",     "scarlet",   "bottom_trousers",      "black",   "shoes_boots", "black",   "hair_quiff",       "black",    "ruby"),
        ("costume_chef",        "top_costume_chef",        "caramel",   "bottom_trousers",      "dark",    "shoes_boots", "black",   "hair_bun",         "chestnut", "amber"),
        ("costume_idol",        "top_costume_idol",        "lavender",  "bottom_pleated_skirt", "violet",  "shoes_boots", "white",   "hair_wavy_long",   "pink",     "magenta"),
    ]
    cst_specs = []
    for cid, top, tv, bot, bv, sh, sv, hair, hc, eye in costume_combos:
        slots = {"hair": hair, "face": "face_round", "top": top, "bottom": bot, "shoes": sh}
        variants = {"hair": hc, "face": eye, "top": tv, "bottom": bv, "shoes": sv}
        if cid == "costume_explorer":
            slots["bag"] = "bag_satchel"
            variants["bag"] = "olive"
        cst_specs.append({"slots": slots, "variants": variants, "skin": "fair", "dirs": ["S", "SE", "E", "NE", "N"], "frames": [0]})
        # Also test battle ready pose with sword in E dir
        slots_b = {**slots, "weapon_main": "weapon_training_sword"}
        cst_specs.append({"slots": slots_b, "variants": variants, "skin": "fair", "dirs": ["E"], "frames": [8]})
    w, h, cst_imgs = bake_batch(cst_specs)
    # Split into 2 clean pages of 8 costumes each so image resolution stays super crisp!
    for page in range(2):
        subset = costume_combos[page * 8 : (page + 1) * 8]
        csheet = Image.new("RGBA", (6 * cw + 175, len(subset) * ch + 28), (38, 56, 44, 255))
        dr = ImageDraw.Draw(csheet)
        dr.text((168, 6), "S              SE             E              NE             N            Battle(E)", fill=(255, 232, 168, 255))
        for idx, row_meta in enumerate(subset):
            gidx = page * 8 + idx
            im5 = Image.frombytes("RGBA", (w, h * 5), cst_imgs[gidx * 2])
            imb = Image.frombytes("RGBA", (w, h), cst_imgs[gidx * 2 + 1])
            dr.text((10, 20 + idx * ch + ch // 2 - 6), row_meta[0], fill=(248, 242, 224, 255))
            for c in range(5):
                cell = im5.crop((0, c * h, w, (c + 1) * h)).resize((cw, ch), Image.NEAREST)
                csheet.alpha_composite(cell, (165 + c * cw, 20 + idx * ch))
            csheet.alpha_composite(imb.resize((cw, ch), Image.NEAREST), (165 + 5 * cw, 20 + idx * ch))
        csheet.save(out_dir / f"review_costumes_part{page + 1}.png")
    print("Rendered review sheets to", out_dir)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--render-review", type=Path, default=None)
    args = parser.parse_args()
    build()
    verify()
    if args.render_review:
        render_review(args.render_review)


if __name__ == "__main__":
    main()
