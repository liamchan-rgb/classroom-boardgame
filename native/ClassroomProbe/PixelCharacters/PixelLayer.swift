import Foundation

// 人物像素精灵：索引色图层。与 hd2d-walk-demo/src/pixel/PixelLayer.ts 对应。
// 每个像素存「调色板编号 + 明暗阶」，不存 RGB —— 形状与颜色彻底分离，换色只换调色板。

final class PixelLayer {
    let w: Int
    let h: Int
    /// 0 = 空；否则 = shade × 4 + 1
    var idx: [UInt8]
    /// 该像素使用的调色板在 palettes 中的下标
    var pid: [UInt8]
    private(set) var palettes: [SpritePalette] = []
    private var cur = 0

    private static let outCode = Shade.code(Shade.outline)
    private static let softCode = Shade.code(Shade.softOutline)

    init(_ w: Int, _ h: Int) {
        self.w = w
        self.h = h
        idx = [UInt8](repeating: 0, count: w * h)
        pid = [UInt8](repeating: 0, count: w * h)
    }

    func clear() {
        for i in idx.indices { idx[i] = 0 }
        palettes.removeAll(keepingCapacity: true)
        cur = 0
    }

    private func index(of p: SpritePalette) -> Int {
        if let i = palettes.firstIndex(where: { $0 === p }) { return i }
        palettes.append(p)
        return palettes.count - 1
    }

    /// 选择后续绘制使用的调色板
    func use(_ p: SpritePalette) { cur = index(of: p) }

    /// 画一个像素；shade < 0 表示擦除
    func px(_ x0: Double, _ y0: Double, _ shade: Double) {
        let x = Int(jsRound(x0)), y = Int(jsRound(y0))
        if x < 0 || y < 0 || x >= w || y >= h { return }
        let i = y * w + x
        if shade < 0 { idx[i] = 0; return }
        idx[i] = Shade.code(shade)
        pid[i] = UInt8(cur)
    }

    /// 把已有像素调亮 / 调暗 delta 阶（限制在 暗部…高光 之间）
    func reshade(_ x: Int, _ y: Int, _ delta: Double) {
        if x < 0 || y < 0 || x >= w || y >= h { return }
        let i = y * w + x
        if idx[i] == 0 { return }
        let v = Double(idx[i] - 1) / Shade.sub
        if v < Shade.dark || v > Shade.hi { return }
        idx[i] = Shade.code(max(Shade.dark, min(Shade.hi, v + delta)))
    }

    func has(_ x: Int, _ y: Int) -> Bool { idx[y * w + x] > 0 }

    /// 自动 1px 外描边：受光侧（只挨着右 / 下的形状）用浅描边，其余用深描边
    func outline() {
        let src = idx
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if src[i] != 0 { continue }
                let left = x > 0 && src[i - 1] > 0
                let up = y > 0 && src[i - w] > 0
                let right = x < w - 1 && src[i + 1] > 0
                let down = y < h - 1 && src[i + w] > 0
                if !left && !up && !right && !down { continue }
                let lit = !left && !up
                idx[i] = Shade.code(lit ? Shade.softOutline : Shade.outline)
                pid[i] = pid[left ? i - 1 : up ? i - w : right ? i + 1 : i + w]
            }
        }
    }

    /// 背光侧反光：贴着右缘 / 下缘轮廓的暗部像素提亮一点。在描边之前调用。
    func bounce(amount: Double = 0.5, lo: Double = 0.6, hi: Double = 1.9) {
        let src = idx
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if src[i] == 0 { continue }
                let edge = (x == w - 1 || src[i + 1] == 0) || (y == h - 1 || src[i + w] == 0)
                if !edge { continue }
                let v = Double(src[i] - 1) / Shade.sub
                if v < lo || v > hi { continue }
                idx[i] = Shade.code(min(hi, v + amount))
            }
        }
    }

    /// 接触阴影：src（刚画好的上层部件）在本层投下朝右下的柔和阴影。
    /// 用 Float 存压暗量，和网页端的 Float32Array 一致。
    func castShadow(_ src: PixelLayer, taps: [(Int, Int, Double)]) {
        var dark = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let v = src.idx[y * w + x]
                if v == 0 || v == Self.outCode || v == Self.softCode { continue }
                for (dx, dy, k) in taps {
                    let tx = x + dx, ty = y + dy
                    if tx < 0 || ty < 0 || tx >= w || ty >= h { continue }
                    let ti = ty * w + tx
                    if Double(dark[ti]) < k { dark[ti] = Float(k) }
                }
            }
        }
        for i in 0..<dark.count {
            if dark[i] == 0 || src.idx[i] != 0 || idx[i] == 0 { continue }
            let v = Double(idx[i] - 1) / Shade.sub
            if v <= Shade.outline + 0.25 || v > Shade.hi { continue }
            idx[i] = Shade.code(max(0.25, v - Double(dark[i])))
        }
    }

    /// 把本层盖到 dst 上。
    /// innerLine：本层描边落在 dst 本体像素上时（部件之间的内部线条）改用本部件的暗色；
    /// maskBelow：只写在 dst 已有的本体像素上（五官等贴在表面的细节）。
    func draw(onto dst: PixelLayer, innerLine: Double? = nil, maskBelow: Bool = false) {
        let out = Self.outCode, soft = Self.softCode
        let map = palettes.map { dst.index(of: $0) }
        for i in 0..<(w * h) {
            let v = idx[i]
            if v == 0 { continue }
            let under = dst.idx[i]
            if maskBelow && (under == 0 || under == out || under == soft) { continue }
            if let inner = innerLine, v == out || v == soft, under != 0, under != out, under != soft {
                dst.idx[i] = Shade.code(v == out ? inner : inner + 0.5)
            } else {
                dst.idx[i] = v
            }
            dst.pid[i] = UInt8(map[Int(pid[i])])
        }
    }

    /// 查表上色，写入 RGBA 缓冲（offset 开始，行宽 rowStride 个像素）
    func writeRGBA(into out: inout [UInt8], offsetX: Int = 0, offsetY: Int = 0, rowStride: Int? = nil, flip: Bool = false) {
        let stride = rowStride ?? w
        let tables = palettes.map { $0.rgbTable }
        for y in 0..<h {
            for x in 0..<w {
                let v = idx[y * w + x]
                if v == 0 { continue }
                let sx = flip ? w - 1 - x : x
                let o = ((offsetY + y) * stride + offsetX + sx) * 4
                let t = tables[Int(pid[y * w + x])]
                let c = Int(v - 1) * 3
                out[o] = t[c]; out[o + 1] = t[c + 1]; out[o + 2] = t[c + 2]; out[o + 3] = 255
            }
        }
    }
}
