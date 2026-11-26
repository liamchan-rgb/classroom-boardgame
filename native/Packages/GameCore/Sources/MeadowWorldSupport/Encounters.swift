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
    public static let version = 3

    /// Road distance from each node to its nearest camp, and which camp that is. With several team camps every camp
    /// gets its own easy-to-hard ring of spots around it (a single camp: the same as before).
    public static func campDistances(_ layout: GeneratedMeadowMap) -> [Int:(camp:Int,distance:Double)] {
        let camps=layout.map.nodes.filter{$0.kind == .start}.map(\.id).sorted()
        var best=[Int:(camp:Int,distance:Double)]()
        for camp in camps { best[camp]=(camp,0) }
        var remaining=Set(layout.map.nodes.map(\.id))
        // Shortest physical road distance, rather than node ID, screen position,
        // or traversal history. Stable tie breaks avoid Dictionary/hash ordering.
        while let node=remaining.min(by:{
            let a=best[$0]?.distance ?? .infinity,b=best[$1]?.distance ?? .infinity
            return a==b ? $0<$1:a<b
        }) {
            remaining.remove(node)
            guard let here=best[node] else{continue}
            for road in layout.roads where road.from==node || road.to==node {
                let other=road.from==node ? road.to:road.from
                let length=zip(road.points,road.points.dropFirst()).reduce(0.0){$0+hypot($1.1.x-$1.0.x,$1.1.y-$1.0.y)}
                let d=here.distance+length
                if let old=best[other],old.distance<d || (old.distance==d && old.camp<=here.camp) {continue}
                best[other]=(here.camp,d)
            }
        }
        return best
    }

    public static func plan(_ layout: GeneratedMeadowMap) -> [MeadowPlannedEncounter] {
        guard layout.map.nodes.contains(where:{$0.kind == .start}) else{return []}
        let near=campDistances(layout)
        let distances=near.mapValues(\.distance)
        func ordered(_ kind:NodeKind)->[MapNode] {
            layout.map.nodes.filter{$0.kind==kind}.sorted {
                let a=distances[$0.id] ?? .infinity,b=distances[$1.id] ?? .infinity
                return a==b ? $0.id<$1.id:a<b
            }
        }
        var result=[MeadowPlannedEncounter]()
        let combats=ordered(.combat),bosses=ordered(.boss)
        // Each camp's own spots, nearest first: every team meets an opening fight, then middle, then deep ones.
        let camps=Set(combats.compactMap{near[$0.id]?.camp})
        for node in combats {
            let mine=combats.filter{near[$0.id]?.camp==near[node.id]?.camp}
            let rank=mine.firstIndex(where:{$0.id==node.id}) ?? 0
            let count=camps.count>1 ? mine.count:combats.count
            let band=rank==0 ? "opening":(rank*2<count ? "middle":"deep")
            let isApex=band=="deep" && ((layout.configuration.total>=14 && rank==count-1) || (count>=5 && rank==count-1))
            let choices:[[String]]
            switch band {
            case "opening":
                choices=[["slime"],["hopShroom"],["acornBandit"],["bubbleCrab"]]
            case "middle":
                choices=[["wolf"],["goblinArcher"],["stingWasp"],["brambleSprite"],
                         ["slime","goblinArcher"],["hopShroom","acornBandit"],["bubbleCrab","stingWasp"],["wolf","goblinShaman"]]
            default:
                if isApex {
                    choices=[["crystalGolem"],["frostAlphaWolf","wolf"],["runeKnight","shadowOwl"],["crystalGolem","goblinShaman"]]
                } else {
                    choices=[["stoneGuardian"],["runeKnight"],["emberLizard"],
                             ["stoneGuardian","goblinShaman"],["brambleSprite","shadowOwl"],["emberLizard","wolf"],["bubbleCrab","goblinArcher","goblinShaman"]]
                }
            }
            result.append(.init(nodeID:node.id,band:band,distance:distances[node.id] ?? 0,
                                templates:choices[Int(sample(seed:layout.configuration.seed,node:node.id)%UInt64(choices.count))]))
        }
        for (rank,node) in bosses.enumerated() {
            // A short single-boss expedition stays in the lightweight boss tier
            // so students never open directly against endgame group damage.
            let readyForHeavyBoss=combats.count>=4 && layout.configuration.reward>=2
            let total=layout.configuration.total
            let pool:[String]
            if !readyForHeavyBoss {
                pool=bosses.count==1 ? ["caveTroll","mushroomKing"]:(rank==bosses.count-1 ? ["ruinDragon","frostPhoenix"]:["mushroomKing","caveTroll"])
            } else if bosses.count==1 {
                if total>=18 { pool=["frostPhoenix","eclipseBehemoth"] }
                else if total>=14 { pool=["thornTreant","ruinDragon","frostPhoenix"] }
                else { pool=["caveTroll","goblinWarlord","thornTreant","ruinDragon"] }
            } else if rank==bosses.count-1 {
                pool=(total>=18 || bosses.count>=3) ? ["ruinDragon","frostPhoenix","eclipseBehemoth"]:["ruinDragon","frostPhoenix"]
            } else {
                pool=["mushroomKing","caveTroll","goblinWarlord","thornTreant"]
            }
            let picked=pool[Int(sample(seed:layout.configuration.seed,node:node.id)%UInt64(pool.count))]
            result.append(.init(nodeID:node.id,band:"boss",distance:distances[node.id] ?? 0,templates:[picked]))
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
