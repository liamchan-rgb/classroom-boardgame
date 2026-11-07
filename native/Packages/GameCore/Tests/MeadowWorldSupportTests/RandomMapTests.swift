import XCTest
import ClassroomGameCore
@testable import MeadowWorldSupport

final class RandomMapTests: XCTestCase {
    func testSizesSeedsAndGraphContracts() throws {
        for n in 4...30 { for seed in 0..<24 {
            let c=MeadowMapConfiguration.suggested(total:n,seed:UInt64(seed))
            let result:GeneratedMeadowMap
            do { result=try MeadowMapGenerator.generate(c) } catch { throw GameError("N=\(n),seed=\(seed): \(error)") }
            try result.map.validate()
            XCTAssertEqual(result.map.nodes.count,n)
            let landmarks=result.props.filter{$0.nodeID != nil}
            XCTAssertEqual(landmarks.count,n)
            XCTAssertEqual(Set(landmarks.compactMap(\.nodeID)),Set(result.map.nodes.map(\.id)))
            let assets:[NodeKind:String]=[.start:"CampTent",.combat:"NodeCombatOutpost",.boss:"NodeBossSanctum",.reward:"NodeRewardCache",.empty:"NodeWaystone"]
            for node in result.map.nodes {
                let building=landmarks.first{$0.nodeID==node.id}!
                XCTAssertEqual(building.asset,assets[node.kind])
                XCTAssertEqual(building.x,node.x*1280,accuracy:0.000001)
                XCTAssertEqual(building.y+26,node.y*result.coordinateHeight,accuracy:0.000001)
            }
            XCTAssertEqual(result.map.nodes.filter{$0.kind == .start}.count,1)
            for (kind,count) in [(NodeKind.combat,c.combat),(.boss,c.boss),(.reward,c.reward),(.empty,c.empty)] {
                XCTAssertEqual(result.map.nodes.filter{$0.kind==kind}.count,count)
            }
            XCTAssertEqual(result.roads.count,n-1+c.extraRoads)
            XCTAssertEqual(result.map.roads.count,result.roads.count)
            for road in result.roads {
                let a=result.map.nodes.first{$0.id==road.from}!,b=result.map.nodes.first{$0.id==road.to}!
                XCTAssertEqual(road.points.first!.x,a.x*1280,accuracy:0.000001)
                XCTAssertEqual(road.points.last!.y,b.y*result.coordinateHeight,accuracy:0.000001)
            }
            XCTAssertTrue(result.map.nodes.allSatisfy{(0...1).contains($0.x) && (0...1).contains($0.y)})
            XCTAssertTrue(result.props.filter{$0.nodeID == nil}.allSatisfy{MeadowMapGenerator.distance(MeadowWorldPoint($0.x,$0.y),to:result.roads)>58})
            if let camp=result.props.first(where:{$0.asset == "CampTent"}) {
                XCTAssertTrue((50...1230).contains(camp.x) && (110...(result.coordinateHeight-15)).contains(camp.y))
                XCTAssertTrue(result.props.filter{$0.asset != "CampTent"}.allSatisfy{hypot($0.x-camp.x,$0.y-camp.y)>150})
            }
        } }
    }
    func testRoadHeadingsDoNotRegressToAxisAlignedRows() throws {
        for n in [4,10,30] {
            var axial=0,total=0
            for seed in 0..<12 {
                let map=try MeadowMapGenerator.generate(.suggested(total:n,seed:UInt64(seed)))
                for road in map.roads {
                    let a=road.points.first!,b=road.points.last!,dx=abs(a.x-b.x),dy=abs(a.y-b.y)
                    total+=1
                    if min(dx,dy)/hypot(dx,dy)<sin(Double.pi/12) {axial+=1}
                }
            }
            // Prevent a return to an overwhelmingly horizontal/vertical road
            // network. Artistic acceptance still needs whole-map inspection.
            XCTAssertLessThan(Double(axial)/Double(total),0.65,"N=\(n)")
        }
    }
    func testExactManualQuotasAndNoBoss() throws {
        var c=MeadowMapConfiguration();c.combat=0;c.boss=0;c.reward=0;c.empty=9
        let r=try MeadowMapGenerator.generate(c)
        XCTAssertEqual(r.map.nodes.filter{$0.kind == .empty}.count,9)
        XCTAssertFalse(r.map.nodes.contains{$0.kind == .boss || $0.kind == .combat})
    }
    func testDeterministicAndDecorationIndependent() throws {
        let c=MeadowMapConfiguration()
        let a=try MeadowMapGenerator.generate(c),b=try MeadowMapGenerator.generate(c)
        XCTAssertEqual(a,b)
        let enc=JSONEncoder();enc.outputFormatting=[.sortedKeys]
        XCTAssertEqual(try enc.encode(a),try enc.encode(b))
        var different=c;different.decorationCount=10
        let d=try MeadowMapGenerator.generate(different)
        XCTAssertEqual(a.map,d.map);XCTAssertEqual(a.roads,d.roads)
        different.seed=777
        XCTAssertNotEqual(a.map,try MeadowMapGenerator.generate(different).map)
    }
    func testInvalidAndImpossibleConstraintsFailWithoutChangingQuota() {
        var c=MeadowMapConfiguration();c.empty=2
        XCTAssertThrowsError(try MeadowMapGenerator.generate(c))
        c.empty = -1;XCTAssertThrowsError(try MeadowMapGenerator.generate(c))
        c=MeadowMapConfiguration.suggested(total:4);c.extraRoads=2
        XCTAssertThrowsError(try MeadowMapGenerator.generate(c))
        c.extraRoads=1;c.minimumBossHops=3
        XCTAssertThrowsError(try MeadowMapGenerator.generate(c)) // 4-cell ring diameter is 2.
        c=MeadowMapConfiguration();c.total=Int.max
        XCTAssertThrowsError(try MeadowMapGenerator.generate(c))
    }
    func testBossHopConstraintAndCodableSnapshot() throws {
        var c=MeadowMapConfiguration();c.minimumBossHops=3
        let r=try MeadowMapGenerator.generate(c),start=r.map.nodes.first{$0.kind == .start}!.id
        XCTAssertTrue(r.map.nodes.filter{$0.kind == .boss}.allSatisfy{r.map.distance(from:start,to:$0.id)!>=3})
        let copy=try JSONDecoder().decode(GeneratedMeadowMap.self,from:JSONEncoder().encode(r))
        XCTAssertEqual(r,copy)
    }
    func testTotalAndCategoryControlsAlwaysRebalance() throws {
        for total in 4...30 {
            let c=try MeadowMapConfiguration().changingTotal(to:total)
            try c.validate();XCTAssertEqual(c.total,total)
            for field in 0..<4 { for value in 0..<total {
                let changed=try c.changingCount(field:field,to:value)
                try changed.validate()
                XCTAssertEqual([changed.combat,changed.boss,changed.reward,changed.empty][field],value)
                XCTAssertEqual(1+changed.combat+changed.boss+changed.reward+changed.empty,total)
            } }
        }
        var large=MeadowMapConfiguration.suggested(total:30);large.extraRoads=10
        let small=try large.changingTotal(to:4)
        XCTAssertEqual(small.extraRoads,MeadowMapGenerator.maximumExtraRoads(total:4))
        XCTAssertThrowsError(try large.changingTotal(to:3))
    }
    func testSingleCategoryDenseMapsHaveEveryLandmark() throws {
        for total in [4,10,30] { for field in 0..<4 { for extra in [0,MeadowMapGenerator.maximumExtraRoads(total:total)] {
            var c=try MeadowMapConfiguration.suggested(total:total).changingCount(field:field,to:total-1)
            c.extraRoads=extra
            let m:GeneratedMeadowMap
            do { m=try MeadowMapGenerator.generate(c) } catch { throw GameError("dense N=\(total) extra=\(extra) field=\(field): \(error)") }
            XCTAssertEqual(m.props.filter{$0.nodeID != nil}.count,total)
        } } }
    }

}
