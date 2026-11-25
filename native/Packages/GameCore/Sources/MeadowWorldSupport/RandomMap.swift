import Foundation
import ClassroomGameCore

public struct MeadowMapConfiguration: Codable, Equatable {
    public var seed: UInt64 = 31827
    public var total = 10
    public var combat = 4
    public var boss = 1
    public var reward = 3
    public var empty = 1
    public var extraRoads = 1
    public var minimumBossHops = 0
    public var decorationCount = 100
    /// Team camps (1–3). Each team starts at its own camp; extra camps take the place of the last empty/supply/combat nodes.
    public var starts: Int? = nil
    public init() {}
    public static func suggested(total: Int, seed: UInt64 = 31827) -> Self {
        var c = Self(); c.seed = seed; c.total = total
        guard (4...30).contains(total) else { return c }
        c.combat = Int(floor(Double(total) * 0.4)); c.reward = Int(floor(Double(total) * 0.3))
        c.empty = total - 2 - c.combat - c.reward
        return c
    }
    public func changingTotal(to value: Int) throws -> Self {
        guard (4...30).contains(value) else { throw GameError("总节点数须为4—30。") }
        var c=Self.suggested(total:value,seed:seed)
        c.extraRoads=min(extraRoads,MeadowMapGenerator.maximumExtraRoads(total:value))
        c.minimumBossHops=min(minimumBossHops,value-1);c.decorationCount=decorationCount
        try c.validate();return c
    }
    /// Field order: combat, boss, reward, empty. Preserve the edited value;
    /// consume empty slots first, then other categories in stable order.
    public func changingCount(field: Int, to value: Int) throws -> Self {
        try validate()
        guard (0...3).contains(field) else { throw GameError("节点分类无效。") }
        var values=[combat,boss,reward,empty]
        values[field]=min(total-1,max(0,value))
        let difference=total-1-values.reduce(0,+)
        if difference>=0 { values[field==3 ? 0:3]+=difference }
        else {
            var remaining = -difference
            for index in [3,0,2,1] where index != field {
                let take=min(values[index],remaining);values[index]-=take;remaining-=take
            }
        }
        var c=self;c.combat=values[0];c.boss=values[1];c.reward=values[2];c.empty=values[3]
        try c.validate();return c
    }
    public func validate() throws {
        guard (4...30).contains(total) else { throw GameError("总节点数须为4—30。") }
        guard [combat,boss,reward,empty].allSatisfy({ (0...30).contains($0) }),
              1 + combat + boss + reward + empty == total else { throw GameError("起点固定1，各类数量须为非负整数，总和须等于总节点数。") }
        guard (0...MeadowMapGenerator.maximumExtraRoads(total: total)).contains(extraRoads) else {
            throw GameError("此规模可增加0—\(MeadowMapGenerator.maximumExtraRoads(total: total))条环路道路。")
        }
        guard (0..<total).contains(minimumBossHops), (0...120).contains(decorationCount) else { throw GameError("Boss距离或装饰数量无效。") }
        guard (1...3).contains(starts ?? 1), total-1-boss >= (starts ?? 1)-1 else { throw GameError("队伍起点须为1—3个，且地点数量足够。") }
    }
}

public struct MeadowWorldPoint: Codable, Equatable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x=x; self.y=y }
}
public struct MeadowWorldRoad: Codable, Equatable {
    public let from: Int
    public let to: Int
    public let width: Double
    public let points: [MeadowWorldPoint]
}
public struct MeadowWorldProp: Codable, Equatable {
    public let asset: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let wind: Double
    public var nodeID: Int? = nil
}
public struct GeneratedMeadowMap: Codable, Equatable {
    public let generatorVersion: Int
    public let configuration: MeadowMapConfiguration
    public let map: GameMap
    public let roads: [MeadowWorldRoad]
    public let props: [MeadowWorldProp]
    public let coordinateHeight: Double
    public let spawn: MeadowWorldPoint
}

