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
            var remaining=positions.indices.filter{$0 != start};topology.shuffle(&remaining);remaining.sort{distance[$0]>distance[$1]}
            let bosses=Array(remaining.prefix(c.boss));if bosses.contains(where:{distance[$0]<c.minimumBossHops}){continue}
            var kinds=Array(repeating:NodeKind.empty,count:c.total);kinds[start] = .start
            for id in bosses{kinds[id] = .boss};remaining.removeAll{bosses.contains($0)};topology.shuffle(&remaining)
            for (id,kind) in zip(remaining,Array(repeating:NodeKind.combat,count:c.combat)+Array(repeating:NodeKind.reward,count:c.reward)+Array(repeating:NodeKind.empty,count:c.empty)){kinds[id]=kind}
            let titles:[NodeKind:String]=[.start:"起点营地",.combat:"林间战斗",.boss:"首领遗迹",.reward:"补给棚",.empty:"林间水井"]
            let nodes=positions.indices.map{MapNode(id:$0,name:"\(titles[kinds[$0]]!) · \($0+1)",kind:kinds[$0],x:positions[$0].x/1280,y:positions[$0].y/height,reward:kinds[$0] == .reward ? NodeReward():nil)}
            let map=GameMap(nodes:nodes,roads:roads.map{MapRoad($0.from,$0.to)},seed:c.seed,revealed:[start]);try map.validate()
            let catalog:[NodeKind:(String,Double)]=[.start:("CampTent",105),.combat:("NodeCombatOutpost",90),.boss:("NodeBossSanctum",104),.reward:("NodeRewardCache",86),.empty:("NodeWaystone",74)]
            var props=positions.indices.map{ id -> MeadowWorldProp in
                let (asset,width)=catalog[kinds[id]]!
                return MeadowWorldProp(asset:asset,x:positions[id].x,y:positions[id].y-26,width:width,wind:0,nodeID:id)
            }
            let landmarkCount=props.count
            var decoration=MapRandom(state:c.seed ^ 0x50524f5053)
            let assets=["OakA","OakB","Pines","RockLow","RockHigh","RockSmall","Shrub","Flowers"]
            for _ in 0..<1800 {
                if props.count>=c.decorationCount+landmarkCount{break}
                let p=MeadowWorldPoint(decoration.value(-70,1350),decoration.value(-80,height+100))
                guard self.distance(p,to:roads)>58,positions.allSatisfy({length($0,p)>84}),props.allSatisfy({hypot($0.x-p.x,$0.y-p.y)>($0.nodeID != nil ? ($0.asset=="CampTent" ? 150:130):max(42,$0.width*0.6))}) else{continue}
                let asset=assets[Int(decoration.next()%UInt64(assets.count))]
                let width=asset=="Flowers" ? decoration.value(14,23):asset=="Shrub" ? decoration.value(25,35):asset.hasPrefix("Rock") ? decoration.value(76,108):decoration.value(60,88)
                props.append(MeadowWorldProp(asset:asset,x:p.x,y:p.y,width:width,wind:asset.hasPrefix("Rock") ? 0:1))
            }
            return GeneratedMeadowMap(generatorVersion:version,configuration:c,map:map,roads:roads,props:props,coordinateHeight:height,spawn:positions[start])
        }
        throw GameError("在64次尝试内无法满足道路净空、建筑与Boss距离要求，请更换种子或减少环路。节点数量未改变。")
    }
}
