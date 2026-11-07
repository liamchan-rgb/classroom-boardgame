import Foundation
import MeadowWorldSupport

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
        var nodeID: Int? = nil
    }
    struct Road: Codable {
        let from: Int
        let to: Int
        let width: CGFloat
        let points: [MapPoint]
        var sampled: Bool? = nil
    }
    struct Discovery: Codable {
        let x: CGFloat
        let y: CGFloat
        let title: String
        var kind: String? = nil
        var nodeID: Int? = nil
    }
    let seed: UInt64
    let props: [Prop]
    let roads: [Road]
    let discoveries: [Discovery]
    let textureBudgetMiB: Double
    var spawn: MapPoint? = nil
    var startNodeID: Int? = nil
    var mapHeight: CGFloat? = nil

    var worldBounds: CGRect { CGRect(x:-160,y:-220,width:1600,height:max(1160,(mapHeight ?? 720)+440)) }

    // Rise from the foot to the actual opaque PNG top, including each asset's
    // aspect and alpha margin. A short roof badge never floats at canvas top.
    static func landmarkBadgeRise(asset: String, width: CGFloat) -> CGFloat {
        let rises:[String:CGFloat]=["CampTent":(404*0.90-8)/607,
            "NodeCombatOutpost":0.92-43/512.0,"NodeBossSanctum":0.92-38/512.0,
            "NodeRewardCache":0.92-102/512.0,"NodeWaystone":0.92-17/512.0]
        return width*(rises[asset] ?? 0.92)+14
    }
    func landmarkBadgePoint(nodeID: Int?) -> CGPoint? {
        guard let nodeID,let prop=props.first(where:{$0.nodeID==nodeID}) else { return nil }
        return CGPoint(x:prop.x,y:prop.y-Self.landmarkBadgeRise(asset:prop.asset,width:prop.width))
    }

    static func generated(_ map: GeneratedMeadowMap) -> SceneDefinition {
        SceneDefinition(seed:map.configuration.seed,
            props:map.props.map { Prop(asset:$0.asset,x:CGFloat($0.x),y:CGFloat($0.y),width:CGFloat($0.width),mirror:false,wind:Float($0.wind),nodeID:$0.nodeID) },
            roads:map.roads.map { Road(from:$0.from,to:$0.to,width:CGFloat($0.width),points:$0.points.map { MapPoint(x:CGFloat($0.x),y:CGFloat($0.y)) },sampled:true) },
            discoveries:map.map.nodes.filter{$0.kind.rawValue != "start"}.map { Discovery(x:CGFloat($0.x*1280),y:CGFloat($0.y*map.coordinateHeight),title:$0.name,kind:$0.kind.rawValue,nodeID:$0.id) },
            textureBudgetMiB:166.14,spawn:MapPoint(x:CGFloat(map.spawn.x),y:CGFloat(map.spawn.y)),startNodeID:map.map.nodes.first{$0.kind.rawValue == "start"}!.id,mapHeight:CGFloat(map.coordinateHeight))
    }

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
