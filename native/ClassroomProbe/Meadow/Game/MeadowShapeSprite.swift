import SpriteKit
import UIKit

/// Flat shapes (rings, plates, route lines, marker discs) as textured sprites. SKShapeNode re-strokes its path on the
/// CPU every frame (bounding box, tessellation), which showed up as steady main-thread cost on the map; a sprite is
/// drawn once into a texture (cached by look) and from then on costs only the GPU.
enum MeadowShapeSprite {
    private static var cache: [String: SKTexture] = [:]
    private static let scale: CGFloat = 2

    private static func key(_ c: SKColor?) -> String {
        guard let c else { return "-" }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.3f,%.3f,%.3f,%.3f", r, g, b, a)
    }
    /// The texture of `path` (in node coordinates, y up) with its bounds; drawn once per distinct shape.
    private static func texture(_ path: CGPath, fill: SKColor?, stroke: SKColor?, lineWidth: CGFloat, cacheKey: String?) -> (SKTexture, CGRect) {
        let pad = (stroke != nil ? lineWidth : 0) / 2 + 1
        let box = path.boundingBoxOfPath.insetBy(dx: -pad, dy: -pad).integral
        if let cacheKey, let hit = cache[cacheKey] { return (hit, box) }
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = false
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: box.size, format: format).image { r in
            let cg = r.cgContext
            cg.translateBy(x: 0, y: box.height); cg.scaleBy(x: 1, y: -1)   // SpriteKit's y-up
            cg.translateBy(x: -box.minX, y: -box.minY)
            cg.addPath(path)
            if let fill { cg.setFillColor(fill.cgColor); cg.fillPath(); cg.addPath(path) }
            if let stroke, lineWidth > 0 { cg.setStrokeColor(stroke.cgColor); cg.setLineWidth(lineWidth); cg.setLineCap(.round); cg.setLineJoin(.round); cg.strokePath() }
        }
        let texture = SKTexture(image: image)
        if let cacheKey { if cache.count > 400 { cache.removeAll() }; cache[cacheKey] = texture }
        return (texture, box)
    }
    /// A sprite showing `path` placed so the path's own coordinates line up with the node's.
    static func sprite(_ path: CGPath, fill: SKColor?, stroke: SKColor? = nil, lineWidth: CGFloat = 0, cacheKey: String? = nil) -> SKSpriteNode {
        let node = SKSpriteNode()
        set(node, path: path, fill: fill, stroke: stroke, lineWidth: lineWidth, cacheKey: cacheKey)
        return node
    }
    /// Re-draws an existing sprite with a new shape (only when the shape really changed).
    static func set(_ node: SKSpriteNode, path: CGPath, fill: SKColor?, stroke: SKColor? = nil, lineWidth: CGFloat = 0, cacheKey: String? = nil) {
        let (texture, box) = texture(path, fill: fill, stroke: stroke, lineWidth: lineWidth, cacheKey: cacheKey)
        node.texture = texture; node.size = box.size
        node.anchorPoint = CGPoint(x: -box.minX / box.width, y: -box.minY / box.height)
    }
    static func ellipse(_ size: CGSize, fill: SKColor? = nil, stroke: SKColor? = nil, lineWidth: CGFloat = 0) -> SKSpriteNode {
        sprite(CGPath(ellipseIn: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height), transform: nil),
               fill: fill, stroke: stroke, lineWidth: lineWidth, cacheKey: "e\(size)|\(key(fill))|\(key(stroke))|\(lineWidth)")
    }
    static func circle(_ r: CGFloat, fill: SKColor? = nil, stroke: SKColor? = nil, lineWidth: CGFloat = 0) -> SKSpriteNode {
        ellipse(CGSize(width: r * 2, height: r * 2), fill: fill, stroke: stroke, lineWidth: lineWidth)
    }
    static func roundedRectPath(_ size: CGSize, radius: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height), cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
    static func roundedRect(_ size: CGSize, radius: CGFloat, fill: SKColor? = nil, stroke: SKColor? = nil, lineWidth: CGFloat = 0) -> SKSpriteNode {
        sprite(roundedRectPath(size, radius: radius), fill: fill, stroke: stroke, lineWidth: lineWidth,
               cacheKey: "r\(size)|\(radius)|\(key(fill))|\(key(stroke))|\(lineWidth)")
    }
    static func setRoundedRect(_ node: SKSpriteNode, _ size: CGSize, radius: CGFloat, fill: SKColor? = nil, stroke: SKColor? = nil, lineWidth: CGFloat = 0) {
        set(node, path: roundedRectPath(size, radius: radius), fill: fill, stroke: stroke, lineWidth: lineWidth,
            cacheKey: "r\(size)|\(radius)|\(key(fill))|\(key(stroke))|\(lineWidth)")
    }
    /// An invisible hit area (taps find it by its frame; nothing is drawn).
    static func hitArea(radius r: CGFloat) -> SKSpriteNode { SKSpriteNode(color: SKColor(white: 0, alpha: 0.001), size: CGSize(width: r * 2, height: r * 2)) }
}
