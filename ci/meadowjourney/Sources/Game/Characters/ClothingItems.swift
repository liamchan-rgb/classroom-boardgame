import Foundation

// 人物像素精灵：衣服、鞋、围巾、挎包。与 items/top|bottom|shoes|scarf|bag/*.ts 逐个对应。
// 新增衣服时，网页工具和这里各加一份实现；ParityTests 会比对两端出图。

enum ClothingItems {
    private typealias H = ItemHelpers
    private static let O = Shade.outline, D = Shade.dark, B = Shade.base, Lt = Shade.light, Hi = Shade.hi

    // MARK: 蓝色旅人装

    static let travelerJacket: ItemDef = {
        let blue = SpritePalette("jacket-blue", ["#0c1430", "#1c3464", "#2f589e", "#5288cc", "#a0c8f0"])
        let trim = SpritePalette("trim-white", ["#3c4258", "#8088a0", "#c2c4c8", "#ece8dc", "#fffcf2"])
        let metal = SpritePalette("button-gold", ["#3e2408", "#8a5c16", "#d8a430", "#f6d86c", "#fff6c0"])
        let rows = 13.2, hemH = 3.0
        let body = PartDef(layer: .fixed(.top), draw: { c in
            let g = c.g, pose = c.pose
            let hw = pose.torsoHalf, ny = pose.neckY
            let hem = rows - hemH
            c.pal("main")
            H.torsoShape(c, rows: rows, flare: 2) { lam, _, r, _, _ in
                if r > hem { return -1 }
                if r < 2.6 { return O }
                if r < 3.6 || r > hem - 0.6 { return D }
                return g.t(lam, r > 7 && r < 10 ? -0.12 : 0.05)
            }
            c.pal("trim")
            H.torsoShape(c, rows: rows, flare: 2) { lam, _, r, _, _ in r <= hem ? -1 : g.t(lam, r > rows - 0.7 ? -0.35 : 0.3) }
            c.pal("main")
            g.clip = true
            g.fold(Rig.cx - hw + 1, ny + 4.8, Rig.cx - hw + 3.8, ny + 7.4)
            g.fold(Rig.cx + hw - 1, ny + 4.4, Rig.cx + hw - 3.4, ny + 7)
            if pose.cos > 0.3 {
                let fx = H.frontX(c)
                g.line(fx, ny + 3, fx, ny + hem - 0.6, BrushOp.darken)
                c.pal("trim")
                g.tri(SpritePoint(x: fx, y: ny + 2.2), SpritePoint(x: fx - 3.8, y: ny + 2.8), SpritePoint(x: fx - 0.4, y: ny + 7), Lt)
                g.tri(SpritePoint(x: fx, y: ny + 2.2), SpritePoint(x: fx + 3.8, y: ny + 2.8), SpritePoint(x: fx + 0.4, y: ny + 7), B)
                c.pal("metal")
                for r in [7.0, 9.0] {
                    g.dot(fx + 1.2, ny + r, Hi)
                    g.dot(fx + 1.2, ny + r + 1, D)
                }
            } else if pose.cos < -0.3 {
                let bx = Rig.cx - hw * 0.4 * pose.sin
                g.line(bx, ny + 3.5, bx, ny + 7, BrushOp.darken)
                g.rect(bx - 3.4, ny + 7.4, 6.8, 1.6) { _, v in v < ny + 8.1 ? Lt : D }
                c.pal("metal")
                g.dot(bx - 3, ny + 7.8, Hi)
                g.dot(bx + 3, ny + 7.8, Lt)
            } else {
                g.line(Rig.cx - 0.6, ny + 5, Rig.cx - 0.6, ny + hem - 1, BrushOp.darken)
                g.line(Rig.cx + 0.6, ny + 8.6, Rig.cx + 3, ny + 8.6, BrushOp.lighten)
            }
            g.clip = false
        })
        return ItemDef(
            id: "top_traveler", name: "蓝色旅人装", slot: .top,
            palettes: ["main": blue, "trim": trim, "metal": metal],
            variants: [
                ItemVariant(id: "blue", name: "蓝", palettes: ["main": blue]),
                ItemVariant(id: "green", name: "绿", palettes: ["main": .ramp("jacket-green", "#3a8a54")]),
                ItemVariant(id: "purple", name: "紫", palettes: ["main": .ramp("jacket-purple", "#6e4eb0")]),
            ],
            parts: [body] + H.sleeveParts(cuffKey: "trim"))
    }()

