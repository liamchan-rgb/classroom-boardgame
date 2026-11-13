import Foundation

struct MapPoint: Codable {
    let x: CGFloat
    let y: CGFloat
    var point: CGPoint { CGPoint(x: x, y: y) }
}

struct SceneDefinition: Codable {
    struct Prop: Codable {
        let asset: String
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let mirror: Bool
        let wind: Float
    }
    struct Road: Codable {
        let from: Int
        let to: Int
        let width: CGFloat
        let points: [MapPoint]
    }
    struct Discovery: Codable {
        let x: CGFloat
        let y: CGFloat
        let title: String
    }
    let seed: UInt64
    let props: [Prop]
    let roads: [Road]
    let discoveries: [Discovery]
    let textureBudgetMiB: Double

    static func load() -> SceneDefinition {
        guard let url = Bundle.main.url(forResource: "SceneMap", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let definition = try? JSONDecoder().decode(SceneDefinition.self, from: data) else {
            fatalError("Missing or invalid SceneMap.json")
        }
        return definition
    }
}

struct MeadowRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(state >> 33) / CGFloat(UInt64(1) << 31)
    }
    mutating func value(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        lower + (upper - lower) * next()
    }
}
