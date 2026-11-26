// Procedural Equipment Expansion for pixel-baker.js (v1.0 — Staged Expansion Pack)
// Adds:
//   - 17 new wearable weapons (slot: "weapon_main", strictly reusing existing hold
//     skeletons: down / shoulder / bow / up, with 4-phase bakeFx glow on all 9 Epic & Legendary weapons)
//   - 14 new wearable armors (slot: "top", id: top_<snake_case>, compatible with all
//     20 hairstyles & 18 eye colors, with 4-phase bakeFx glow on all 7 Epic & Legendary armors)
//
// Designed for injection alongside pixel_character_expansion.js by install_expansion_pack.py
// (requires extended bridge symbols: St, Z, lt, O, ye, jt, At, ko, Ut, xe, te, be, Qe, rt).
function registerEquipmentExpansion(C) {
  const {
    k, v, Me,
    J, gt, Mt, Pe, ae, uo, ue, ut, wt,
    z, Q, V, _t, Et, pt, ct,
    St, Z, lt, O, ye, jt, At, ko, Ut, xe, te, be, Qe, rt
  } = C;

  // =========================================================================
  // SHARED PALETTES (5-stop HD-2D pixel ramps matching pixel_baker_core.js)
  // =========================================================================
  const P = {
    wood:    k("eq-wood",    "#1a0e06", "#4e2e14", "#86562a", "#bc8644", "#e8b874"),
    woodL:   k("eq-woodL",   "#26180c", "#6c4824", "#a87842", "#d8aa6a", "#f8dcb0"),
    iron:    k("eq-iron",    "#141820", "#465060", "#7c889c", "#b8c4d6", "#eef4fc"),
    silver:  k("eq-silver",  "#1c2234", "#5a6680", "#9eaac0", "#dae4f4", "#ffffff"),
    gold:    k("eq-gold",    "#3c2206", "#8c5c14", "#d69e2c", "#f8d464", "#fff6be"),
    bronze:  k("eq-bronze",  "#2a1608", "#683c18", "#a46830", "#d89c54", "#f8d494"),
    leather: k("eq-leather", "#180c06", "#462814", "#784826", "#ae723e", "#dda468"),
    cream:   k("eq-cream",   "#3c3426", "#82745c", "#bcaf92", "#e6dcc2", "#faf4e4"),
    olive:   k("eq-olive",   "#12200c", "#2e4e1e", "#4e7c34", "#7eb056", "#bce088"),
    leaf:    k("eq-leaf",    "#0c2810", "#1e6028", "#3c9e42", "#78d864", "#c4fc98"),
    emerald: k("eq-emerald", "#062a18", "#106c42", "#26b672", "#6ef0a6", "#d8ffe8"),
    ice:     k("eq-ice",     "#0c2a54", "#226cb8", "#4eb2f2", "#a2e4ff", "#f2ffff"),
    teal:    k("eq-teal",    "#0a2a34", "#1a6274", "#32a4b4", "#70dce0", "#ccfcfc"),
    blue:    k("eq-blue",    "#0a183c", "#1c3c86", "#3468cc", "#6aa6f2", "#c4e4ff"),
    indigo:  k("eq-indigo",  "#0c0e2c", "#202664", "#3c469e", "#6e7cd4", "#b8c6fa"),
    purple:  k("eq-purple",  "#1c0c38", "#462280", "#7a44c4", "#b67ef2", "#ebd4ff"),
    obsid:   k("eq-obsid",   "#0c0b14", "#242234", "#44405c", "#747094", "#b4b0cc"),
    crimson: k("eq-crimson", "#2e060c", "#741420", "#be2836", "#f05e5c", "#ffb4a8"),
    fire:    k("eq-fire",    "#6a1408", "#c84214", "#f68e28", "#ffd45c", "#fff8cc"),
    white:   k("eq-white",   "#384056", "#848ea8", "#c6cee0", "#ecf0f8", "#ffffff"),
    string:  k("eq-string",  "#38362a", "#8a846c", "#c8c2a8", "#ece8d4", "#ffffff"),
    fxIce:   k("eq-fx-ice",  "#1854a8", "#42a4f0", "#8ce0ff", "#d4f8ff", "#ffffff"),
    fxWind:  k("eq-fx-wind", "#146674", "#34b8c4", "#7ef0f0", "#ccfefe", "#ffffff"),
    fxLeaf:  k("eq-fx-leaf", "#10582c", "#28a856", "#66e888", "#beffc8", "#f0fff2"),
    fxPurp:  k("eq-fx-purp", "#3c1878", "#7c3ed0", "#ba7eff", "#e4c4ff", "#fff4ff"),
    fxFire:  k("eq-fx-fire", "#7a1c0c", "#d04a18", "#f6902c", "#ffd060", "#fff6c8"),
    fxGold:  k("eq-fx-gold", "#7c4808", "#cc8818", "#f8c83c", "#ffea88", "#ffffdc"),
    fxHoly:  k("eq-fx-holy", "#4c5c94", "#98b8ec", "#d8ecff", "#f6fbff", "#ffffff")
  };

  // =========================================================================
  // SHARED WEAPON / ARMOR DRAWING HELPERS
  // =========================================================================

  // Reusable bow renderer with configurable limb/wrap/string/arrow palettes & curve scale
  function makeBowDraw(opts) {
    const { halfLen = 13, recurve = 0, wingTips = false, boltGlow = false } = opts;
    return function drawBow(ctx, solidPass) {
      const h = lt(ctx);
      if (!h) return;
      const { g, pose } = ctx;
      const r = pose.sin, i = pose.cos * 0.35;
      const sx = -h.dy, sy = h.dx;
      const dot = sx * r + sy * i;
      const sign = dot >= 0 ? 1 : -1;
      const bend = 2.5 * Math.max(0.35, Math.min(1, Math.abs(dot) * 1.4));
      const ptAt = t => {
        const u = t / halfLen;
        const off = -sign * bend * (u * u - recurve * Math.pow(Math.abs(u), 3) * 0.45);
        return { x: h.x + h.dx * t * h.k + sx * off, y: h.y + h.dy * t * h.k + sy * off };
      };
      const pts = Array.from({ length: 13 }, (_, idx) => ptAt(-halfLen + idx * 2 * halfLen / 12));
      if (solidPass) {
        ctx.pal("wood");
        g.ribbon(pts, t => 1.0 - 0.42 * Math.abs(t - 0.5) * 2, (t, n) => n < -0.3 ? 3 : n > 0.4 ? 1 : g.t(t) > 3 ? 4 : 2);
        ctx.pal("wrap");
        g.ribbon([ptAt(-1.8), ptAt(0), ptAt(1.8)], () => 1.1, (t, n) => n < 0 ? 3 : 1);
        if (wingTips) {
          ctx.pal("trim");
          for (const endT of [-halfLen, halfLen]) {
            const p = ptAt(endT);
            g.dot(p.x + sx * sign * 1.4, p.y + sy * sign * 1.4, 4);
            g.dot(p.x + sx * sign * 2.2, p.y + sy * sign * 2.2, 3);
          }
        }
        return;
      }
      const pTop = ptAt(halfLen), pBot = ptAt(-halfLen);
      const drawing = pose.fx === "arrow" && pose.anim === "shoot";
      const hr = pose.handR;
      ctx.pal("string");
      if (drawing) {
        g.line(pTop.x, pTop.y, hr.x, hr.y + 0.4, 3);
        g.line(pBot.x, pBot.y, hr.x, hr.y + 0.4, 2);
        const ax = pose.sin, ay = pose.cos * 0.35 + 0.02;
        const len = Math.hypot(ax, ay) || 1;
        const ux = ax / len, uy = ay / len;
        const reach = 15 * (0.4 + 0.6 * Math.min(1, len));
        const tx = hr.x + ux * reach, ty = hr.y + 0.4 + uy * reach;
        ctx.pal("arrow");
        g.line(hr.x, hr.y + 0.4, tx, ty, boltGlow ? 4 : 3);
        g.dot(tx, ty, 4);
        ctx.pal("fletch");
        g.dot(hr.x + ux * 1.2, hr.y + 0.4 + uy * 1.2 - 0.6, 3);
        g.dot(hr.x + ux * 1.2, hr.y + 0.4 + uy * 1.2 + 0.6, 2);
      } else {
        g.line(pTop.x, pTop.y, pBot.x, pBot.y, 2);
      }
    };
  }

  // Reusable flowing armor back cape (matches pixel_character_expansion.js)
  function makeArmorCape(opts) {
    const {
      mainKey = "cloth", trimKey = "trim", liningKey = null,
      lenOffset = 7.5, extraWidth = 3.2, asymmetric = false, starry = false
    } = opts;
    return {
      layer: "cape",
      draw: ctx => {
        const { g, pose } = ctx;
        const { sin, cos } = pose;
        const showingBack = cos < 0.3;
        const walking = pose.anim === "walk";
        const sway = walking ? Math.sin(pose.phase + 1) : 0;
        const topW = (asymmetric ? 4.8 : 6.0) * Math.abs(cos) + 2.8 * Math.abs(sin) + 1.0;
        const botW = topW + extraWidth;
        const cxBase = pose.torsoX(3) - sin * 3.4 + (asymmetric ? -cos * 2.2 : 0);
        const y0 = pose.neckY - 0.2;
        const y1 = Et - lenOffset;
        const folds = 2.0 + Math.abs(cos) * 1.1;
        g.grit = 0.18;
        g.fill(cxBase - botW - 5, y0, cxBase + botW + 5, y1 + 2, (x, y) => {
          const p = Math.min(1, (y - y0) / (y1 - y0));
          if (p < 0) return -1;
          const cx = cxBase + sway * p * 1.5 - sin * p * 2.1;
          const hw = topW + (botW - topW) * p;
          const nx = (x - cx) / hw;
          if (Math.abs(nx) > 1) return -1;
          const wave = nx * folds * Math.PI + p * sway * 0.7;
          const hem = y1 + 0.7 * Math.sin(wave + 0.5);
          if (y > hem) return -1;
          const ridge = Math.sin(wave + 0.8) * Math.min(1, p * 1.6);
          if (!showingBack) {
            if (liningKey) { ctx.pal(liningKey); return g.t(0.1 + ridge * 0.4, -0.2); }
            ctx.pal(mainKey); return ridge > 0.3 ? 1 : 0;
          }
          let shade = 0.18 + nx * z * 0.85 + ridge * 0.65;
          if (p < 0.12) shade -= 0.5;
          const fromHem = hem - y;
          if (trimKey && fromHem > 0.9 && fromHem < 2.3) {
            ctx.pal(trimKey); return g.t(shade, 0.25);
          }
          if (starry && ((Math.floor(x * 1.3) * 17 + Math.floor(y * 1.3) * 31) % 29 === 0) && p > 0.22) {
            ctx.pal(trimKey); return 4;
          }
          ctx.pal(mainKey);
          return g.t(shade);
        });
      }
    };
  }

  // Reusable armor 4-phase shoulder/chest subtle glow (bakeFx)
  function makeArmorGlow(palKey, style = "shoulders") {
    return xe(ctx => {
      const { pose, g } = ctx;
      ctx.pal(palKey);
      g.grit = 0;
      if (style === "shoulders" || style === "holy") {
        for (const side of ["L", "R"]) {
          const arm = wt(ctx, side);
          const active = (ctx.phase % 2 === 0) === (side === "L");
          if (!arm.hand.front && Math.abs(pose.cos) < 0.3) continue;
          g.dot(arm.shoulder.x, arm.shoulder.y - 0.5, active ? 4 : 3);
          if (active) {
            const lift = 1.8 + (ctx.phase >> 1) * 1.3;
            te(ctx, arm.shoulder.x + (side === "L" ? -0.8 : 0.8) * pose.cos, arm.shoulder.y - lift, 1);
          }
        }
      }
      if (style === "flame") {
        for (const side of ["L", "R"]) {
          const arm = wt(ctx, side);
          if (!arm.hand.front && Math.abs(pose.cos) < 0.3) continue;
          const phaseOff = side === "L" ? ctx.phase : (ctx.phase + 2) % 4;
          be(ctx, arm.shoulder.x, arm.shoulder.y - 1.2 - phaseOff * 0.4, 2.0 + (phaseOff % 2) * 0.7);
        }
      }
      if (style === "stars" || style === "holy") {
        if (pose.cos > 0.2) {
          const cx = gt(ctx), cy = pose.neckY + 5.5;
          const ang = ctx.phase * Math.PI * 0.5;
          g.dot(cx + Math.cos(ang) * 4.2, cy + Math.sin(ang) * 2.2, 4);
          g.dot(cx - Math.cos(ang) * 3.8, cy - Math.sin(ang) * 2.0, 3);
        }
      }
    }, "arm_front");
  }

  // =========================================================================
  // PART A: 17 NEW WEARABLE WEAPONS (strictly hold: down / shoulder / bow / up)
  // =========================================================================

  // 1. 橡木弹弓 (oakSlingshot, Common, hold: bow)
  Me({
    id: "weapon_oak_slingshot", name: "橡木弹弓", slot: "weapon_main", hold: "bow", gameItem: "oakSlingshot",
    palettes: { wood: P.wood, wrap: P.leaf, band: P.leather, stone: P.iron },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g, pose } = ctx;
        ctx.pal("wood");
        Z(ctx, h, -3.5, 4.5, 1.1, (s, n) => n < 0 ? 3 : 1);
        ctx.pal("wrap");
        Z(ctx, h, -1.8, 2.2, 1.25, (s, n) => n < 0 ? 3 : 2);
        // Y-fork branches
        const base = O(h, 4.2, 0), forkL = O(h, 11.2, -4.2), forkR = O(h, 11.2, 4.2);
        ctx.pal("wood");
        g.capsule(base.x, base.y, forkL.x, forkL.y, 1.0, 0.85, s => s > 0 ? 3 : 1);
        g.capsule(base.x, base.y, forkR.x, forkR.y, 1.0, 0.85, s => s > 0 ? 3 : 1);
        // Elastic leather band + pebble when aiming
        ctx.pal("band");
        const pull = pose.fx === "arrow" && pose.anim === "shoot" ? pose.handR : O(h, 9.6, 0);
        g.line(forkL.x, forkL.y, pull.x, pull.y, 2);
        g.line(forkR.x, forkR.y, pull.x, pull.y, 2);
        ctx.pal("stone");
        g.ellipse(pull.x, pull.y, 1.5, 1.5, s => s > 0.2 ? 4 : 2);
      }
    }]
  }, "expansion/weapon/oak_slingshot");

  // 2. 橡木法杖 (woodenStaff, Common, hold: up)
  Me({
    id: "weapon_wooden_staff", name: "橡木法杖", slot: "weapon_main", hold: "up", gameItem: "woodenStaff",
    palettes: { wood: P.woodL, leaf: P.leaf, gem: P.fxLeaf, fx: P.fxLeaf },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g } = ctx;
        ctx.pal("wood");
        Z(ctx, h, -10, 31, 0.82, (s, n) => n < -0.1 ? 3 : n > 0.4 ? 1 : 2);
        const top = O(h, 31, 0), f1 = O(h, 36.5, -2.8), f2 = O(h, 36.5, 2.8);
        g.capsule(top.x, top.y, f1.x, f1.y, 0.8, 0.55, s => s > 0 ? 3 : 1);
        g.capsule(top.x, top.y, f2.x, f2.y, 0.8, 0.55, s => s > 0 ? 3 : 1);
        ctx.pal("leaf");
        const lf1 = O(h, 28, -2.5), lf2 = O(h, 26.5, 2.4);
        g.ellipse(lf1.x, lf1.y, 1.9, 1.1, s => s > 0 ? 3 : 2);
        g.ellipse(lf2.x, lf2.y, 1.8, 1.0, s => s > 0 ? 3 : 1);
        ctx.pal("gem");
        const orb = O(h, 36.5, 0);
        ko(ctx, orb.x, orb.y, 2.6);
      }
    }, At(h => O(h, 36.5), "fx", 0.9)]
  }, "expansion/weapon/wooden_staff");

  // 3. 铁制双匕 (ironDagger, Common, hold: down)
  Me({
    id: "weapon_iron_dagger", name: "铁制双匕", slot: "weapon_main", hold: "down", gameItem: "ironDagger",
    palettes: { blade: P.iron, hilt: P.silver, grip: P.blue, fx: P.fxHoly },
    parts: [{
      layer: "weapon",
      draw: ctx => St(ctx, { from: 2.8, to: 15.5, half: 1.05, tip: 4.0, curve: -1.1, core: "fuller", grip: 2.6, guard: [2.9, 1.1, 0.6], pommel: 1.0 })
    }, jt(4, 17)]
  }, "expansion/weapon/iron_dagger");

  // 4. 霜晶魔杖 (frostWand, Rare, hold: up)
  Me({
    id: "weapon_frost_wand", name: "霜晶魔杖", slot: "weapon_main", hold: "up", gameItem: "frostWand",
    palettes: { shaft: P.silver, gem: P.ice, fx: P.fxIce },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g } = ctx;
        ctx.pal("shaft");
        Z(ctx, h, -9, 31, 0.75, (s, n) => n < 0 ? 3 : 1);
        const c = O(h, 36.0, 0);
        ctx.pal("gem");
        // Hexagonal snowflake crystal
        for (let i = 0; i < 6; i++) {
          const a = i * Math.PI / 3;
          g.line(c.x, c.y, c.x + Math.cos(a) * 5.2, c.y + Math.sin(a) * 5.2, i % 2 === 0 ? 4 : 3);
        }
        ko(ctx, c.x, c.y, 2.8);
      }
    }, At(h => O(h, 36.0), "fx", 1.0)]
  }, "expansion/weapon/frost_wand");

  // 5. 骑士战戟 (knightHalberd, Rare, hold: shoulder)
  Me({
    id: "weapon_knight_halberd", name: "骑士战戟", slot: "weapon_main", hold: "shoulder", gameItem: "knightHalberd",
    palettes: { shaft: P.wood, blade: P.silver, trim: P.gold, tassel: P.crimson, fx: P.fxHoly },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g } = ctx;
        ctx.pal("shaft");
        Z(ctx, h, -7, 29, 0.82, (s, n) => n < 0 ? 3 : 1);
        // Spear point
        ctx.pal("blade");
        Z(ctx, h, 28, 36.5, 1.5, (s, n) => {
          const w = 1.45 * (1 - (s - 28) / 8.5);
          return Math.abs(n) > w ? -1 : n < 0 ? 4 : 2;
        });
        // Crescent axe blade on side
        Z(ctx, h, 22, 31, 6.2, (s, n) => {
          if (n > -0.8 || n < -5.8) return -1;
          const ds = (s - 26.5) / 4.6;
          const dn = (n + 1.0) / 4.8;
          if (ds * ds + dn * dn > 1.0) return -1;
          return n < -4.2 ? 4 : ds < 0 ? 3 : 2;
        });
        // Back spike & crimson tassel
        const collar = O(h, 24, 0), spike = O(h, 26, 4.0), tas = O(h, 21.5, 2.2);
        g.line(collar.x, collar.y, spike.x, spike.y, 3);
        ctx.pal("trim");
        g.ellipse(collar.x, collar.y, 1.5, 1.5, s => s > 0 ? 4 : 2);
        ctx.pal("tassel");
        g.capsule(collar.x, collar.y, tas.x, tas.y + 3.2, 0.9, 1.2, s => s > 0 ? 3 : 1);
      }
    }, jt(10, 36), At(h => O(h, 30), "fx", 0.9)]
  }, "expansion/weapon/knight_halberd");

  // 6. 炎铁巨斧 (flameAxe, Epic, hold: shoulder, + bakeFx flame!)
  Me({
    id: "weapon_flame_axe", name: "炎铁巨斧", slot: "weapon_main", hold: "shoulder", gameItem: "flameAxe",
    palettes: { shaft: P.wood, gold: P.gold, head: P.obsid, fire: P.fire, fx: P.fxFire },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        ctx.pal("shaft");
        Z(ctx, h, -6, 28, 0.95, (s, n) => n < 0 ? 3 : 1);
        ctx.pal("gold");
        Z(ctx, h, 18, 20, 1.35, (s, n) => n < 0 ? 4 : 2);
        // Double-bit obsidian axe blades with blazing molten outer edge
        Z(ctx, h, 19.5, 31.5, 7.2, (s, n) => {
          const an = Math.abs(n);
          if (an < 0.7 || an > 6.8) return -1;
          const span = 2.1 + an * 0.52;
          if (Math.abs(s - 25.5) > span) return -1;
          if (an > 5.0) { ctx.pal("fire"); return an > 5.9 ? 4 : 3; }
          ctx.pal("head");
          return s > 25.5 ? 3 : 1;
        });
      }
    }, jt(10, 34), At(h => O(h, 26), "fx", 1.1),
      Ut((ctx, h) => {
        for (let e = 0; e < 4; e++) {
          const s = 21 + e * 2.8, side = (e % 2 === 0 ? -1 : 1) * (5.6 + ((ctx.phase + e) % 2) * 0.8);
          const p = O(h, s, side);
          be(ctx, p.x, p.y, 1.8 + ((ctx.phase + e) % 3) * 0.65);
        }
      })
    ]
  }, "expansion/weapon/flame_axe");

  // 7. 迅雷手弩 (thunderCrossbow, Epic, hold: bow, + bakeFx lightning!)
  Me({
    id: "weapon_thunder_crossbow", name: "迅雷手弩", slot: "weapon_main", hold: "bow", gameItem: "thunderCrossbow",
    palettes: { stock: P.purple, trim: P.gold, bolt: P.ice, fx: P.fxIce },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g } = ctx;
        ctx.pal("stock");
        Z(ctx, h, -4, 11, 1.3, (s, n) => n < 0 ? 3 : 1);
        // Winged prod cross-arms
        const c = O(h, 8.5, 0), wL = O(h, 5.5, -8.5), wR = O(h, 5.5, 8.5);
        ctx.pal("trim");
        g.capsule(c.x, c.y, wL.x, wL.y, 1.2, 0.8, s => s > 0 ? 4 : 2);
        g.capsule(c.x, c.y, wR.x, wR.y, 1.2, 0.8, s => s > 0 ? 4 : 2);
        // Glowing lightning string & loaded thunder crystal bolt
        ctx.pal("bolt");
        const tail = O(h, 1.5, 0), tip = O(h, 14.5, 0);
        g.line(wL.x, wL.y, tail.x, tail.y, 3);
        g.line(wR.x, wR.y, tail.x, tail.y, 3);
        g.line(tail.x, tail.y, tip.x, tip.y, 4);
        g.dot(tip.x, tip.y, 4);
      }
    }, Ut((ctx, h) => {
      const p1 = O(h, 13.5, (ctx.phase % 2 ? -1.4 : 1.4));
      const p2 = O(h, 6.0, ctx.phase < 2 ? -8.2 : 8.2);
      te(ctx, p1.x, p1.y, 1);
      ctx.g.dot(p2.x, p2.y, 4);
    })]
  }, "expansion/weapon/thunder_crossbow");

  // 8. 翡翠长杖 (emeraldScepter, Epic, hold: up, + bakeFx emerald!)
  Me({
    id: "weapon_emerald_scepter", name: "翡翠长杖", slot: "weapon_main", hold: "up", gameItem: "emeraldScepter",
    palettes: { gold: P.gold, vine: P.leaf, gem: P.emerald, fx: P.fxLeaf },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g } = ctx;
        ctx.pal("gold");
        Z(ctx, h, -10, 32, 0.85, (s, n) => n < 0 ? 3 : 1);
        ctx.pal("vine");
        Z(ctx, h, -6, 30, 1.05, (s, n) => Math.abs(n - Math.sin(s * 0.7) * 0.8) < 0.42 ? 3 : -1);
        const orb = O(h, 37.5, 0);
        ctx.pal("gold");
        g.ellipse(orb.x, orb.y + 1.2, 4.4, 4.4, (s, x, y) => Math.hypot(x - orb.x, y - (orb.y + 1.2)) > 3.2 && y > orb.y - 1 ? 3 : -1);
        ctx.pal("gem");
        ko(ctx, orb.x, orb.y, 3.1);
      }
    }, At(h => O(h, 37.5), "fx", 1.15),
      Ut((ctx, h) => {
        const orb = O(h, 37.5, 0);
        Qe(ctx, orb.x, orb.y, 6, 7.8 + (ctx.phase % 2) * 1.8, ctx.phase * Math.PI / 8);
        const a = ctx.phase * Math.PI * 0.5;
        te(ctx, orb.x + Math.cos(a) * 5.2, orb.y + Math.sin(a) * 4.6, 1);
      })
    ]
  }, "expansion/weapon/emerald_scepter");

  // 9. 暗影双刃 (shadowTwinblades, Epic, hold: down, + bakeFx purple mist!)
  Me({
    id: "weapon_shadow_twinblades", name: "暗影双刃", slot: "weapon_main", hold: "down", gameItem: "shadowTwinblades",
    palettes: { blade: P.purple, hilt: P.obsid, grip: P.indigo, gem: P.fxPurp, fx: P.fxPurp },
    parts: [{
      layer: "weapon",
      draw: ctx => St(ctx, { from: 3.0, to: 21.0, half: 1.5, tip: 5.5, curve: -2.0, core: "glow", grip: 2.8, guard: [4.2, 1.3, 1.6], pommel: 1.2 }, true)
    }, jt(5, 23), At(h => O(h, 17), "fx", 1.0),
      Ut((ctx, h) => {
        [O(h, 8, -2.5), O(h, 13, 2.2), O(h, 18, -1.8), O(h, 11, -3.0)].forEach((p, idx) =>
          idx === ctx.phase ? te(ctx, p.x, p.y, 2) : ctx.g.dot(p.x, p.y, (idx + ctx.phase) % 2 ? 4 : 3)
        );
      })
    ]
  }, "expansion/weapon/shadow_twinblades");

  // 10. 破晓圣剑 (sunbreakerBlade, Legendary, hold: shoulder, + bakeFx sun rays!)
  Me({
    id: "weapon_sunbreaker_blade", name: "破晓圣剑", slot: "weapon_main", hold: "shoulder", gameItem: "sunbreakerBlade",
    palettes: { blade: P.white, hilt: P.gold, grip: P.crimson, gem: P.fire, fx: P.fxGold },
    parts: [{
      layer: "weapon",
      draw: ctx => St(ctx, { from: 4.4, to: 33.0, half: 2.35, tip: 5.2, core: "glow", grip: 5.0, guard: [5.4, 1.8, 1.5], pommel: 1.6 }, true)
    }, jt(9, 36), At(h => O(h, 29), "fx", 1.2),
      Ut((ctx, h) => {
        const mid = O(h, 22, 0), tip = O(h, 32, 0);
        Qe(ctx, tip.x, tip.y, 6, 6.5 + (ctx.phase % 2) * 1.8, ctx.phase * Math.PI / 8);
        te(ctx, mid.x, mid.y + (ctx.phase % 2 ? -2.4 : 2.4), 1);
      })
    ]
  }, "expansion/weapon/sunbreaker_blade");

  // 11. 星陨长弓 (astralGreatbow, Legendary, hold: bow, + bakeFx starlight!)
  const drawAstralBow = makeBowDraw({ halfLen: 15, recurve: 0.75, wingTips: true, boltGlow: true });
  Me({
    id: "weapon_astral_greatbow", name: "星陨长弓", slot: "weapon_main", hold: "bow", gameItem: "astralGreatbow",
    palettes: { wood: P.indigo, wrap: P.gold, trim: P.gold, string: P.fxHoly, arrow: P.fxGold, fletch: P.fxGold, fx: P.fxGold },
    parts: [
      { layer: "weapon", draw: ctx => drawAstralBow(ctx, true) },
      { layer: "weapon", outline: false, draw: ctx => drawAstralBow(ctx, false) },
      Ut((ctx, h) => {
        const spots = [O(h, 12, -2.5), O(h, -12, -2.5), O(h, 5, 2.2), O(h, -5, 2.2)];
        spots.forEach((p, idx) => idx === ctx.phase ? te(ctx, p.x, p.y, 2) : ctx.g.dot(p.x, p.y, 4));
      })
    ]
  }, "expansion/weapon/astral_greatbow");

  // 12. 林野木枪 (wildwoodSpear, Common, Set 1, hold: down)
  Me({
    id: "weapon_wildwood_spear", name: "林野木枪", slot: "weapon_main", hold: "down", gameItem: "wildwoodSpear",
    palettes: { shaft: P.wood, vine: P.leaf, blade: P.iron, fx: P.fxLeaf },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g } = ctx;
        ctx.pal("shaft");
        Z(ctx, h, -6, 17, 0.72, (s, n) => n < 0 ? 3 : 1);
        ctx.pal("blade");
        Z(ctx, h, 16.5, 24.5, 1.75, (s, n) => {
          const t = (s - 16.5) / 8.0;
          const w = Math.sin(t * Math.PI) * 1.65 + (1 - t) * 0.4;
          return Math.abs(n) > w ? -1 : n < 0 ? 4 : 2;
        });
        ctx.pal("vine");
        const lf1 = O(h, 15.5, -2.1), lf2 = O(h, 15.5, 2.1);
        g.ellipse(lf1.x, lf1.y, 1.8, 1.0, s => s > 0 ? 3 : 2);
        g.ellipse(lf2.x, lf2.y, 1.8, 1.0, s => s > 0 ? 3 : 1);
      }
    }, jt(6, 26)]
  }, "expansion/weapon/wildwood_spear");

  // 13. 疾风长弓 (galeLongbow, Rare, Set 2, hold: bow)
  const drawGaleBow = makeBowDraw({ halfLen: 14.5, recurve: 0.9, wingTips: true });
  Me({
    id: "weapon_gale_longbow", name: "疾风长弓", slot: "weapon_main", hold: "bow", gameItem: "galeLongbow",
    palettes: { wood: P.teal, wrap: P.silver, trim: P.white, string: P.fxIce, arrow: P.fxWind, fletch: P.white },
    parts: [
      { layer: "weapon", draw: ctx => drawGaleBow(ctx, true) },
      { layer: "weapon", outline: false, draw: ctx => drawGaleBow(ctx, false) }
    ]
  }, "expansion/weapon/gale_longbow");

  // 14. 橡木战锤 (oakHammer, Rare, Set 3, hold: shoulder)
  Me({
    id: "weapon_oak_hammer", name: "橡木战锤", slot: "weapon_main", hold: "shoulder", gameItem: "oakHammer",
    palettes: { shaft: P.wood, bronze: P.bronze, rune: P.fxLeaf, fx: P.fxLeaf },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        ctx.pal("shaft");
        Z(ctx, h, -6, 26, 0.95, (s, n) => n < 0 ? 3 : 1);
        // Chunky oak-and-bronze warhammer head
        Z(ctx, h, 21.5, 30.0, 5.8, (s, n) => {
          const an = Math.abs(n);
          if (an > 5.4) return -1;
          if (an > 3.8 || s < 22.6 || s > 28.9) { ctx.pal("bronze"); return n < 0 ? 4 : 2; }
          if (Math.abs(s - 25.8) < 1.1 && an < 1.6) { ctx.pal("rune"); return 4; }
          ctx.pal("shaft");
          return n < 0 ? 3 : 1;
        });
      }
    }, jt(9, 32), At(h => O(h, 26), "fx", 0.95)]
  }, "expansion/weapon/oak_hammer");

  // 15. 秘焰法杖 (emberStaff, Epic, Set 5, hold: up, + bakeFx fire!)
  Me({
    id: "weapon_ember_staff", name: "秘焰法杖", slot: "weapon_main", hold: "up", gameItem: "emberStaff",
    palettes: { shaft: P.purple, gold: P.gold, gem: P.fire, fx: P.fxFire },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g } = ctx;
        ctx.pal("shaft");
        Z(ctx, h, -10, 31, 0.82, (s, n) => n < 0 ? 3 : 1);
        ctx.pal("gold");
        Z(ctx, h, 29.5, 31.8, 1.4, (s, n) => n < 0 ? 4 : 2);
        const c = O(h, 37.5, 0);
        // Fiery golden ring cradling flame crystal
        g.fill(c.x - 6, c.y - 6, c.x + 6, c.y + 6, (x, y) => {
          const r = Math.hypot(x - c.x, y - c.y);
          if (Math.abs(r - 4.7) > 0.95) return -1;
          return y < c.y ? 4 : 2;
        });
        ctx.pal("gem");
        ko(ctx, c.x, c.y, 2.8);
      }
    }, At(h => O(h, 37.5), "fx", 1.2),
      Ut((ctx, h) => {
        const c = O(h, 37.5, 0);
        Qe(ctx, c.x, c.y, 6, 8.2 + (ctx.phase % 2) * 1.8, ctx.phase * Math.PI / 8);
        be(ctx, c.x, c.y - 2.2, 3.0 + (ctx.phase % 2) * 1.1);
      })
    ]
  }, "expansion/weapon/ember_staff");

  // 16. 苍穹圣枪 (aegisLance, Legendary, Set 7, hold: shoulder, + bakeFx seraph glow!)
  Me({
    id: "weapon_aegis_lance", name: "苍穹圣枪", slot: "weapon_main", hold: "shoulder", gameItem: "aegisLance",
    palettes: { shaft: P.white, gold: P.gold, tip: P.ice, fx: P.fxGold },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g } = ctx;
        ctx.pal("gold");
        Z(ctx, h, -5, 4.5, 1.0, (s, n) => n < 0 ? 4 : 2);
        // Tapered spiral platinum lance shaft + ice-blue holy point
        Z(ctx, h, 4.5, 35.5, 2.3, (s, n) => {
          const t = (s - 4.5) / 31.0;
          const w = 2.15 * (1 - t * 0.78);
          if (Math.abs(n) > w) return -1;
          if (t > 0.72) { ctx.pal("tip"); return n <= 0 ? 4 : 3; }
          if (Math.floor(s * 0.75 + n * 0.5) % 2 === 0) { ctx.pal("gold"); return n < 0 ? 4 : 2; }
          ctx.pal("shaft"); return n < 0 ? 4 : 2;
        });
        // Unfurled golden angel-wing guard
        const base = O(h, 5.2, 0);
        ctx.pal("gold");
        for (const side of [-1, 1]) {
          const tip = O(h, 11.5, side * 5.6);
          g.capsule(base.x, base.y, tip.x, tip.y, 1.3, 0.75, s => s > 0 ? 4 : 2);
        }
      }
    }, jt(10, 37), At(h => O(h, 33), "fx", 1.2),
      Ut((ctx, h) => {
        const tip = O(h, 34.0, 0);
        Qe(ctx, tip.x, tip.y, 8, 7.5 + (ctx.phase % 2) * 1.8, ctx.phase * Math.PI / 12);
        te(ctx, tip.x, tip.y, 1);
      })
    ]
  }, "expansion/weapon/aegis_lance");

  // 17. 星辰魔典 (astralCodex, Legendary, Set 8, hold: up, + bakeFx orbiting astrolabe!)
  Me({
    id: "weapon_astral_codex", name: "星辰魔典", slot: "weapon_main", hold: "up", gameItem: "astralCodex",
    palettes: { cover: P.indigo, gold: P.gold, page: P.cream, fx: P.fxGold },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g } = ctx;
        const c = O(h, 11.5, 0);
        // Levitating open deep-blue & gold grimoire
        ctx.pal("cover");
        g.fill(c.x - 6.5, c.y - 4.2, c.x + 6.5, c.y + 4.4, (x, y) => {
          const dx = x - c.x, dy = y - c.y;
          const arch = Math.cos(dx / 6.5 * 1.2) * 1.1;
          if (Math.abs(dx) > 6.0 || dy < -3.4 - arch || dy > 3.5 - arch * 0.5) return -1;
          if (Math.abs(dx) > 5.0 || dy > 2.4 - arch * 0.5) { ctx.pal("gold"); return dx < 0 ? 4 : 2; }
          if (Math.abs(dx) < 0.7) { ctx.pal("cover"); return 1; }
          ctx.pal("page");
          return dx < 0 ? 4 : 3;
        });
        // Tiny glowing rune script
        ctx.pal("cover");
        g.line(c.x - 4.0, c.y - 1.0, c.x - 1.5, c.y - 1.0, 3);
        g.line(c.x + 1.5, c.y - 1.0, c.x + 4.0, c.y - 1.0, 3);
        // Floating golden star above pages
        ctx.pal("gold");
        g.dot(c.x, c.y - 6.2, 4);
      }
    }, At(h => O(h, 16), "fx", 1.2),
      Ut((ctx, h) => {
        const c = O(h, 17.5, 0);
        Qe(ctx, c.x, c.y, 6, 7.0 + (ctx.phase % 2) * 1.5, ctx.phase * Math.PI / 6);
        const a = ctx.phase * Math.PI * 0.5;
        te(ctx, c.x + Math.cos(a) * 5.2, c.y + Math.sin(a) * 2.5, 1);
      })
    ]
  }, "expansion/weapon/astral_codex");

  // =========================================================================
  // PART B: 14 NEW WEARABLE ARMORS (slot: "top", id: top_<snake_case>)
  // =========================================================================

  // 1. 旅人布袍 (travelerCloak, Common)
  Me({
    id: "top_traveler_cloak", name: "旅人布袍", slot: "top", gameItem: "travelerCloak",
    palettes: { main: P.cream, cloak: P.olive, trim: P.bronze, belt: P.leather },
    parts: [{
      layer: "top",
      draw: ctx => {
        const { g, pose } = ctx, ny = pose.neckY;
        ctx.pal("main");
        J(ctx, rt, { flare: 1.8 }, (s, nx, p) => {
          if (p < 2.2) return 0;
          if (p < 6.4) { ctx.pal("cloak"); return g.t(s, p > 5.7 ? -0.35 : 0.08); }
          ctx.pal("main");
          return g.t(s, 0.04);
        });
        uo(ctx, 8.6, 10.6, "belt", "trim");
        if (pose.cos > 0.3) {
          ctx.pal("trim"); g.clip = true;
          g.ellipse(gt(ctx), ny + 3.6, 1.3, 1.3, s => s > 0 ? 4 : 2);
          g.clip = false;
        }
      }
    }, ...Mt({ key: "cloak", cuffKey: "main", r: 2.0 })]
  }, "expansion/top/traveler_cloak");

  // 2. 铆钉轻甲 (studdedVest, Common)
  Me({
    id: "top_studded_vest", name: "铆钉轻甲", slot: "top", gameItem: "studdedVest",
    palettes: { main: P.leather, strap: P.wood, metal: P.gold, cloth: P.cream },
    parts: [{
      layer: "top",
      draw: ctx => {
        const { g, pose } = ctx, ny = pose.neckY, hw = pose.torsoHalf;
        ctx.pal("main");
        J(ctx, rt, { flare: 2.0 }, (s, nx, p) => p < 2.4 ? 0 : g.t(s, p > 8.6 && p < 9.6 ? -0.4 : 0.05));
        g.clip = true;
        if (pose.cos > 0.2) {
          const cx = gt(ctx);
          ctx.pal("metal");
          for (const py of [4.2, 6.6, 9.0]) {
            g.dot(cx - 2.3, ny + py, 4);
            g.dot(cx + 2.3, ny + py, 3);
          }
        }
        uo(ctx, 9.2, 11.2, "strap", "metal");
        g.clip = false;
      }
    }, ...Mt({ key: "cloth", cuffKey: "strap", r: 1.9 }), ...ae({ key: "main", trimKey: "metal", r: 2.7 })]
  }, "expansion/top/studded_vest");

  // 3. 精钢锁子甲 (chainmailCoat, Rare)
  Me({
    id: "top_chainmail_coat", name: "精钢锁子甲", slot: "top", gameItem: "chainmailCoat",
    palettes: { main: P.blue, mail: P.silver, trim: P.gold },
    parts: [{
      layer: "top",
      draw: ctx => {
        const { g, pose } = ctx, ny = pose.neckY;
        ctx.pal("main");
        J(ctx, rt + 0.5, { flare: 2.4 }, (s, nx, p, x, y) => {
          if (p < 2.4) return 0;
          if (p > rt - 1.6) { ctx.pal("trim"); return ct(ctx, s, 0.15); }
          if (Math.abs(nx) > 0.78) { ctx.pal("mail"); return ((Math.floor(x) + Math.floor(y)) % 2 === 0) ? 3 : 1; }
          ctx.pal("main"); return g.t(s, 0.04);
        });
        if (pose.cos > 0.3) {
          const cx = gt(ctx);
          ctx.pal("trim"); g.clip = true;
          g.line(cx, ny + 3.4, cx, ny + 8.6, 4);
          g.line(cx - 2.3, ny + 5.6, cx + 2.3, ny + 5.6, 3);
          g.clip = false;
        }
        uo(ctx, 9.4, 11.0, "mail", "trim");
      }
    }, ...Mt({ key: "mail", cuffKey: "trim", r: 2.1 }), ...ae({ key: "mail", trimKey: "trim", r: 3.1 })]
  }, "expansion/top/chainmail_coat");

  // 4. 疾风游侠服 (windrunnerGarb, Rare)
  Me({
    id: "top_windrunner_garb", name: "疾风游侠服", slot: "top", gameItem: "windrunnerGarb",
    palettes: { main: P.teal, trim: P.white, leather: P.leather, cloth: P.teal },
    parts: [
      makeArmorCape({ mainKey: "trim", trimKey: "main", lenOffset: 10.5, extraWidth: 2.2, asymmetric: true }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx, ny = pose.neckY;
          ctx.pal("main");
          J(ctx, rt, { flare: 2.1 }, (s, nx, p) => {
            if (p < 2.3) return 0;
            if (p < 3.8) { ctx.pal("trim"); return g.t(s, 0.15); }
            ctx.pal("main"); return g.t(s, 0.05);
          });
          uo(ctx, 8.8, 10.6, "leather", "trim");
        }
      },
      ...Mt({ key: "main", cuffKey: "leather", r: 1.95 }),
      ...ae({ key: "leather", trimKey: "trim", r: 2.6, only: "L" })
    ]
  }, "expansion/top/windrunner_garb");

  // 5. 秘银板甲 (mithrilPlate, Epic, + bakeFx shimmer!)
  Me({
    id: "top_mithril_plate", name: "秘银板甲", slot: "top", gameItem: "mithrilPlate",
    palettes: { main: P.silver, trim: P.purple, cloth: P.indigo, fx: P.fxPurp },
    parts: [
      makeArmorCape({ mainKey: "cloth", trimKey: "trim", lenOffset: 7.5, extraWidth: 3.2 }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx, ny = pose.neckY;
          ctx.pal("main");
          J(ctx, rt + 0.2, { flare: 2.6 }, (s, nx, p) => {
            if (p < 2.4) return 0;
            if (p > rt - 1.6 || (p > 8.6 && p < 9.5)) { ctx.pal("trim"); return ct(ctx, s, 0.15); }
            ctx.pal("main"); return ct(ctx, s, p < 3.5 ? -0.35 : 0.1);
          });
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            ctx.pal("trim"); g.clip = true;
            g.ellipse(cx, ny + 5.6, 1.8, 2.0, s => s > 0.2 ? 4 : 2);
            g.clip = false;
          }
        }
      },
      ...Mt({ key: "main", cuffKey: "trim", r: 2.1 }),
      ...ae({ key: "main", trimKey: "trim", r: 3.5, spikes: true }),
      makeArmorGlow("fx", "shoulders")
    ]
  }, "expansion/top/mithril_plate");

  // 6. 奥术星纹袍 (arcaneMantle, Epic, + bakeFx orbiting stars!)
  Me({
    id: "top_arcane_mantle", name: "奥术星纹袍", slot: "top", gameItem: "arcaneMantle",
    palettes: { main: P.indigo, trim: P.gold, cloth: P.purple, fx: P.fxGold },
    parts: [
      makeArmorCape({ mainKey: "cloth", trimKey: "trim", lenOffset: 6.0, extraWidth: 3.6, starry: true }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx, ny = pose.neckY;
          ctx.pal("main");
          J(ctx, rt + 1.8, { flare: 3.2 }, (s, nx, p) => {
            if (p < 2.0) return 0;
            if (p > rt + 0.3 || Math.abs(nx) > 0.86 && p > 9.5) { ctx.pal("trim"); return g.t(s, 0.2); }
            ctx.pal("main"); return g.t(s, 0.04);
          });
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            ctx.pal("trim"); g.clip = true;
            g.line(cx, ny + 3.2, cx, ny + 8.0, 4);
            g.line(cx - 2.2, ny + 5.4, cx + 2.2, ny + 5.4, 4);
            g.clip = false;
          }
          uo(ctx, 8.8, 10.6, "cloth", "trim");
        }
      },
      ...Mt({ key: "main", cuffKey: "trim", r: 2.2, length: 0.82 }),
      ...ae({ key: "cloth", trimKey: "trim", r: 3.0 }),
      makeArmorGlow("fx", "stars")
    ]
  }, "expansion/top/arcane_mantle");

  // 7. 泰坦重堡铠 (titanFortressArmor, Legendary, + bakeFx solar!)
  Me({
    id: "top_titan_fortress_armor", name: "泰坦重堡铠", slot: "top", gameItem: "titanFortressArmor",
    palettes: { main: P.white, trim: P.gold, cloth: P.bronze, gem: P.fire, fx: P.fxGold },
    parts: [{
      layer: "top",
      draw: ctx => {
        const { g, pose } = ctx, ny = pose.neckY;
        ctx.pal("main");
        J(ctx, rt + 0.4, { flare: 3.0, pad: 0.5 }, (s, nx, p) => {
          if (p < 2.4) return 0;
          if (p > rt - 1.8 || (p > 8.2 && p < 9.4)) { ctx.pal("trim"); return ct(ctx, s, 0.2); }
          ctx.pal("main"); return ct(ctx, s, p < 3.6 ? -0.35 : 0.12);
        });
        if (pose.cos > 0.3) {
          const cx = gt(ctx);
          ctx.pal("gem"); g.clip = true;
          g.ellipse(cx, ny + 5.4, 2.2, 2.2, s => s > 0.2 ? 4 : 2);
          g.clip = false;
        }
      }
    }, ...Mt({ key: "cloth", cuffKey: "trim", r: 2.25 }),
      ...ae({ key: "trim", trimKey: "main", r: 4.0, spikes: true }),
      makeArmorGlow("fx", "holy")
    ]
  }, "expansion/top/titan_fortress_armor");

  // 8. 炽凰羽衣 (phoenixFeatherRobe, Legendary, + bakeFx flames!)
  Me({
    id: "top_phoenix_feather_robe", name: "炽凰羽衣", slot: "top", gameItem: "phoenixFeatherRobe",
    palettes: { main: P.crimson, trim: P.gold, cloth: P.fire, fx: P.fxFire },
    parts: [
      makeArmorCape({ mainKey: "cloth", trimKey: "trim", lenOffset: 6.0, extraWidth: 3.8 }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx, ny = pose.neckY;
          ctx.pal("main");
          J(ctx, rt + 1.4, { flare: 3.0 }, (s, nx, p) => {
            if (p < 2.2) return 0;
            if (p > rt - 0.5) { ctx.pal("trim"); return ct(ctx, s, 0.25); }
            if (p > 9.5) { ctx.pal("cloth"); return g.t(s, 0.15); }
            ctx.pal("main"); return g.t(s, 0.08);
          });
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            ctx.pal("trim"); g.clip = true;
            g.tri({ x: cx - 2.2, y: ny + 4.0 }, { x: cx + 2.2, y: ny + 4.0 }, { x: cx, y: ny + 7.8 }, 4);
            g.clip = false;
          }
          uo(ctx, 8.8, 10.6, "trim", "cloth");
        }
      },
      ...Mt({ key: "main", cuffKey: "trim", r: 2.15 }),
      ...ae({ key: "cloth", trimKey: "trim", r: 3.6, spikes: true }),
      makeArmorGlow("fx", "flame")
    ]
  }, "expansion/top/phoenix_feather_robe");

  // 9. 林野叶甲 (wildwoodArmor, Common, Set 1)
  Me({
    id: "top_wildwood_armor", name: "林野叶甲", slot: "top", gameItem: "wildwoodArmor",
    palettes: { main: P.leather, leaf: P.leaf, belt: P.wood, trim: P.woodL },
    parts: [{
      layer: "top",
      draw: ctx => {
        const { g } = ctx;
        ctx.pal("main");
        J(ctx, rt, { flare: 2.2 }, (s, nx, p) => {
          if (p < 2.2) return 0;
          if (p < 5.6 + Math.abs(Math.sin(nx * 6)) * 1.1) { ctx.pal("leaf"); return g.t(s, 0.1); }
          ctx.pal("main"); return g.t(s, 0.02);
        });
        uo(ctx, 9.0, 10.8, "belt", "trim");
      }
    }, ...Mt({ key: "trim", cuffKey: "leaf", r: 2.0 }), ...ae({ key: "leaf", trimKey: "main", r: 3.0 })]
  }, "expansion/top/wildwood_armor");

  // 10. 疾风轻甲 (galeArmor, Rare, Set 2)
  Me({
    id: "top_gale_armor", name: "疾风轻甲", slot: "top", gameItem: "galeArmor",
    palettes: { main: P.blue, trim: P.white, cloth: P.teal, metal: P.silver },
    parts: [
      makeArmorCape({ mainKey: "trim", trimKey: "cloth", lenOffset: 8.5, extraWidth: 3.0, asymmetric: true }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx, ny = pose.neckY;
          ctx.pal("main");
          J(ctx, rt, { flare: 2.3 }, (s, nx, p) => {
            if (p < 2.3) return 0;
            if (p > rt - 1.5) { ctx.pal("trim"); return g.t(s, 0.2); }
            ctx.pal("main"); return ct(ctx, s, 0.06);
          });
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            ctx.pal("trim"); g.clip = true;
            g.line(cx - 2.4, ny + 4.4, cx + 2.4, ny + 6.4, 4);
            g.clip = false;
          }
          uo(ctx, 9.0, 10.6, "metal", "trim");
        }
      },
      ...Mt({ key: "cloth", cuffKey: "trim", r: 2.0 }),
      ...ae({ key: "trim", trimKey: "main", r: 3.1 })
    ]
  }, "expansion/top/gale_armor");

  // 11. 橡木重甲 (oakArmor, Rare, Set 3)
  Me({
    id: "top_oak_armor", name: "橡木重甲", slot: "top", gameItem: "oakArmor",
    palettes: { main: P.bronze, bark: P.wood, moss: P.leaf, trim: P.woodL },
    parts: [{
      layer: "top",
      draw: ctx => {
        const { g, pose } = ctx, ny = pose.neckY;
        ctx.pal("main");
        J(ctx, rt + 0.3, { flare: 2.6, pad: 0.3 }, (s, nx, p, x, y) => {
          if (p < 2.4) return 0;
          if (p > rt - 1.6) { ctx.pal("trim"); return ct(ctx, s, 0.1); }
          ctx.pal("main");
          const grain = Math.sin(x * 2.1 + y * 0.4) > 0.65 ? -0.35 : 0.08;
          return ct(ctx, s, grain);
        });
        if (pose.cos > 0.3) {
          const cx = gt(ctx);
          ctx.pal("moss"); g.clip = true;
          g.ellipse(cx, ny + 5.6, 1.9, 1.9, s => s > 0.1 ? 4 : 2);
          g.clip = false;
        }
        uo(ctx, 9.2, 11.0, "bark", "trim");
      }
    }, ...Mt({ key: "bark", cuffKey: "main", r: 2.15 }), ...ae({ key: "main", trimKey: "moss", r: 3.5 })]
  }, "expansion/top/oak_armor");

  // 12. 秘焰法袍 (emberArmor, Epic, Set 5, + bakeFx flame!)
  Me({
    id: "top_ember_armor", name: "秘焰法袍", slot: "top", gameItem: "emberArmor",
    palettes: { main: P.purple, flame: P.fire, cloth: P.crimson, trim: P.gold, fx: P.fxFire },
    parts: [
      makeArmorCape({ mainKey: "cloth", trimKey: "flame", lenOffset: 6.8, extraWidth: 3.4 }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx, ny = pose.neckY;
          ctx.pal("main");
          J(ctx, rt + 1.4, { flare: 3.0 }, (s, nx, p) => {
            if (p < 2.2) return 0;
            if (p > rt - 1.2) { ctx.pal("flame"); return g.t(s, 0.25); }
            ctx.pal("main"); return g.t(s, 0.05);
          });
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            ctx.pal("flame"); g.clip = true;
            g.tri({ x: cx - 2.0, y: ny + 6.6 }, { x: cx + 2.0, y: ny + 6.6 }, { x: cx, y: ny + 3.2 }, 4);
            g.clip = false;
          }
          uo(ctx, 8.8, 10.6, "trim", "flame");
        }
      },
      ...Mt({ key: "main", cuffKey: "flame", r: 2.1 }),
      ...ae({ key: "main", trimKey: "flame", r: 3.4, spikes: true }),
      makeArmorGlow("fx", "flame")
    ]
  }, "expansion/top/ember_armor");

  // 13. 苍穹光铠 (aegisArmor, Legendary, Set 7, + bakeFx seraph!)
  Me({
    id: "top_aegis_armor", name: "苍穹光铠", slot: "top", gameItem: "aegisArmor",
    palettes: { main: P.white, trim: P.gold, cloth: P.white, fx: P.fxGold },
    parts: [
      makeArmorCape({ mainKey: "cloth", trimKey: "trim", lenOffset: 6.2, extraWidth: 3.8 }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx, ny = pose.neckY;
          ctx.pal("main");
          J(ctx, rt + 0.4, { flare: 2.8, pad: 0.3 }, (s, nx, p) => {
            if (p < 2.4) return 0;
            if (p > rt - 1.7 || Math.abs(Math.abs(nx) - 0.94) < 0.05) { ctx.pal("trim"); return ct(ctx, s, 0.2); }
            ctx.pal("main"); return ct(ctx, s, 0.14);
          });
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            ctx.pal("trim"); g.clip = true;
            g.line(cx, ny + 3.0, cx, ny + 8.6, 4);
            g.line(cx - 2.6, ny + 5.2, cx + 2.6, ny + 5.2, 4);
            g.clip = false;
          }
          uo(ctx, 9.2, 10.8, "trim", "main");
        }
      },
      ...Mt({ key: "main", cuffKey: "trim", r: 2.2 }),
      ...ae({ key: "main", trimKey: "trim", r: 3.8, spikes: true }),
      makeArmorGlow("fx", "holy")
    ]
  }, "expansion/top/aegis_armor");

  // 14. 星辰法衣 (astralArmor, Legendary, Set 8, + bakeFx constellation!)
  Me({
    id: "top_astral_armor", name: "星辰法衣", slot: "top", gameItem: "astralArmor",
    palettes: { main: P.indigo, trim: P.gold, cloth: P.purple, blue: P.blue, fx: P.fxGold },
    parts: [
      makeArmorCape({ mainKey: "cloth", trimKey: "trim", lenOffset: 5.8, extraWidth: 4.0, starry: true }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx, ny = pose.neckY;
          ctx.pal("main");
          J(ctx, rt + 1.8, { flare: 3.4 }, (s, nx, p, x, y) => {
            if (p < 2.0) return 0;
            if (p > rt + 0.3) { ctx.pal("trim"); return ct(ctx, s, 0.25); }
            if (((Math.floor(x * 1.5) * 13 + Math.floor(y * 1.5) * 29) % 23 === 0) && p > 4.0) {
              ctx.pal("trim"); return 4;
            }
            ctx.pal("main"); return g.t(s, 0.05);
          });
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            ctx.pal("trim"); g.clip = true;
            g.line(cx - 2.4, ny + 4.0, cx, ny + 6.4, 3);
            g.line(cx, ny + 6.4, cx + 2.5, ny + 4.4, 3);
            g.dot(cx - 2.4, ny + 4.0, 4); g.dot(cx, ny + 6.4, 4); g.dot(cx + 2.5, ny + 4.4, 4);
            g.clip = false;
          }
          uo(ctx, 8.8, 10.6, "blue", "trim");
        }
      },
      ...Mt({ key: "blue", cuffKey: "trim", r: 2.2, length: 0.82 }),
      ...ae({ key: "main", trimKey: "trim", r: 3.4, spikes: true }),
      makeArmorGlow("fx", "stars")
    ]
  }, "expansion/top/astral_armor");
}