    // MARK: 红色斗篷装

    static let redCloak: ItemDef = {
        let red = SpritePalette("cloak-red", ["#2e0810", "#701422", "#b42a34", "#e0584c", "#fa9c84"])
        let gold = SpritePalette("trim-gold", ["#3e2408", "#8a5c16", "#d8a430", "#f6d86c", "#fff6c0"])
        let leather = SpritePalette("belt-leather", ["#140a06", "#34200f", "#583820", "#80542e", "#aa7a48"])
        let rows = 12.8

        func cape(_ c: DrawContext) {
            let g = c.g, pose = c.pose
            let sin = pose.sin, cos = pose.cos
            let outside = cos < 0.3
            let walking = pose.walking
            let sway = walking ? msin(pose.phase + 1) : 0
            let hwTop = 6.6 * abs(cos) + 3 * abs(sin) + 1.2
            let hwBottom = hwTop + 3.8
            let cx0 = Rig.cx - sin * 3.8
            let y0 = pose.neckY - 0.5, y1 = Rig.footY - 6
            let folds = 2.2 + abs(cos) * 1.4
            g.grit = 0.24
            g.fill(cx0 - hwBottom - 6, y0, cx0 + hwBottom + 6, y1 + 2) { u, v in
                let t = min(1, (v - y0) / (y1 - y0))
                if t < 0 { return -1 }
                let mid = cx0 + sway * t * 1.6 - sin * t * 2.4
                let hw = hwTop + (hwBottom - hwTop) * t
                let nx = (u - mid) / hw
                if abs(nx) > 1 { return -1 }
                let f = nx * folds * Double.pi + t * sway * 0.8
                let hem = y1 + 0.9 * msin(f + 0.6) + 0.5 * msin(f * 2.7 + 1)
                    + (walking ? 0.5 * msin(pose.phase * 2 + nx * 2) : 0)
                if v > hem { return -1 }
                let depth = min(1, t * 1.7)
                let ridge = msin(f + 0.9) * depth
                if !outside {
                    c.pal("main")
                    return ridge > 0.3 ? D : O
                }
                var lam = 0.18 + nx * Light.x * 0.9 + ridge * 0.75
                if t < 0.12 { lam -= 0.6 }
                let dh = hem - v
                if dh > 1.4 && dh < 3.2 {
                    c.pal("trim")
                    return g.t(lam, 0.25)
                }
                c.pal("main")
                return g.t(lam)
            }
        }

        func mantle(_ c: DrawContext) {
            let g = c.g, pose = c.pose
            let ny = pose.neckY
            let hw = pose.torsoHalf + 2.9
            let y0 = ny - 2, yb = ny + 4.6
            g.fill(Rig.cx - hw, y0, Rig.cx + hw, yb + 1.4) { u, v in
                let nx = (u - Rig.cx) / hw
                if abs(nx) > 1 { return -1 }
                let top = y0 + 2.9 * (1 - (1 - nx * nx).squareRoot())
                let bottom = yb + 0.7 * mcos(nx * hw * 0.9)
                if v < top || v > bottom { return -1 }
                let k = (v - y0) / (yb - y0)
                let lam = nx * Light.x + (k * 1.5 - 0.75) * Light.y + (1 - nx * nx).squareRoot() * Light.z * 0.85
                let db = bottom - v
                if db > 0.6 && db < 2 {
                    c.pal("trim")
                    return g.t(lam, 0.2)
                }
                c.pal("main")
                return g.t(lam)
            }
            if pose.cos > 0.3 {
                let fx = H.frontX(c)
                c.pal("trim")
                g.ellipse(fx, ny + 1.4, 1.3, 1.3) { lam, _, _, _, _ in lam > 0.5 ? Hi : lam > -0.1 ? Lt : D }
            }
        }

        let tunic = PartDef(layer: .fixed(.top), draw: { c in
            let g = c.g, pose = c.pose
            let hw = pose.torsoHalf, ny = pose.neckY
            c.pal("main")
            H.torsoShape(c, rows: rows, flare: 1.6) { lam, _, r, _, _ in r > rows - 1.6 ? -1 : g.t(lam, r > 9.8 ? -0.1 : 0) }
            c.pal("trim")
            H.torsoShape(c, rows: rows, flare: 1.6) { lam, _, r, _, _ in r <= rows - 1.6 ? -1 : g.t(lam, 0.2) }
            c.pal("belt")
            H.torsoShape(c, rows: rows, flare: 1.6) { lam, _, r, _, _ in
                r < 8 || r > 9.8 ? -1 : r < 8.6 ? Lt : r > 9.3 ? O : g.t(lam, -0.25)
            }
            g.clip = true
            c.pal("main")
            g.fold(Rig.cx - hw + 1, ny + 4.6, Rig.cx - hw + 3.6, ny + 7.2)
            g.fold(Rig.cx + hw - 1, ny + 4.2, Rig.cx + hw - 3.2, ny + 6.8)
            if pose.cos > 0.3 {
                let fx = H.frontX(c)
                c.pal("trim")
                if g.S >= 0.8 { g.line(fx, ny + 4.6, fx, ny + 7.6, B) }
                g.rect(fx - 1.2, ny + 7.8, 2.4, 2.4) { u, v in u < fx - 0.4 || v < ny + 8.5 ? Hi : D }
            } else {
                g.line(Rig.cx, ny + 4, Rig.cx, ny + 7.6, BrushOp.darken)
            }
            g.clip = false
        })

        return ItemDef(
            id: "top_red_cloak", name: "红色斗篷装", slot: .top,
            palettes: ["main": red, "trim": gold, "belt": leather],
            variants: [
                ItemVariant(id: "red", name: "红", palettes: ["main": red]),
                ItemVariant(id: "forest", name: "墨绿", palettes: ["main": .ramp("cloak-forest", "#2c6e48")]),
                ItemVariant(id: "night", name: "夜蓝", palettes: ["main": .ramp("cloak-night", "#34428c")]),
            ],
            parts: [PartDef(layer: .fixed(.cape), draw: cape), tunic]
                + H.sleeveParts(cuffKey: "trim") + [PartDef(layer: .fixed(.mantle), draw: mantle)],
            layerOverride: { dir in dir == .N || dir == .NE ? [.cape: LayerId.mantle.z - 1] : [:] })
    }()

