import UIKit
import SpriteKit

struct AtlasRect: Decodable {
    let id: String
    let kind: String?
    let sourceRect: [Double]
    let anchorPx: [Double]?
    var rect: CGRect { CGRect(x: sourceRect[0], y: sourceRect[1], width: sourceRect[2], height: sourceRect[3]) }
}
struct HeroFrame: Decodable {
    let index: Int
    let sourceRect: [Double]
    let anchorPx: [Double]
    var rect: CGRect { CGRect(x: sourceRect[0], y: sourceRect[1], width: sourceRect[2], height: sourceRect[3]) }
}
struct AtlasManifest: Decodable {
    let terrain: [AtlasRect]
    let sceneryAndLandmarks: [AtlasRect]
    let adventurerFrames: [HeroFrame]
}
struct SpriteAsset {
    let id: String
    let image: CGImage
    let texture: SKTexture
    let anchorTop: CGPoint
    var anchor: CGPoint { CGPoint(x: anchorTop.x / CGFloat(image.width), y: 1 - anchorTop.y / CGFloat(image.height)) }
}
struct ShadowAsset { let texture: SKTexture; let size: CGSize; let anchor: CGPoint }

enum AssetError: LocalizedError {
    case missing(String), malformed(String)
    var errorDescription: String? {
        switch self { case .missing(let id): return "缺少素材：\(id)"; case .malformed(let id): return "素材定义无效：\(id)" }
    }
}

