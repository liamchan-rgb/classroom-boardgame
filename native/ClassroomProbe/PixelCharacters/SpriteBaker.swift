import CoreGraphics
import SpriteKit

// 人物像素精灵：烘焙。把一套装备合成为图集，供 SpriteKit 使用。
// 图集排布与 hd2d-walk-demo/scripts/export.ts 完全一致（也就是 Assets.xcassets 里 HeroNDirections 的格式）。

enum SpriteBaker {
    /// 游戏现有的人物图集格式：1536×1536，4×4，每格 384×384，脚底在 y = 336
    static let atlasCell = 384
    static let atlasFootY = 336
    /// 行：正面、左（右侧镜像）、背面、右
    static let atlasRows: [(Dir5, Bool)] = [(.S, false), (.E, true), (.N, false), (.E, false)]
    /// 列：待机、左脚在前、过渡、右脚在前 → 原生 sheet 的列号
    static let atlasCols = [0, 6, 5, 3]

    /// 合成一帧，返回该帧的索引色图层
    static func frame(_ entries: [LoadoutEntry], dir: Dir5, col: Int) -> PixelLayer {
        let layer = PixelLayer(SpriteRig.sprW, SpriteRig.sprH)
        Paperdoll.composeFrame(entries, dir: dir, frame: col, into: layer)
        return layer
    }

    /// 兼容游戏现有格式的 4×4 图集（整数倍最近邻放大）
    static func atlas(_ equipment: SpriteEquipment) -> CGImage? {
        let entries = equipment.resolve()
        let S = SpriteRig.spriteScale, w = SpriteRig.sprW, h = SpriteRig.sprH
        let size = atlasCell * 4
        let k = max(1, Int(min(Double(atlasCell - 16) / Double(w), Double(atlasFootY) / (SpriteRig.footY * S + 1)).rounded(.down)))
        let ox = Int(jsRound(Double(atlasCell) / 2 - SpriteRig.cx * S * Double(k)))
        let oy = Int(jsRound(Double(atlasFootY) - (SpriteRig.footY * S + 1) * Double(k)))

        var cache: [String: [UInt8]] = [:]
        func small(_ dir: Dir5, _ col: Int) -> [UInt8] {
            let key = "\(dir.rawValue)-\(col)"
            if let hit = cache[key] { return hit }
            var buf = [UInt8](repeating: 0, count: w * h * 4)
            frame(entries, dir: dir, col: col).writeRGBA(into: &buf)
            cache[key] = buf
            return buf
        }

        var out = [UInt8](repeating: 0, count: size * size * 4)
        for (r, row) in atlasRows.enumerated() {
            for (c, col) in atlasCols.enumerated() {
                let src = small(row.0, col)
                let flip = row.1
                let x0 = c * atlasCell + (flip ? atlasCell - ox - w * k : ox)
                let y0 = r * atlasCell + oy
                for y in 0..<h {
                    for x in 0..<w {
                        let si = (y * w + (flip ? w - 1 - x : x)) * 4
                        if src[si + 3] == 0 { continue }
                        for by in 0..<k {
                            let ty = y0 + y * k + by
                            if ty < 0 || ty >= size { continue }
                            for bx in 0..<k {
                                let tx = x0 + x * k + bx
                                if tx < 0 || tx >= size { continue }
                                let ti = (ty * size + tx) * 4
                                out[ti] = src[si]; out[ti + 1] = src[si + 1]; out[ti + 2] = src[si + 2]; out[ti + 3] = 255
                            }
                        }
                    }
                }
            }
        }
        return makeImage(out, width: size, height: size)
    }

    /// 原生 sheet：5 行（S/SE/E/NE/N）× 8 列（待机 0-1、行走 2-7），每格 sprW×sprH
    static func sheet(_ equipment: SpriteEquipment) -> CGImage? {
        let entries = equipment.resolve()
        let w = SpriteRig.sprW, h = SpriteRig.sprH, cols = SpriteRig.framesPerDir
        var out = [UInt8](repeating: 0, count: w * cols * h * Dir5.allCases.count * 4)
        for (r, dir) in Dir5.allCases.enumerated() {
            for col in 0..<cols {
                frame(entries, dir: dir, col: col).writeRGBA(into: &out, offsetX: col * w, offsetY: r * h, rowStride: w * cols)
            }
        }
        return makeImage(out, width: w * cols, height: h * Dir5.allCases.count)
    }

    static func makeImage(_ rgba: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// 角色预设 → SpriteKit 图集纹理（最近邻采样，像素画缩放时不发糊）
    static func atlasTexture(for preset: CharacterPreset, catalog: CharacterCatalog = .shared) -> SKTexture? {
        guard let eq = try? catalog.equipment(for: preset), let image = atlas(eq) else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }
}