    // MARK: 深色长裤

    static let trousers: ItemDef = {
        let dark = SpritePalette("trousers-dark", ["#0a0a12", "#1a1c2a", "#2e3142", "#484c62", "#6c7088"])
        func leg(_ i: Int) -> PartDef {
            PartDef(layer: .fixed(.bottom), draw: { c in
                let g = c.g
                let l = c.pose.legs[i]
                let fb = H.farBias(c, l.foot.near)
                let fx = l.foot.x, fy = l.foot.y - 5
                c.pal("main")
                g.anchor(fx, fy)
                g.capsule(l.hip.x, l.hip.y, fx, fy, 2.8, 2.5) { lam, _, _, _, _ in g.t(lam, fb + 0.05) }
                let kx = (l.hip.x + fx) / 2, ky = (l.hip.y + fy) / 2
                g.fold(kx - 1.8, ky, kx + 1.4, ky + 0.7)
                g.fold(fx - 1.8, fy - 1.4, fx + 1.6, fy - 0.8, highlight: false)
            })
        }
        let hips = PartDef(layer: .fixed(.bottom), draw: { c in
            let g = c.g, pose = c.pose
            let hw = pose.torsoHalf - 0.2, y = pose.legs[0].hip.y
            c.pal("main")
            g.fill(Rig.cx - hw, y - 4.5, Rig.cx + hw, y + 3) { u, v in
                let nx = (u - Rig.cx) / hw
                if abs(nx) > 1 || v < y - 4.5 { return -1 }
                if v > y + 1 + 1.4 * (1 - abs(nx)) { return -1 }
                return g.t(nx * Light.x + (1 - nx * nx).squareRoot() * Light.z, -0.15)
            }
            if abs(pose.sin) < 0.9 {
                let sx = Rig.cx + pose.sin * 2.2
                g.clip = true
                g.line(sx, y - 1, sx, y + 2.2, BrushOp.darken)
                g.clip = false
            }
        })
        return ItemDef(
            id: "bottom_trousers", name: "深色长裤", slot: .bottom, palettes: ["main": dark],
            variants: [
                ItemVariant(id: "dark", name: "深灰蓝", palettes: ["main": dark]),
                ItemVariant(id: "brown", name: "深棕", palettes: ["main": .ramp("trousers-brown", "#54392a")]),
                ItemVariant(id: "white", name: "米白", palettes: ["main": .ramp("trousers-cream", "#c4b898")]),
            ],
            parts: [leg(0), leg(1), hips])
    }()

    // MARK: 棕色短靴

