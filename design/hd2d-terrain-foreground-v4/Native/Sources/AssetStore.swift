import UIKit
import SpriteKit
import CoreImage

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
struct ModularManifest: Decodable {
    let sceneModules: [AtlasRect]
    let actorFrames: [HeroFrame]
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
    // Crops have small clear padding; keep all roles the same displayed height.
    var actorScale: CGFloat { 74 / max(1,CGFloat(image.height)-12) }
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
    let modularManifest: ModularManifest
    private let bundle: Bundle
    private var originals: [String: CGImage] = [:]
    private var sprites: [String: SpriteAsset] = [:]
    private var shadows: [String: ShadowAsset] = [:]
    private var terrain: [Int: SKTexture] = [:]
    private var highlights: [String: SKTexture] = [:]
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    init(bundle: Bundle = .main) throws {
        self.bundle = bundle
        guard let url = bundle.url(forResource: "module-manifest", withExtension: "json", subdirectory: "Art") else { throw AssetError.missing("module-manifest") }
        manifest = try JSONDecoder().decode(AtlasManifest.self, from: Data(contentsOf: url))
        guard let moduleURL=bundle.url(forResource:"modular-manifest",withExtension:"json",subdirectory:"Art") else { throw AssetError.missing("modular-manifest") }
        modularManifest=try JSONDecoder().decode(ModularManifest.self,from:Data(contentsOf:moduleURL))
    }
    private func image(_ name: String) throws -> CGImage {
        if let image = originals[name] { return image }
        guard let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "Art"), let image = UIImage(contentsOfFile: url.path)?.cgImage else { throw AssetError.missing(name) }
        originals[name] = image; return image
    }
    func module(_ id: String) throws -> SpriteAsset {
        if let asset = sprites[id] { return asset }
        guard let row = modularManifest.sceneModules.first(where: { $0.id == id }) ?? manifest.sceneryAndLandmarks.first(where: { $0.id == id }), row.sourceRect.count == 4,
              let anchor = row.anchorPx, anchor.count == 2, let kind = row.kind,
              let cropped = try image(kind + "_atlas").cropping(to: row.rect) else { throw AssetError.malformed(id) }
        return cache(id, cropped, CGPoint(x: anchor[0], y: anchor[1]))
    }
    func hero(_ index: Int) throws -> SpriteAsset {
        let id = "hero-\(index)"; if let asset = sprites[id] { return asset }
        guard let row = modularManifest.actorFrames.first(where: { $0.index == index }), row.anchorPx.count == 2,
              let cropped = try image("actor_frames_v4").cropping(to: row.rect) else { throw AssetError.malformed(id) }
        return cache(id, cropped, CGPoint(x: row.anchorPx[0], y: row.anchorPx[1]))
    }
    func referenceActor(_ id: String) throws -> SpriteAsset { try hero(id == "ranger" ? 8 : 9) }
    private func cache(_ id: String, _ image: CGImage, _ anchor: CGPoint) -> SpriteAsset {
        let texture = SKTexture(cgImage: image); texture.filteringMode = .nearest
        let asset = SpriteAsset(id: id, image: image, texture: texture, anchorTop: anchor)
        sprites[id] = asset; return asset
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
            c.setBlendMode(.sourceIn); c.setFillColor(UIColor(red: 0.10, green: 0.16, blue: 0.15, alpha: 1).cgColor); c.fill(input)
        }
        // Small cached penumbra, never blur the source albedo.
        let ci = CIImage(image:result)!
        let softened=ci.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:1.6]).cropped(to:ci.extent)
        let texture = ciContext.createCGImage(softened,from:ci.extent).map { SKTexture(cgImage:$0) } ?? SKTexture(image:result)
        texture.filteringMode = .linear
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
    // One low-resolution world field is generated once; RGB stores detail, forest and sun.
    // The texture is sampled continuously across terrain patches, independent of the camera.
    func meadowField(_ field: MeadowField) -> SKTexture {
        let side = 256
        var rgba = [UInt8](repeating: 255, count: side*side*4)
        for y in 0..<side { for x in 0..<side {
            let p = CGPoint(x: field.bounds.minX + (CGFloat(x)+0.5)/CGFloat(side)*field.bounds.width,
                            y: field.bounds.maxY - (CGFloat(y)+0.5)/CGFloat(side)*field.bounds.height)
            let value = field.channels(p), index = (y*side+x)*4
            rgba[index] = UInt8(value.detail*255)
            rgba[index+1] = UInt8(value.forest*255)
            rgba[index+2] = UInt8(value.sunlight*255)
        } }
        let data = Data(rgba) as CFData
        let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: side*4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        let texture = SKTexture(cgImage: image); texture.filteringMode = .linear
        return texture
    }
    func terrainField(_ field: MeadowField) -> SKTexture {
        let side=256;var pixels=[UInt8](repeating:255,count:side*side*4)
        for y in 0..<side { for x in 0..<side {
            let point=CGPoint(x:field.bounds.minX+(CGFloat(x)+0.5)/CGFloat(side)*field.bounds.width,
                              y:field.bounds.maxY-(CGFloat(y)+0.5)/CGFloat(side)*field.bounds.height)
            let normal=field.normal(point),index=(y*side+x)*4
            pixels[index]=UInt8((normal.x*0.5+0.5)*255);pixels[index+1]=UInt8((normal.y*0.5+0.5)*255)
            pixels[index+2]=UInt8(min(1,max(0,field.height(point)/56))*255)
        } }
        let cg=CGImage(width:side,height:side,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:side*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
            provider:CGDataProvider(data:Data(pixels) as CFData)!,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
        let texture=SKTexture(cgImage:cg);texture.filteringMode = .linear;return texture
    }
    func campClearing() throws -> SKTexture {
        let size=CGSize(width:320,height:180),source=try material("earth")
        let format=UIGraphicsImageRendererFormat();format.scale=1
        let output=UIGraphicsImageRenderer(size:size,format:format).image { renderer in
            let c=renderer.cgContext;c.interpolationQuality = .none
            UIImage(cgImage:source).draw(in:CGRect(origin:.zero,size:size))
            c.setBlendMode(.destinationIn)
            let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[UIColor(white:1,alpha:0.92).cgColor,UIColor.clear.cgColor] as CFArray,locations:[0.30,1])!
            c.saveGState();c.scaleBy(x:1,y:0.5625)
            c.drawRadialGradient(gradient,startCenter:CGPoint(x:160,y:160),startRadius:0,endCenter:CGPoint(x:160,y:160),endRadius:160,options:[])
            c.restoreGState()
        }
        let texture=SKTexture(image:output);texture.filteringMode = .nearest;return texture
    }
    // Only effect textures are soft. Albedo/actors/roads retain nearest filtering.
    func radialTexture(warm: Bool = false) -> SKTexture {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128), format: format).image { renderer in
            let center = warm ? UIColor(red: 1, green: 0.86, blue: 0.55, alpha: 0.85) : UIColor(red: 0.04, green: 0.09, blue: 0.12, alpha: 0.9)
            let edge = center.withAlphaComponent(0)
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [center.cgColor,edge.cgColor] as CFArray, locations: [0,1])!
            renderer.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 64,y: 64), startRadius: 0,
                                                 endCenter: CGPoint(x: 64,y: 64), endRadius: 64, options: [])
        }
        let texture = SKTexture(image: image); texture.filteringMode = .linear; return texture
    }
    // Downsampled highlight-only mask. Gaussian spread affects this additive layer,
    // never the original pixel sprite; cached once per immutable asset.
    func highlightBloom(_ asset: SpriteAsset) -> SKTexture? {
        if let existing = highlights[asset.id] { return existing }
        let width = 128, height = max(1, Int(Double(asset.image.height)/Double(asset.image.width)*128))
        var rgba = [UInt8](repeating: 0, count: width*height*4)
        let made = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let c = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width*4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            c.interpolationQuality = .none
            c.draw(asset.image, in: CGRect(x: 0,y: 0,width: width,height: height)); return true
        }
        guard made else { return nil }
        for i in stride(from: 0, to: rgba.count, by: 4) {
            let alpha = Double(rgba[i+3])/255
            let lum = (Double(rgba[i])*0.2126+Double(rgba[i+1])*0.7152+Double(rgba[i+2])*0.0722)/255/max(0.001,alpha)
            let glow = MeadowField.smooth(0.69,0.93,lum)*alpha
            rgba[i] = UInt8(255*glow); rgba[i+1] = UInt8(226*glow); rgba[i+2] = UInt8(164*glow); rgba[i+3] = UInt8(255*glow)
        }
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        guard let image = CGImage(width: width,height: height,bitsPerComponent: 8,bitsPerPixel: 32,bytesPerRow: width*4,
                                  space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider,decode: nil,shouldInterpolate: true,intent: .defaultIntent) else { return nil }
        let input = CIImage(cgImage: image)
        let soft = input.clampedToExtent().applyingFilter("CIGaussianBlur",parameters: [kCIInputRadiusKey: 1.4]).cropped(to: input.extent)
        guard let output = ciContext.createCGImage(soft,from: input.extent) else { return nil }
        let texture = SKTexture(cgImage: output); texture.filteringMode = .linear; highlights[asset.id] = texture; return texture
    }
    func roadTexture(curve: RoadCurve, width: CGFloat = 30) throws -> (SKTexture, CGRect) {
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
            c.addPath(path); c.setStrokeColor(UIColor(red: 0.64,green: 0.55,blue: 0.32,alpha: 0.12).cgColor)
            c.setLineWidth(width+18); c.setLineCap(.round); c.strokePath()
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