final class AssetStore {
    let manifest: AtlasManifest
    private let bundle: Bundle
    private var originals: [String: CGImage] = [:]
    private var sprites: [String: SpriteAsset] = [:]
    private var normals: [String: SKTexture] = [:]
    private var shadows: [String: ShadowAsset] = [:]
    private var terrain: [Int: SKTexture] = [:]
    init(bundle: Bundle = .main) throws {
        self.bundle = bundle
        guard let url = bundle.url(forResource: "module-manifest", withExtension: "json", subdirectory: "Art") else { throw AssetError.missing("module-manifest") }
        manifest = try JSONDecoder().decode(AtlasManifest.self, from: Data(contentsOf: url))
    }
    private func image(_ name: String) throws -> CGImage {
        if let image = originals[name] { return image }
        guard let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "Art"), let image = UIImage(contentsOfFile: url.path)?.cgImage else { throw AssetError.missing(name) }
        originals[name] = image; return image
    }
    func module(_ id: String) throws -> SpriteAsset {
        if let asset = sprites[id] { return asset }
        guard let row = manifest.sceneryAndLandmarks.first(where: { $0.id == id }), row.sourceRect.count == 4,
              let anchor = row.anchorPx, anchor.count == 2, let kind = row.kind,
              let cropped = try image(kind + "_atlas").cropping(to: row.rect) else { throw AssetError.malformed(id) }
        return cache(id, cropped, CGPoint(x: anchor[0], y: anchor[1]))
    }
    func hero(_ index: Int) throws -> SpriteAsset {
        let id = "hero-\(index)"; if let asset = sprites[id] { return asset }
        guard let row = manifest.adventurerFrames.first(where: { $0.index == index }), row.anchorPx.count == 2,
              let cropped = try image("adventurer_sheet").cropping(to: row.rect) else { throw AssetError.malformed(id) }
        return cache(id, cropped, CGPoint(x: row.anchorPx[0], y: row.anchorPx[1]))
    }
    func referenceActor(_ id: String) throws -> SpriteAsset {
        if let asset = sprites[id] { return asset }
        let source = try image("class_\(id)_portrait")
        return cache(id, source, CGPoint(x: CGFloat(source.width) / 2, y: CGFloat(source.height) - 2))
    }
    private func cache(_ id: String, _ image: CGImage, _ anchor: CGPoint) -> SpriteAsset {
        let texture = SKTexture(cgImage: image); texture.filteringMode = .nearest
        let asset = SpriteAsset(id: id, image: image, texture: texture, anchorTop: anchor)
        sprites[id] = asset; return asset
    }
    func normal(id: String, texture: SKTexture) -> SKTexture {
        if let existing = normals[id] { return existing }
        // A luminance-derived experimental normal map, not an artist-authored height map.
        let normal = texture.generatingNormalMap(withSmoothness: 0.6, contrast: 0.15)
        normal.filteringMode = .nearest; normals[id] = normal; return normal
    }
    func projectedShadow(_ asset: SpriteAsset) -> ShadowAsset {
        if let result = shadows[asset.id] { return result }
        let input = CGRect(x: 0, y: 0, width: asset.image.width, height: asset.image.height)
        let transform = SunProjection().transform(anchorTop: asset.anchorTop)
        let bounds = input.applying(transform).integral.insetBy(dx: -3, dy: -3)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let result = UIGraphicsImageRenderer(size: bounds.size, format: format).image { renderer in
            let c = renderer.cgContext
            c.translateBy(x: -bounds.minX, y: -bounds.minY); c.concatenate(transform)
            UIImage(cgImage: asset.image).draw(in: input)
            c.setBlendMode(.sourceIn); c.setFillColor(UIColor(red: 0.05, green: 0.13, blue: 0.20, alpha: 1).cgColor); c.fill(input)
        }
        let texture = SKTexture(image: result); texture.filteringMode = .linear
        let foot = SunProjection().projectedFoot(anchorTop: asset.anchorTop)
        let shadow = ShadowAsset(texture: texture, size: bounds.size,
            anchor: CGPoint(x: (foot.x - bounds.minX) / bounds.width, y: 1 - (foot.y - bounds.minY) / bounds.height))
        shadows[asset.id] = shadow; return shadow
    }
    func material(_ id: String) throws -> CGImage {
        guard let row = manifest.terrain.first(where: { $0.id == id }), let cropped = try image("terrain_atlas").cropping(to: row.rect) else { throw AssetError.malformed(id) }
        return cropped
    }
    func groundVariant(_ variant: Int) throws -> SKTexture {
        let key = variant % 8; if let texture = terrain[key] { return texture }
        let source = try material(key % 5 == 0 ? "meadow_earth" : "meadow")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let output = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { renderer in
            let c = renderer.cgContext; c.interpolationQuality = .none
            let shift = CGFloat(key * 13), sample = source.cropping(to: CGRect(x: 20 + shift, y: 22 + shift, width: 490, height: 490)) ?? source
            UIImage(cgImage: sample).draw(in: CGRect(x: 0, y: 0, width: 512, height: 512))
            c.setBlendMode(.destinationIn)
            let colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.065, 0.935, 1]) {
                c.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 512, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                c.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 512), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
        }
        let texture = SKTexture(image: output); texture.filteringMode = .nearest; terrain[key] = texture; return texture
    }
    func roadTexture(curve: RoadCurve, width: CGFloat = 25) throws -> (SKTexture, CGRect) {
        let samples = (0...150).map { curve.point(Double($0)/150) }
        let xs = samples.map(\.x), ys = samples.map(\.y)
        let bounds = CGRect(x: xs.min()! - 24, y: ys.min()! - 24, width: xs.max()! - xs.min()! + 48, height: ys.max()! - ys.min()! + 48).integral
        let material = try self.material("earth")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let result = UIGraphicsImageRenderer(size: bounds.size, format: format).image { renderer in
            let c = renderer.cgContext; c.interpolationQuality = .none
            // UIKit is down-positive. Convert the same world cubic used by movement.
            func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - bounds.minX, y: bounds.maxY - p.y) }
            let path = CGMutablePath(); path.move(to: local(curve.a)); path.addCurve(to: local(curve.b), control1: local(curve.c1), control2: local(curve.c2))
            c.addPath(path); c.setStrokeColor(UIColor(red: 0.46, green: 0.37, blue: 0.19, alpha: 0.20).cgColor); c.setLineWidth(width + 10); c.setLineCap(.round); c.strokePath()
            let polygon = CGMutablePath(); var sides: [[CGPoint]] = [[], []]
            for (i, p) in samples.enumerated() {
                let tangent = curve.tangent(Double(i)/150), radius = width/2 + sin(CGFloat(i)*1.7)*1.2 + sin(CGFloat(i)*0.41)*1.3
                for side in 0...1 { let sign: CGFloat = side == 0 ? -1 : 1; sides[side].append(local(CGPoint(x: p.x-tangent.y*radius*sign, y: p.y+tangent.x*radius*sign))) }
            }
            for (i, p) in (sides[0] + Array(sides[1].reversed())).enumerated() { if i == 0 { polygon.move(to: p) } else { polygon.addLine(to: p) } }
            polygon.closeSubpath(); c.saveGState(); c.addPath(polygon); c.clip()
            let tile = CGSize(width: 96, height: 96)
            for y in stride(from: 0.0, to: Double(bounds.height), by: 96) { for x in stride(from: 0.0, to: Double(bounds.width), by: 96) {
                UIImage(cgImage: material).draw(in: CGRect(origin: CGPoint(x: x, y: y), size: tile))
            } }
            c.restoreGState()
        }
        let texture = SKTexture(image: result); texture.filteringMode = .nearest; return (texture, bounds)
    }
}
