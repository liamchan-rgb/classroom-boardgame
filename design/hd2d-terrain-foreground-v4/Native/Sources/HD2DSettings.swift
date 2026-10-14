import Foundation
import CoreGraphics

// Presentation-only parameters. No game seed, path or command is mutated.
struct HD2DSettings: Equatable {
    var terrain = true
    var foregroundTrees = true
    var directionalLight = true
    var colorGrade = true
    var vegetation = true
    var relief = true
    var contactShadows = true
    var bloom = true
    var atmosphere = true
    var edgeDepth = true
    var environmentalMotion = true
    var shadowStrength: Double = 0.62
    var vegetationContrast: Double = 0.55
    var bloomStrength: Double = 0.22
    var atmosphereStrength: Double = 0.30
    var depthRadius: Double = 0.9
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
    case ground = 0, foliage = 1, rock = 2, building = 3, actor = 4, road = 5, lowPlant = 6, terrain = 7
    static func asset(_ id: String) -> Self {
        if id.hasPrefix("ground-") { return .ground }
        if id.hasPrefix("road-") { return .road }
        if id == "oak_single" || id == "fir_single" || id == "mixed_grove" || id == "fir_grove" { return .foliage }
        if id == "terrace" || id == "bank" { return .terrain }
        if id.contains("rock") { return .rock }
        if id.hasPrefix("camp") || id.hasPrefix("tower") || id.hasPrefix("ruin") || id == "fence" { return .building }
        if id == "ground_tuft" || id == "flowers" { return .lowPlant }
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
    var forestCenters: [CGPoint] {
        let shift = CGFloat(Int(seed % 23)-11)*4
        return [CGPoint(x: 300+shift,y:1080),CGPoint(x:1040,y:1380+shift),CGPoint(x:1390-shift,y:940),
                CGPoint(x:200,y:290-shift),CGPoint(x:1350+shift,y:350)]
    }
    func forest(_ p: CGPoint) -> Double {
        let cluster = forestCenters.map { center -> Double in
            let x = Double(p.x-center.x)/220, y = Double(p.y-center.y)/175
            return exp(-(x*x+y*y)*0.85)
        }.max() ?? 0
        let variation = noise(CGPoint(x:p.x+411,y:p.y-217),scale:150)
        return min(1,cluster*(0.74+0.26*variation))
    }
    // Geometric low hills. This is a height field, not luminance from painted grass.
    func height(_ p: CGPoint) -> Double {
        38*noise(p,scale:570)+18*noise(CGPoint(x:p.x+280,y:p.y-115),scale:240)
    }
    func normal(_ p: CGPoint) -> (x: Double,y: Double,z: Double) {
        let step: CGFloat = 12
        let dx = (height(CGPoint(x:p.x+step,y:p.y))-height(CGPoint(x:p.x-step,y:p.y)))/Double(step*2)
        let dy = (height(CGPoint(x:p.x,y:p.y+step))-height(CGPoint(x:p.x,y:p.y-step)))/Double(step*2)
        let x = -dx*3.2,y = -dy*3.2,length = sqrt(x*x+y*y+1)
        return (x/length,y/length,1/length)
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
