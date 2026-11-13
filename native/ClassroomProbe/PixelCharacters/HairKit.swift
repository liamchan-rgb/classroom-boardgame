import Foundation

// 人物像素精灵：发型引擎。与 hd2d-walk-demo/src/items/kits/hairKit.ts 对应。
// 发型是纯数据：Resources/CharacterParts/hair/*.json，网页工具和这里读同一份文件。

struct PaletteVariantData: Decodable {
    let id: String
    let name: String
    let palette: [String]?
    let base: String?

    func make(_ paletteId: String) -> SpritePalette {
        if let palette { return SpritePalette(paletteId, palette) }
        return .ramp(paletteId, base ?? "#808080")
    }
}

struct HairData: Decodable {
    struct Lock: Decodable {
        let phi: Double
        let a0: Double?
        let a1: Double
        let twist: Double?
        let flick: Double?
        let lift: Double?
        let width: Double
        let tier: Int?
    }
    let id: String
    let name: String
    let palette: [String]
    let variants: [PaletteVariantData]?
    /// 发际线：[[方位绝对值, 纬度], …]
    let hairline: [[Double]]
    let locks: [Lock]
}

enum HairKit {
    private struct Lock {
        let phi, a0, a1, twist, flick, lift, width: Double
        let tier: Int
    }

    private struct Proj {
        let x, y, near: Double
    }

    /// 发型整体相对头的大小
    private static let hs = SpriteRig.headRX / 10.4
    private static let rx = 11.6 * hs, ry = 11 * hs
    /// 前后方向的半径：比左右窄，侧面看头才是圆的
    private static let rz = 10.2 * hs
    private static let tilt = 18 * Double.pi / 180
    private static let ct = mcos(tilt), st = msin(tilt)
    private static let rad = Double.pi / 180

    /// 发际线分段线性插值
    static func hairlineAt(_ points: [[Double]], _ phiAbs: Double) -> Double {
        for i in 0..<(points.count - 1) {
            let p0 = points[i][0], a0 = points[i][1], p1 = points[i + 1][0], a1 = points[i + 1][1]
            if phiAbs < p1 { return p1 == p0 ? a1 : a0 + ((phiAbs - p0) / (p1 - p0)) * (a1 - a0) }
        }
        return points[points.count - 1][1]
    }

    private static func project(_ pose: CharacterPose, _ cx: Double, _ cy: Double,
                                _ alphaDeg: Double, _ phiDeg: Double, _ rho: Double) -> Proj {
        let a = alphaDeg * rad, p = phiDeg * rad
        let w = cos(a), f = sin(a) * cos(p), s = sin(a) * sin(p)
        let fz = (f * rz) / rx
        let X = s * pose.cos + fz * pose.sin
        let n = fz * pose.cos - s * pose.sin
        return Proj(x: cx + rx * rho * X, y: cy - ry * rho * (w * ct - n * st), near: n * ct + w * st)
    }

    private static func lockPath(_ pose: CharacterPose, _ cx: Double, _ cy: Double, _ k: Lock, _ i: Int) -> [Proj] {
        var pts: [Proj] = []
        let swing = pose.walking ? sin(pose.phase * 2 + Double(i) * 1.3) : 0
        for n in 0...12 {
            let s = Double(n) / 12
            let rho = 1 + k.lift + (k.flick - 1 + swing * 0.03) * s * s * s
            pts.append(project(pose, cx, cy, k.a0 + (k.a1 - k.a0 + swing * 2.5) * s, k.phi + (k.twist + swing * 4) * s * s, rho))
        }
        return pts
    }

    /// 发束粗细：根部细，中段最粗，发梢收尖
    private static func profile(_ s: Double) -> Double {
        s < 0.55 ? 0.5 + 0.5 * (s / 0.55) : max(0, 1 - pow((s - 0.55) / 0.45, 1.7))
    }

