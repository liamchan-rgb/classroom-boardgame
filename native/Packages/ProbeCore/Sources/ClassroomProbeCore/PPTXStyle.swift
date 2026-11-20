import Foundation

/// How a shape is drawn: its outline geometry, fill and line, and (for text) where the text sits inside it.
public struct SlideShapeStyle {
    /// DrawingML preset geometry (`rect`, `roundRect`, `ellipse`, `line`…).
    public var kind: String = "rect"
    public var fill: String?
    public var line: String?
    /// Line width in EMU.
    public var lineWidth: Double = 12700
    /// Vertical text anchor: `t`, `ctr` or `b`.
    public var anchor: String = "t"
    /// Text insets in EMU (left, top, right, bottom).
    public var insets: [Double] = [91440, 45720, 91440, 45720]
    /// First preset adjust value (for example the corner radius of a `roundRect`, in 1/100000 of the short side).
    public var adjust: Double?
    public var flipH = false
    public var flipV = false
    public init() {}
}

extension XMLNode {
    func child(_ name: String) -> XMLNode? { children.first { $0.name == name } }
}

/// Theme colours and fonts, and the master's colour map (bg1 → lt1 …), used to turn DrawingML colours into hex.
struct SlidePalette {
    var scheme: [String: String] = [:]
    var map: [String: String] = ["bg1": "lt1", "tx1": "dk1", "bg2": "lt2", "tx2": "dk2"]
    var majorFont: String?
    var minorFont: String?

    mutating func load(theme: XMLNode) {
        if let colours = theme.first("clrScheme") {
            for entry in colours.children {
                for colour in entry.children { if let value = base(colour) { scheme[entry.name] = value; break } }
            }
        }
        majorFont = theme.first("majorFont")?.child("latin")?.attributes["typeface"].flatMap { $0.isEmpty ? nil : $0 }
        minorFont = theme.first("minorFont")?.child("latin")?.attributes["typeface"].flatMap { $0.isEmpty ? nil : $0 }
    }
    /// Colour-map attributes (`bg1="lt1"` …) from a master's clrMap or a slide's overrideClrMapping.
    mutating func remap(_ node: XMLNode?) {
        guard let node else { return }
        for (key, value) in node.attributes where !key.contains(":") { map[key] = value }
    }
    func font(_ typeface: String?) -> String? {
        guard let typeface, !typeface.isEmpty else { return nil }
        if typeface.hasPrefix("+mj") { return majorFont }
        if typeface.hasPrefix("+mn") { return minorFont }
        return typeface
    }

    private static let preset: [String: String] = [
        "black": "000000", "white": "FFFFFF", "red": "FF0000", "green": "008000", "blue": "0000FF", "yellow": "FFFF00",
        "gray": "808080", "grey": "808080", "darkGray": "A9A9A9", "lightGray": "D3D3D3", "orange": "FFA500", "purple": "800080",
    ]
    /// The colour of one colour element before its modifiers.
    private func base(_ node: XMLNode) -> String? {
        switch node.name {
        case "srgbClr": return node.attributes["val"]
        case "sysClr": return node.attributes["lastClr"] ?? (node.attributes["val"] == "window" ? "FFFFFF" : "000000")
        case "schemeClr":
            let name = node.attributes["val"] ?? ""
            return scheme[map[name] ?? name] ?? scheme[name]
        case "prstClr": return Self.preset[node.attributes["val"] ?? ""]
        case "scrgbClr":
            let parts = ["r", "g", "b"].map { Double(node.attributes[$0] ?? "0") ?? 0 }
            return parts.map { String(format: "%02X", Int(max(0, min(255, ($0 / 100000) * 255)).rounded())) }.joined()
        default: return nil
        }
    }
    /// A colour element (srgbClr, schemeClr …) with its lumMod / lumOff / tint / shade applied, as RRGGBB.
    func hex(_ node: XMLNode) -> String? {
        guard let start = base(node), start.count == 6, let value = UInt32(start, radix: 16) else { return nil }
        var r = Double((value >> 16) & 255) / 255, g = Double((value >> 8) & 255) / 255, b = Double(value & 255) / 255
        for modifier in node.children {
            guard let amount = Double(modifier.attributes["val"] ?? "").map({ $0 / 100000 }) else { continue }
            switch modifier.name {
            case "lumMod", "lumOff":
                var (h, s, l) = Self.hsl(r, g, b)
                l = modifier.name == "lumMod" ? l * amount : l + amount
                (r, g, b) = Self.rgb(h, s, max(0, min(1, l)))
            case "tint": (r, g, b) = (r * amount + (1 - amount), g * amount + (1 - amount), b * amount + (1 - amount))
            case "shade": (r, g, b) = (r * amount, g * amount, b * amount)
            default: continue
            }
        }
        return [r, g, b].map { String(format: "%02X", Int((max(0, min(1, $0)) * 255).rounded())) }.joined()
    }
    /// The first colour element directly inside `container` (for example a solidFill).
    func colour(in container: XMLNode?) -> String? { container?.children.lazy.compactMap { self.hex($0) }.first }
    /// `owner`'s solidFill colour (rPr, defRPr, ln …).
    func solid(_ owner: XMLNode?) -> String? { colour(in: owner?.child("solidFill")) }

    enum Fill { case unspecified, none, colour(String) }
    /// The fill a shape properties node (spPr / bgPr) asks for. A gradient shows as its first stop.
    func fill(_ properties: XMLNode?) -> Fill {
        guard let properties else { return .unspecified }
        if properties.child("noFill") != nil { return .none }
        if let c = solid(properties) { return .colour(c) }
        if let stops = properties.child("gradFill")?.child("gsLst")?.children, let c = stops.lazy.compactMap({ self.colour(in: $0) }).first { return .colour(c) }
        if let c = colour(in: properties.child("pattFill")?.child("fgClr")) { return .colour(c) }
        return .unspecified
    }

    private static func hsl(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let high = max(r, g, b), low = min(r, g, b), l = (high + low) / 2
        guard high != low else { return (0, 0, l) }
        let d = high - low, s = l > 0.5 ? d / (2 - high - low) : d / (high + low)
        var h: Double
        if high == r { h = (g - b) / d + (g < b ? 6 : 0) } else if high == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        h /= 6
        return (h, s, l)
    }
    private static func rgb(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        guard s > 0 else { return (l, l, l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
        func channel(_ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }; if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        return (channel(h + 1 / 3), channel(h), channel(h - 1 / 3))
    }
}

/// Run formatting gathered from the run itself and every list style it inherits from (first value found wins).
struct SlideTextProps {
    var size: Double?
    var bold: Bool?
    var italic: Bool?
    var colour: String?
    var font: String?
    var align: String?

    mutating func take(run properties: XMLNode?, palette: SlidePalette) {
        guard let properties else { return }
        if size == nil, let s = Double(properties.attributes["sz"] ?? "") { size = s / 100 }
        if bold == nil, let b = properties.attributes["b"] { bold = ["1", "true"].contains(b) }
        if italic == nil, let i = properties.attributes["i"] { italic = ["1", "true"].contains(i) }
        if colour == nil { colour = palette.solid(properties) }
        if font == nil { font = palette.font(properties.child("latin")?.attributes["typeface"]) ?? palette.font(properties.child("ea")?.attributes["typeface"]) }
    }
    /// A list-style level (`a:lvl1pPr` …): its alignment and default run properties.
    mutating func take(level: XMLNode?, palette: SlidePalette) {
        guard let level else { return }
        if align == nil { align = level.attributes["algn"] }
        take(run: level.child("defRPr"), palette: palette)
    }
}
