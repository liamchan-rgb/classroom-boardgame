import Foundation

// 人物像素精灵：五官引擎。与 hd2d-walk-demo/src/items/kits/faceKit.ts 对应。
// 五官是纯数据：Resources/CharacterParts/face/*.json。按像素格摆，只画在脸上（maskBelow），不描边。

struct FaceData: Decodable {
    struct Palettes: Decodable {
        let eye: [String]?
        let blush: [String]?
    }
    struct Variant: Decodable {
        let id: String
        let name: String
        let palettes: Palettes
    }
    /// ["front", -5, 0]：图案名（加 ! 表示镜像）+ 格坐标
    struct EyePlacement: Decodable {
        let pattern: String
        let x: Int
        let y: Int
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            pattern = try c.decode(String.self)
            x = try c.decode(Int.self)
            y = try c.decode(Int.self)
        }
    }
    struct View: Decodable {
        let eyes: [EyePlacement]?
        let blush: [[Int]]?
        let mouth: [[Int]]?
        let brows: [[Int]]?
    }
    let id: String
    let name: String
    let palettes: Palettes
    let variants: [Variant]?
    let patterns: [String: [String]]
    let views: [String: View]
}

enum FaceKit {
    static func mirror(_ rows: [String]) -> [String] { rows.map { String($0.reversed()) } }

    /// 五官原点（像素）与一格的像素数
    static func origin(_ c: DrawContext) -> (px: Int, py: Int, k: Int) {
        let S = c.g.S
        let hx = c.pose.head.x + c.pose.sin * 0.9, hy = c.pose.head.y
        return (Int(jsRound(hx * S)), Int(jsRound((hy + 0.4) * S)), max(1, Int(jsRound(S))))
    }

    private static func draw(_ c: DrawContext, _ d: FaceData) {
        guard let view = d.views[c.dir.rawValue] else { return }
        let g = c.g
        let o = origin(c)
        func dot(_ cell: [Int], _ shade: Double) {
            g.cellsPx([String(Int(shade))], o.px + cell[0] * o.k, o.py + cell[1] * o.k)
        }
        c.pal("eye")
        for e in view.eyes ?? [] {
            let mirrored = e.pattern.hasSuffix("!")
            let name = mirrored ? String(e.pattern.dropLast()) : e.pattern
            guard let rows = d.patterns[name] else { continue }
            g.cellsPx(mirrored ? mirror(rows) : rows, o.px + e.x * o.k, o.py + e.y * o.k)
        }
        c.pal("blush")
        for cell in view.blush ?? [] { dot(cell, Shade.base) }
        c.pal("skin")
        for cell in view.mouth ?? [] { dot(cell, Shade.dark) }
        for cell in view.brows ?? [] { dot(cell, Shade.dark) }
    }

    static func make(_ d: FaceData) -> ItemDef {
        var palettes: [String: SpritePalette] = [:]
        if let eye = d.palettes.eye { palettes["eye"] = SpritePalette("\(d.id)-eye", eye) }
        if let blush = d.palettes.blush { palettes["blush"] = SpritePalette("\(d.id)-blush", blush) }
        let variants = (d.variants ?? []).map { v -> ItemVariant in
            var p: [String: SpritePalette] = [:]
            if let eye = v.palettes.eye { p["eye"] = SpritePalette("\(d.id)-\(v.id)-eye", eye) }
            if let blush = v.palettes.blush { p["blush"] = SpritePalette("\(d.id)-\(v.id)-blush", blush) }
            return ItemVariant(id: v.id, name: v.name, palettes: p)
        }
        return ItemDef(
            id: d.id, name: d.name, slot: .face, palettes: palettes, variants: variants,
            parts: [PartDef(layer: .fixed(.head), draw: { c in FaceKit.draw(c, d) }, outline: false, maskBelow: true)])
    }
}