    private static func drawLocks(_ c: DrawContext, _ locks: [Lock], _ hairline: [[Double]], back: Bool) {
        let g = c.g, pose = c.pose
        let cx = pose.head.x + pose.sin * 0.2, cy = pose.head.y - 1.2
        c.pal("main")
        g.grit = 0.1
        g.anchor(cx, cy)
        func headLight(_ u: Double, _ v: Double) -> Double { -((u - cx) / rx) * 0.62 + ((cy - v) / ry) * 0.7 }
        func ring(_ u: Double, _ v: Double) -> Bool {
            let x = (u - cx) / rx, y = (cy - v) / ry - 0.16 * x * x
            return y > 0.3 && y < 0.46 && headLight(u, v) > 0.12
        }

        if !back {
            // 发根底色：把像素反投影回球面，落在发际线以内的就是头发
            let rxView = hypot(rx * pose.cos, rz * pose.sin)
            g.fill(cx - rx, cy - ry, cx + rx, cy + ry) { u, v in
                let X = (u - cx) / rxView, a = (cy - v) / ry
                let q = 1 - X * X
                if q <= 0 || a * a > q { return -1 }
                let sq = q.squareRoot()
                let beta = acos(max(-1, min(1, a / sq))) - tilt
                let w = sq * cos(beta), n = sq * sin(beta)
                let s = X * pose.cos - n * pose.sin, f = X * pose.sin + n * pose.cos
                let alpha = acos(max(-1, min(1, w))) / rad
                let phi = abs(atan2(s, f)) / rad
                if alpha >= hairlineAt(hairline, phi) { return -1 }
                return ring(u, v) ? Shade.light : g.t(headLight(u, v) * 0.9 - 0.55)
            }
        }

        // 按深度从远到近排；深度相同的保持原顺序（与网页端的稳定排序一致）
        struct Item {
            let lock: Lock
            let pts: [Proj]
            let depth: Double
            let index: Int
        }
        var items: [Item] = []
        for (i, k) in locks.enumerated() {
            let pts = lockPath(pose, cx, cy, k, i)
            if (pts[8].near < -0.12) != back { continue }
            items.append(Item(lock: k, pts: pts, depth: pts[8].near + Double(k.tier) * 0.6, index: i))
        }
        items.sort { $0.depth != $1.depth ? $0.depth < $1.depth : $0.index < $1.index }

        for item in items {
            let k = item.lock, pts = item.pts
            let points = pts.map { SpritePoint(x: $0.x, y: $0.y) }
            g.ribbon(points, halfW: { s in k.width * hs * profile(s) }) { lam, o, s, u, v in
                if k.tier == 2 { return o > 0.2 ? Shade.dark : s > 0.5 ? Shade.light : Shade.base }
                let gl = headLight(u, v)
                var sh = g.t(gl * 0.95 + lam * 0.3 - 0.22 + (back ? -0.45 : 0))
                if ring(u, v) && o < 0.6 { sh = gl > 0.42 ? Shade.hi : max(sh + 1, Shade.light + 0.5) }
                if o > 0.72 && s > 0.25 { sh = max(Shade.outline + 0.5, sh - 1.5) }
                if s > 0.9 { sh = max(Shade.dark, sh - 0.5) }
                return sh
            }
        }
    }

    static func make(_ d: HairData) -> ItemDef {
        let locks = d.locks.map {
            Lock(phi: $0.phi, a0: $0.a0 ?? 5, a1: $0.a1, twist: $0.twist ?? 0, flick: $0.flick ?? 1.06,
                 lift: $0.lift ?? 0, width: $0.width, tier: $0.tier ?? 0)
        }
        let variants = (d.variants ?? []).map {
            ItemVariant(id: $0.id, name: $0.name, palettes: ["main": $0.make("\(d.id)-\($0.id)")])
        }
        let hairline = d.hairline
        return ItemDef(
            id: d.id, name: d.name, slot: .hair,
            palettes: ["main": SpritePalette("\(d.id)-main", d.palette)],
            variants: variants,
            parts: [
                PartDef(layer: .fixed(.hairBack), draw: { c in drawLocks(c, locks, hairline, back: true) }),
                PartDef(layer: .fixed(.hair), draw: { c in drawLocks(c, locks, hairline, back: false) }),
            ])
    }
}
