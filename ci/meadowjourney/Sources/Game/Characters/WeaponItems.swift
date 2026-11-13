import Foundation

// 人物像素精灵：武器。与 items/weapon/*.ts 对应。按手部锚点（坐标 + 角度）绘制，
// 图层按方向和握持方式自动选择身前 / 头后 / 身后。

enum WeaponItems {
    private static let D = Shade.dark, B = Shade.base, Lt = Shade.light, Hi = Shade.hi

    static let shortSword: ItemDef = {
        let steel = SpritePalette("steel", ["#141a28", "#56647e", "#a0b0c6", "#dce8f2", "#ffffff"])
        let hilt = SpritePalette("hilt-gold", ["#3e2408", "#8a5c16", "#d8a430", "#f6d86c", "#fff6c0"])
        let grip = SpritePalette("grip-leather", ["#140a06", "#34200f", "#583820", "#80542e", "#aa7a48"])
        let part = PartDef(layer: .weapon, draw: { c in
            guard let h = c.hand else { return }
            let g = c.g
            let dx = cos(h.angle), dy = sin(h.angle)
            let x = h.x, y = h.y + 0.6
            c.pal("blade")
            g.axis(x, y, dx, dy, 3.8, 19.5, 1.2) { t, o in
                let hw = t < 15.5 ? 1.15 : (1.15 * (19.5 - t)) / 4
                if abs(o) > hw { return -1 }
                if o < -0.15 { return t > 7 && t < 14 ? Hi : Lt }
                return o > 0.55 ? D : B
            }
            c.pal("grip")
            g.axis(x, y, dx, dy, -2.4, 3, 0.75) { t, o in
                o > 0.3 ? D : (Int((t * 1.2 + 10).rounded(.down)) % 2 != 0 ? B : Lt)
            }
            c.pal("hilt")
            g.axis(x, y, dx, dy, 2.6, 4.2, 3.3) { t, o in
                let bend = 0.2 * abs(o)
                if t < 2.7 + bend || t > 3.9 + bend { return -1 }
                return o < -1.6 ? Hi : o > 1.8 ? D : Lt
            }
            g.ellipse(x - dx * 3.2, y - dy * 3.2, 1.2, 1.2) { lam, _, _, _, _ in lam > 0.4 ? Hi : lam > -0.2 ? B : D }
        })
        return ItemDef(id: "weapon_short_sword", name: "短剑", slot: .weaponMain,
                       palettes: ["blade": steel, "hilt": hilt, "grip": grip], parts: [part], hold: .down)
    }()

    static let staff: ItemDef = {
        let wood = SpritePalette("staff-wood", ["#180e08", "#4a2e18", "#7c522a", "#aa7a40", "#d4a460"])
        let gold = SpritePalette("staff-gold", ["#3e2408", "#8a5c16", "#d8a430", "#f6d86c", "#fff6c0"])
        let gem = SpritePalette("staff-gem", ["#082a44", "#147aa0", "#30c2dc", "#90f0f4", "#f0ffff"])
        let part = PartDef(layer: .weapon, draw: { c in
            guard let h = c.hand else { return }
            let g = c.g
            let dx = cos(h.angle), dy = sin(h.angle)
            let x = h.x, y = h.y + 0.6
            c.pal("wood")
            g.axis(x, y, dx, dy, -11, 34.5, 0.75) { t, o in
                if t > -2 && t < 2.8 { return o > 0.2 ? D : (Int((t * 1.2 + 10).rounded(.down)) % 2 != 0 ? B : Lt) }
                let knot = abs((t + 40).truncatingRemainder(dividingBy: 7) - 3.5) < 0.5
                return o < 0 ? (knot ? B : Lt) : D
            }
            c.pal("gold")
            g.axis(x, y, dx, dy, 33.6, 35.6, 1.2) { _, o in o < -0.4 ? Hi : o > 0.5 ? D : Lt }
            g.axis(x, y, dx, dy, -12.4, -11, 1.05) { _, o in o < 0 ? Lt : D }
            let ox = x + dx * 40, oy = y + dy * 40
            g.fill(ox - 6, oy - 6, ox + 6, oy + 6) { u, v in
                let ex = u - ox, ey = v - oy
                let d = hypot(ex, ey)
                let along = (ex * dx + ey * dy) / (d == 0 ? 1 : d)
                let half = 0.8 * max(0, 1 - max(0, along + 0.2) * 1.1)
                if abs(d - 4.2) > half || along > 0.62 { return -1 }
                let lit = -(ex * 0.56 + ey * 0.62) / d
                return lit > 0.55 ? Hi : lit > 0 ? Lt : lit > -0.6 ? B : D
            }
            c.pal("gem")
            g.ellipse(ox, oy, 2.7, 2.7) { lam, _, _, _, _ in lam > 0.8 ? Hi : lam > 0.4 ? Lt : lam > -0.15 ? B : D }
            g.dot(ox - 1, oy - 1.1, Hi)
            g.dot(ox + dx * 4.5 - dy * 2.4, oy + dy * 4.5 + dx * 2.4, Hi)
            g.dot(ox - dy * 5 + dx, oy + dx * 5 + dy, Lt)
        })
        return ItemDef(id: "weapon_staff", name: "法杖", slot: .weaponMain,
                       palettes: ["wood": wood, "gold": gold, "gem": gem],
                       variants: [
                           ItemVariant(id: "aqua", name: "水蓝宝珠", palettes: ["gem": gem]),
                           ItemVariant(id: "ember", name: "炽红宝珠", palettes: ["gem": .ramp("staff-gem-ember", "#e8552c")]),
                           ItemVariant(id: "violet", name: "紫晶宝珠", palettes: ["gem": .ramp("staff-gem-violet", "#9a5ce0")]),
                       ],
                       parts: [part])
    }()
}