// Stable SplitMix64 streams; no Swift hashValue, process random seed or dice RNG.
private struct MapRandom {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z=state; z=(z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z=(z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
    mutating func value(_ low: Double, _ high: Double) -> Double {
        low + (high-low) * Double(next() >> 11) / 9007199254740992
    }
    mutating func shuffle<T>(_ values: inout [T]) {
        guard values.count > 1 else { return }
        for i in stride(from: values.count-1, through: 1, by: -1) {
            values.swapAt(i, Int(next() % UInt64(i+1)))
        }
    }
}

public enum MeadowMapGenerator {
    public static let version = 3

    /// All landmark variants per node kind; keeps Combat (red), Reward (green), Boss (gold/purple), and Rest (calm blue/warm) immediately readable.
    public static let landmarkVariants: [NodeKind: [(asset: String, width: Double)]] = [
        .start: [("CampTent", 105)],
        .combat: [("NodeCombatOutpost", 90), ("NodeCombatTower", 90), ("NodeCombatDen", 92)],
        .boss: [("NodeBossSanctum", 104), ("NodeBossAltar", 102), ("NodeBossRuins", 104)],
        .reward: [("NodeRewardCache", 86), ("NodeRewardWagon", 92), ("NodeRewardCottage", 92)],
        .empty: [("NodeWaystone", 76), ("NodeShrine", 80), ("NodePavilion", 84)]
    ]

    public static let landmarkAssets: [NodeKind: Set<String>] = landmarkVariants.mapValues { Set($0.map(\.asset)) }

    /// Complete set of prop/landmark asset names permitted in saved campaign layouts (backward compatible with v3 saves).
    public static let supportedAssets: Set<String> = [
        "CampTent",
        "NodeCombatOutpost", "NodeCombatTower", "NodeCombatDen",
        "NodeBossSanctum", "NodeBossAltar", "NodeBossRuins",
        "NodeRewardCache", "NodeRewardWagon", "NodeRewardCottage",
        "NodeWaystone", "NodeShrine", "NodePavilion",
        "OakA", "OakB", "Pines",
        "MapTreeAutumnOak", "MapTreeAutumnMaple", "MapTreeBlossom", "MapTreePineAlpine",
        "Shrub", "MapShrubAutumn",
        "RockLow", "RockHigh", "RockSmall", "MapRockSlate", "MapRockAutumn",
        "Flowers", "MapFlowersBlue", "MapFlowersCrimson", "MapFlowersLavender",
        "MapPond", "MapBridgeWood", "MapCliffTerrace", "MapPropStoneArch",
        "MapPropSignpost", "MapPropLanternPost", "MapPropCampfire",
        "MapPropRuinedPillar", "MapPropSupplies", "MapLogMushrooms",
        "MapGroundStonePlaza", "MapPropVictoryBanner"
    ]

    /// Smooth deterministic biome value in [0, 1], shared in spirit with `meadowGroundFragment` so flora matches terrain tinting.
    public static func biomeNoise(x: Double, y: Double, seed: UInt64) -> Double {
        let phase = Double(seed % 1024) * 0.61803398875
        let n1 = sin(x * 0.0029 + phase) * cos(y * 0.0031 - phase * 0.7)
        let n2 = sin((x * 0.0017 - y * 0.0021) + phase * 1.3)
        return max(0, min(1, 0.5 + 0.34 * n1 + 0.22 * n2))
    }

    public static func maximumExtraRoads(total: Int) -> Int {
        guard (4...30).contains(total) else { return 0 }
        // Preserve the previous control's conservative cycle budget. Layout is
        // now a scattered planar graph, not this budget's historical grid.
        let cols=Int(sqrt(Double(total)*1.35).rounded())
        return total-cols-Int(ceil(Double(total)/Double(cols)))+1
    }
    private struct Rect {
        let left:Double,top:Double,right:Double,bottom:Double
        func blocks(_ a:MeadowWorldPoint,_ b:MeadowWorldPoint) -> Bool {
            var lo=0.0,hi=1.0
            for (origin,delta,minV,maxV) in [(a.x,b.x-a.x,left,right),(a.y,b.y-a.y,top,bottom)] {
                if abs(delta)<1e-9 { if origin<=minV+1e-6 || origin>=maxV-1e-6 { return false };continue }
                let t1=(minV-origin)/delta,t2=(maxV-origin)/delta
                lo=max(lo,min(t1,t2));hi=min(hi,max(t1,t2))
                if lo>=hi-1e-6 { return false }
            }
            return lo<1-1e-6 && hi>1e-6
        }
        var corners:[MeadowWorldPoint] { [.init(left,top),.init(right,top),.init(right,bottom),.init(left,bottom)] }
    }
    private static func cross(_ a:MeadowWorldPoint,_ b:MeadowWorldPoint,_ c:MeadowWorldPoint)->Double {
        (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)
    }
    private static func length(_ a:MeadowWorldPoint,_ b:MeadowWorldPoint)->Double { hypot(b.x-a.x,b.y-a.y) }
    private struct Triangle { let a:Int,b:Int,c:Int }
    private static func planarEdges(_ input:[MeadowWorldPoint],height:Double)->[(Int,Int)] {
        // Bowyer-Watson triangulation; sorted boundary keys keep replay stable.
        let n=input.count,m=max(1280,height)*8
        let p=input+[.init(-m,-m),.init(3*m,-m),.init(-m,3*m)]
        var triangles=[Triangle(a:n,b:n+1,c:n+2)]
        for i in 0..<n {
            var boundary=[Int:Int](),keep=[Triangle]()
            for t in triangles {
                let a=p[t.a],b=p[t.b],c=p[t.c],q=p[i]
                let ax=a.x-q.x,ay=a.y-q.y,bx=b.x-q.x,by=b.y-q.y,cx=c.x-q.x,cy=c.y-q.y
                let d=(ax*ax+ay*ay)*(bx*cy-cx*by)-(bx*bx+by*by)*(ax*cy-cx*ay)+(cx*cx+cy*cy)*(ax*by-bx*ay)
                let inside=cross(a,b,c)>0 ? d>1e-6:d < -1e-6
                if inside {
                    for (u,v) in [(t.a,t.b),(t.b,t.c),(t.c,t.a)] {
                        let key=min(u,v)*(n+3)+max(u,v);boundary[key,default:0]+=1
                    }
                } else { keep.append(t) }
            }
            for key in boundary.keys.sorted() where boundary[key]==1 {
                let a=key/(n+3),b=key%(n+3)
                if abs(cross(p[a],p[b],p[i]))>1e-7 { keep.append(Triangle(a:a,b:b,c:i)) }
            }
            triangles=keep
        }
        var keys=Set<Int>()
        for t in triangles where max(t.a,max(t.b,t.c))<n {
            for (a,b) in [(t.a,t.b),(t.b,t.c),(t.c,t.a)] { keys.insert(min(a,b)*n+max(a,b)) }
        }
        return keys.sorted().map{($0/n,$0%n)}
    }
    private static func route(_ p:MeadowWorldPoint,_ q:MeadowWorldPoint,obstacles:[Rect],bend:Double)->[MeadowWorldPoint]? {
        var active=Set(obstacles.indices.filter{obstacles[$0].blocks(p,q)})
        for _ in 0..<obstacles.count+1 {
            let vertices=[p,q]+active.sorted().flatMap{obstacles[$0].corners}
            var costs=Array(repeating:Double.infinity,count:vertices.count),previous=Array(repeating:-1,count:vertices.count),used=Set<Int>()
            costs[0]=0
            for _ in vertices.indices {
                guard let u=vertices.indices.filter({!used.contains($0)}).min(by:{costs[$0]<costs[$1]}),costs[u].isFinite else { break }
                if u==1 { break };used.insert(u)
                for v in vertices.indices where v != u && !used.contains(v) {
                    if active.contains(where:{obstacles[$0].blocks(vertices[u],vertices[v])}) { continue }
                    let next=costs[u]+length(vertices[u],vertices[v])
                    if next<costs[v] { costs[v]=next;previous[v]=u }
                }
            }
            guard costs[1].isFinite else { return nil }
            var path=[q],index=1
            while index != 0 { index=previous[index];guard index>=0 else{return nil};path.append(vertices[index]) }
            path.reverse()
            // Explicit loop avoids shadowing the obstacle index in the closure.
            var found=Set<Int>()
            for i in obstacles.indices where !active.contains(i) {
                if zip(path,path.dropFirst()).contains(where:{obstacles[i].blocks($0.0,$0.1)}) { found.insert(i) }
            }
            if !found.isEmpty { active.formUnion(found);continue }
            // Rounded visibility corners; the outer routing rectangle includes
            // enough clearance to round without cutting the actual building.
            var smooth=[p]
            if path.count==2 {
                let l=length(p,q),m=MeadowWorldPoint((p.x+q.x)/2-(q.y-p.y)/l*bend,(p.y+q.y)/2+(q.x-p.x)/l*bend)
                for i in 1...16 {
                    let t=Double(i)/16,s=1-t
                    smooth.append(.init(s*s*p.x+2*s*t*m.x+t*t*q.x,s*s*p.y+2*s*t*m.y+t*t*q.y))
                }
            } else {
                for i in 1..<path.count-1 {
                    let a=path[i-1],b=path[i],c=path[i+1]
                    let cut=min(18,min(length(a,b),length(b,c))*0.22)
                    let entry=MeadowWorldPoint(b.x+(a.x-b.x)*cut/length(a,b),b.y+(a.y-b.y)*cut/length(a,b))
                    let exit=MeadowWorldPoint(b.x+(c.x-b.x)*cut/length(b,c),b.y+(c.y-b.y)*cut/length(b,c))
                    smooth.append(entry)
                    for k in 1...6 {
                        let t=Double(k)/6,s=1-t
                        smooth.append(.init(s*s*entry.x+2*s*t*b.x+t*t*exit.x,s*s*entry.y+2*s*t*b.y+t*t*exit.y))
                    }
                }
                smooth.append(q)
            }
            return smooth
        }
        return nil
    }
    private static func conflicts(_ a:MeadowWorldRoad,_ b:MeadowWorldRoad)->Bool {
        if a.from==b.from || a.from==b.to || a.to==b.from || a.to==b.to { return false }
        for (p,q) in zip(a.points,a.points.dropFirst()) { for (r,s) in zip(b.points,b.points.dropFirst()) {
            if max(p.x,q.x)+22<min(r.x,s.x) || max(r.x,s.x)+22<min(p.x,q.x) || max(p.y,q.y)+22<min(r.y,s.y) || max(r.y,s.y)+22<min(p.y,q.y) { continue }
            if cross(p,q,r)*cross(p,q,s)<0 && cross(r,s,p)*cross(r,s,q)<0 { return true }
            if segmentDistance(p,r,s)<22 || segmentDistance(q,r,s)<22 || segmentDistance(r,p,q)<22 || segmentDistance(s,p,q)<22 { return true }
        } }
        return false
    }
    private static func segmentDistance(_ p:MeadowWorldPoint,_ a:MeadowWorldPoint,_ b:MeadowWorldPoint)->Double {
        let dx=b.x-a.x,dy=b.y-a.y,t=max(0,min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/max(0.001,dx*dx+dy*dy)))
        return hypot(p.x-a.x-t*dx,p.y-a.y-t*dy)
    }
    public static func distance(_ p:MeadowWorldPoint,to roads:[MeadowWorldRoad])->Double {
        roads.flatMap { zip($0.points,$0.points.dropFirst()).map{segmentDistance(p,$0.0,$0.1)} }.min() ?? .infinity
    }
    public static func generate(_ c:MeadowMapConfiguration)throws->GeneratedMeadowMap {
        try c.validate()
        for attempt in 0..<64 {
            var layout=MapRandom(state:c.seed ^ 0x4c41594f5554 &+ UInt64(attempt))
            let height=max(860,500+Double(c.total)*55),phase=layout.value(0,2 * .pi),lobe=layout.value(0,2 * .pi)
            let rx=layout.value(460,500),ry=(height-360)/2
            var positions=[MeadowWorldPoint]()
            for i in 0..<c.total {
                let theta=Double(i)*2.399963229728653+phase+layout.value(-0.06,0.06)
                let radius=sqrt((Double(i)+0.5)/Double(c.total))
                let shape=0.94+0.07*sin(theta*3+lobe)+0.04*cos(theta*5-phase)
                let y=radius*sin(theta)*shape
                positions.append(.init(640+rx*radius*cos(theta)*shape+42*sin(y*3+phase),height/2+ry*y))
            }
            // Relax in physical coordinates, so a tall footprint does not
            // compress neighboring points into narrow horizontal rows.
            for _ in 0..<72 {
                for i in positions.indices { for j in positions.indices where j<i {
                    let d=length(positions[i],positions[j])
                    if d<180 && d>1e-6 {
                        let push=(180-d)*0.52,dx=(positions[i].x-positions[j].x)/d*push,dy=(positions[i].y-positions[j].y)/d*push
                        positions[i].x+=dx;positions[i].y+=dy;positions[j].x-=dx;positions[j].y-=dy
                    }
                } }
                for i in positions.indices { positions[i].x=max(100,min(1180,positions[i].x));positions[i].y=max(175,min(height-150,positions[i].y)) }
            }
            if positions.indices.contains(where:{i in positions.indices.contains{j in j<i && length(positions[i],positions[j])<174}}) { continue }
            // Every building sits directly behind its road endpoint: this point
            // is its front apron, not a separate remote node marker.
            let obstacles=positions.map{Rect(left:$0.x-73,top:$0.y-144,right:$0.x+73,bottom:$0.y-12)}
            let inner=positions.map{Rect(left:$0.x-66,top:$0.y-138,right:$0.x+66,bottom:$0.y-14)}
            var topology=MapRandom(state:c.seed ^ 0x544f504f &+ UInt64(attempt)),curves=MapRandom(state:c.seed ^ 0x524f414453)
            var routes=[(MeadowWorldRoad,Double)]()
            for (a,b) in planarEdges(positions,height:height) {
                guard let points=route(positions[a],positions[b],obstacles:obstacles,bend:curves.value(-38,38)) else { continue }
                if inner.contains(where:{rect in zip(points,points.dropFirst()).contains{rect.blocks($0.0,$0.1)}}) { continue }
                let road=MeadowWorldRoad(from:a,to:b,width:22,points:points)
                routes.append((road,zip(points,points.dropFirst()).map{length($0.0,$0.1)}.reduce(0,+)*topology.value(0.85,1.3)))
            }
            routes.sort{$0.1<$1.1}
            var groups=Array(0..<c.total),roads=[MeadowWorldRoad](),spare=[MeadowWorldRoad]()
            for (road,_) in routes {
                let a=road.from,b=road.to,ga=groups[a],gb=groups[b]
                if ga != gb && !roads.contains(where:{conflicts(road,$0)}) {
                    roads.append(road);groups=groups.map{$0==gb ? ga:$0}
                } else { spare.append(road) }
            }
            guard roads.count==c.total-1 else { continue }
            for road in spare where roads.count<c.total-1+c.extraRoads {
                if !roads.contains(where:{conflicts(road,$0)}) { roads.append(road) }
            }
            guard roads.count==c.total-1+c.extraRoads else { continue }
            roads.sort{$0.from==$1.from ? $0.to<$1.to:$0.from<$1.from}
            let start=positions.indices.max{ positions[$0].y-positions[$0].x*0.25 < positions[$1].y-positions[$1].x*0.25 }!
            var distance=Array(repeating:-1,count:c.total);distance[start]=0
            var queue=[start],cursor=0
            while cursor<queue.count {
                let u=queue[cursor];cursor+=1
                for road in roads {
                    let v=road.from==u ? road.to:road.to==u ? road.from:-1
                    if v>=0 && distance[v]<0 {distance[v]=distance[u]+1;queue.append(v)}
                }
            }
            func hopsFrom(_ origin:Int)->[Int] {
                var d=Array(repeating:-1,count:c.total);d[origin]=0;var q=[origin],i=0
                while i<q.count {let u=q[i];i+=1;for road in roads {let v=road.from==u ? road.to:road.to==u ? road.from:-1;if v>=0 && d[v]<0 {d[v]=d[u]+1;q.append(v)}}}
                return d
            }
            var remaining=positions.indices.filter{$0 != start};topology.shuffle(&remaining)
            var kinds=Array(repeating:NodeKind.empty,count:c.total);kinds[start] = .start
            var camps=[start]
            if (c.starts ?? 1)>1 {
                // Team maps: camps first (each as far in road hops from the camps already placed as possible), then the
                // bosses where every camp is about equally far away, so no team starts next to all the bosses.
                for _ in 1..<(c.starts ?? 1) {
                    var hops=Array(repeating:Int.max,count:c.total)
                    for camp in camps {let d=hopsFrom(camp);for n in 0..<c.total where d[n]>=0 {hops[n]=min(hops[n],d[n])}}
                    guard let pick=remaining.max(by:{hops[$0]==hops[$1] ? $0>$1:hops[$0]<hops[$1]}) else{break}
                    camps.append(pick);kinds[pick] = .start;remaining.removeAll{$0==pick}
                }
                let tables=camps.map(hopsFrom)
                func spread(_ n:Int)->Int {let v=tables.map{$0[n]};return (v.max() ?? 0)-(v.min() ?? 0)}
                func nearest(_ n:Int)->Int {tables.map{$0[n]}.min() ?? 0}
                remaining.sort{spread($0)==spread($1) ? (nearest($0)==nearest($1) ? $0<$1:nearest($0)>nearest($1)):spread($0)<spread($1)}
                let bosses=Array(remaining.prefix(c.boss));if bosses.contains(where:{nearest($0)<c.minimumBossHops}){continue}
                for id in bosses{kinds[id] = .boss};remaining.removeAll{bosses.contains($0)};topology.shuffle(&remaining)
            } else {
                remaining.sort{distance[$0]>distance[$1]}
                let bosses=Array(remaining.prefix(c.boss));if bosses.contains(where:{distance[$0]<c.minimumBossHops}){continue}
                for id in bosses{kinds[id] = .boss};remaining.removeAll{bosses.contains($0)};topology.shuffle(&remaining)
            }
            for (id,kind) in zip(remaining,Array(repeating:NodeKind.combat,count:c.combat)+Array(repeating:NodeKind.reward,count:c.reward)+Array(repeating:NodeKind.empty,count:c.empty)){kinds[id]=kind}
            let titles:[NodeKind:String]=[.start:"起点营地",.combat:"林间战斗",.boss:"首领遗迹",.reward:"补给棚",.empty:"林间水井"]
            let nodes=positions.indices.map{MapNode(id:$0,name:"\(titles[kinds[$0]]!) · \($0+1)",kind:kinds[$0],x:positions[$0].x/1280,y:positions[$0].y/height,reward:kinds[$0] == .reward ? NodeReward():nil)}
            let map=GameMap(nodes:nodes,roads:roads.map{MapRoad($0.from,$0.to)},seed:c.seed,revealed:Set(camps));try map.validate()
            var variantRNG=MapRandom(state:c.seed ^ 0x4c414e44)
            var variantDecks:[NodeKind:[(asset:String,width:Double)]]=[:]
            var variantCursors:[NodeKind:Int]=[:]
            for (kind,list) in Self.landmarkVariants {
                var deck=list;variantRNG.shuffle(&deck);variantDecks[kind]=deck;variantCursors[kind]=0
            }
            var props=positions.indices.map{ id -> MeadowWorldProp in
                let kind=kinds[id]
                let deck=variantDecks[kind] ?? [("NodeWaystone",76)]
                let cursor=variantCursors[kind] ?? 0
                variantCursors[kind]=cursor+1
                let pick=deck[cursor%deck.count]
                return MeadowWorldProp(asset:pick.asset,x:positions[id].x,y:positions[id].y-26,width:pick.width,wind:0,nodeID:id)
            }
            let landmarkCount=props.count
            let bossPositions=positions.indices.filter{kinds[$0] == .boss}.map{positions[$0]}
            let campPositions=positions.indices.filter{kinds[$0] == .start}.map{positions[$0]}
            var decoration=MapRandom(state:c.seed ^ 0x50524f5053)
            let maxProps=c.decorationCount+landmarkCount

            enum Zone { case sanctum, autumn, blossom, meadow }
            func zoneAt(_ p:MeadowWorldPoint)->Zone {
                if bossPositions.contains(where:{length($0,p)<235}) { return .sanctum }
                let b=Self.biomeNoise(x:p.x,y:p.y,seed:c.seed)
                if b>0.60 { return .autumn }
                if b<0.38 { return .blossom }
                return .meadow
            }
            func clearanceOK(_ p:MeadowWorldPoint,roadClear:Double=58,nodeClear:Double=84,extraPropClear:Double=0)->Bool {
                guard self.distance(p,to:roads)>roadClear else { return false }
                guard positions.allSatisfy({length($0,p)>nodeClear}) else { return false }
                guard campPositions.allSatisfy({hypot($0.x-p.x,$0.y-p.y-26)>152}) else { return false }
                return props.allSatisfy { prop in
                    let minDist:Double
                    if prop.nodeID != nil {
                        minDist = prop.asset=="CampTent" ? 152 : max(126, extraPropClear)
                    } else if prop.asset=="MapPond" || prop.asset=="MapCliffTerrace" {
                        minDist = max(78, prop.width*0.62, extraPropClear)
                    } else {
                        minDist = max(36, prop.width*0.54, extraPropClear)
                    }
                    return hypot(prop.x-p.x,prop.y-p.y)>minDist
                }
            }
            func windFor(_ asset:String)->Double {
                if asset.hasPrefix("Rock") || asset.hasPrefix("MapRock") || asset=="MapPond" || asset=="MapCliffTerrace" || asset=="MapPropStoneArch" || asset=="MapPropRuinedPillar" || asset=="MapLogMushrooms" { return 0 }
                return 1
            }
            func widthFor(_ asset:String)->Double {
                switch asset {
                case "Flowers","MapFlowersBlue","MapFlowersCrimson","MapFlowersLavender": return decoration.value(15,24)
                case "Shrub","MapShrubAutumn": return decoration.value(26,38)
                case "RockLow","RockHigh","RockSmall","MapRockSlate","MapRockAutumn": return decoration.value(70,100)
                case "MapPond": return decoration.value(104,126)
                case "MapCliffTerrace": return decoration.value(116,144)
                case "MapPropStoneArch": return decoration.value(62,74)
                case "MapPropRuinedPillar": return decoration.value(42,52)
                case "MapLogMushrooms": return decoration.value(48,60)
                default: return decoration.value(62,90)
                }
            }

            // 1. Scenic focal features (ponds, border cliffs, stone arch, ruined pillars near boss, mossy logs)
            if c.decorationCount >= 18 {
                let targetPonds = c.total >= 12 ? 2 : 1
                var placedPonds = 0
                for _ in 0..<140 where placedPonds < targetPonds && props.count < maxProps {
                    let p=MeadowWorldPoint(decoration.value(90,1190),decoration.value(85,height-95))
                    guard clearanceOK(p,roadClear:88,nodeClear:125,extraPropClear:90) else { continue }
                    let pw=widthFor("MapPond")
                    props.append(MeadowWorldProp(asset:"MapPond",x:p.x,y:p.y,width:pw,wind:0))
                    placedPonds += 1
                    // Tuck 2 flowers beside the pond bank
                    for _ in 0..<8 {
                        if props.count >= maxProps { break }
                        let ang=decoration.value(0,2 * .pi), rad=decoration.value(pw*0.58,pw*0.74)
                        let fp=MeadowWorldPoint(p.x+cos(ang)*rad,p.y+sin(ang)*rad*0.72)
                        if self.distance(fp,to:roads)>58 && positions.allSatisfy({length($0,fp)>84}) && campPositions.allSatisfy({hypot($0.x-fp.x,$0.y-26-fp.y)>152}) && props.allSatisfy({hypot($0.x-fp.x,$0.y-fp.y)>($0.asset=="MapPond" ? pw*0.52 : ($0.nodeID != nil ? ($0.asset=="CampTent" ? 152:126):22))}) {
                            let fa = decoration.next()%2==0 ? "MapFlowersBlue":"Flowers"
                            props.append(MeadowWorldProp(asset:fa,x:fp.x,y:fp.y,width:widthFor(fa),wind:1))
                            break
                        }
                    }
                }
                // Perimeter cliff terraces framing upper/outer edges
                let targetCliffs = min(4, max(2, c.decorationCount/28))
                var placedCliffs = 0
                for _ in 0..<140 where placedCliffs < targetCliffs && props.count < maxProps {
                    let edgePick = Int(decoration.next()%4)
                    let p:MeadowWorldPoint
                    if edgePick < 2 { p=MeadowWorldPoint(decoration.value(40,1240),decoration.value(-55,115)) }
                    else if edgePick == 2 { p=MeadowWorldPoint(decoration.value(-55,85),decoration.value(80,height-80)) }
                    else { p=MeadowWorldPoint(decoration.value(1195,1335),decoration.value(80,height-80)) }
                    guard clearanceOK(p,roadClear:72,nodeClear:112,extraPropClear:84) else { continue }
                    props.append(MeadowWorldProp(asset:"MapCliffTerrace",x:p.x,y:p.y,width:widthFor("MapCliffTerrace"),wind:0))
                    placedCliffs += 1
                }
                // Ancient ruined pillars around Boss zones
                for boss in bossPositions {
                    var placed = 0
                    for _ in 0..<45 where placed < 2 && props.count < maxProps {
                        let ang=decoration.value(0,2 * .pi), rad=decoration.value(128,215)
                        let p=MeadowWorldPoint(boss.x+cos(ang)*rad,boss.y+sin(ang)*rad)
                        guard (-40...1320).contains(p.x),(-40...(height+60)).contains(p.y) else { continue }
                        guard clearanceOK(p,roadClear:64,nodeClear:105,extraPropClear:52) else { continue }
                        props.append(MeadowWorldProp(asset:"MapPropRuinedPillar",x:p.x,y:p.y,width:widthFor("MapPropRuinedPillar"),wind:0))
                        placed += 1
                    }
                }
                // 1-2 mossy stone arches & 2-3 fallen mushroom logs in scenic woodland pockets
                for (asset,target) in [("MapPropStoneArch", c.total >= 10 ? 2 : 1),("MapLogMushrooms", c.total >= 10 ? 3 : 2)] {
                    var placed = 0
                    for _ in 0..<90 where placed < target && props.count < maxProps {
                        let p=MeadowWorldPoint(decoration.value(40,1240),decoration.value(40,height-40))
                        guard clearanceOK(p,roadClear:68,nodeClear:105,extraPropClear:56) else { continue }
                        props.append(MeadowWorldProp(asset:asset,x:p.x,y:p.y,width:widthFor(asset),wind:0))
                        placed += 1
                    }
                }
            }

            // 2. Biome-coherent clustered groves, rocks, shrubs & wildflower meadows
            let sanctumTrees=["MapTreePineAlpine","Pines","OakA"]
            let autumnTrees=["MapTreeAutumnOak","MapTreeAutumnMaple","OakA"]
            let blossomTrees=["MapTreeBlossom","OakB","OakA"]
            let meadowTrees=["OakA","OakB","Pines","MapTreeBlossom","MapTreeAutumnOak"]
            let sanctumFlowers=["MapFlowersLavender","MapFlowersBlue"]
            let autumnFlowers=["MapFlowersCrimson","Flowers"]
            let blossomFlowers=["MapFlowersBlue","MapFlowersLavender","Flowers"]
            let meadowFlowers=["Flowers","MapFlowersBlue","MapFlowersCrimson","MapFlowersLavender"]

            func pickBiomeAsset(_ zone:Zone)->String {
                let roll=Int(decoration.next()%100)
                switch zone {
                case .sanctum:
                    if roll < 44 { return sanctumTrees[Int(decoration.next()%UInt64(sanctumTrees.count))] }
                    if roll < 70 { return decoration.next()%3 != 0 ? "MapRockSlate" : "RockLow" }
                    if roll < 84 { return "Shrub" }
                    return sanctumFlowers[Int(decoration.next()%UInt64(sanctumFlowers.count))]
                case .autumn:
                    if roll < 46 { return autumnTrees[Int(decoration.next()%UInt64(autumnTrees.count))] }
                    if roll < 64 { return decoration.next()%3 != 0 ? "MapRockAutumn" : "RockSmall" }
                    if roll < 82 { return "MapShrubAutumn" }
                    return autumnFlowers[Int(decoration.next()%UInt64(autumnFlowers.count))]
                case .blossom:
                    if roll < 42 { return blossomTrees[Int(decoration.next()%UInt64(blossomTrees.count))] }
                    if roll < 54 { return "RockSmall" }
                    if roll < 70 { return "Shrub" }
                    return blossomFlowers[Int(decoration.next()%UInt64(blossomFlowers.count))]
                case .meadow:
                    if roll < 44 { return meadowTrees[Int(decoration.next()%UInt64(meadowTrees.count))] }
                    if roll < 60 { return ["RockLow","RockHigh","RockSmall"][Int(decoration.next()%3)] }
                    if roll < 74 { return decoration.next()%3==0 ? "MapShrubAutumn" : "Shrub" }
                    return meadowFlowers[Int(decoration.next()%UInt64(meadowFlowers.count))]
                }
            }

            for _ in 0..<2200 {
                if props.count>=maxProps{break}
                let p=MeadowWorldPoint(decoration.value(-70,1350),decoration.value(-80,height+100))
                guard clearanceOK(p) else{continue}
                let zone=zoneAt(p)
                let asset=pickBiomeAsset(zone)
                let w=widthFor(asset)
                props.append(MeadowWorldProp(asset:asset,x:p.x,y:p.y,width:w,wind:windFor(asset)))

                // Cluster companion trees, shrubs, or flower patches for organic groves instead of uniform confetti
                let isTree = asset=="OakA" || asset=="OakB" || asset=="Pines" || asset.hasPrefix("MapTree")
                let isFlower = asset=="Flowers" || asset.hasPrefix("MapFlowers")
                if isTree && props.count < maxProps && decoration.next()%100 < 58 {
                    let count = decoration.next()%2==0 ? 1 : 2
                    for _ in 0..<count where props.count < maxProps {
                        let ang=decoration.value(0,2 * .pi), rad=decoration.value(44,76)
                        let cp=MeadowWorldPoint(p.x+cos(ang)*rad,p.y+sin(ang)*rad*0.78)
                        guard (-80...1360).contains(cp.x),(-90...(height+110)).contains(cp.y) else { continue }
                        guard clearanceOK(cp,roadClear:58,nodeClear:84,extraPropClear:0) else { continue }
                        let subRoll=Int(decoration.next()%100)
                        let companion:String
                        if subRoll < 50 { companion = asset }
                        else if subRoll < 78 { companion = zone == .autumn ? "MapShrubAutumn" : "Shrub" }
                        else {
                            let fl = zone == .sanctum ? sanctumFlowers : zone == .autumn ? autumnFlowers : zone == .blossom ? blossomFlowers : meadowFlowers
                            companion = fl[Int(decoration.next()%UInt64(fl.count))]
                        }
                        props.append(MeadowWorldProp(asset:companion,x:cp.x,y:cp.y,width:widthFor(companion),wind:windFor(companion)))
                    }
                } else if isFlower && props.count < maxProps && decoration.next()%100 < 65 {
                    let count = 1 + Int(decoration.next()%2)
                    for _ in 0..<count where props.count < maxProps {
                        let ang=decoration.value(0,2 * .pi), rad=decoration.value(18,34)
                        let cp=MeadowWorldPoint(p.x+cos(ang)*rad,p.y+sin(ang)*rad*0.8)
                        guard self.distance(cp,to:roads)>58,positions.allSatisfy({length($0,cp)>84}),campPositions.allSatisfy({hypot($0.x-cp.x,$0.y-26-cp.y)>152}) else { continue }
                        guard props.allSatisfy({hypot($0.x-cp.x,$0.y-cp.y)>($0.nodeID != nil ? ($0.asset=="CampTent" ? 152:126):14)}) else { continue }
                        props.append(MeadowWorldProp(asset:asset,x:cp.x,y:cp.y,width:widthFor(asset),wind:1))
                    }
                }
            }
            return GeneratedMeadowMap(generatorVersion:version,configuration:c,map:map,roads:roads,props:props,coordinateHeight:height,spawn:positions[start])
        }
        throw GameError("在64次尝试内无法满足道路净空、建筑与Boss距离要求，请更换种子或减少环路。节点数量未改变。")
    }
}
