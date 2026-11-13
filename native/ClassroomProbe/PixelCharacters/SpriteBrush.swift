import Foundation

// 人物像素精灵：画笔。与 hd2d-walk-demo/src/pixel/Brush.ts 对应。
// 在「单位坐标」（64×96 的画布）里画连续形状，每个像素取中心点求值：
// 形状内外、表面法线 → 左上方光照 → 量化到调色板的明暗阶。

struct SpritePoint {
    var x: Double
    var y: Double
}

enum SpriteLight {
    /// 光源方向（指向光源，左上偏前）
    static let x = -0.56, y = -0.62, z = 0.55
}

/// 特殊「颜色」：对已有像素做相对操作
enum BrushOp {
    static let darken = -10.0
    static let lighten = -11.0
    static let erase = -12.0
}

private let toneX: [Double] = [-1.03, -0.41, 0.21, 0.71, 1.09]

/// 光照强度（约 −1…1）→ 连续的明暗阶 0…4
func shadeOf(_ v: Double) -> Double {
    if v <= toneX[0] { return Shade.outline }
    for i in 1..<5 where v < toneX[i] {
        return Double(i - 1) + (v - toneX[i - 1]) / (toneX[i] - toneX[i - 1])
    }
    return Shade.hi
}

/// 量化到最近的 1/4 阶（不抖动）
func spriteTone(_ lam: Double, _ bias: Double = 0) -> Double {
    jsRound(shadeOf(lam + bias) * Shade.sub) / Shade.sub
}

/// 4×4 Bayer 有序抖动阈值
private let bayer: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { ($0 + 0.5) / 16 }

/// 整数格点上的哈希噪声，0…1（与 JS 的 Math.imul / >>> 位运算一致）
private func hash2(_ x: Int, _ y: Int) -> Double {
    var n = Int32(truncatingIfNeeded: x) &* 374761393 &+ Int32(truncatingIfNeeded: y) &* 668265263
    n = (n ^ Int32(bitPattern: UInt32(bitPattern: n) >> 13)) &* 1274126177
    let r = UInt32(bitPattern: n ^ Int32(bitPattern: UInt32(bitPattern: n) >> 16))
    return Double(r) / 4294967295
}

final class SpriteBrush {
    let L: PixelLayer
    let S: Double
    /// 为 true 时只在本层已有像素上作画（衣褶、纽扣等细节）
    var clip = false
    /// 粗粝度：量化前给光照加的噪声幅度
    var grit = 0.16
    /// 是否在相邻两档色之间做有序抖动
    var dither = true
    /// 自上而下的整体光照渐变幅度
    var vgrad = 0.24

    private var ax = 0, ay = 0, ci = 0, cj = 0

    init(_ L: PixelLayer, _ S: Double) {
        self.L = L
        self.S = S
    }

    /// 噪声纹理的原点（单位坐标），设在会动的关节上，纹理跟着肢体走
    func anchor(_ u: Double, _ v: Double) {
        ax = Int(jsRound(u * S))
        ay = Int(jsRound(v * S))
    }

    private func noise() -> Double {
        let x = ci - ax, y = cj - ay
        let cell = max(2.0, jsRound(2.6 * S))
        let gxD = (Double(x) / cell).rounded(.down), gyD = (Double(y) / cell).rounded(.down)
        let fx = Double(x) / cell - gxD, fy = Double(y) / cell - gyD
        let gx = Int(gxD), gy = Int(gyD)
        let a = hash2(gx, gy), b = hash2(gx + 1, gy), c = hash2(gx, gy + 1), d = hash2(gx + 1, gy + 1)
        let blotch = a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy
        return (blotch * 2 - 1) * 0.85 + (hash2(x + 31, y - 17) * 2 - 1) * 0.22
    }

    /// 带粗粝感的量化：光照 + 斑块噪声 → 连续明暗阶 → 按 Bayer 阈值落到相邻两档之一
    func t(_ lam: Double, _ bias: Double = 0) -> Double {
        let vert = vgrad * (1 - (2 * Double(cj)) / Double(L.h))
        let x = shadeOf(lam + bias + vert + noise() * grit) * Shade.sub
        if !dither { return jsRound(x) / Shade.sub }
        let i = (((ci - ax) % 4) + 4) % 4, j = (((cj - ay) % 4) + 4) % 4
        return min(4 * Shade.sub, (x + bayer[j * 4 + i]).rounded(.down)) / Shade.sub
    }

