// Procedural Character Customization Expansion for pixel-baker.js
// Adds:
//   - 20 curated hand-tuned 5-ramp hair colors (shared across ALL 20 hairstyles)
//   - 12 brand-new procedural hairstyles (total 20 hairstyles)
//   - 12 brand-new pure jewel eye colors + 2 heterochromia faces (total 18 eye options)
//   - 3 brand-new procedural bottom styles + expanded trouser/boot colorways
//   - 16 brand-new original non-equipment costumes (时装 — zero in-game armor reuse)
//
// Injected cleanly into pixel-baker.js by native/tools/build_pixel_baker.py.
function registerCharacterExpansion(C) {
  const {
    k, v, ie, Me, ho, Je, ze, We, Ao, i0,
    J, gt, Mt, Pe, ae, uo, ue, ut, wt, Le,
    z, mt, Q, V, _t, Et, pt, ct, xa,
    ma: baseTrousers, Sa: baseBoots
  } = C;

  // =========================================================================
  // 1. 20 CURATED 5-RAMP HAIR COLORS (applied to ALL 8 existing + 12 new)
  // =========================================================================
  const EXPANDED_HAIR_COLORS = [
    { id: "black",    name: "墨黑",   palette: ["#08080e", "#1a1a26", "#30323e", "#52566a", "#9098b0"] },
    { id: "brown",    name: "暖棕",   palette: ["#1c100c", "#4a2a1a", "#7c4a2a", "#b47c42", "#ecc27a"] },
    { id: "chestnut", name: "栗红",   palette: ["#1e0c0a", "#4e1e16", "#86362a", "#c0603e", "#f0a070"] },
    { id: "blonde",   name: "灿金",   palette: ["#4a2c10", "#96641e", "#d4a036", "#f2cc5e", "#fff2ac"] },
    { id: "cream",    name: "奶油金", palette: ["#4c3a24", "#92764c", "#d2b682", "#f2dfae", "#fff8e4"] },
    { id: "caramel",  name: "焦糖橘", palette: ["#381408", "#843412", "#d06020", "#f69844", "#ffda92"] },
    { id: "red",      name: "绯红",   palette: ["#2c080c", "#6c141c", "#b42a2e", "#e45c4e", "#ffa88e"] },
    { id: "wine",     name: "酒红",   palette: ["#220612", "#521028", "#862044", "#ba4668", "#ec8aa4"] },
    { id: "pink",     name: "樱粉",   palette: ["#48162a", "#923a5c", "#d67094", "#f6acc6", "#ffe6f0"] },
    { id: "coral",    name: "珊瑚粉", palette: ["#441816", "#903832", "#d86c58", "#f8a68c", "#ffe2d4"] },
    { id: "violet",   name: "薰衣紫", palette: ["#1c0e32", "#462872", "#764cb4", "#aa82e4", "#e0d0ff"] },
    { id: "lavender", name: "淡丁香", palette: ["#302248", "#6c5492", "#a68ec8", "#d4c2f0", "#f4eeff"] },
    { id: "navy",     name: "靛蓝",   palette: ["#0c1228", "#1e2c5c", "#344e92", "#5a7cc4", "#a2c2f4"] },
    { id: "sky",      name: "天空蓝", palette: ["#102646", "#245e98", "#489edc", "#8cd4fa", "#def6ff"] },
    { id: "teal",     name: "青绿",   palette: ["#0a262a", "#185a5a", "#2c968e", "#68ceb8", "#c0f6e6"] },
    { id: "mint",     name: "薄荷绿", palette: ["#163830", "#3a7a68", "#70bc9c", "#b0e6c6", "#e8fff2"] },
    { id: "emerald",  name: "翡翠绿", palette: ["#0a2212", "#185228", "#2e8842", "#62c06a", "#b4eeaa"] },
    { id: "ash",      name: "雾灰褐", palette: ["#1e1a18", "#483e38", "#786a5e", "#aa9c8c", "#ded4c6"] },
    { id: "silver",   name: "银白",   palette: ["#2e3246", "#6a7088", "#a8b0c2", "#d8dee8", "#ffffff"] },
    { id: "midnight", name: "星夜紫", palette: ["#0c0818", "#20163e", "#3c2c6c", "#6c56a4", "#b4a4e4"] }
  ];

  // Upgrade existing 8 hairstyles so every hairstyle shares all 20 hand-tuned hair colors
  for (const key of Object.keys(Ao).sort()) {
    const def = { ...Ao[key], variants: [] };
    ie.set(def.id, ho(def, EXPANDED_HAIR_COLORS));
  }

  // =========================================================================
  // 2. 12 BRAND-NEW PROCEDURAL HAIRSTYLES (total 20 hairstyles)
  // =========================================================================
  const CLEAN_STYLE = {
    clump: 0.7, global: 0.75, ring: true, streaks: true,
    grit: 0.04, dither: false, closeHoles: true, seamFloor: 1.5, floor: 1, innerLine: 1.25
  };
  const CRISPY_STYLE = {
    clump: 0.7, global: 0.75, ring: false, streaks: true,
    grit: 0.04, dither: false, closeHoles: true, seamFloor: 1.5, floor: 1, innerLine: 1.25
  };

  const NEW_HAIRSTYLES = [
    // 1. 双马尾 — high-perched symmetric twin-tails visible in all 5 views
    {
      id: "hair_twintails",
      name: "双马尾",
      palette: ["#48162a", "#923a5c", "#d67094", "#f6acc6", "#ffe6f0"],
      style: CLEAN_STYLE,
      hairline: [[0, 48], [64, 50], [98, 94], [100, 112], [180, 118]],
      locks: [
        { phi: -46, a1: 64, twist: 14, flick: 1.12, width: 3.2, tip: 0.65 },
        { phi: -18, a1: 66, twist: 10, flick: 1.12, width: 3.4, tip: 0.65 },
        { phi: 12,  a1: 64, twist: -8, flick: 1.12, width: 3.4, tip: 0.65 },
        { phi: 42,  a1: 62, twist: -14, flick: 1.12, width: 3.2, tip: 0.65 },
        { phi: -86, a1: 98, twist: 4, flick: 1.08, width: 3.0, tip: 0.8, taper: 0.7, drop: 5, spread: -0.3 },
        { phi: 86,  a1: 98, twist: -4, flick: 1.08, width: 3.0, tip: 0.8, taper: 0.7, drop: 5, spread: -0.3 },
        { phi: 132, a1: 112, twist: 18, flick: 1.04, width: 4.0, tip: 0.65 },
        { phi: -132, a1: 112, twist: -18, flick: 1.04, width: 4.0, tip: 0.65 },
        { phi: 162, a1: 110, twist: 10, flick: 1.04, width: 4.4, tip: 0.65 },
        { phi: -162, a1: 110, twist: -10, flick: 1.04, width: 4.4, tip: 0.65 },
        // Left & right twin-tail bunches (layered thick tails with playful outward splay)
        { phi: -106, a0: 46, a1: 76, flick: 1.34, lift: 0.16, width: 3.4, taper: 0.84, tip: 0.95, drop: 23, spread: 3.0, twist: -10, tier: 1 },
        { phi: -118, a0: 52, a1: 82, flick: 1.24, lift: 0.12, width: 3.1, taper: 0.82, tip: 0.95, drop: 21, spread: 2.2, twist: -4, tier: 0 },
        { phi: 106,  a0: 46, a1: 76, flick: 1.34, lift: 0.16, width: 3.4, taper: 0.84, tip: 0.95, drop: 23, spread: 3.0, twist: 10, tier: 1 },
        { phi: 118,  a0: 52, a1: 82, flick: 1.24, lift: 0.12, width: 3.1, taper: 0.82, tip: 0.95, drop: 21, spread: 2.2, twist: 4, tier: 0 }
      ]
    },
    // 2. 双丸子头 — two round odango buns perched high on upper sides
    {
      id: "hair_twin_buns",
      name: "双丸子头",
      palette: ["#08080e", "#1a1a26", "#30323e", "#52566a", "#9098b0"],
      style: CLEAN_STYLE,
      hairline: [[0, 48], [62, 50], [98, 92], [100, 110], [180, 116]],
      locks: [
        { phi: -44, a1: 64, twist: 10, flick: 1.12, width: 3.3, tip: 0.65 },
        { phi: -15, a1: 64, twist: 4, flick: 1.12, width: 3.4, tip: 0.65 },
        { phi: 15,  a1: 64, twist: -4, flick: 1.12, width: 3.4, tip: 0.65 },
        { phi: 44,  a1: 64, twist: -10, flick: 1.12, width: 3.3, tip: 0.65 },
        { phi: -92, a1: 96, twist: 4, flick: 1.08, width: 3.0, tip: 0.8, taper: 0.7, drop: 4, spread: -0.3 },
        { phi: 92,  a1: 96, twist: -4, flick: 1.08, width: 3.0, tip: 0.8, taper: 0.7, drop: 4, spread: -0.3 },
        { phi: 132, a1: 112, twist: 14, flick: 1.04, width: 4.2, tip: 0.65 },
        { phi: -132, a1: 112, twist: -14, flick: 1.04, width: 4.2, tip: 0.65 },
        { phi: 164, a1: 110, twist: 6, flick: 1.04, width: 4.4, tip: 0.65 },
        { phi: -164, a1: 110, twist: -6, flick: 1.04, width: 4.4, tip: 0.65 },
        // Left odango bun
        { phi: -96,  a0: 28, a1: 48, flick: 0.90, lift: 0.56, width: 3.3, tier: 1, tip: 1.8, taper: 0.48, twist: 0 },
        { phi: -112, a0: 24, a1: 46, flick: 0.90, lift: 0.58, width: 3.4, tier: 1, tip: 1.8, taper: 0.48, twist: 0 },
        { phi: -128, a0: 28, a1: 48, flick: 0.90, lift: 0.56, width: 3.3, tier: 1, tip: 1.8, taper: 0.48, twist: 0 },
        { phi: -112, a0: 38, a1: 56, flick: 0.90, lift: 0.54, width: 3.2, tier: 1, tip: 1.8, taper: 0.48, twist: 0 },
        // Right odango bun
        { phi: 96,   a0: 28, a1: 48, flick: 0.90, lift: 0.56, width: 3.3, tier: 1, tip: 1.8, taper: 0.48, twist: 0 },
        { phi: 112,  a0: 24, a1: 46, flick: 0.90, lift: 0.58, width: 3.4, tier: 1, tip: 1.8, taper: 0.48, twist: 0 },
        { phi: 128,  a0: 28, a1: 48, flick: 0.90, lift: 0.56, width: 3.3, tier: 1, tip: 1.8, taper: 0.48, twist: 0 },
        { phi: 112,  a0: 38, a1: 56, flick: 0.90, lift: 0.54, width: 3.2, tier: 1, tip: 1.8, taper: 0.48, twist: 0 }
      ]
    },
    // 3. 齐刘海波波头 — classic rounded bob with straight full fringe
    {
      id: "hair_bob_cut",
      name: "齐刘海波波",
      palette: ["#1c100c", "#4a2a1a", "#7c4a2a", "#b47c42", "#ecc27a"],
      style: CLEAN_STYLE,
      hairline: [[0, 56], [68, 56], [96, 98], [96, 118], [180, 124]],
      locks: [
        { phi: -54, a1: 66, twist: -4, flick: 1.04, width: 3.4, tip: 1.2, taper: 0.72 },
        { phi: -26, a1: 65, twist: 0,  flick: 1.04, width: 3.6, tip: 1.3, taper: 0.76 },
        { phi: 0,   a1: 65, twist: 0,  flick: 1.04, width: 3.6, tip: 1.3, taper: 0.76 },
        { phi: 26,  a1: 65, twist: 0,  flick: 1.04, width: 3.6, tip: 1.3, taper: 0.76 },
        { phi: 54,  a1: 66, twist: 4,  flick: 1.04, width: 3.4, tip: 1.2, taper: 0.72 },
        // Rounded jaw-hugging curved bob shell
        { phi: -80,  a1: 108, twist: 8,  flick: 1.02, lift: 0.04, width: 3.5, tip: 1.15, taper: 0.82, drop: 6, spread: -1.4 },
        { phi: 80,   a1: 108, twist: -8, flick: 1.02, lift: 0.04, width: 3.5, tip: 1.15, taper: 0.82, drop: 6, spread: -1.4 },
        { phi: -108, a1: 116, twist: 4,  flick: 1.02, lift: 0.05, width: 3.7, tip: 1.15, taper: 0.82, drop: 7, spread: -1.0 },
        { phi: 108,  a1: 116, twist: -4, flick: 1.02, lift: 0.05, width: 3.7, tip: 1.15, taper: 0.82, drop: 7, spread: -1.0 },
        { phi: -138, a1: 120, twist: 0,  flick: 1.02, lift: 0.04, width: 3.9, tip: 1.15, taper: 0.82, drop: 7, spread: -0.6 },
        { phi: 138,  a1: 120, twist: 0,  flick: 1.02, lift: 0.04, width: 3.9, tip: 1.15, taper: 0.82, drop: 7, spread: -0.6 },
        { phi: 168,  a1: 120, twist: 0,  flick: 1.02, lift: 0.04, width: 4.1, tip: 1.15, taper: 0.82, drop: 7, spread: -0.4 },
        { phi: -168, a1: 120, twist: 0,  flick: 1.02, lift: 0.04, width: 4.1, tip: 1.15, taper: 0.82, drop: 7, spread: -0.4 }
      ]
    },
    // 4. 热血刺猬发 — dynamic anime RPG spiky hair
    {
      id: "hair_spiky",
      name: "热血刺猬发",
      palette: ["#4a2c10", "#96641e", "#d4a036", "#f2cc5e", "#fff2ac"],
      style: CRISPY_STYLE,
      hairline: [[0, 44], [64, 46], [96, 86], [100, 108], [180, 118]],
      locks: [
        { phi: -54, a1: 68, twist: -18, flick: 1.42, width: 3.2, tip: 0.45 },
        { phi: -24, a1: 72, twist: -8,  flick: 1.36, width: 3.2, tip: 0.45 },
        { phi: 4,   a1: 70, twist: 8,   flick: 1.38, width: 3.2, tip: 0.45 },
        { phi: 34,  a1: 68, twist: 18,  flick: 1.44, width: 3.2, tip: 0.45 },
        { phi: 64,  a1: 74, twist: 22,  flick: 1.48, width: 3.0, tip: 0.45 },
        { phi: -96, a1: 98, twist: -10, flick: 1.42, width: 3.2, tip: 0.45 },
        { phi: 96,  a1: 98, twist: 10,  flick: 1.42, width: 3.2, tip: 0.45 },
        { phi: 132, a1: 118, twist: 12, flick: 1.40, width: 3.6, tip: 0.5 },
        { phi: -132, a1: 118, twist: -12, flick: 1.40, width: 3.6, tip: 0.5 },
        { phi: 164, a1: 122, twist: 8,  flick: 1.42, width: 3.8, tip: 0.5 },
        { phi: -164, a1: 122, twist: -8, flick: 1.42, width: 3.8, tip: 0.5 },
        // Bold upper radial hero spikes
        { phi: -155, a0: 4, a1: 42, twist: -16, flick: 1.72, lift: 0.08, width: 3.0, tier: 1, tip: 0.42 },
        { phi: -95,  a0: 4, a1: 40, twist: -18, flick: 1.70, lift: 0.08, width: 2.9, tier: 1, tip: 0.42 },
        { phi: -35,  a0: 4, a1: 38, twist: -14, flick: 1.74, lift: 0.10, width: 2.8, tier: 1, tip: 0.42 },
        { phi: 25,   a0: 4, a1: 38, twist: 16,  flick: 1.74, lift: 0.10, width: 2.8, tier: 1, tip: 0.42 },
        { phi: 90,   a0: 4, a1: 40, twist: 18,  flick: 1.70, lift: 0.08, width: 2.9, tier: 1, tip: 0.42 },
        { phi: 150,  a0: 4, a1: 42, twist: 16,  flick: 1.72, lift: 0.08, width: 3.0, tier: 1, tip: 0.42 }
      ]
    },
    // 5. 狼尾层次发 — shaggy layered wolf-cut / mullet with flared nape
    {
      id: "hair_wolf_cut",
      name: "狼尾层次发",
      palette: ["#0c1228", "#1e2c5c", "#344e92", "#5a7cc4", "#a2c2f4"],
      style: CRISPY_STYLE,
      hairline: [[0, 48], [66, 50], [98, 96], [100, 118], [180, 130]],
      locks: [
        { phi: -56, a1: 72, twist: 16, flick: 1.24, width: 3.1, tip: 0.55 },
        { phi: -28, a1: 76, twist: 18, flick: 1.22, width: 3.3, tip: 0.55 },
        { phi: 0,   a1: 72, twist: 14, flick: 1.22, width: 3.2, tip: 0.55 },
        { phi: 28,  a1: 74, twist: -10, flick: 1.22, width: 3.2, tip: 0.55 },
        { phi: 56,  a1: 70, twist: -16, flick: 1.24, width: 3.1, tip: 0.55 },
        // Cheek-skimming feathered side locks
        { phi: -88, a1: 106, twist: -6, flick: 1.22, width: 3.0, tip: 0.6, taper: 0.72, drop: 5, spread: 0.9 },
        { phi: 88,  a1: 106, twist: 6,  flick: 1.22, width: 3.0, tip: 0.6, taper: 0.72, drop: 5, spread: 0.9 },
        // Shaggy flared wolf-tail nape strands
        { phi: -116, a1: 118, twist: -10, flick: 1.28, width: 3.1, tip: 0.55, taper: 0.72, drop: 9, spread: 2.2 },
        { phi: 116,  a1: 118, twist: 10,  flick: 1.28, width: 3.1, tip: 0.55, taper: 0.72, drop: 9, spread: 2.2 },
        { phi: -144, a1: 122, twist: -8,  flick: 1.26, width: 3.3, tip: 0.55, taper: 0.74, drop: 11, spread: 1.6 },
        { phi: 144,  a1: 122, twist: 8,   flick: 1.26, width: 3.3, tip: 0.55, taper: 0.74, drop: 11, spread: 1.6 },
        { phi: 170,  a1: 124, twist: 6,   flick: 1.26, width: 3.4, tip: 0.55, taper: 0.74, drop: 12, spread: 1.0 },
        { phi: -170, a1: 124, twist: -6,  flick: 1.26, width: 3.4, tip: 0.55, taper: 0.74, drop: 12, spread: 1.0 },
        // Crown layered feather spikes
        { phi: -120, a0: 3, a1: 42, twist: 18, flick: 1.48, lift: 0.05, width: 2.8, tier: 1, tip: 0.5 },
        { phi: -45,  a0: 3, a1: 38, twist: 20, flick: 1.46, lift: 0.05, width: 2.6, tier: 1, tip: 0.5 },
        { phi: 50,   a0: 3, a1: 38, twist: -18, flick: 1.46, lift: 0.05, width: 2.6, tier: 1, tip: 0.5 },
        { phi: 130,  a0: 3, a1: 42, twist: -16, flick: 1.48, lift: 0.05, width: 2.8, tier: 1, tip: 0.5 }
      ]
    },
    // 6. 公主切长直发 — straight blunt bangs + sharp cheek locks + waist-length back veil
    {
      id: "hair_hime_cut",
      name: "公主切长发",
      palette: ["#0c0818", "#20163e", "#3c2c6c", "#6c56a4", "#b4a4e4"],
      style: CLEAN_STYLE,
      hairline: [[0, 54], [68, 54], [94, 98], [94, 120], [180, 128]],
      locks: [
        // Crisp blunt fringe
        { phi: -48, a1: 64, twist: 0, flick: 1.04, width: 3.4, tip: 1.3, taper: 0.78 },
        { phi: -24, a1: 64, twist: 0, flick: 1.04, width: 3.5, tip: 1.3, taper: 0.78 },
        { phi: 0,   a1: 64, twist: 0, flick: 1.04, width: 3.5, tip: 1.3, taper: 0.78 },
        { phi: 24,  a1: 64, twist: 0, flick: 1.04, width: 3.5, tip: 1.3, taper: 0.78 },
        { phi: 48,  a1: 64, twist: 0, flick: 1.04, width: 3.4, tip: 1.3, taper: 0.78 },
        // Iconic sharp straight cheek-level hime side-locks
        { phi: -74, a1: 96, twist: 0, flick: 1.04, width: 3.0, tip: 1.4, taper: 0.86, drop: 6, spread: -0.2 },
        { phi: 74,  a1: 96, twist: 0, flick: 1.04, width: 3.0, tip: 1.4, taper: 0.86, drop: 6, spread: -0.2 },
        // Long straight flowing back curtain
        { phi: -102, a1: 108, twist: 0, flick: 1.02, width: 3.2, tip: 1.1, taper: 0.86, drop: 19, spread: 0.0 },
        { phi: 102,  a1: 108, twist: 0, flick: 1.02, width: 3.2, tip: 1.1, taper: 0.86, drop: 19, spread: 0.0 },
        { phi: -126, a1: 114, twist: 0, flick: 1.02, width: 3.4, tip: 1.1, taper: 0.86, drop: 21, spread: 0.0 },
        { phi: 126,  a1: 114, twist: 0, flick: 1.02, width: 3.4, tip: 1.1, taper: 0.86, drop: 21, spread: 0.0 },
        { phi: -152, a1: 118, twist: 0, flick: 1.02, width: 3.6, tip: 1.1, taper: 0.86, drop: 22, spread: 0.0 },
        { phi: 152,  a1: 118, twist: 0, flick: 1.02, width: 3.6, tip: 1.1, taper: 0.86, drop: 22, spread: 0.0 },
        { phi: 174,  a1: 118, twist: 0, flick: 1.02, width: 3.6, tip: 1.1, taper: 0.86, drop: 22, spread: 0.0 },
        { phi: -174, a1: 118, twist: 0, flick: 1.02, width: 3.6, tip: 1.1, taper: 0.86, drop: 22, spread: 0.0 }
      ]
    },
    // 7. 浪漫波浪长发 — voluminous flowing wavy long hair
    {
      id: "hair_wavy_long",
      name: "浪漫大波浪",
      palette: ["#381408", "#843412", "#d06020", "#f69844", "#ffda92"],
      style: CLEAN_STYLE,
      hairline: [[0, 48], [64, 50], [94, 96], [96, 118], [180, 128]],
      locks: [
        { phi: -50, a1: 68, twist: -18, flick: 1.18, lift: 0.06, width: 3.4, tip: 0.75 },
        { phi: -22, a1: 66, twist: -14, flick: 1.16, lift: 0.06, width: 3.4, tip: 0.75 },
        { phi: 12,  a1: 68, twist: 16,  flick: 1.18, lift: 0.06, width: 3.5, tip: 0.75 },
        { phi: 44,  a1: 66, twist: 18,  flick: 1.18, lift: 0.06, width: 3.4, tip: 0.75 },
        // Wide billowing wavy cascading locks
        { phi: -82,  a1: 102, twist: -12, flick: 1.18, lift: 0.08, width: 3.4, tip: 0.9, taper: 0.84, drop: 14, spread: 2.2 },
        { phi: 82,   a1: 102, twist: 12,  flick: 1.18, lift: 0.08, width: 3.4, tip: 0.9, taper: 0.84, drop: 14, spread: 2.2 },
        { phi: -108, a1: 110, twist: 10,  flick: 1.16, lift: 0.10, width: 3.6, tip: 0.9, taper: 0.84, drop: 18, spread: 3.0 },
        { phi: 108,  a1: 110, twist: -10, flick: 1.16, lift: 0.10, width: 3.6, tip: 0.9, taper: 0.84, drop: 18, spread: 3.0 },
        { phi: -136, a1: 116, twist: -8,  flick: 1.14, lift: 0.08, width: 3.8, tip: 0.9, taper: 0.84, drop: 19, spread: 2.2 },
        { phi: 136,  a1: 116, twist: 8,   flick: 1.14, lift: 0.08, width: 3.8, tip: 0.9, taper: 0.84, drop: 19, spread: 2.2 },
        { phi: -164, a1: 118, twist: 6,   flick: 1.12, lift: 0.08, width: 3.8, tip: 0.9, taper: 0.84, drop: 20, spread: 1.2 },
        { phi: 164,  a1: 118, twist: -6,  flick: 1.12, lift: 0.08, width: 3.8, tip: 0.9, taper: 0.84, drop: 20, spread: 1.2 },
        // Fluffy crown waves
        { phi: -135, a0: 4, a1: 42, twist: 24, flick: 1.24, lift: 0.10, width: 3.2, tier: 1, tip: 0.8 },
        { phi: -55,  a0: 4, a1: 38, twist: 22, flick: 1.22, lift: 0.10, width: 3.0, tier: 1, tip: 0.8 },
        { phi: 55,   a0: 4, a1: 38, twist: -22, flick: 1.22, lift: 0.10, width: 3.0, tier: 1, tip: 0.8 },
        { phi: 135,  a0: 4, a1: 42, twist: -24, flick: 1.24, lift: 0.10, width: 3.2, tier: 1, tip: 0.8 }
      ]
    },
    // 8. 半扎公主头 — gathered top-back half-bun + flowing shoulder hair
    {
      id: "hair_half_up",
      name: "半扎公主头",
      palette: ["#4c3a24", "#92764c", "#d2b682", "#f2dfae", "#fff8e4"],
      style: CLEAN_STYLE,
      hairline: [[0, 48], [64, 50], [96, 94], [98, 116], [180, 126]],
      locks: [
        { phi: -44, a1: 64, twist: 18, flick: 1.12, width: 3.2, tip: 0.65 },
        { phi: -16, a1: 64, twist: 20, flick: 1.12, width: 3.4, tip: 0.65 },
        { phi: 14,  a1: 62, twist: 18, flick: 1.12, width: 3.2, tip: 0.65 },
        { phi: 44,  a1: 62, twist: -14, flick: 1.12, width: 3.2, tip: 0.65 },
        // Flowing lower shoulder locks
        { phi: -86,  a1: 102, twist: 4,  flick: 1.06, width: 2.9, tip: 0.85, taper: 0.78, drop: 10, spread: -0.2 },
        { phi: 86,   a1: 102, twist: -4, flick: 1.06, width: 2.9, tip: 0.85, taper: 0.78, drop: 10, spread: -0.2 },
        { phi: -116, a1: 112, twist: 0,  flick: 1.06, width: 3.2, tip: 0.85, taper: 0.80, drop: 14, spread: 0.2 },
        { phi: 116,  a1: 112, twist: 0,  flick: 1.06, width: 3.2, tip: 0.85, taper: 0.80, drop: 14, spread: 0.2 },
        { phi: -146, a1: 116, twist: 0,  flick: 1.06, width: 3.4, tip: 0.85, taper: 0.80, drop: 15, spread: 0.2 },
        { phi: 146,  a1: 116, twist: 0,  flick: 1.06, width: 3.4, tip: 0.85, taper: 0.80, drop: 15, spread: 0.2 },
        { phi: 170,  a1: 118, twist: 0,  flick: 1.06, width: 3.4, tip: 0.85, taper: 0.80, drop: 15, spread: 0.0 },
        { phi: -170, a1: 118, twist: 0,  flick: 1.06, width: 3.4, tip: 0.85, taper: 0.80, drop: 15, spread: 0.0 },
        // Gathered half-up knot / mini-bun on upper back + short ribbon cascade
        { phi: 155,  a0: 36, a1: 56, flick: 0.94, lift: 0.44, width: 3.1, tier: 1, tip: 1.6, taper: 0.46, twist: 0 },
        { phi: -155, a0: 36, a1: 56, flick: 0.94, lift: 0.44, width: 3.1, tier: 1, tip: 1.6, taper: 0.46, twist: 0 },
        { phi: 180,  a0: 34, a1: 58, flick: 0.94, lift: 0.48, width: 3.3, tier: 1, tip: 1.6, taper: 0.46, twist: 0 },
        { phi: 180,  a0: 54, a1: 72, flick: 1.24, lift: 0.16, width: 2.8, taper: 0.72, tip: 0.9, drop: 11, spread: 0.4, twist: 0 }
      ]
    },
    // 9. 中分括号发 — stylish center-parted curtain bangs
    {
      id: "hair_curtain",
      name: "中分括号发",
      palette: ["#1e1a18", "#483e38", "#786a5e", "#aa9c8c", "#ded4c6"],
      style: CLEAN_STYLE,
      hairline: [[0, 38], [24, 46], [68, 54], [98, 94], [100, 114], [180, 122]],
      locks: [
        // Symmetrical outward-swept curtain bangs leaving clean center part
        { phi: -16, a0: 10, a1: 76, twist: -34, flick: 1.14, lift: 0.04, width: 3.4, tip: 0.65 },
        { phi: -44, a0: 10, a1: 82, twist: -22, flick: 1.12, lift: 0.04, width: 3.4, tip: 0.65 },
        { phi: 16,  a0: 10, a1: 76, twist: 34,  flick: 1.14, lift: 0.04, width: 3.4, tip: 0.65 },
        { phi: 44,  a0: 10, a1: 82, twist: 22,  flick: 1.12, lift: 0.04, width: 3.4, tip: 0.65 },
        // Soft layered sides & back
        { phi: -86,  a1: 106, twist: -8, flick: 1.08, width: 3.3, tip: 0.7, drop: 2, spread: -0.4 },
        { phi: 86,   a1: 106, twist: 8,  flick: 1.08, width: 3.3, tip: 0.7, drop: 2, spread: -0.4 },
        { phi: -120, a1: 118, twist: -4, flick: 1.06, width: 3.8, tip: 0.7 },
        { phi: 120,  a1: 118, twist: 4,  flick: 1.06, width: 3.8, tip: 0.7 },
        { phi: -154, a1: 120, twist: 0,  flick: 1.06, width: 4.0, tip: 0.7 },
        { phi: 154,  a1: 120, twist: 0,  flick: 1.06, width: 4.0, tip: 0.7 },
        { phi: 180,  a1: 120, twist: 0,  flick: 1.06, width: 4.0, tip: 0.7 },
        // Lifted center-part volume
        { phi: -28, a0: 4, a1: 38, twist: -28, flick: 1.24, lift: 0.08, width: 3.0, tier: 1, tip: 0.7 },
        { phi: 28,  a0: 4, a1: 38, twist: 28,  flick: 1.24, lift: 0.08, width: 3.0, tier: 1, tip: 0.7 }
      ]
    },
    // 10. 蓬松羊毛卷 — adorable bouncy fluffy curly cloud dome
    {
      id: "hair_fluffy_curl",
      name: "蓬松羊毛卷",
      palette: ["#1c100c", "#4a2a1a", "#7c4a2a", "#b47c42", "#ecc27a"],
      style: { ...CLEAN_STYLE, ring: false, grit: 0.08 },
      hairline: [[0, 48], [64, 52], [96, 98], [100, 118], [180, 124]],
      locks: [
        // Curly bangs + fluffy rounded dome (taller crown, snugger cheek curls)
        { phi: -44, a0: 14, a1: 64, twist: -14, flick: 1.12, lift: 0.12, width: 3.8, tip: 1.5, taper: 0.58 },
        { phi: -16, a0: 12, a1: 64, twist: 12,  flick: 1.12, lift: 0.14, width: 3.9, tip: 1.5, taper: 0.58 },
        { phi: 16,  a0: 12, a1: 64, twist: -12, flick: 1.12, lift: 0.14, width: 3.9, tip: 1.5, taper: 0.58 },
        { phi: 44,  a0: 14, a1: 64, twist: 14,  flick: 1.12, lift: 0.12, width: 3.8, tip: 1.5, taper: 0.58 },
        { phi: -80, a0: 18, a1: 102, twist: -12, flick: 1.10, lift: 0.10, width: 3.8, tip: 1.4, taper: 0.65, drop: 4, spread: -0.4 },
        { phi: 80,  a0: 18, a1: 102, twist: 12,  flick: 1.10, lift: 0.10, width: 3.8, tip: 1.4, taper: 0.65, drop: 4, spread: -0.4 },
        { phi: -112, a0: 18, a1: 114, twist: 10,  flick: 1.12, lift: 0.12, width: 4.0, tip: 1.4, taper: 0.65, drop: 5, spread: 0.0 },
        { phi: 112,  a0: 18, a1: 114, twist: -10, flick: 1.12, lift: 0.12, width: 4.0, tip: 1.4, taper: 0.65, drop: 5, spread: 0.0 },
        { phi: -148, a0: 18, a1: 118, twist: -10, flick: 1.12, lift: 0.12, width: 4.1, tip: 1.4, taper: 0.65, drop: 5, spread: 0.0 },
        { phi: 148,  a0: 18, a1: 118, twist: 10,  flick: 1.12, lift: 0.12, width: 4.1, tip: 1.4, taper: 0.65, drop: 5, spread: 0.0 },
        { phi: 180,  a0: 18, a1: 120, twist: 0,   flick: 1.12, lift: 0.12, width: 4.2, tip: 1.4, taper: 0.65, drop: 5, spread: 0.0 },
        // Rounded fluffy top crown curls (gives soft spherical curly volume!)
        { phi: -135, a0: 4, a1: 36, twist: 16,  flick: 1.14, lift: 0.24, width: 3.8, tier: 1, tip: 1.6, taper: 0.5 },
        { phi: -55,  a0: 4, a1: 34, twist: -16, flick: 1.14, lift: 0.24, width: 3.8, tier: 1, tip: 1.6, taper: 0.5 },
        { phi: 0,    a0: 2, a1: 30, twist: 10,  flick: 1.14, lift: 0.26, width: 3.8, tier: 1, tip: 1.6, taper: 0.5 },
        { phi: 55,   a0: 4, a1: 34, twist: 16,  flick: 1.14, lift: 0.24, width: 3.8, tier: 1, tip: 1.6, taper: 0.5 },
        { phi: 135,  a0: 4, a1: 36, twist: -16, flick: 1.14, lift: 0.24, width: 3.8, tier: 1, tip: 1.6, taper: 0.5 }
      ]
    },
    // 11. 侧麻花辫 — gentle swept bangs + thick woven side braid cascading over shoulder
    {
      id: "hair_side_braid",
      name: "侧麻花辫",
      palette: ["#1e0c0a", "#4e1e16", "#86362a", "#c0603e", "#f0a070"],
      style: CLEAN_STYLE,
      hairline: [[0, 48], [62, 50], [98, 94], [100, 114], [180, 120]],
      locks: [
        { phi: -44, a1: 66, twist: 24, flick: 1.12, width: 3.3, tip: 0.65 },
        { phi: -14, a1: 64, twist: 26, flick: 1.12, width: 3.4, tip: 0.65 },
        { phi: 18,  a1: 60, twist: 24, flick: 1.12, width: 3.2, tip: 0.65 },
        { phi: 52,  a1: 70, twist: 40, flick: 1.06, width: 3.4, tip: 0.65 },
        { phi: -86, a1: 100, twist: 6, flick: 1.08, width: 3.1, tip: 0.8, taper: 0.72, drop: 5, spread: -0.2 },
        { phi: 92,  a1: 98, twist: -6, flick: 1.08, width: 3.1, tip: 0.8, taper: 0.72, drop: 4, spread: -0.2 },
        { phi: 130, a1: 114, twist: 22, flick: 1.04, width: 4.2, tip: 0.65 },
        { phi: -130, a1: 114, twist: -22, flick: 1.04, width: 4.2, tip: 0.65 },
        { phi: 164, a1: 112, twist: 10, flick: 1.04, width: 4.4, tip: 0.65 },
        { phi: -164, a1: 112, twist: -10, flick: 1.04, width: 4.4, tip: 0.65 }
      ]
    },
    // 12. 飒爽背头 — confident open-forehead swept-back quiff/pompadour
    {
      id: "hair_quiff",
      name: "飒爽背头",
      palette: ["#2e3246", "#6a7088", "#a8b0c2", "#d8dee8", "#ffffff"],
      style: CRISPY_STYLE,
      hairline: [[0, 32], [44, 38], [86, 78], [100, 102], [180, 114]],
      locks: [
        // Swept-back forehead crest waves
        { phi: -30, a0: 14, a1: 52, twist: -22, flick: 1.24, lift: 0.16, width: 3.4, tier: 1, tip: 0.65 },
        { phi: 0,   a0: 12, a1: 50, twist: 14,  flick: 1.28, lift: 0.20, width: 3.6, tier: 1, tip: 0.65 },
        { phi: 30,  a0: 14, a1: 52, twist: 26,  flick: 1.24, lift: 0.16, width: 3.4, tier: 1, tip: 0.65 },
        // Sleek tapered sides swept backward
        { phi: -78,  a0: 16, a1: 86, twist: -26, flick: 1.06, width: 3.1, tip: 0.65 },
        { phi: 78,   a0: 16, a1: 86, twist: 26,  flick: 1.06, width: 3.1, tip: 0.65 },
        { phi: -116, a0: 12, a1: 110, twist: -14, flick: 1.06, width: 3.7, tip: 0.65 },
        { phi: 116,  a0: 12, a1: 110, twist: 14,  flick: 1.06, width: 3.7, tip: 0.65 },
        { phi: -150, a0: 10, a1: 114, twist: -6,  flick: 1.06, width: 4.0, tip: 0.65 },
        { phi: 150,  a0: 10, a1: 114, twist: 6,   flick: 1.06, width: 4.0, tip: 0.65 },
        { phi: 180,  a0: 10, a1: 116, twist: 0,   flick: 1.06, width: 4.0, tip: 0.65 },
        // Slicked-back crown ridge
        { phi: 180,  a0: 2, a1: 42, twist: 0, flick: 1.26, lift: 0.12, width: 3.4, tier: 1, tip: 0.6 }
      ]
    }
  ];

  // Register the 12 new hairstyles with all 20 hair colors
  for (const def of NEW_HAIRSTYLES) {
    const item = ho(def, EXPANDED_HAIR_COLORS);

    // Add real woven braided plait over one shoulder for hair_side_braid!
    if (def.id === "hair_side_braid") {
      const braidTie = k("braid-gold-tie", "#3e2408", "#8a5c16", "#d8a430", "#f6d86c", "#fff6c0");
      item.palettes.tie = braidTie;
      const drawBraid = (ctx, targetLayer) => {
        const { g, pose } = ctx;
        const cx = pose.head.x + pose.sin * 0.2;
        const cy = pose.head.y - 1.2;
        // Anchor behind left ear (phi = -104, a = 104)
        const root = xa(pose, cx, cy, 102, -102, 1.04);
        const inFront = root.near >= -0.22;
        if ((targetLayer === "hair") !== inFront) return;
        const sway = pose.anim === "walk" ? Math.sin(pose.phase * 2) * 1.1 : 0;
        const driftX = (root.x < cx ? -1.4 : 1.0) + pose.sin * 0.6;
        ctx.pal("main");
        g.grit = 0.04;
        g.dither = false;
        g.anchor(root.x, root.y);
        // 5 overlapping woven braid beads descending cleanly over shoulder
        const segs = 5;
        let lastX = root.x, lastY = root.y;
        for (let s = 0; s < segs; s++) {
          const t = (s + 0.5) / segs;
          const bx = root.x + driftX * t + sway * t * t + (s % 2 === 0 ? -0.55 : 0.55);
          const by = root.y + 3.2 * (s + 0.65);
          const rx = 2.15 - t * 0.45;
          const ry = 2.0 - t * 0.25;
          g.ellipse(bx, by, rx, ry, (shade, lx, ly) => {
            const twist = (s % 2 === 0 ? 1 : -1) * lx * 0.45;
            return Math.min(4, Math.max(1, g.t(shade * 0.9 + twist, 0.15)));
          });
          lastX = bx;
          lastY = by;
        }
        // Tapered hair tassel tip below the tie
        g.capsule(lastX, lastY + 1.8, lastX + sway * 0.4, lastY + 5.2, 1.5, 0.45, s => Math.max(1, g.t(s, 0.05)));
        // Tiny golden ribbon band tying the braid
        ctx.pal("tie");
        g.ellipse(lastX, lastY + 1.7, 1.5, 0.95, s => s > 0.2 ? 4 : 2);
      };
      item.parts.push({ layer: "cape", innerLine: 1.25, draw: ctx => drawBraid(ctx, "cape") });
      item.parts.push({ layer: "hair", innerLine: 1.25, draw: ctx => drawBraid(ctx, "hair") });
    }

    // Add tiny pearl/gold hair-tie accents at the base of twin-tails & twin-buns for extra charm
    if (def.id === "hair_twintails") {
      const ribbonPal = k("twintail-ribbon", "#3e2408", "#8a5c16", "#d8a430", "#f6d86c", "#fff6c0");
      item.palettes.tie = ribbonPal;
      const drawTies = (ctx, frontPass) => {
        const { g, pose } = ctx;
        const cx = pose.head.x + pose.sin * 0.2;
        const cy = pose.head.y - 1.2;
        ctx.pal("tie");
        g.grit = 0;
        for (const phi of [-106, 106]) {
          const p = xa(pose, cx, cy, 62, phi, 1.12);
          const isFront = p.near >= -0.15;
          if (isFront !== frontPass) continue;
          g.ellipse(p.x, p.y, 1.55, 1.1, s => s > 0.2 ? 4 : 3);
        }
      };
      item.parts.push({ layer: "hair_back", outline: false, draw: ctx => drawTies(ctx, false) });
      item.parts.push({ layer: "hair", outline: false, draw: ctx => drawTies(ctx, true) });
    }

    Me(item, "expansion/hair/" + def.id);
  }

  // =========================================================================
  // 3. 18 EYE COLORS (16 pure jewel eyes on face_round + 2 heterochromia faces)
  // =========================================================================
  const EXPANDED_EYE_VARIANTS = [
    { id: "teal",     name: "碧青瞳",   palettes: { eye: ["#17101e", "#1e3a5c", "#3e9aa8", "#8ad8d8", "#ffffff"] } },
    { id: "amber",    name: "琥珀瞳",   palettes: { eye: ["#1e120a", "#5a3410", "#c07a20", "#f0c060", "#ffffff"] } },
    { id: "violet",   name: "紫晶瞳",   palettes: { eye: ["#160e22", "#3a2266", "#7a52c0", "#c0a0f0", "#ffffff"] } },
    { id: "blue",     name: "蔚蓝瞳",   palettes: { eye: ["#14101e", "#1c2e6a", "#3a64c4", "#86b4f4", "#ffffff"] } },
    { id: "green",    name: "翠绿瞳",   palettes: { eye: ["#10180e", "#1e4a24", "#3e8a46", "#90d48a", "#ffffff"] } },
    { id: "ruby",     name: "绯红瞳",   palettes: { eye: ["#22060c", "#6c1020", "#cc2a3c", "#ff848e", "#ffffff"] } },
    { id: "sakura",   name: "樱粉瞳",   palettes: { eye: ["#2a0c1c", "#7c2650", "#dc6296", "#ffb2d4", "#ffffff"] } },
    { id: "gold",     name: "琉璃金瞳", palettes: { eye: ["#241604", "#744c0c", "#dca420", "#ffe478", "#ffffff"] } },
    { id: "ice",      name: "冰晶蓝瞳", palettes: { eye: ["#101e30", "#2c6496", "#6ec4ee", "#c6f2ff", "#ffffff"] } },
    { id: "obsidian", name: "墨玉瞳",   palettes: { eye: ["#08080e", "#1e2030", "#424864", "#8a94b4", "#ffffff"] } },
    { id: "hazel",    name: "栗棕瞳",   palettes: { eye: ["#1e1008", "#542c14", "#985828", "#d89c60", "#ffffff"] } },
    { id: "emerald",  name: "森翡翠瞳", palettes: { eye: ["#081e12", "#145c34", "#28b464", "#86f2aa", "#ffffff"] } },
    { id: "orange",   name: "落日橙瞳", palettes: { eye: ["#280e04", "#7e300c", "#e46e22", "#ffba6c", "#ffffff"] } },
    { id: "silver",   name: "银月瞳",   palettes: { eye: ["#181c28", "#485068", "#8e98b2", "#d4dce8", "#ffffff"] } },
    { id: "indigo",   name: "星海蓝瞳", palettes: { eye: ["#0c0c24", "#20246e", "#4454c8", "#98a8ff", "#ffffff"] } },
    { id: "magenta",  name: "莓果洋红", palettes: { eye: ["#240620", "#6c145e", "#c430a4", "#f890e2", "#ffffff"] } }
  ];

  // Replace face_round with all 16 pure jewel eye variants
  ie.set("face_round", Je({ ...i0, variants: EXPANDED_EYE_VARIANTS }));

  // Helper for heterochromia (异色瞳) faces using exact face_round geometry
  function makeHeteroFace(id, name, leftEyeHexes, rightEyeHexes) {
    const palettes = {
      eyeL: k(`${id}-eyeL`, ...leftEyeHexes),
      eyeR: k(`${id}-eyeR`, ...rightEyeHexes),
      blush: k(`${id}-blush`, ...i0.palettes.blush)
    };
    return {
      id,
      name,
      slot: "face",
      palettes,
      variants: [],
      parts: [{
        layer: "head",
        mask: "below",
        outline: false,
        draw: ctx => {
          const view = i0.views[ctx.dir];
          if (!view) return;
          const { g } = ctx;
          const { px, py, k: step } = ze(ctx);
          const dot = (d, val) => g.cellsPx([String(val)], px + d[0] * step, py + d[1] * step);
          (view.eyes || []).forEach(([patName, ox, oy], idx) => {
            ctx.pal(idx === 0 ? "eyeL" : "eyeR");
            const mirrored = patName.endsWith("!");
            const pat = i0.patterns[mirrored ? patName.slice(0, -1) : patName];
            g.cellsPx(mirrored ? We(pat) : pat, px + ox * step, py + oy * step);
          });
          ctx.pal("blush");
          for (const d of view.blush || []) dot(d, 2);
          ctx.pal("skin");
          for (const d of view.mouth || []) dot(d, 1);
          for (const d of view.brows || []) dot(d, 1);
        }
      }]
    };
  }

  Me(
    makeHeteroFace(
      "face_hetero_gold_blue", "金蓝异瞳",
      ["#241604", "#744c0c", "#dca420", "#ffe478", "#ffffff"],
      ["#14101e", "#1c2e6a", "#3a64c4", "#86b4f4", "#ffffff"]
    ),
    "expansion/face/hetero_gold_blue"
  );
  Me(
    makeHeteroFace(
      "face_hetero_crimson_cyan", "绯青异瞳",
      ["#22060c", "#6c1020", "#cc2a3c", "#ff848e", "#ffffff"],
      ["#101e30", "#2c6496", "#6ec4ee", "#c6f2ff", "#ffffff"]
    ),
    "expansion/face/hetero_crimson_cyan"
  );

  // =========================================================================
  // 4. EXPANDED BOTTOMS & SHOES (coordinated with costumes + usable in Lab)
  // =========================================================================
  const EXTRA_TROUSER_VARIANTS = [
    { id: "navy",    name: "学院藏蓝", palettes: { main: k("tr-navy",    "#0a0e20", "#182448", "#2a3e72", "#46609c", "#7492cc") } },
    { id: "denim",   name: "丹宁蓝",   palettes: { main: k("tr-denim",   "#0e1828", "#223c60", "#3a6294", "#628ec0", "#9cc2e8") } },
    { id: "khaki",   name: "卡其沙",   palettes: { main: k("tr-khaki",   "#241a0e", "#5a462c", "#90744e", "#bea278", "#e6d2ae") } },
    { id: "slate",   name: "学院灰",   palettes: { main: k("tr-slate",   "#12141c", "#2c303e", "#4e5468", "#788098", "#aeb6cc") } },
    { id: "black",   name: "曜石黑",   palettes: { main: k("tr-black",   "#06060a", "#14141c", "#242632", "#3e4254", "#666c82") } },
    { id: "indigo",  name: "星夜靛",   palettes: { main: k("tr-indigo",  "#0a081e", "#1c1848", "#302a74", "#5048a6", "#847cd6") } },
    { id: "crimson", name: "酒红",     palettes: { main: k("tr-crimson", "#20060c", "#4e101c", "#822030", "#b24250", "#e27a84") } },
    { id: "forest",  name: "森绿",     palettes: { main: k("tr-forest",  "#0a1810", "#183c24", "#2c643e", "#4e925e", "#82c48c") } }
  ];
  for (const variant of EXTRA_TROUSER_VARIANTS) {
    if (!baseTrousers.variants.some(x => x.id === variant.id)) baseTrousers.variants.push(variant);
  }

  const EXTRA_BOOT_VARIANTS = [
    { id: "white",   name: "雪白",   palettes: { main: k("bt-white",   "#303444", "#767c90", "#b8bcc8", "#e6e8ee", "#ffffff") } },
    { id: "cream",   name: "暖米",   palettes: { main: k("bt-cream",   "#3a2c1c", "#806648", "#bca27e", "#e4d0ae", "#fff4dc") } },
    { id: "navy",    name: "藏蓝",   palettes: { main: k("bt-navy",    "#080c1c", "#16244a", "#284078", "#4866a6", "#80a0da") } },
    { id: "crimson", name: "酒红",   palettes: { main: k("bt-crimson", "#24060c", "#58121e", "#942434", "#c84c58", "#f68c94") } },
    { id: "tan",     name: "浅驼",   palettes: { main: k("bt-tan",     "#26160a", "#603a1c", "#9c6638", "#ce965e", "#f6cc96") } }
  ];
  for (const variant of EXTRA_BOOT_VARIANTS) {
    if (!baseBoots.variants.some(x => x.id === variant.id)) baseBoots.variants.push(variant);
  }

  // Brand-new procedural bottom: Pleated Skirt + Knee Socks
  const skirtNavy = k("skirt-navy", "#080e22", "#162652", "#264084", "#4666b4", "#7ea2e6");
  const sockWhite = k("sock-white", "#34384a", "#7e8498", "#c2c6d2", "#eceef4", "#ffffff");
  const drawSockLeg = idx => ({
    layer: "bottom",
    draw: ctx => {
      const { g } = ctx;
      const leg = ctx.pose.legs[idx];
      const shade = ut(ctx, leg.foot);
      const fx = leg.foot.x, fy = leg.foot.y - 5;
      ctx.pal("sock");
      g.anchor(fx, fy);
      g.capsule(leg.knee.x, leg.knee.y, fx, fy, 1.9, 1.8, c => g.t(c, shade + 0.1));
    }
  });
  const pleatedSkirt = {
    id: "bottom_pleated_skirt",
    name: "百褶裙配长袜",
    slot: "bottom",
    palettes: { main: skirtNavy, trim: sockWhite, sock: sockWhite },
    variants: [
      { id: "navy",    name: "藏蓝", palettes: { main: skirtNavy } },
      { id: "crimson", name: "格纹红", palettes: { main: k("skirt-crimson", "#260812", "#621426", "#a2263c", "#d45064", "#fa94a2") } },
      { id: "violet",  name: "星梦紫", palettes: { main: k("skirt-violet",  "#1c0e34", "#482876", "#784cb8", "#aa82e6", "#dfd0ff") } },
      { id: "gold",    name: "向日葵", palettes: { main: k("skirt-gold",    "#3c2208", "#8c5a14", "#d69a28", "#f6cb5a", "#fff2aa") } },
      { id: "slate",   name: "学院灰", palettes: { main: k("skirt-slate",   "#161822", "#343a4c", "#5a6278", "#8892aa", "#c0c8dc") } }
    ],
    parts: [
      drawSockLeg(0),
      drawSockLeg(1),
      {
        layer: "bottom",
        draw: ctx => {
          const { g, pose } = ctx;
          const sway = pose.anim === "walk" ? Math.sin(pose.phase) * 0.7 : 0;
          const hipY = pose.legs[0].hip.y - 3.6;
          const hipX = (pose.legs[0].hip.x + pose.legs[1].hip.x) / 2;
          const topHalf = pose.torsoHalf + 0.3;
          const botHalf = topHalf + 3.4 - Math.abs(pose.sin) * 0.8;
          const h = 9.4;
          g.anchor(hipX, hipY);
          g.fill(hipX - botHalf - 2, hipY, hipX + botHalf + 2, hipY + h + 1.4, (x, y) => {
            const p = (y - hipY) / h;
            if (p < 0 || p > 1.05) return -1;
            const cx = hipX + sway * p;
            const hw = topHalf + (botHalf - topHalf) * p;
            const nx = (x - cx) / hw;
            if (Math.abs(nx) > 1) return -1;
            const pleat = Math.sin(nx * 14 + pose.sin * 2.2);
            const hemY = hipY + h + 0.55 * pleat;
            if (y > hemY) return -1;
            const distBottom = hemY - y;
            if (distBottom > 0.9 && distBottom < 2.1) {
              ctx.pal("trim");
              return g.t(nx * z + Math.sqrt(Math.max(0, 1 - nx * nx)) * Q, 0.25);
            }
            ctx.pal("main");
            return g.t(nx * z + Math.sqrt(Math.max(0, 1 - nx * nx)) * Q + pleat * 0.38, -0.05);
          });
        }
      }
    ]
  };
  Me(pleatedSkirt, "expansion/bottom/pleated_skirt");

  // Brand-new procedural bottom: Shorts + Knee Socks
  const shortsBrown = k("shorts-brown", "#1c1008", "#4c301a", "#7e5432", "#b08252", "#deb682");
  const shortsSocks = {
    id: "bottom_shorts_socks",
    name: "短裤配长袜",
    slot: "bottom",
    palettes: { main: shortsBrown, sock: sockWhite },
    variants: [
      { id: "brown", name: "暖棕", palettes: { main: shortsBrown } },
      { id: "white", name: "雪白", palettes: { main: sockWhite } },
      { id: "navy",  name: "藏蓝", palettes: { main: skirtNavy } },
      { id: "khaki", name: "卡其", palettes: { main: k("shorts-khaki", "#241a0e", "#5a462c", "#90744e", "#bea278", "#e6d2ae") } }
    ],
    parts: [
      drawSockLeg(0),
      drawSockLeg(1),
      ...[0, 1].map(idx => ({
        layer: "bottom",
        draw: ctx => {
          const { g } = ctx;
          const leg = ctx.pose.legs[idx];
          const shade = ut(ctx, leg.foot);
          ctx.pal("main");
          g.anchor(leg.knee.x, leg.knee.y);
          g.capsule(leg.hip.x, leg.hip.y, leg.knee.x, leg.knee.y - 1.2, 2.7, 2.5, c => g.t(c, shade + 0.05));
        }
      })),
      {
        layer: "bottom",
        draw: ctx => {
          const { g, pose } = ctx;
          const a = pose.torsoHalf - 0.1;
          const n = pose.legs[0].hip.y;
          const r = (pose.legs[0].hip.x + pose.legs[1].hip.x) / 2;
          ctx.pal("main");
          g.fill(r - a, n - 4.5, r + a, n + 2.5, (x, y) => {
            const l = (x - r) / a;
            return Math.abs(l) > 1 || y < n - 4.5 || y > n + 1.2 ? -1 : g.t(l * z + Math.sqrt(1 - l * l) * Q, -0.1);
          });
        }
      }
    ]
  };
  Me(shortsSocks, "expansion/bottom/shorts_socks");

  // Brand-new procedural bottom: Wide Hakama / Traditional Robe Skirt-Pants
  const hakamaCrimson = k("hakama-crimson", "#24060c", "#5c1220", "#982436", "#cc4e5c", "#f69298");
  const hakama = {
    id: "bottom_hakama",
    name: "阔腿长袴",
    slot: "bottom",
    palettes: { main: hakamaCrimson },
    variants: [
      { id: "crimson", name: "绯红", palettes: { main: hakamaCrimson } },
      { id: "ivory",   name: "月白", palettes: { main: k("hakama-ivory", "#343642", "#787c8c", "#babec8", "#e6e8ec", "#ffffff") } },
      { id: "navy",    name: "靛青", palettes: { main: skirtNavy } },
      { id: "teal",    name: "青玉", palettes: { main: k("hakama-teal", "#0a2022", "#184e50", "#2a8480", "#58bab0", "#a6e8dc") } }
    ],
    parts: [
      ...[0, 1].map(idx => ({
        layer: "bottom",
        draw: ctx => {
          const { g } = ctx;
          const leg = ctx.pose.legs[idx];
          const shade = ut(ctx, leg.foot);
          ctx.pal("main");
          g.anchor(leg.foot.x, leg.foot.y - 4);
          g.capsule(leg.hip.x, leg.hip.y, leg.knee.x, leg.knee.y, 3.1, 3.0, c => g.t(c, shade + 0.05));
          g.capsule(leg.knee.x, leg.knee.y, leg.foot.x, leg.foot.y - 3.6, 3.0, 2.8, c => g.t(c, shade + 0.05));
        }
      })),
      {
        layer: "bottom",
        draw: ctx => {
          const { g, pose } = ctx;
          const a = pose.torsoHalf + 0.8;
          const n = pose.legs[0].hip.y;
          const r = (pose.legs[0].hip.x + pose.legs[1].hip.x) / 2;
          ctx.pal("main");
          g.fill(r - a, n - 4.5, r + a, n + 4.2, (x, y) => {
            const l = (x - r) / a;
            if (Math.abs(l) > 1 || y < n - 4.5 || y > n + 3.6) return -1;
            const fold = Math.sin(l * 9) * 0.25;
            return g.t(l * z + Math.sqrt(1 - l * l) * Q + fold, -0.05);
          });
        }
      }
    ]
  };
  Me(hakama, "expansion/bottom/hakama");

  // =========================================================================
  // 5. SHARED COSTUME TAILORING HELPERS (native HD-2D shading & animation)
  // =========================================================================

  // Flowing back cape / swallowtail coat-tail / phantom cloak
  function makeBackCape(opts) {
    const {
      mainKey = "main",
      trimKey = "trim",
      liningKey = null,
      lenOffset = 7,
      extraWidth = 3.2,
      splitTail = false,
      asymmetric = false
    } = opts;
    return {
      layer: "cape",
      draw: ctx => {
        const { g, pose } = ctx;
        const { sin, cos } = pose;
        const showingBack = cos < 0.3;
        const walking = pose.anim === "walk";
        const sway = walking ? Math.sin(pose.phase + 1) : 0;
        const topW = (asymmetric ? 4.8 : 6.2) * Math.abs(cos) + 2.8 * Math.abs(sin) + 1.0;
        const botW = topW + extraWidth;
        const cxBase = pose.torsoX(3) - sin * 3.4 + (asymmetric ? -cos * 2.2 : 0);
        const y0 = pose.neckY - 0.3;
        const y1 = Et - lenOffset;
        const folds = 2.0 + Math.abs(cos) * 1.2;
        g.grit = 0.2;
        g.fill(cxBase - botW - 5, y0, cxBase + botW + 5, y1 + 2, (x, y) => {
          const p = Math.min(1, (y - y0) / (y1 - y0));
          if (p < 0) return -1;
          const cx = cxBase + sway * p * 1.5 - sin * p * 2.1;
          const hw = topW + (botW - topW) * p;
          const nx = (x - cx) / hw;
          if (Math.abs(nx) > 1) return -1;
          if (splitTail && p > 0.52 && Math.abs(nx) < (p - 0.52) * 0.42) return -1;
          const wave = nx * folds * Math.PI + p * sway * 0.7;
          const hem = y1 + 0.75 * Math.sin(wave + 0.5) + (walking ? 0.45 * Math.sin(pose.phase * 2 + nx * 2) : 0);
          if (y > hem) return -1;
          const amp = Math.min(1, p * 1.6);
          const ridge = Math.sin(wave + 0.8) * amp;
          if (!showingBack) {
            if (liningKey) {
              ctx.pal(liningKey);
              return g.t(0.1 + ridge * 0.5, -0.2);
            }
            ctx.pal(mainKey);
            return ridge > 0.3 ? 1 : 0;
          }
          let shade = 0.18 + nx * z * 0.85 + ridge * 0.7;
          if (p < 0.12) shade -= 0.55;
          const fromHem = hem - y;
          if (trimKey && fromHem > 1.1 && fromHem < 2.6) {
            ctx.pal(trimKey);
            return g.t(shade, 0.25);
          }
          ctx.pal(mainKey);
          return g.t(shade);
        });
      }
    };
  }

  // Crisp pixel ribbon bow (for sailor tie, sundress apron bow, kimono obi bow, idol waist bow)
  function drawBow(ctx, cx, cy, scale, key) {
    const { g } = ctx;
    ctx.pal(key);
    g.ellipse(cx - 1.7 * scale, cy, 1.45 * scale, 1.1 * scale, s => g.t(s, 0.15));
    g.ellipse(cx + 1.7 * scale, cy, 1.45 * scale, 1.1 * scale, s => g.t(s, 0.0));
    g.ellipse(cx, cy, 0.9 * scale, 0.9 * scale, s => s > 0.1 ? 4 : 2);
    g.capsule(cx - 0.5 * scale, cy + 0.6 * scale, cx - 1.6 * scale, cy + 3.0 * scale, 0.7 * scale, 0.55 * scale, s => g.t(s, 0.05));
    g.capsule(cx + 0.5 * scale, cy + 0.6 * scale, cx + 1.6 * scale, cy + 3.0 * scale, 0.7 * scale, 0.55 * scale, s => g.t(s, -0.1));
  }

  // Long dress / robe / coat skirt extension attached smoothly to torso waist
  function drawExtendedSkirt(ctx, startP, totalH, flare, drawFn) {
    const { g, pose } = ctx;
    const sway = pose.anim === "walk" ? Math.sin(pose.phase) * 0.9 : 0;
    const ny = pose.neckY;
    const baseHalf = pose.torsoHalf;
    const padX = Math.abs(pose.torsoX(0) - pose.torsoX(totalH)) + flare + 3;
    g.fill(pt - baseHalf - padX, ny + startP - 1, pt + baseHalf + padX, ny + totalH + 1.5, (x, y) => {
      const p = y - ny;
      if (p < startP || p > totalH) return -1;
      const t = (p - startP) / Math.max(0.1, totalH - startP);
      const cx = pose.torsoX(Math.min(13.2, p)) + sway * t * t;
      const hw = baseHalf + flare * Math.pow(t, 0.95);
      const nx = (x - cx) / hw;
      if (Math.abs(nx) > 1) return -1;
      const shade = nx * z + Math.sqrt(Math.max(0, 1 - nx * nx)) * Q + 0.05;
      return drawFn(shade, nx, p, t, x, y);
    });
  }

  // Short puffy sleeves helper
  function makePuffSleeves(key, cuffKey, length = 0.45, radius = 2.4) {
    const sideFn = side => ({
      layer: ue(side),
      draw: ctx => {
        const { g } = ctx;
        const arm = wt(ctx, side);
        const sh = ut(ctx, arm.hand);
        ctx.pal(key);
        g.anchor(arm.shoulder.x, arm.shoulder.y);
        g.ellipse(arm.shoulder.x, arm.shoulder.y + 0.9, radius + 0.5, radius + 0.3, s => g.t(s, sh + 0.1));
        const end = Pe(ctx, side, [radius, radius + 0.1, radius - 0.3], length);
        if (cuffKey) {
          ctx.pal(cuffKey);
          g.ellipse(end.x, end.y, radius - 0.1, 1.0, s => g.t(s, sh + 0.2));
        }
      }
    });
    return [sideFn("L"), sideFn("R")];
  }

  // =========================================================================
  // 6. 16 BRAND-NEW ORIGINAL NON-EQUIPMENT COSTUMES (时装)
  // =========================================================================
  const GOLD_TRIM = k("cst-gold", "#3e2408", "#8a5c16", "#d8a430", "#f6d86c", "#fff6c0");
  const IVORY_WHITE = k("cst-ivory", "#3a3e52", "#82889e", "#c4c6ce", "#eeece4", "#fffdf6");
  const CRIMSON_ACC = k("cst-crimson", "#2c060c", "#6e121e", "#b82434", "#e85458", "#ffa4a0");
  const LEATHER_BELT = k("cst-leather", "#160a06", "#3a2210", "#643e22", "#946438", "#c4945e");

  // --- 1. 学院制服 (Academy Blazer Uniform) ---
  const academyNavy = k("cst-acad-navy", "#0a1026", "#1a2854", "#2c4484", "#4a6ab0", "#86a8e4");
  Me({
    id: "top_costume_academy",
    name: "学院制服",
    slot: "top",
    palettes: { main: academyNavy, shirt: IVORY_WHITE, tie: CRIMSON_ACC, gold: GOLD_TRIM },
    variants: [
      { id: "navy",   name: "学院蓝", palettes: { main: academyNavy, tie: CRIMSON_ACC } },
      { id: "forest", name: "常春藤绿", palettes: { main: k("cst-acad-green", "#081c14", "#164430", "#267050", "#46a074", "#86d4a8"), tie: GOLD_TRIM } },
      { id: "wine",   name: "英伦酒红", palettes: { main: k("cst-acad-wine", "#240812", "#581628", "#8e2842", "#c0526c", "#f094a8"), tie: academyNavy } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY, hw = pose.torsoHalf;
          ctx.pal("main");
          J(ctx, 13.8, { flare: 1.8 }, (s, nx, p) => {
            if (p < 2.2) return 0;
            if (p > 12.6) { ctx.pal("gold"); return g.t(s, 0.15); }
            ctx.pal("main");
            return g.t(s, p > 9.5 ? -0.06 : 0.04);
          });
          g.clip = true;
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            // Crisp white V-shirt & collar
            ctx.pal("shirt");
            g.tri({ x: cx - 3.6, y: ny + 1.8 }, { x: cx + 3.6, y: ny + 1.8 }, { x: cx, y: ny + 7.6 }, 4);
            // Crimson necktie
            ctx.pal("tie");
            g.line(cx, ny + 3.2, cx, ny + 8.6, 3);
            g.ellipse(cx, ny + 3.2, 1.1, 0.9, s => s > 0 ? 4 : 2);
            // Gold blazer buttons & tiny academy crest
            ctx.pal("gold");
            g.dot(cx - 2.6, ny + 5.6, 4);
            g.dot(cx - 2.6, ny + 6.4, 3);
            g.dot(cx + 1.3, ny + 9.2, 4);
            g.dot(cx + 1.3, ny + 11.2, 4);
            ctx.pal("main");
            g.line(cx, ny + 8.2, cx, ny + 13.2, V);
          } else if (pose.cos < -0.3) {
            const cx = pose.torsoX(6) - hw * 0.3 * pose.sin;
            g.line(cx, ny + 8.8, cx, ny + 13.2, V);
            ctx.pal("gold");
            g.line(cx - 2.6, ny + 8.4, cx + 2.6, ny + 8.4, 3);
          }
          g.clip = false;
        }
      },
      ...Mt({ key: "main", cuffKey: "gold", r: 2.0 })
    ]
  }, "expansion/top/costume_academy");

  // --- 2. 海风海军装 (Sailor Uniform) ---
  const sailorBlue = k("cst-sailor-blue", "#08122c", "#162c64", "#2850a0", "#4e80d4", "#98c2f8");
  Me({
    id: "top_costume_sailor",
    name: "海风海军装",
    slot: "top",
    palettes: { main: IVORY_WHITE, collar: sailorBlue, tie: CRIMSON_ACC },
    variants: [
      { id: "navy",   name: "经典海蓝", palettes: { collar: sailorBlue, tie: CRIMSON_ACC } },
      { id: "sky",    name: "晴空天蓝", palettes: { collar: k("cst-sailor-sky", "#102a4a", "#26649e", "#4ca4e0", "#8cd6fa", "#daf6ff"), tie: GOLD_TRIM } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          ctx.pal("main");
          J(ctx, 13.0, { flare: 1.5 }, (s, nx, p) => {
            if (p < 2.2) return 0;
            if (p > 11.4) { ctx.pal("collar"); return g.t(s, -0.05); }
            ctx.pal("main");
            return g.t(s, 0.08);
          });
          g.clip = true;
          g.fold(pose.torsoX(6) - pose.torsoHalf + 1.2, ny + 6.5, pose.torsoX(6) - pose.torsoHalf + 3.6, ny + 8.6);
          g.fold(pose.torsoX(6) + pose.torsoHalf - 1.2, ny + 6.2, pose.torsoX(6) + pose.torsoHalf - 3.4, ny + 8.4);
          g.clip = false;
        }
      },
      ...Mt({ key: "main", cuffKey: "collar", r: 2.0 }),
      // Iconic sailor collar: V-cut front + square double-striped sailor flap on back!
      {
        layer: "mantle",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          const hw = pose.torsoHalf + 2.4;
          const cx = pose.torsoX(1);
          if (pose.cos < -0.25) {
            // Back square sailor flap with bright white border stripe
            const flapW = hw * 0.92;
            const y0 = ny - 0.8, y1 = ny + 7.2;
            g.fill(cx - flapW, y0, cx + flapW, y1, (x, y) => {
              const nx = (x - cx) / flapW;
              if (Math.abs(nx) > 1 || y < y0 || y > y1) return -1;
              const edgeX = flapW - Math.abs(x - cx);
              const edgeY = y1 - y;
              const isStripe = (edgeY > 0.9 && edgeY < 2.0) || (edgeX > 0.9 && edgeX < 2.0 && y > y0 + 1.2);
              ctx.pal(isStripe ? "main" : "collar");
              return g.t(nx * z + Math.sqrt(Math.max(0, 1 - nx * nx)) * Q, isStripe ? 0.3 : 0.05);
            });
          } else {
            // Front/side draped V sailor collar
            const y0 = ny - 1.0, y1 = ny + 5.6;
            const frontX = gt(ctx);
            g.fill(cx - hw, y0, cx + hw, y1, (x, y) => {
              const nx = (x - cx) / hw;
              if (Math.abs(nx) > 1) return -1;
              const topY = y0 + 1.8 * (1 - Math.sqrt(1 - nx * nx));
              const dFront = Math.abs(x - frontX) / Math.max(2.5, hw);
              const botY = y1 - dFront * 1.4;
              if (y < topY || y > botY) return -1;
              // Open V neckline in center front
              if (pose.cos > 0.2 && Math.abs(x - frontX) < (y - topY) * 0.42 && y < ny + 4.0) return -1;
              const isStripe = botY - y > 0.7 && botY - y < 1.8;
              ctx.pal(isStripe ? "main" : "collar");
              return g.t(nx * z + Math.sqrt(Math.max(0, 1 - nx * nx)) * Q, isStripe ? 0.3 : 0.05);
            });
            if (pose.cos > 0.25) {
              drawBow(ctx, frontX, ny + 4.8, 0.95, "tie");
            }
          }
        }
      }
    ]
  }, "expansion/top/costume_sailor");

  // --- 3. 星夜学院袍 (Starry Academy Mage Robe — scholarly robe, NOT armor!) ---
  const mageIndigo = k("cst-mage-indigo", "#0c0e2c", "#1e2262", "#343c96", "#5862c8", "#9ca8f2");
  const mageViolet = k("cst-mage-violet", "#1e0c36", "#4e227c", "#8442ba", "#ba7ae8", "#ebd0ff");
  Me({
    id: "top_costume_mage_robe",
    name: "星夜学院袍",
    slot: "top",
    palettes: { main: mageIndigo, sash: mageViolet, trim: GOLD_TRIM },
    variants: [
      { id: "indigo",  name: "星夜靛", palettes: { main: mageIndigo, sash: mageViolet } },
      { id: "emerald", name: "秘境绿", palettes: { main: k("cst-mage-grn", "#081c18", "#14483a", "#247c60", "#48b48a", "#92e8c0"), sash: GOLD_TRIM } },
      { id: "crimson", name: "赤焰红", palettes: { main: CRIMSON_ACC, sash: GOLD_TRIM } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          // Flowing long wizard robe extending down over thighs with gold hem & vertical celestial stole
          drawExtendedSkirt(ctx, 0, 19.6, 4.4, (s, nx, p, t) => {
            if (p < 2.2) { ctx.pal("main"); return 0; }
            const distBot = 19.6 - p;
            if (distBot < 2.1 && distBot > 0.6) {
              ctx.pal("trim");
              return g.t(s, 0.25);
            }
            if (p > 8.2 && p < 10.4) {
              ctx.pal("sash");
              return g.t(s, 0.12);
            }
            // Central vertical gold stole band on front
            if (pose.cos > 0.3 && Math.abs(nx - pose.sin * 0.55) < 0.18 && p > 2.8 && p < 18.6) {
              ctx.pal("trim");
              return g.t(s, 0.22);
            }
            ctx.pal("main");
            const pleat = p > 10 ? Math.sin(nx * 10) * 0.22 : 0;
            return g.t(s + pleat, p < 3.4 ? -0.2 : 0.04);
          });
          // Tiny golden stars along the front hem/chest
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            ctx.pal("trim");
            g.clip = true;
            g.dot(cx, ny + 5.2, 4);
            g.dot(cx - 3.6, ny + 15.8, 4);
            g.dot(cx + 3.6, ny + 15.8, 4);
            g.clip = false;
          }
        }
      },
      ...Mt({ key: "main", cuffKey: "trim", r: 2.35, length: 0.78 }),
      // Scholarly shoulder capelet with gold crescent clasp
      {
        layer: "mantle",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          const hw = pose.torsoHalf + 2.6;
          const cx = pose.torsoX(1);
          const y0 = ny - 1.6, y1 = ny + 4.4;
          g.fill(cx - hw, y0, cx + hw, y1 + 1.2, (x, y) => {
            const nx = (x - cx) / hw;
            if (Math.abs(nx) > 1) return -1;
            const top = y0 + 2.2 * (1 - Math.sqrt(1 - nx * nx));
            const bot = y1 + 0.7 * Math.cos(nx * 5);
            if (y < top || y > bot) return -1;
            const isTrim = bot - y > 0.5 && bot - y < 1.6;
            ctx.pal(isTrim ? "trim" : "sash");
            return g.t(nx * z + Math.sqrt(Math.max(0, 1 - nx * nx)) * Q, isTrim ? 0.25 : 0.05);
          });
          if (pose.cos > 0.3) {
            const fx = gt(ctx);
            ctx.pal("trim");
            g.ellipse(fx, ny + 1.6, 1.35, 1.35, s => s > 0.3 ? 4 : 3);
          }
        }
      }
    ]
  }, "expansion/top/costume_mage_robe");

  // --- 4. 元气连帽卫衣 (Cozy Pullover Hoodie) ---
  const hoodieCoral = k("cst-hoodie-coral", "#3c120a", "#8c321c", "#dc623a", "#f89a66", "#ffdcb8");
  const hoodieMint = k("cst-hoodie-mint", "#12342c", "#2c7462", "#58b498", "#9ae0c4", "#dffef0");
  Me({
    id: "top_costume_hoodie",
    name: "元气连帽卫衣",
    slot: "top",
    palettes: { main: hoodieCoral, trim: IVORY_WHITE },
    variants: [
      { id: "coral", name: "元气珊瑚", palettes: { main: hoodieCoral } },
      { id: "mint",  name: "清新薄荷", palettes: { main: hoodieMint } },
      { id: "sky",   name: "天空蓝",   palettes: { main: k("cst-hoodie-sky", "#102644", "#245c94", "#4898d8", "#88ccf8", "#daf4ff") } }
    ],
    parts: [
      // Hood resting behind neck (clearly readable from SE, E, NE, N!)
      {
        layer: "cape",
        draw: ctx => {
          const { g, pose } = ctx;
          if (pose.cos > 0.65) return;
          const cx = pose.torsoX(1) - pose.sin * 2.8;
          const cy = pose.neckY + 1.8;
          const rx = 5.4 - Math.abs(pose.sin) * 1.1;
          const ry = 4.2;
          ctx.pal("main");
          g.ellipse(cx, cy, rx, ry, (s, lx, ly) => g.t(s, ly > 0.3 ? -0.25 : 0.1));
          g.clip = true;
          g.line(cx - rx * 0.6, cy + 1.0, cx + rx * 0.6, cy + 1.0, V);
          g.clip = false;
        }
      },
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY, hw = pose.torsoHalf;
          ctx.pal("main");
          J(ctx, 13.6, { flare: 1.4, pad: 0.4 }, (s, nx, p) => {
            if (p < 2.2) return 0;
            if (p > 11.4) { ctx.pal("trim"); return g.t(s, 0.12); }
            ctx.pal("main");
            return g.t(s, p > 7.8 && p < 11.2 ? 0.08 : 0.0);
          });
          g.clip = true;
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            // Kangaroo pocket outline & cream drawstrings
            g.line(cx - 3.4, ny + 8.0, cx + 3.4, ny + 8.0, V);
            g.line(cx - 3.6, ny + 8.2, cx - 4.4, ny + 11.0, V);
            g.line(cx + 3.6, ny + 8.2, cx + 4.4, ny + 11.0, V);
            ctx.pal("trim");
            g.line(cx - 1.3, ny + 3.0, cx - 1.5, ny + 6.8, 4);
            g.line(cx + 1.3, ny + 3.0, cx + 1.5, ny + 6.8, 4);
          } else {
            g.fold(pose.torsoX(6) - hw + 1.2, ny + 5.5, pose.torsoX(6) + hw - 1.2, ny + 6.8);
          }
          g.clip = false;
        }
      },
      ...Mt({ key: "main", cuffKey: "trim", r: 2.25 }),
      // Thick rolled hoodie collar encircling neck
      {
        layer: "mantle",
        draw: ctx => {
          const { g, pose } = ctx;
          const cx = pose.torsoX(0) - pose.sin * 0.5;
          const cy = pose.neckY + 0.8;
          const rx = pose.torsoHalf + 1.2;
          ctx.pal("main");
          g.ellipse(cx, cy, rx, 2.3, (s, lx, ly) => g.t(s, ly < -0.2 ? 0.2 : -0.1));
        }
      }
    ]
  }, "expansion/top/costume_hoodie");

  // --- 5. 森林背带装 (Adventurer Denim Overalls over Puffy Shirt) ---
  const denimBib = k("cst-denim-bib", "#0e1a2e", "#22406a", "#3c6ba0", "#689cd0", "#a6cef2");
  const shirtCream = k("cst-shirt-cream", "#403628", "#887860", "#c8bc9e", "#ece4cc", "#fffcf0");
  Me({
    id: "top_costume_overalls",
    name: "森林背带装",
    slot: "top",
    palettes: { main: denimBib, shirt: shirtCream, gold: GOLD_TRIM },
    variants: [
      { id: "denim",      name: "复古丹宁", palettes: { main: denimBib } },
      { id: "terracotta", name: "暖焦糖",   palettes: { main: k("cst-ov-terra", "#2e120a", "#6e321a", "#b05a32", "#dc8c5a", "#f8c89a") } },
      { id: "moss",       name: "林间苔绿", palettes: { main: k("cst-ov-moss",  "#102012", "#28502c", "#468046", "#74b26a", "#b4e0a4") } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          // Cream shirt base + denim bib & straps
          J(ctx, 13.4, { flare: 1.4 }, (s, nx, p) => {
            if (p < 2.0) { ctx.pal("shirt"); return 0; }
            if (p > 9.4) { ctx.pal("main"); return g.t(s, -0.05); }
            // Front bib panel + twin suspender straps
            if (pose.cos > 0.2) {
              const cx = nx - pose.sin * 0.55;
              const inBib = p > 4.4 && Math.abs(cx) < 0.62;
              const inStrap = p <= 4.6 && (Math.abs(cx + 0.42) < 0.16 || Math.abs(cx - 0.42) < 0.16);
              if (inBib || inStrap) { ctx.pal("main"); return g.t(s, 0.08); }
            } else if (pose.cos < -0.2) {
              // Back X-straps!
              const t = (p - 2.0) / 7.4;
              const s1 = -0.45 + 0.9 * t, s2 = 0.45 - 0.9 * t;
              if (Math.abs(nx - s1) < 0.16 || Math.abs(nx - s2) < 0.16) { ctx.pal("main"); return g.t(s, 0.05); }
            } else {
              // Side view strap
              if (Math.abs(nx) < 0.24) { ctx.pal("main"); return g.t(s, 0.05); }
            }
            ctx.pal("shirt");
            return g.t(s, 0.12);
          });
          // Brass bib buttons + front pocket stitching
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            g.clip = true;
            ctx.pal("gold");
            g.dot(cx - 2.6, ny + 5.0, 4);
            g.dot(cx + 2.6, ny + 5.0, 4);
            ctx.pal("main");
            g.line(cx - 2.0, ny + 7.2, cx + 2.0, ny + 7.2, V);
            g.clip = false;
          }
        }
      },
      ...makePuffSleeves("shirt", "main", 0.56, 2.2)
    ]
  }, "expansion/top/costume_overalls");

  // --- 6. 樱韵和服 (Sakura Kimono + Taiko Obi) ---
  const kimonoSakura = k("cst-kim-sakura", "#421628", "#8e3c5c", "#d87498", "#f6b0ca", "#ffe8f2");
  const kimonoObi = k("cst-kim-obi", "#0a102a", "#1c2860", "#304894", "#5674c4", "#98b8f2");
  Me({
    id: "top_costume_kimono",
    name: "樱韵和服",
    slot: "top",
    palettes: { main: kimonoSakura, collar: IVORY_WHITE, obi: kimonoObi, gold: GOLD_TRIM },
    variants: [
      { id: "sakura", name: "樱粉", palettes: { main: kimonoSakura, obi: kimonoObi } },
      { id: "indigo", name: "靛蓝", palettes: { main: kimonoObi, obi: CRIMSON_ACC } },
      { id: "jade",   name: "青瓷", palettes: { main: k("cst-kim-jade", "#0e2a28", "#20645e", "#3ea496", "#84dac8", "#d2f8ee"), obi: CRIMSON_ACC } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          drawExtendedSkirt(ctx, 0, 19.2, 2.6, (s, nx, p) => {
            if (p < 2.0) { ctx.pal("collar"); return 2; }
            // Wide brocade obi sash around waist
            if (p >= 7.6 && p <= 11.4) {
              if (p > 9.1 && p < 10.0) { ctx.pal("gold"); return g.t(s, 0.35); }
              ctx.pal("obi");
              return g.t(s, 0.05);
            }
            // Diagonal white crossover kimono collar (Y-lapel) on front
            if (pose.cos > 0.25 && p < 7.8) {
              const fx = nx - pose.sin * 0.55;
              const leftDiag = Math.abs(fx - (-0.42 + (p - 2.0) * 0.11));
              const rightDiag = Math.abs(fx - (0.42 - (p - 2.0) * 0.11));
              if (leftDiag < 0.16 || (rightDiag < 0.16 && p < 5.6)) {
                ctx.pal("collar");
                return g.t(s, 0.25);
              }
            }
            // Subtle kimono hem border
            if (p > 17.4) {
              ctx.pal("obi");
              return g.t(s, 0.05);
            }
            ctx.pal("main");
            // Subtle sakura petal specks on skirt
            const petal = p > 12.2 && ((Math.floor(nx * 6 + 10) + Math.floor(p * 0.7)) % 5 === 0);
            return g.t(s, petal ? 0.55 : 0.04);
          });
          // Iconic square taiko obi bow on the back!
          if (pose.cos < -0.25) {
            const bx = pose.torsoX(8) - pose.sin * 1.4;
            ctx.pal("obi");
            g.rect(bx - 3.6, ny + 6.4, 7.2, 5.4, (x, y) => {
              const rx = (x - bx) / 3.6;
              return g.t(rx * z + 0.35, y > ny + 10.4 ? -0.3 : 0.12);
            });
            ctx.pal("gold");
            g.line(bx - 3.4, ny + 9.2, bx + 3.4, ny + 9.2, 4);
          }
        }
      },
      // Flowing wide kimono sleeves
      ...Mt({ key: "main", cuffKey: "collar", r: 2.55, length: 0.76 })
    ]
  }, "expansion/top/costume_kimono");

  // --- 7. 青玉侠客衫 (Jade-White Traditional Hanfu Adventurer Robe) ---
  const hanfuJade = k("cst-hf-jade", "#0c2624", "#1c5e58", "#329c90", "#70d4c2", "#c4f6ea");
  const hanfuWhite = k("cst-hf-white", "#323a46", "#7a8696", "#bec6d0", "#eaedf0", "#ffffff");
  Me({
    id: "top_costume_hanfu",
    name: "青玉侠客衫",
    slot: "top",
    palettes: { main: hanfuWhite, trim: hanfuJade, gold: GOLD_TRIM },
    variants: [
      { id: "jade",  name: "青玉白", palettes: { main: hanfuWhite, trim: hanfuJade } },
      { id: "ink",   name: "水墨玄", palettes: { main: k("cst-hf-ink", "#0a0c14", "#1e2436", "#38425c", "#647292", "#a2b0ce"), trim: GOLD_TRIM } },
      { id: "cloud", name: "云霞绯", palettes: { main: hanfuWhite, trim: CRIMSON_ACC } }
    ],
    parts: [
      makeBackCape({ mainKey: "trim", trimKey: "gold", lenOffset: 10, extraWidth: 1.8, splitTail: true }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          drawExtendedSkirt(ctx, 0, 19.0, 3.2, (s, nx, p) => {
            if (p < 2.0) { ctx.pal("trim"); return 1; }
            // Split front lower panels showing movement
            if (p > 13.8 && pose.cos > 0.2 && Math.abs(nx - pose.sin * 0.5) < (p - 13.8) * 0.045) return -1;
            // Jade belt sash
            if (p >= 8.2 && p <= 10.6) {
              ctx.pal("trim");
              return g.t(s, p > 9.9 ? -0.25 : 0.15);
            }
            // Crossed right-over-left Hanfu collar (交领右衽)
            if (pose.cos > 0.25 && p < 8.2) {
              const fx = nx - pose.sin * 0.55;
              const lapel = Math.abs(fx - (-0.42 + (p - 2.0) * 0.14));
              if (lapel < 0.16) { ctx.pal("trim"); return g.t(s, 0.2); }
            }
            // Flowing vertical jade border trim
            if (p > 17.2) { ctx.pal("trim"); return g.t(s, 0.15); }
            ctx.pal("main");
            return g.t(s, 0.08);
          });
          // Hanging jade & gold waist pendant tassel
          if (pose.cos > 0.25) {
            const cx = gt(ctx);
            ctx.pal("gold");
            g.ellipse(cx + 1.6, ny + 9.4, 1.1, 1.1, s => s > 0 ? 4 : 3);
            ctx.pal("trim");
            g.line(cx + 1.6, ny + 10.6, cx + 1.8, ny + 15.2, 3);
            g.dot(cx + 1.8, ny + 15.5, 4);
          }
        }
      },
      ...Mt({ key: "main", cuffKey: "trim", r: 2.3, length: 0.78 })
    ]
  }, "expansion/top/costume_hanfu");

  // --- 8. 宫廷小礼服 (Aristocratic Wine & Ivory Tailcoat) ---
  const nobleWine = k("cst-nob-wine", "#26060e", "#5e1222", "#9a2238", "#ce5062", "#f894a0");
  Me({
    id: "top_costume_noble",
    name: "宫廷小礼服",
    slot: "top",
    palettes: { main: nobleWine, lace: IVORY_WHITE, gold: GOLD_TRIM },
    variants: [
      { id: "wine",  name: "酒红宫廷", palettes: { main: nobleWine } },
      { id: "royal", name: "皇家蓝",   palettes: { main: academyNavy } }
    ],
    layerOverride: d => (d === "N" || d === "NE" ? { cape: Le.mantle - 1 } : {}),
    parts: [
      // Split swallowtail coat-tails at the back!
      makeBackCape({ mainKey: "main", trimKey: "gold", lenOffset: 9, extraWidth: 1.6, splitTail: true }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          ctx.pal("main");
          J(ctx, 13.4, { flare: 1.6 }, (s, nx, p) => {
            if (p < 2.2) return 0;
            if (p > 11.8) { ctx.pal("gold"); return g.t(s, 0.2); }
            ctx.pal("main");
            return g.t(s, 0.05);
          });
          g.clip = true;
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            // Ruffled ivory jabot cravat
            ctx.pal("lace");
            g.ellipse(cx, ny + 4.4, 2.0, 2.6, s => g.t(s, 0.25));
            // Gold double-breasted frogging stripes
            ctx.pal("gold");
            for (const row of [5.8, 7.8, 9.8]) {
              g.line(cx - 3.2, ny + row, cx - 1.2, ny + row, 4);
              g.line(cx + 1.2, ny + row, cx + 3.2, ny + row, 3);
            }
          }
          g.clip = false;
        }
      },
      ...Mt({ key: "main", cuffKey: "lace", r: 2.0 }),
      ...ae({ key: "main", trimKey: "gold", r: 2.4 })
    ]
  }, "expansion/top/costume_noble");

  // --- 9. 向日葵田园裙 (Sunflower Countryside Sundress + White Apron) ---
  const sunGold = k("cst-sun-gold", "#3e2206", "#905a12", "#e0a224", "#fad458", "#fff6b0");
  Me({
    id: "top_costume_sundress",
    name: "向日葵田园裙",
    slot: "top",
    palettes: { main: sunGold, apron: IVORY_WHITE, ribbon: CRIMSON_ACC },
    variants: [
      { id: "sunflower", name: "向日葵黄", palettes: { main: sunGold } },
      { id: "peach",     name: "蜜桃粉",   palettes: { main: kimonoSakura } },
      { id: "sky",       name: "晴空蓝",   palettes: { main: k("cst-sun-sky", "#102846", "#28649e", "#52a8e2", "#96dafc", "#e2f8ff") } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          drawExtendedSkirt(ctx, 0, 19.4, 5.2, (s, nx, p, t) => {
            if (p < 2.2) { ctx.pal("apron"); return 3; }
            // Crisp white scalloped lace hem along the bottom
            const distBot = 19.4 - p;
            if (distBot < 1.9 + 0.45 * Math.sin(nx * 16)) {
              ctx.pal("apron");
              return g.t(s, 0.25);
            }
            // White waist sash
            if (p >= 7.8 && p <= 9.6) {
              ctx.pal("apron");
              return g.t(s, 0.2);
            }
            // Front pinafore apron panel
            if (pose.cos > 0.25 && p > 9.4 && p < 16.6 && Math.abs(nx - pose.sin * 0.48) < 0.46) {
              ctx.pal("apron");
              return g.t(s, 0.18);
            }
            ctx.pal("main");
            const gather = p > 9.4 ? Math.sin(nx * 13) * 0.28 : 0;
            return g.t(s + gather, 0.08);
          });
          // Sweet bow on back waist, or tiny red ribbon bow at front collar!
          if (pose.cos < -0.25) {
            drawBow(ctx, pose.torsoX(9) - pose.sin * 1.2, ny + 9.2, 1.05, "apron");
          } else if (pose.cos > 0.3) {
            drawBow(ctx, gt(ctx), ny + 3.4, 0.72, "ribbon");
          }
        }
      },
      ...makePuffSleeves("main", "apron", 0.42, 2.35)
    ]
  }, "expansion/top/costume_sundress");

  // --- 10. 航海船长装 (Sea Captain's Long Greatcoat with Gold Epaulettes) ---
  const capCrimson = k("cst-cap-red", "#28060a", "#66121a", "#aa242c", "#dc524c", "#fa9686");
  Me({
    id: "top_costume_captain",
    name: "航海船长装",
    slot: "top",
    palettes: { main: capCrimson, vest: IVORY_WHITE, belt: LEATHER_BELT, gold: GOLD_TRIM },
    variants: [
      { id: "crimson", name: "赤红船长", palettes: { main: capCrimson } },
      { id: "navy",    name: "深海船长", palettes: { main: academyNavy } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          drawExtendedSkirt(ctx, 0, 18.6, 3.8, (s, nx, p) => {
            if (p < 2.2) { ctx.pal("main"); return 0; }
            // Open coat front revealing cream waistcoat + gold trim lapels
            if (pose.cos > 0.25) {
              const fx = nx - pose.sin * 0.55;
              if (p > 12.6 && Math.abs(fx) < 0.24) return -1; // open lower greatcoat slit
              if (p <= 12.6 && Math.abs(fx) < 0.28) {
                ctx.pal("vest");
                return g.t(s, 0.15);
              }
              if (Math.abs(Math.abs(fx) - 0.32) < 0.10) {
                ctx.pal("gold");
                return g.t(s, 0.25);
              }
            }
            if (p > 17.0) { ctx.pal("gold"); return g.t(s, 0.2); }
            ctx.pal("main");
            return g.t(s, 0.04);
          });
          // Bold leather captain belt with big gold buckle
          uo(ctx, 8.8, 10.8, "belt", "gold");
        }
      },
      ...Mt({ key: "main", cuffKey: "gold", r: 2.15 }),
      // Golden tasseled shoulder epaulettes!
      ...["L", "R"].map(side => ({
        layer: ue(side),
        draw: ctx => {
          const { g } = ctx;
          const arm = wt(ctx, side);
          const sh = ut(ctx, arm.hand);
          const sx = arm.shoulder.x, sy = arm.shoulder.y;
          ctx.pal("gold");
          g.ellipse(sx, sy - 0.2, 3.0, 1.4, s => ct(ctx, s, sh + 0.15));
          // Hanging gold fringe tassels
          for (const dx of [-1.6, -0.5, 0.6, 1.6]) {
            g.line(sx + dx, sy + 0.9, sx + dx, sy + 2.3, dx < 0 ? 4 : 3);
          }
        }
      }))
    ]
  }, "expansion/top/costume_captain");

  // --- 11. 吟游诗人装 (Emerald Minstrel Vest + Jaunty Half-Shoulder Capelet) ---
  const bardEmerald = k("cst-bard-grn", "#0a2214", "#1a5630", "#2e8c4c", "#60c274", "#b0eeaa");
  const bardPlum = k("cst-bard-plum", "#220a24", "#541c56", "#8c348c", "#c064bc", "#f0a8ec");
  Me({
    id: "top_costume_bard",
    name: "吟游诗人装",
    slot: "top",
    palettes: { main: bardEmerald, shirt: shirtCream, cape: bardEmerald, belt: LEATHER_BELT, gold: GOLD_TRIM },
    variants: [
      { id: "emerald", name: "翡翠诗谣", palettes: { main: bardEmerald, cape: bardEmerald } },
      { id: "plum",    name: "紫罗兰诗谣", palettes: { main: bardPlum, cape: bardPlum } }
    ],
    layerOverride: d => (d === "N" || d === "NE" ? { cape: Le.mantle - 1 } : {}),
    parts: [
      makeBackCape({ mainKey: "cape", trimKey: "gold", lenOffset: 14, extraWidth: 2.4, asymmetric: true }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          J(ctx, 13.6, { flare: 2.0 }, (s, nx, p) => {
            if (p < 2.2) { ctx.pal("shirt"); return 2; }
            if (p > 12.2) { ctx.pal("gold"); return g.t(s, 0.2); }
            // Diamond-quilted minstrel vest texture
            ctx.pal("main");
            const diag = ((Math.floor(nx * 5 + p * 0.45 + 10) + Math.floor(nx * 5 - p * 0.45 + 20)) % 2 === 0);
            return g.t(s, diag ? 0.14 : -0.14);
          });
          // Front laced shirt collar opening
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            g.clip = true;
            ctx.pal("shirt");
            g.tri({ x: cx - 2.4, y: ny + 1.8 }, { x: cx + 2.4, y: ny + 1.8 }, { x: cx, y: ny + 6.0 }, 4);
            ctx.pal("gold");
            g.line(cx - 1.2, ny + 3.8, cx + 1.2, ny + 3.8, 3);
            g.line(cx - 0.8, ny + 5.0, cx + 0.8, ny + 5.0, 3);
            g.clip = false;
          }
          uo(ctx, 9.0, 10.8, "belt", "gold");
        }
      },
      // Puffed white minstrel shirt sleeves with emerald cuffs
      ...Mt({ key: "shirt", cuffKey: "main", r: 2.25 }),
      // Asymmetric half-shoulder minstrel mantle with gold clasp
      {
        layer: "mantle",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          const cx = pose.torsoX(1) - pose.cos * 2.2;
          const rx = pose.torsoHalf * 0.8 + 1.6;
          ctx.pal("cape");
          g.ellipse(cx, ny + 1.8, rx, 2.8, (s, lx, ly) => {
            if (ly > 0.65) { ctx.pal("gold"); return g.t(s, 0.25); }
            ctx.pal("cape");
            return g.t(s, 0.05);
          });
          if (pose.cos > 0.2) {
            ctx.pal("gold");
            g.ellipse(gt(ctx) - 1.4, ny + 1.6, 1.2, 1.2, s => s > 0.2 ? 4 : 3);
          }
        }
      }
    ]
  }, "expansion/top/costume_bard");

  // --- 12. 冬日毛绒大衣 (Cozy Fur-Trimmed Winter Parka Coat) ---
  const winterSky = k("cst-win-sky", "#102846", "#265c92", "#4c96d2", "#88c8f4", "#d8f2ff");
  const winterBerry = k("cst-win-berry", "#2e0a18", "#701a38", "#b4325c", "#e4688c", "#ffb2c6");
  Me({
    id: "top_costume_winter_coat",
    name: "冬日毛绒大衣",
    slot: "top",
    palettes: { main: winterSky, fur: IVORY_WHITE, toggle: LEATHER_BELT },
    variants: [
      { id: "glacier", name: "冰雪蓝", palettes: { main: winterSky } },
      { id: "berry",   name: "莓果红", palettes: { main: winterBerry } },
      { id: "cocoa",   name: "热可可", palettes: { main: k("cst-win-cocoa", "#24140c", "#583420", "#8e5c3a", "#c28e62", "#ecc89e") } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          drawExtendedSkirt(ctx, 0, 16.8, 2.8, (s, nx, p) => {
            if (p < 2.2) { ctx.pal("fur"); return 3; }
            // Fluffy thick snow-white fur lower hem band
            const distBot = 16.8 - p;
            if (distBot < 2.5 + 0.35 * Math.sin(nx * 14)) {
              ctx.pal("fur");
              return g.t(s, 0.22);
            }
            ctx.pal("main");
            return g.t(s, 0.04);
          });
          // Wooden duffle toggles down center front
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            g.clip = true;
            g.line(cx, ny + 3.4, cx, ny + 14.0, V);
            ctx.pal("toggle");
            for (const row of [5.4, 8.2, 11.0]) {
              g.line(cx - 1.8, ny + row, cx + 1.8, ny + row, 3);
              g.dot(cx - 1.8, ny + row, 2);
              g.dot(cx + 1.8, ny + row, 4);
            }
            g.clip = false;
          }
        }
      },
      ...Mt({ key: "main", cuffKey: "fur", r: 2.3 }),
      // Fluffy scalloped snow-white fur collar encircling neck!
      {
        layer: "mantle",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          const cx = pose.torsoX(0) + pose.sin * 0.4;
          const rx = pose.torsoHalf + 2.0;
          ctx.pal("fur");
          g.fill(cx - rx, ny - 1.8, cx + rx, ny + 3.4, (x, y) => {
            const nx = (x - cx) / rx;
            if (Math.abs(nx) > 1) return -1;
            const puff = 0.55 * Math.sin(nx * 14);
            const ry = 2.4 + puff * 0.45;
            const ny2 = (y - (ny + 0.8)) / ry;
            if (nx * nx + ny2 * ny2 > 1) return -1;
            return g.t(nx * z + ny2 * mt + 0.45, 0.2);
          });
        }
      }
    ]
  }, "expansion/top/costume_winter_coat");

  // --- 13. 探险家工装 (Field Explorer Safari Jacket + Neckerchief) ---
  const expKhaki = k("cst-exp-khaki", "#281e10", "#644e2e", "#a28252", "#d2b47c", "#f6e4b4");
  const expMoss = k("cst-exp-moss", "#0e2212", "#24542a", "#428844", "#76bc6a", "#b8ea9e");
  Me({
    id: "top_costume_explorer",
    name: "探险家工装",
    slot: "top",
    palettes: { main: expKhaki, scarf: expMoss, belt: LEATHER_BELT, gold: GOLD_TRIM },
    variants: [
      { id: "khaki", name: "沙地卡其", palettes: { main: expKhaki, scarf: expMoss } },
      { id: "olive", name: "丛林橄榄", palettes: { main: expMoss, scarf: CRIMSON_ACC } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          ctx.pal("main");
          J(ctx, 13.6, { flare: 1.8 }, (s, nx, p) => p < 2.2 ? 0 : g.t(s, p > 9.4 ? -0.05 : 0.06));
          g.clip = true;
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            g.line(cx, ny + 3.0, cx, ny + 13.0, V);
            // Twin field chest pockets with brass snaps
            for (const dx of [-3.0, 3.0]) {
              g.rect(cx + dx - 1.3, ny + 4.8, 2.6, 2.8, (x, y) => y < ny + 5.6 ? 1 : 3);
              ctx.pal("gold");
              g.dot(cx + dx, ny + 5.7, 4);
              ctx.pal("main");
            }
          }
          g.clip = false;
          uo(ctx, 8.8, 10.6, "belt", "gold");
        }
      },
      ...Mt({ key: "main", cuffKey: "belt", r: 2.05, length: 0.65 }),
      // Triangular explorer neckerchief knotted at throat
      {
        layer: "scarf",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          const cx = pose.torsoX(0) + pose.sin * 0.5;
          const rx = pose.torsoHalf + 1.0;
          ctx.pal("scarf");
          g.ellipse(cx, ny + 1.6, rx, 1.8, s => g.t(s, 0.05));
          if (pose.cos > 0.25) {
            const fx = gt(ctx);
            g.tri({ x: fx - 2.6, y: ny + 2.2 }, { x: fx + 2.6, y: ny + 2.2 }, { x: fx, y: ny + 6.4 }, 3);
            g.dot(fx, ny + 2.8, 4);
          } else if (pose.cos < -0.25) {
            g.tri({ x: cx - 3.0, y: ny + 2.0 }, { x: cx + 3.0, y: ny + 2.0 }, { x: cx, y: ny + 5.8 }, 2);
          }
        }
      }
    ]
  }, "expansion/top/costume_explorer");

  // --- 14. 暗夜怪盗装 (Phantom Thief Black Coat + Scarlet-Lined Cloak) ---
  const phBlack = k("cst-ph-black", "#06060c", "#161622", "#282a3a", "#464a62", "#7880a0");
  const phSilver = k("cst-ph-silver", "#1e2432", "#5c667c", "#a4b0c4", "#dce4f0", "#ffffff");
  Me({
    id: "top_costume_phantom",
    name: "暗夜怪盗装",
    slot: "top",
    palettes: { main: phBlack, lining: CRIMSON_ACC, shirt: IVORY_WHITE, silver: phSilver },
    variants: [
      { id: "scarlet", name: "猩红怪盗", palettes: { lining: CRIMSON_ACC } },
      { id: "cobalt",  name: "湛蓝怪盗", palettes: { lining: sailorBlue } }
    ],
    layerOverride: d => (d === "N" || d === "NE" ? { cape: Le.mantle - 1 } : {}),
    parts: [
      makeBackCape({ mainKey: "main", trimKey: "lining", liningKey: "lining", lenOffset: 6, extraWidth: 4.0 }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          ctx.pal("main");
          J(ctx, 13.8, { flare: 1.8 }, (s, nx, p) => p < 2.2 ? 0 : g.t(s, 0.04));
          g.clip = true;
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            // Crisp white cravat + scarlet lapel trim + diagonal silver watch chain
            ctx.pal("shirt");
            g.tri({ x: cx - 2.4, y: ny + 2.0 }, { x: cx + 2.4, y: ny + 2.0 }, { x: cx, y: ny + 6.4 }, 4);
            ctx.pal("lining");
            g.line(cx - 2.6, ny + 2.2, cx - 0.8, ny + 6.8, 3);
            g.line(cx + 2.6, ny + 2.2, cx + 0.8, ny + 6.8, 3);
            ctx.pal("silver");
            g.line(cx - 2.6, ny + 9.2, cx + 2.2, ny + 10.6, 4);
            g.dot(cx + 2.2, ny + 10.8, 4);
          }
          g.clip = false;
        }
      },
      // Sleek black sleeves with crisp white phantom-glove cuffs
      ...Mt({ key: "main", cuffKey: "shirt", r: 1.95 }),
      // Dramatic upturned phantom collar lined in scarlet
      {
        layer: "mantle",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          const cx = pose.torsoX(0) - pose.sin * 0.6;
          const hw = pose.torsoHalf + 1.8;
          g.fill(cx - hw, ny - 2.4, cx + hw, ny + 3.2, (x, y) => {
            const nx = (x - cx) / hw;
            if (Math.abs(nx) > 1) return -1;
            const top = ny - 2.2 + 2.0 * (1 - nx * nx);
            const bot = ny + 2.6;
            if (y < top || y > bot) return -1;
            if (pose.cos > 0.25 && Math.abs(x - gt(ctx)) < 2.1) return -1;
            const isInner = y < top + 1.2 && pose.cos > -0.2;
            ctx.pal(isInner ? "lining" : "main");
            return g.t(nx * z + 0.4, isInner ? 0.25 : 0.05);
          });
        }
      }
    ]
  }, "expansion/top/costume_phantom");

  // --- 15. 甜点小厨师 (Pastry Chef Coat + Caramel Checkered Apron) ---
  const chefApron = k("cst-chef-apron", "#32180c", "#744020", "#b8703c", "#e4a468", "#ffe0b0");
  const chefBtn = k("cst-chef-btn", "#10121a", "#2e3240", "#545a6e", "#848ca2", "#bec6d8");
  Me({
    id: "top_costume_chef",
    name: "甜点小厨师",
    slot: "top",
    palettes: { main: IVORY_WHITE, apron: chefApron, tie: CRIMSON_ACC, btn: chefBtn },
    variants: [
      { id: "caramel", name: "焦糖围裙", palettes: { apron: chefApron, tie: CRIMSON_ACC } },
      { id: "berry",   name: "草莓围裙", palettes: { apron: kimonoSakura, tie: winterBerry } },
      { id: "matcha",  name: "抹茶围裙", palettes: { apron: expMoss, tie: GOLD_TRIM } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          drawExtendedSkirt(ctx, 0, 17.4, 2.2, (s, nx, p) => {
            if (p < 2.0) { ctx.pal("main"); return 2; }
            // Checkered caramel waist apron wrapping around hips
            if (p >= 8.6) {
              ctx.pal("apron");
              const check = ((Math.floor(nx * 6 + 10) + Math.floor(p * 0.8)) % 2 === 0);
              return g.t(s, check ? 0.2 : -0.15);
            }
            ctx.pal("main");
            return g.t(s, 0.12);
          });
          // Double-breasted chef buttons on front; apron bow tie on back!
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            g.clip = true;
            ctx.pal("btn");
            for (const row of [4.6, 6.6]) {
              g.dot(cx - 1.8, ny + row, 1);
              g.dot(cx + 1.8, ny + row, 1);
            }
            g.clip = false;
            // Cheerful red chef neckerchief knot at throat
            drawBow(ctx, cx, ny + 2.4, 0.78, "tie");
          } else if (pose.cos < -0.25) {
            drawBow(ctx, pose.torsoX(9) - pose.sin * 1.2, ny + 9.4, 0.9, "apron");
          }
        }
      },
      ...Mt({ key: "main", cuffKey: "apron", r: 2.0, length: 0.62 })
    ]
  }, "expansion/top/costume_chef");

  // --- 16. 星梦偶像装 (Starlight Stage Idol Jacket + Ruffled Pleated Dress) ---
  const idolViolet = k("cst-idol-vio", "#200e3c", "#52288e", "#8852d4", "#bc8cf8", "#ecdcff");
  const idolPink = k("cst-idol-pink", "#3e0c2c", "#8e2462", "#d8509a", "#f894c8", "#ffe0f0");
  Me({
    id: "top_costume_idol",
    name: "星梦偶像装",
    slot: "top",
    palettes: { main: idolViolet, accent: idolPink, shirt: IVORY_WHITE, gold: GOLD_TRIM },
    variants: [
      { id: "lavender", name: "星梦紫", palettes: { main: idolViolet, accent: idolPink } },
      { id: "sakura",   name: "甜心粉", palettes: { main: idolPink, accent: winterSky } },
      { id: "aqua",     name: "梦幻蓝", palettes: { main: winterSky, accent: idolViolet } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          drawExtendedSkirt(ctx, 0, 18.6, 5.4, (s, nx, p) => {
            if (p < 2.2) { ctx.pal("shirt"); return 3; }
            // Layered ruffled stage skirt below waist
            if (p > 9.4) {
              const distBot = 18.6 - p;
              const pleat = Math.sin(nx * 15) * 0.32;
              if (distBot < 1.6) { ctx.pal("shirt"); return g.t(s, 0.28); }
              if (distBot < 2.8) { ctx.pal("gold"); return g.t(s, 0.25); }
              if (p < 14.2) { ctx.pal("main"); return g.t(s + pleat, 0.08); }
              ctx.pal("accent");
              return g.t(s + pleat, 0.1);
            }
            // Gold stage waist belt
            if (p > 8.0) { ctx.pal("gold"); return g.t(s, 0.25); }
            // Cropped idol jacket over crisp white pleated blouse
            if (pose.cos > 0.25 && Math.abs(nx - pose.sin * 0.55) < 0.34) {
              ctx.pal("shirt");
              return g.t(s, 0.22);
            }
            ctx.pal("main");
            return g.t(s, 0.08);
          });
          // Radiant golden star brooch on chest + stage waist ribbon bow on back!
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            ctx.pal("gold");
            g.dot(cx, ny + 4.8, 4);
            g.dot(cx - 1.0, ny + 4.8, 3);
            g.dot(cx + 1.0, ny + 4.8, 3);
            g.dot(cx, ny + 3.8, 3);
            g.dot(cx, ny + 5.8, 3);
          } else if (pose.cos < -0.25) {
            drawBow(ctx, pose.torsoX(9) - pose.sin * 1.2, ny + 9.2, 1.15, "accent");
          }
        }
      },
      ...makePuffSleeves("main", "gold", 0.5, 2.3)
    ]
  }, "expansion/top/costume_idol");
}
