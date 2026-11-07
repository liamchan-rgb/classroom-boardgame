import Foundation
import ClassroomGameCore

/// New-game roster planning only. Saved units (including legacy deer and manual
/// edits) are authoritative; loading a campaign never calls this planner.
public struct MeadowPlannedEncounter: Codable, Equatable {
    public let nodeID: Int
    public let band: String
    public let distance: Double
    public let templates: [String]
}

public enum MeadowEncounterPlanner {
    public static let version = 2

    public static func plan(_ layout: GeneratedMeadowMap) -> [MeadowPlannedEncounter] {
        guard let start=layout.map.nodes.first(where:{$0.kind == .start})?.id else{return []}
        // Shortest physical road distance, rather than node ID, screen position,
        // or traversal history. Stable tie breaks avoid Dictionary/hash ordering.
        var distances=[start:0.0],remaining=Set(layout.map.nodes.map(\.id))
        while let node=remaining.min(by:{
            let a=distances[$0] ?? .infinity,b=distances[$1] ?? .infinity
            return a==b ? $0<$1:a<b
        }) {
            remaining.remove(node)
            guard let distance=distances[node] else{continue}
            for road in layout.roads where road.from==node || road.to==node {
                let other=road.from==node ? road.to:road.from
                let length=zip(road.points,road.points.dropFirst()).reduce(0.0){$0+hypot($1.1.x-$1.0.x,$1.1.y-$1.0.y)}
                distances[other]=min(distances[other] ?? .infinity,distance+length)
            }
        }
        func ordered(_ kind:NodeKind)->[MapNode] {
            layout.map.nodes.filter{$0.kind==kind}.sorted {
                let a=distances[$0.id] ?? .infinity,b=distances[$1.id] ?? .infinity
                return a==b ? $0.id<$1.id:a<b
            }
        }
        var result=[MeadowPlannedEncounter]()
        let combats=ordered(.combat),bosses=ordered(.boss)
        for (rank,node) in combats.enumerated() {
            let band=rank==0 ? "opening":(rank*2<combats.count ? "middle":"deep")
            let choices:[[String]]
            switch band {
            case "opening": choices=[["slime"]]
            case "middle": choices=[["wolf"],["goblinArcher"],["slime","wolf"],["slime","goblinArcher"]]
            default: choices=[["stoneGuardian"],["wolf","goblinArcher"],["stoneGuardian","slime"],["slime","wolf","goblinArcher"]]
            }
            result.append(.init(nodeID:node.id,band:band,distance:distances[node.id] ?? 0,
                                templates:choices[Int(sample(seed:layout.configuration.seed,node:node.id)%UInt64(choices.count))]))
        }
        for (rank,node) in bosses.enumerated() {
            // A short single-boss expedition should not open against the full
            // dragon's high group damage. Explicit boss-rush configurations keep
            // their final dragon; monster stats, skills and dice remain original.
            let readyForDragon=combats.count>=4 && layout.configuration.reward>=2
            let dragon=bosses.count==1 ? readyForDragon && sample(seed:layout.configuration.seed,node:node.id)&1==1:rank==bosses.count-1
            result.append(.init(nodeID:node.id,band:"boss",distance:distances[node.id] ?? 0,templates:[dragon ? "ruinDragon":"caveTroll"]))
        }
        return result.sorted{$0.nodeID<$1.nodeID}
    }

    /// Independent domain-separated SplitMix64 sample. Never consumes the
    /// layout/decorations stream or GameState.random used for battle dice.
    private static func sample(seed:UInt64,node:Int)->UInt64 {
        var z=(seed ^ 0x454e434f554e5431) &+ UInt64(node) &* 0x9e3779b97f4a7c15
        z=(z ^ (z>>30)) &* 0xbf58476d1ce4e5b9
        z=(z ^ (z>>27)) &* 0x94d049bb133111eb
        return z ^ (z>>31)
    }

    public static func summary(_ layout:GeneratedMeadowMap,catalog:GameCatalog)throws->String {
        let encounters=plan(layout)
        guard !encounters.isEmpty else{return "本次无战斗地点，可探索后返回营地结算。"}
        let lines=try encounters.map { encounter -> String in
            let names=try encounter.templates.map{try catalog.monster($0).name}.joined(separator:" + ")
            let label=encounter.band=="boss" ? "首领":"战斗"
            return "\(label) #\(encounter.nodeID) · \(names)"
        }
        return "本次遭遇（可在地图中编辑地点）\n"+lines.joined(separator:"\n")
    }
}