    private func put(_ i: Int, _ j: Int, _ s: Double) {
        if i < 0 || j < 0 || i >= L.w || j >= L.h { return }
        let has = L.idx[j * L.w + i] > 0
        if s == BrushOp.darken { if has { L.reshade(i, j, -1) }; return }
        if s == BrushOp.lighten { if has { L.reshade(i, j, 1) }; return }
        if s == BrushOp.erase { L.px(Double(i), Double(j), -1); return }
        if s < 0 { return }
        if clip && !has { return }
        L.px(Double(i), Double(j), s)
    }

    /// 对单位坐标包围盒内的每个像素中心求值。fn 返回明暗阶，−1 跳过。
    func fill(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ fn: (Double, Double) -> Double) {
        let i0 = max(0, Int((x0 * S).rounded(.down))), i1 = min(L.w - 1, Int((x1 * S).rounded(.up)))
        let j0 = max(0, Int((y0 * S).rounded(.down))), j1 = min(L.h - 1, Int((y1 * S).rounded(.up)))
        if i0 > i1 || j0 > j1 { return }
        for j in j0...j1 {
            for i in i0...i1 {
                ci = i
                cj = j
                let s = fn((Double(i) + 0.5) / S, (Double(j) + 0.5) / S)
                if s != -1 { put(i, j, s) }
            }
        }
    }