    static let boots: ItemDef = {
        let brown = SpritePalette("boots-brown", ["#160c06", "#3c2212", "#6c4024", "#9c6838", "#d09c5c"])
        func boot(_ i: Int) -> PartDef {
            PartDef(layer: .fixed(.shoes), draw: { c in
                let g = c.g, pose = c.pose
                let f = pose.legs[i].foot
                let fb = H.farBias(c, f.near)
                let x = f.x, y = f.y
                let toe = pose.sin * 2.1
                let front = pose.cos > 0.9
                c.pal("main")
                g.anchor(x, y)
                let sole = y + (front ? 1.1 : 0.4)
                let fcx = x + toe * 0.9, fcy = y - 1.4 + (front ? 0.7 : 0)
                let frx = 3.1 + abs(toe) * 0.75, fry = 2.6
                g.fill(fcx - frx, fcy - fry, fcx + frx, sole) { u, v in
                    let nx = (u - fcx) / frx, ny = (v - fcy) / fry
                    let d = nx * nx + ny * ny
                    if d > 1 || v > sole { return -1 }
                    if v > sole - 0.8 { return O }
                    return g.t(nx * Light.x + ny * Light.y + (1 - d).squareRoot() * Light.z, fb)
                }
                g.capsule(x, y - 5.2, x, y - 2.4, 2.8, 2.9) { lam, _, _, _, _ in g.t(lam, fb) }
                g.fill(x - 3.6, y - 7, x + 3.6, y - 4.6) { u, v in
                    let nx = (u - x) / 3.5
                    if abs(nx) > 1 || v < y - 6.9 || v > y - 4.7 { return -1 }
                    return g.t(nx * Light.x + (1 - nx * nx).squareRoot() * Light.z, fb + (v > y - 5.4 ? -0.3 : 0.3))
                }
                g.clip = true
                g.line(x - 2.8, y - 4.4, x + 3, y - 4.4, BrushOp.darken)
                if fb == 0 {
                    g.dot(x - 2.6, y - 6.6, Hi)
                    if pose.cos > 0.3 {
                        let lx = x + pose.sin * 1.2
                        g.line(lx - 1, y - 3, lx + 1, y - 3, BrushOp.lighten)
                    } else if pose.cos < -0.3 {
                        g.line(x, y - 4.8, x, y - 1.4, BrushOp.darken)
                    } else {
                        g.fold(x - 1.2, y - 3.4, x + 2, y - 2.6)
                    }
                    g.dot(fcx - 0.8 + toe * 0.3, fcy - 1, BrushOp.lighten)
                } else {
                    g.line(x - 2.8, y - 3.8, x + 3, y - 3.8, D)
                }
                g.clip = false
            })
        }
        return ItemDef(
            id: "shoes_boots", name: "棕色短靴", slot: .shoes, palettes: ["main": brown],
            variants: [
                ItemVariant(id: "brown", name: "棕", palettes: ["main": brown]),
                ItemVariant(id: "black", name: "黑", palettes: ["main": .ramp("boots-black", "#34343e")]),
            ],
            parts: [boot(0), boot(1)])
    }()

    // MARK: 深蓝围巾（颈圈；飘动的尾巴是运行时效果，游戏端暂未接入）

