import Foundation
import CoreGraphics

// Presentation-only parameters. No game seed, path or command is mutated.
struct HD2DSettings: Equatable {
    var directionalLight = true
    var colorGrade = true
    var vegetation = true
    var relief = true
    var contactShadows = true
    var bloom = true
    var atmosphere = true
    var edgeDepth = true
    var environmentalMotion = true
    var shadowStrength: Double = 0.78
    var vegetationContrast: Double = 0.46
    var bloomStrength: Double = 0.32
    var atmosphereStrength: Double = 0.30
    var depthRadius: Double = 1.4
    var motionStrength: Double = 0.45
    func bounded() -> Self {
        var value = self
        value.shadowStrength = Self.clamp(shadowStrength)
        value.vegetationContrast = Self.clamp(vegetationContrast)
        value.bloomStrength = Self.clamp(bloomStrength)
        value.atmosphereStrength = Self.clamp(atmosphereStrength)
        value.depthRadius = depthRadius.isFinite ? min(2.2, max(0, depthRadius)) : 0
        value.motionStrength = Self.clamp(motionStrength)
        return value
    }
    private static func clamp(_ x: Double) -> Double { x.isFinite ? min(1, max(0, x)) : 0 }
}

enum SurfaceKind: Float {
    case ground = 0, foliage = 1, rock = 2, building = 3, actor = 4, road = 5, lowPlant = 6
    static func asset(_ id: String) -> Self {
        if id.hasPrefix("ground-") { return .ground }
        if id.hasPrefix("road-") { return .road }
        if id == "mixed_grove" || id == "fir_grove" { return .foliage }
        if id.contains("rock") { return .rock }
        if id.hasPrefix("camp") || id.hasPrefix("tower") || id.hasPrefix("ruin") || id == "fence" { return .building }
        if id == "flowers" { return .lowPlant }
        return .actor
    }
}

// Smooth, deterministic, multi-scale value noise in world coordinates.
// It is independent of camera zoom, screen aspect and engine RNG.
struct MeadowField {
    let seed: UInt64
    let roads: [RoadCurve]
    let landmarks: [CGPoint]
    let bounds = CGRect(x: -768, y: -768, width: 3072, height: 3072)
    private func hash(_ x: Int, _ y: Int) -> Double {
        var n = UInt64(bitPattern: Int64(x)) &* 0x9E3779B185EBCA87
        n ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2AE3D27D4EB4F ^ seed
        n = (n ^ (n >> 30)) &* 0xBF58476D1CE4E5B9
        n = (n ^ (n >> 27)) &* 0x94D049BB133111EB
        return Double(n ^ (n >> 31)) / Double(UInt64.max)
    }
    func noise(_ p: CGPoint, scale: Double) -> Double {
        let x = Double(p.x) / scale, y = Double(p.y) / scale
        let ix = Int(floor(x)), iy = Int(floor(y)), fx = x - floor(x), fy = y - floor(y)
        let u = fx*fx*(3-2*fx), v = fy*fy*(3-2*fy)
        let a = hash(ix, iy)*(1-u) + hash(ix+1, iy)*u
        let b = hash(ix, iy+1)*(1-u) + hash(ix+1, iy+1)*u
        return a*(1-v)+b*v
    }
    func community(_ p: CGPoint) -> Double {
        0.62*noise(p, scale: 330) + 0.28*noise(p, scale: 125) + 0.10*noise(p, scale: 43)
    }
    func forest(_ p: CGPoint) -> Double {
        Self.smooth(0.52, 0.73, noise(CGPoint(x: p.x+411, y: p.y-217), scale: 270))
    }
    func clearance(_ p: CGPoint) -> Double {
        let roadDistance = roads.map { $0.distance(to: p) }.min() ?? .infinity
        let landmarkDistance = landmarks.map { hypot($0.x-p.x, $0.y-p.y) }.min() ?? .infinity
        return min(Self.smooth(22, 86, Double(roadDistance)), Self.smooth(42, 145, Double(landmarkDistance)))
    }
    func channels(_ p: CGPoint) -> (detail: Double, forest: Double, sunlight: Double) {
        let detail = (0.14 + 0.86*Self.smooth(0.30, 0.71, community(p))) * clearance(p)
        let shade = forest(p) * (0.35 + 0.65*clearance(p))
        let light = 0.36 + 0.64*noise(CGPoint(x: p.x+95, y: p.y), scale: 430)
        return (detail, shade, light)
    }
    static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x-a)/(b-a))); return t*t*(3-2*t)
    }
}
