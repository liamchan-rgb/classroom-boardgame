import SpriteKit

struct ShadowProjection {
    let size: CGSize
    let offset: CGPoint
    let cast: CGVector

    init(body: CGSize, anchorY: CGFloat, ratio: CGFloat, softness: CGFloat,
         sun: CGVector = MeadowSun.cast) {
        cast = CGVector(dx: sun.dx * ratio, dy: sun.dy * ratio)
        let margin = softness * 3 + 2
        let projectedHeight = body.height * max(0, 1 - anchorY)
        size = CGSize(width: body.width + projectedHeight * abs(cast.dx) + margin * 2,
                      height: projectedHeight * abs(cast.dy) + margin * 2)
        // Center the full foot-to-crown projection around its actual bounds.
        // Keeping this tied to the same ground anchor prevents the silhouette
        // from appearing detached when object or actor sizes change.
        offset = CGPoint(x: projectedHeight * cast.dx * 0.5,
                         y: -projectedHeight * cast.dy * 0.5)
    }

    func point(x: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(x: x + height * cast.dx, y: -height * cast.dy)
    }
}

/// Samples the source silhouette through an oblique projection, with an
/// elevation-dependent penumbra. The contact patch is a separate, small node.
final class ProjectedShadow: SKSpriteNode {
    private(set) var projection: ShadowProjection
    private let body: CGSize
    private let anchorY: CGFloat
    private let mirror: Float
    private let opacity: Float
    private let ratio: CGFloat
    private let softness: Float
    private let foliage: Float
    private let phase: Float
    private let wind: Float

    init(texture: SKTexture, body: CGSize, anchorY: CGFloat, ratio: CGFloat,
         softness: Float, opacity: Float, mirrored: Bool = false,
         foliage: Bool = false, phase: Float = 0, wind: Float = 0, shader: SKShader) {
        self.body = body
        self.anchorY = anchorY
        self.mirror = mirrored ? -1 : 1
        self.softness = softness
        self.opacity = opacity
        self.ratio = ratio
        self.foliage = foliage ? 1 : 0
        self.phase = phase
        self.wind = wind
        projection = ShadowProjection(body: body, anchorY: anchorY, ratio: ratio, softness: CGFloat(softness))
        super.init(texture: texture, color: .white, size: projection.size)
        self.shader = shader
        zPosition = 40
        update(foot: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(foot: CGPoint, texture: SKTexture? = nil,
                gait: SIMD2<Float> = SIMD2(-1, 0), sun: CGVector = MeadowSun.cast) {
        // Kept in the call signature for existing scene callers. Animation is
        // already present in `texture`; the shadow no longer remaps leg UVs.
        _ = gait
        if let texture { self.texture = texture }
        projection = ShadowProjection(body: body, anchorY: anchorY, ratio: ratio,
                                      softness: CGFloat(softness), sun: sun)
        size = projection.size
        position = CGPoint(x: foot.x + projection.offset.x, y: foot.y + projection.offset.y)
        attributeValues = [
            "a_origin": SKAttributeValue(vectorFloat2: SIMD2(Float(position.x), Float(-position.y))),
            "a_extent": SKAttributeValue(vectorFloat2: SIMD2(Float(size.width), Float(size.height))),
            "a_body": SKAttributeValue(vectorFloat4: SIMD4(Float(body.width), Float(body.height), Float(anchorY), mirror)),
            "a_cast": SKAttributeValue(vectorFloat4: SIMD4(Float(projection.cast.dx), Float(projection.cast.dy), softness, opacity)),
            "a_foliage": SKAttributeValue(float: foliage), "a_phase": SKAttributeValue(float: phase),
            "a_wind": SKAttributeValue(float: wind)
        ]
    }
}