    static let navyScarf: ItemDef = {
        let navy = SpritePalette("scarf-navy", ["#05081a", "#111c44", "#22346e", "#3c549c", "#7c94d4"])
        let part = PartDef(layer: .fixed(.scarf), draw: { c in
            let g = c.g, pose = c.pose
            let hw = pose.torsoHalf + 2.2 - 1.5 * abs(pose.sin)
            let sx = Rig.cx + pose.sin * 0.5
            let yc = pose.neckY + 2.1, hh = 2.6
            c.pal("main")
            g.grit = 0.26
            g.fill(sx - hw, yc - hh, sx + hw, yc + hh) { u, v in
                let nx = (u - sx) / hw, ny = (v - yc) / hh
                if pow(abs(nx), 2.6) + pow(abs(ny), 3) > 1 { return -1 }
                let lam = ny * Light.y * 1.2 + nx * Light.x * 0.6 + max(0, 1 - ny * ny).squareRoot() * Light.z * 0.9
                return g.t(lam + msin((u + v * 0.6) * 1.7) * 0.32, -0.02)
            }
            g.fold(sx - hw + 1, yc - 1.2, sx + hw - 1.6, yc + 1, highlight: false)
            if pose.cos > 0.3 {
                let kx = Rig.cx + (hw - 3.8) * (0.3 + pose.sin * 0.6)
                g.capsule(kx + 0.2, yc + 2.8, kx + 0.8, yc + 9.4, 1.5, 1.8) { lam, _, t, _, _ in
                    (t > 0.68 && t < 0.78) || (t > 0.88 && t < 0.97) ? (lam > 0.2 ? Hi : Lt) : g.t(lam)
                }
                g.ellipse(kx, yc + 2.2, 2.1, 2) { lam, _, _, _, _ in g.t(lam, 0.08) }
            } else if pose.cos < -0.3 {
                let a = pose.proj(2.4, pose.neckUp - 0.5, -5.2)
                g.ellipse(a.x, a.y + 0.6, 2.1, 1.9) { lam, _, _, _, _ in g.t(lam, 0.08) }
            }
        })
        return ItemDef(
            id: "scarf_navy", name: "深蓝围巾", slot: .scarf, palettes: ["main": navy],
            variants: [
                ItemVariant(id: "navy", name: "深蓝", palettes: ["main": navy]),
                ItemVariant(id: "crimson", name: "绯红", palettes: ["main": .ramp("scarf-crimson", "#a82838")]),
                ItemVariant(id: "cream", name: "米白", palettes: ["main": .ramp("scarf-cream", "#d8ccac")]),
                ItemVariant(id: "moss", name: "苔绿", palettes: ["main": .ramp("scarf-moss", "#527e38")]),
            ],
            parts: [part])
    }()

    // MARK: 棕色皮挎包

    static let satchel: ItemDef = {
        let leather = SpritePalette("satchel-leather", ["#1e1008", "#583216", "#8e5828", "#bc8442", "#eabc64"])
        let brass = SpritePalette("satchel-brass", ["#3e2408", "#8a5c16", "#d8a430", "#f6d86c", "#fff6c0"])
        func pouchAt(_ c: DrawContext) -> SpritePoint {
            let j = c.pose.proj(-4, c.pose.neckUp - 12.6, 2.4, 0.1)
            return SpritePoint(x: j.x, y: j.y)
        }
        let pouchLayer = PartLayer.dynamic { c in c.dir == .N ? .cape : .bag }
        let buckle = ["43", "31"]
        let strap = PartDef(layer: .fixed(.bag), draw: { c in
            let g = c.g, pose = c.pose
            let a = pose.proj(5.4, pose.neckUp + 0.4, 0, 0)
            let b = pouchAt(c)
            c.pal("main")
            g.capsule(a.x, a.y, b.x, b.y - 3, 0.8, 0.8) { _, o, _, _, _ in o < -0.2 ? Lt : o > 0.45 ? O : D }
        })
        let pouch = PartDef(layer: pouchLayer, draw: { c in
            let g = c.g
            let p = pouchAt(c)
            let hw = 3.9 - abs(c.pose.sin) * 0.9, hh = 3.7
            c.pal("main")
            g.anchor(p.x, p.y)
            g.grit = 0.24
            g.fill(p.x - hw, p.y - hh, p.x + hw, p.y + hh) { u, v in
                let nx = (u - p.x) / hw, ny = (v - p.y) / hh
                if pow(nx, 4) + pow(ny, 4) > 1 { return -1 }
                let lam = nx * Light.x + (1 - nx * nx).squareRoot() * Light.z
                let flap = -0.05 + 0.3 * mcos(nx * 1.4)
                if ny < flap { return ny > flap - 0.2 ? D : g.t(lam, 0.3) }
                return g.t(lam, -0.3)
            }
            g.clip = true
            g.line(p.x - hw + 0.8, p.y + hh - 0.7, p.x + hw - 0.8, p.y + hh - 0.7, BrushOp.darken)
            g.clip = false
        })
        let clasp = PartDef(layer: pouchLayer, frames: [.S: buckle, .SE: buckle, .E: buckle, .NE: buckle],
                            anchor: pouchAt, offset: (-1, 0), paletteKey: "metal", outline: false)
        return ItemDef(
            id: "bag_satchel", name: "棕色皮挎包", slot: .bag, palettes: ["main": leather, "metal": brass],
            variants: [
                ItemVariant(id: "leather", name: "棕皮", palettes: ["main": leather]),
                ItemVariant(id: "olive", name: "橄榄帆布", palettes: ["main": .ramp("satchel-olive", "#70703a")]),
            ],
            parts: [strap, pouch, clasp])
    }()
}