    /// 椭球：shade(lam, nx, ny, u, v)
    func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double,
                 _ shade: (Double, Double, Double, Double, Double) -> Double) {
        fill(cx - rx, cy - ry, cx + rx, cy + ry) { u, v in
            let nx = (u - cx) / rx, ny = (v - cy) / ry
            let d = nx * nx + ny * ny
            if d > 1 { return -1 }
            return shade(nx * SpriteLight.x + ny * SpriteLight.y + (1 - d).squareRoot() * SpriteLight.z, nx, ny, u, v)
        }
    }

    func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, flat: Double) {
        ellipse(cx, cy, rx, ry) { _, _, _, _, _ in flat }
    }

    /// 胶囊体：shade(lam, o, t, u, v)；o ∈ [−1,1] 横向位置（朝右下为正），t 沿轴 0…1
    func capsule(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ ra: Double, _ rb: Double,
                 _ shade: (Double, Double, Double, Double, Double) -> Double) {
        let dx = bx - ax, dy = by - ay
        var len2 = dx * dx + dy * dy
        if len2 == 0 { len2 = 1e-6 }
        let len = len2.squareRoot()
        var px = -dy / len, py = dx / len
        if px + py < 0 { px = -px; py = -py }
        let pl = px * SpriteLight.x + py * SpriteLight.y
        let r = max(ra, rb)
        fill(min(ax, bx) - r, min(ay, by) - r, max(ax, bx) + r, max(ay, by) + r) { u, v in
            let t = ((u - ax) * dx + (v - ay) * dy) / len2
            let tc = max(0, min(1, t))
            let rr = ra + (rb - ra) * tc
            let ex = u - (ax + dx * tc), ey = v - (ay + dy * tc)
            if ex * ex + ey * ey > rr * rr { return -1 }
            let o = max(-1, min(1, (ex * px + ey * py) / rr))
            return shade(o * pl + (1 - o * o).squareRoot() * SpriteLight.z, o, t, u, v)
        }
    }

    /// 沿折线的带子（发束），halfW(s) 给出 s ∈ [0,1] 处的半宽；shade(lam, o, s, u, v)
    func ribbon(_ pts: [SpritePoint], halfW: (Double) -> Double,
                _ shade: (Double, Double, Double, Double, Double) -> Double) {
        let n = pts.count - 1
        if n < 1 { return }
        var cum = [0.0]
        for i in 0..<n { cum.append(cum[i] + hypot(pts[i + 1].x - pts[i].x, pts[i + 1].y - pts[i].y)) }
        let total = cum[n] == 0 ? 1e-6 : cum[n]
        var x0 = Double.infinity, y0 = Double.infinity, x1 = -Double.infinity, y1 = -Double.infinity, wmax = 0.0
        for i in 0...n {
            x0 = min(x0, pts[i].x); x1 = max(x1, pts[i].x)
            y0 = min(y0, pts[i].y); y1 = max(y1, pts[i].y)
            wmax = max(wmax, halfW(cum[i] / total))
        }
        wmax = max(wmax, halfW(0.5)) * 1.15
        fill(x0 - wmax, y0 - wmax, x1 + wmax, y1 + wmax) { u, v in
            var best = Double.infinity, bs = 0.0, bo = 0.0, bl = 0.0
            for i in 0..<n {
                let a = pts[i], b = pts[i + 1]
                let dx = b.x - a.x, dy = b.y - a.y
                var l2 = dx * dx + dy * dy
                if l2 == 0 { l2 = 1e-6 }
                let tc = max(0, min(1, ((u - a.x) * dx + (v - a.y) * dy) / l2))
                let ex = u - (a.x + dx * tc), ey = v - (a.y + dy * tc)
                let d = ex * ex + ey * ey
                if d >= best { continue }
                best = d
                let l = l2.squareRoot()
                var px = -dy / l, py = dx / l
                if px + py < 0 { px = -px; py = -py }
                bs = (cum[i] + l * tc) / total
                bo = ex * px + ey * py
                bl = px * SpriteLight.x + py * SpriteLight.y
            }
            let hw = halfW(bs)
            if hw <= 0 || best > hw * hw { return -1 }
            let o = max(-1, min(1, bo / hw))
            return shade(o * bl + (1 - o * o).squareRoot() * SpriteLight.z, o, bs, u, v)
        }
    }

    /// 沿某个方向的局部坐标系作画（武器）：fn(t, o)
    func axis(_ x: Double, _ y: Double, _ dx: Double, _ dy: Double,
              _ t0: Double, _ t1: Double, _ half: Double, _ fn: (Double, Double) -> Double) {
        var px = -dy, py = dx
        if px + py < 0 { px = -px; py = -py }
        let xa = x + dx * t0, xb = x + dx * t1, ya = y + dy * t0, yb = y + dy * t1
        fill(min(xa, xb) - half, min(ya, yb) - half, max(xa, xb) + half, max(ya, yb) + half) { u, v in
            let t = (u - x) * dx + (v - y) * dy
            let o = (u - x) * px + (v - y) * py
            return t < t0 || t > t1 || abs(o) > half ? -1 : fn(t, o)
        }
    }

    /// 三角形
    func tri(_ a: SpritePoint, _ b: SpritePoint, _ c: SpritePoint, _ shade: Double) {
        func sign(_ p: SpritePoint, _ q: SpritePoint, _ u: Double, _ v: Double) -> Double {
            (u - q.x) * (p.y - q.y) - (p.x - q.x) * (v - q.y)
        }
        fill(min(a.x, b.x, c.x), min(a.y, b.y, c.y), max(a.x, b.x, c.x), max(a.y, b.y, c.y)) { u, v in
            let d1 = sign(a, b, u, v), d2 = sign(b, c, u, v), d3 = sign(c, a, u, v)
            let neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0
            return neg && pos ? -1 : shade
        }
    }

    /// 轴对齐矩形（单位坐标）
    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ shade: (Double, Double) -> Double) {
        fill(x, y, x + w, y + h) { u, v in
            u < x || u > x + w || v < y || v > y + h ? -1 : shade(u, v)
        }
    }

    /// 一像素宽的线（Bresenham）
    func line(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ shade: Double) {
        var x0 = Int((ax * S).rounded(.down)), y0 = Int((ay * S).rounded(.down))
        let x1 = Int((bx * S).rounded(.down)), y1 = Int((by * S).rounded(.down))
        let dx = abs(x1 - x0), dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        while true {
            put(x0, y0, shade)
            if x0 == x1 && y0 == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x0 += sx }
            if e2 <= dx { err += dx; y0 += sy }
        }
    }

    var defaultCell: Int { max(1, Int(jsRound(S))) }

    /// 贴一个小图案：每个字符一格，'.' 为空，'0'…'4' 为明暗阶；一格 = cell×cell 像素
    func cells(_ rows: [String], _ u: Double, _ v: Double, cell: Int? = nil) {
        let c = cell ?? defaultCell
        let i0 = Int((u * S).rounded(.down)), j0 = Int((v * S).rounded(.down))
        for (r, row) in rows.enumerated() {
            for (k, ch) in row.enumerated() {
                guard let d = ch.wholeNumberValue, d >= 0, d <= 4 else { continue }
                for b in 0..<c { for a in 0..<c { put(i0 + k * c + a, j0 + r * c + b, Double(d)) } }
            }
        }
    }

    /// 同 cells，但位置直接给像素坐标
    func cellsPx(_ rows: [String], _ i0: Int, _ j0: Int, cell: Int? = nil) {
        cells(rows, (Double(i0) + 0.01) / S, (Double(j0) + 0.01) / S, cell: cell)
    }

    /// 一个像素
    func dot(_ u: Double, _ v: Double, _ shade: Double) {
        put(Int((u * S).rounded(.down)), Int((v * S).rounded(.down)), shade)
    }

    /// 一道衣褶：一条暗线，受光侧贴一条亮线。只画在已有像素上。
    func fold(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, highlight: Bool = true) {
        let was = clip
        clip = true
        line(ax, ay, bx, by, BrushOp.darken)
        if highlight {
            let o = 1 / S
            line(ax - o, ay - o, bx - o, by - o, BrushOp.lighten)
        }
        clip = was
    }
}
