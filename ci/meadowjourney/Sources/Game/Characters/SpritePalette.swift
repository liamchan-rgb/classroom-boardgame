import Foundation

// 人物像素精灵：调色板。
// 与 hd2d-walk-demo/src/pixel/palette.ts 逐行对应，两端出图必须一致；改动时两边一起改。

/// 明暗阶：0 描边、1 暗部、2 主色、3 亮部、4 高光；5 是自动派生的浅描边（受光侧）。
enum Shade {
    static let outline = 0.0
    static let dark = 1.0
    static let base = 2.0
    static let light = 3.0
    static let hi = 4.0
    static let softOutline = 5.0
    /// 相邻两个手写色之间细分成几档：4 → 共 17 阶过渡
    static let sub = 4.0

    /// 明暗阶 → 图层里存的编号（1…17 是 17 阶色，21 是浅描边；0 留给空像素）
    static func code(_ shade: Double) -> UInt8 {
        UInt8(jsRound(shade * sub) + 1)
    }
}

/// JavaScript 的 Math.round：.5 一律往正无穷方向取整（Swift 默认是远离零）。
@inline(__always) func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

/// 一个部件的调色板：5 个手写色，从暗到亮。用引用比较身份（同一个对象 = 同一个调色板）。
final class SpritePalette {
    let id: String
    let colors: [String]
    private var table: [UInt8]?

    init(_ id: String, _ colors: [String]) {
        precondition(colors.count == 5, "palette \(id) needs 5 colors")
        self.id = id
        self.colors = colors
    }

    /// 由一个主色自动生成 5 阶色带：暗部偏冷、亮部偏暖。
    static func ramp(_ id: String, _ base: String) -> SpritePalette {
        let (r, g, b) = hexToRGB(base)
        let (h, s, l) = rgbToHSL(r, g, b)
        return SpritePalette(id, [
            hslToHex(hueToward(h, 255, 22), s * 0.95 + 0.05, l * 0.36),
            hslToHex(hueToward(h, 255, 12), s * 1.02, l * 0.68),
            hslToHex(h, s, l),
            hslToHex(hueToward(h, 50, 8), s * 0.95, l + (1 - l) * 0.3),
            hslToHex(hueToward(h, 50, 14), s * 0.85, l + (1 - l) * 0.58),
        ])
    }

    /// RGB 字节表：下标 = shade × 4。手写五阶在 0、4、8、12、16，中间在 OKLab 里插值；下标 20 是浅描边。
    var rgbTable: [UInt8] {
        if let table { return table }
        let n = Int(Shade.softOutline * Shade.sub) + 1
        var out = [UInt8](repeating: 0, count: n * 3)
        let base = colors.map { c -> [Double] in let (r, g, b) = Self.hexToRGB(c); return Self.rgbToOklab(r, g, b) }
        let steps = Int(4 * Shade.sub)
        for i in 0...steps {
            let k = min(3, Int((Double(i) / Shade.sub).rounded(.down)))
            let f = Double(i) / Shade.sub - Double(k)
            let a = base[k], b = base[k + 1]
            let rgb = Self.oklabToRGB(a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f)
            out[i * 3] = rgb.0; out[i * 3 + 1] = rgb.1; out[i * 3 + 2] = rgb.2
        }
        let soft = Self.oklabToRGB(base[0][0] * 0.55 + base[1][0] * 0.45,
                                   base[0][1] * 0.55 + base[1][1] * 0.45,
                                   base[0][2] * 0.55 + base[1][2] * 0.45)
        let si = Int(Shade.softOutline * Shade.sub) * 3
        out[si] = soft.0; out[si + 1] = soft.1; out[si + 2] = soft.2
        table = out
        return out
    }

    // MARK: - 颜色换算

    static func hexToRGB(_ hex: String) -> (Double, Double, Double) {
        var h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        let n = Int(h, radix: 16) ?? 0
        return (Double((n >> 16) & 255), Double((n >> 8) & 255), Double(n & 255))
    }

    private static func rgbToHSL(_ r8: Double, _ g8: Double, _ b8: Double) -> (Double, Double, Double) {
        let r = r8 / 255, g = g8 / 255, b = b8 / 255
        let mx = max(r, g, b), mn = min(r, g, b)
        let l = (mx + mn) / 2
        if mx == mn { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        if mx == r { h = (g - b) / d + (g < b ? 6 : 0) }
        else if mx == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        return (h * 60, s, l)
    }

    private static func hslToHex(_ h0: Double, _ s0: Double, _ l0: Double) -> String {
        let h = (h0.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let s = min(1, max(0, s0)), l = min(1, max(0, l0))
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let rgb: (Double, Double, Double) =
            h < 60 ? (c, x, 0) : h < 120 ? (x, c, 0) : h < 180 ? (0, c, x) :
            h < 240 ? (0, x, c) : h < 300 ? (x, 0, c) : (c, 0, x)
        func to(_ v: Double) -> String {
            let n = Int(jsRound((v + m) * 255))
            let s = String(n, radix: 16)
            return s.count < 2 ? "0" + s : s
        }
        return "#" + to(rgb.0) + to(rgb.1) + to(rgb.2)
    }

    /// 把色相朝 target 方向转 amount 度（走最短路径）
    private static func hueToward(_ h: Double, _ target: Double, _ amount: Double) -> Double {
        let diff = (target - h + 540).truncatingRemainder(dividingBy: 360) - 180
        let sign: Double = diff > 0 ? 1 : diff < 0 ? -1 : 0
        return h + sign * min(abs(diff), amount)
    }

    private static func toLin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    private static func toSRGB(_ c: Double) -> Double { c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055 }

    private static func rgbToOklab(_ r8: Double, _ g8: Double, _ b8: Double) -> [Double] {
        let r = toLin(r8 / 255), g = toLin(g8 / 255), b = toLin(b8 / 255)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return [
            0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
        ]
    }

    private static func oklabToRGB(_ L: Double, _ A: Double, _ B: Double) -> (UInt8, UInt8, UInt8) {
        let l = pow(L + 0.3963377774 * A + 0.2158037573 * B, 3)
        let m = pow(L - 0.1055613458 * A - 0.0638541728 * B, 3)
        let s = pow(L - 0.0894841775 * A - 1.291485548 * B, 3)
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let b = -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s
        func to8(_ v: Double) -> UInt8 {
            UInt8(max(0, min(255, jsRound(toSRGB(max(0, min(1, v))) * 255))))
        }
        return (to8(r), to8(g), to8(b))
    }
}
