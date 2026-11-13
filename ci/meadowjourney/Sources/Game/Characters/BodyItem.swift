import Foundation

// 人物像素精灵：身体底模（皮肤、脸型、耳朵）。与 items/body.ts 对应。五官在 face 槽位（FaceKit）。

enum BodyItem {
    static let skin = SpritePalette("skin", ["#4a2620", "#a86450", "#dc9e7c", "#f4caa2", "#fff0d6"])

    /// 可选肤色
    static let skinTones: [String: SpritePalette] = [
        "fair": skin,
        "light": SpritePalette("skin-light", ["#54302a", "#bc7c66", "#eab896", "#fadcbe", "#fff4e4"]),
        "tan": SpritePalette("skin-tan", ["#3a1e14", "#8a4e34", "#c07a52", "#e0a476", "#f6d0a8"]),
        "deep": SpritePalette("skin-deep", ["#24120c", "#5a3020", "#8a5236", "#b47a54", "#dcaa82"]),
    ]

    private static func arm(_ side: Side) -> PartDef {
        PartDef(layer: ItemHelpers.armLayer(side), draw: { c in
            let g = c.g
            let a = ItemHelpers.arm(c, side)
            let fb = ItemHelpers.farBias(c, a.hand.near)
            g.grit = 0.08
            c.pal("skin")
            ItemHelpers.drawArm(c, side, [1.6, 1.45, 1.3])
            g.ellipse(a.hand.x, a.hand.y + 0.7, 1.7, 1.8) { lam, _, _, _, _ in g.t(lam, fb - 0.05) }
        })
    }

    private static func head(_ c: DrawContext) {
        let g = c.g, pose = c.pose, dir = c.dir
        let hx = pose.head.x + pose.sin * 0.9, hy = pose.head.y
        let rx0 = Rig.headRX, ry0 = Rig.headRY
        g.grit = 0.07
        g.anchor(hx, hy)
        c.pal("skin")
        // 脖子：整个在下巴的阴影里
        let nx0 = pose.head.x - pose.sin * 0.6
        g.rect(nx0 - 1.9, hy + 7, 3.8, 5.2) { _, v in v < hy + 10.4 ? Shade.outline : Shade.dark }
        // 圆脸：下巴几乎不收窄，下半张脸短一点
        g.fill(hx - rx0 - 1, hy - ry0 - 1, hx + rx0 + 1, hy + ry0 + 1) { u, v in
            let dx = u - hx, dy = v - hy
            let lower = dy > 0
            let rx = lower ? rx0 * (1.05 - 0.05 * (dy / ry0) * (dy / ry0)) : rx0
            let ry = lower ? ry0 * 0.84 : ry0
            let nx = dx / rx, ny = dy / ry
            let shape = lower ? pow(abs(nx), 2) + pow(abs(ny), 2.3) : nx * nx + ny * ny
            if shape > 1 { return -1 }
            let d = min(1, nx * nx + ny * ny)
            let lam = nx * Light.x + ny * Light.y + (1 - d).squareRoot() * Light.z
            if dy < -3.4 { return Shade.dark }
            return max(Shade.dark, min(Shade.light, g.t(lam * 0.62, 0.2)))
        }
        g.clip = true
        if dir == .E {
            c.pal("skin")
            g.dot(hx + rx0 - 1.4, hy + 4.4, Shade.dark)
            g.ellipse(hx - 0.8, hy + 2.6, 1.6, 2.2) { lam, _, _, _, _ in lam > 0.3 ? Shade.base : Shade.dark }
            g.dot(hx - 0.8, hy + 2.6, Shade.dark)
        } else if dir == .NE {
            g.ellipse(hx + 6.8, hy + 2.6, 1.3, 2.1) { lam, _, _, _, _ in lam > 0.3 ? Shade.base : Shade.dark }
        }
        g.clip = false
    }

    static let body = ItemDef(
        id: "body", name: "身体", slot: nil, palettes: ["skin": skin],
        parts: [
            arm(.L),
            arm(.R),
            PartDef(layer: .fixed(.legs), draw: { c in
                let g = c.g
                g.grit = 0.08
                c.pal("skin")
                for leg in c.pose.legs {
                    let fb = ItemHelpers.farBias(c, leg.foot.near)
                    g.capsule(leg.hip.x, leg.hip.y, leg.foot.x, leg.foot.y - 1.5, 2.2, 1.8) { lam, _, _, _, _ in g.t(lam, fb) }
                }
            }),
            PartDef(layer: .fixed(.torso), draw: { c in
                c.g.grit = 0.08
                c.pal("skin")
                ItemHelpers.torsoShape(c, rows: 12.5, flare: 0, pad: -0.3) { lam, _, _, _, _ in c.g.t(lam) }
            }),
            PartDef(layer: .fixed(.head), draw: head),
        ])
}
