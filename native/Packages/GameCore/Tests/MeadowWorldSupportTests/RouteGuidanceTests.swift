import XCTest
import ClassroomGameCore
@testable import MeadowWorldSupport

final class RouteGuidanceTests:XCTestCase {
    func testFractionalPartyMeanAccountsForEachCappedRefillAndPartialLastPurchase() {
        XCTAssertEqual(MeadowMovementRules.minimumRouteCoins(distance:800,available:0,capacity:375),17)
        XCTAssertEqual(MeadowMovementRules.minimumRouteCoins(distance:750,available:0,capacity:375),16)
        XCTAssertEqual(MeadowMovementRules.minimumRouteCoins(distance:800,available:375,capacity:375),9)
        XCTAssertEqual(MeadowMovementRules.minimumRouteCoins(distance:375,available:375,capacity:375),0)
        XCTAssertEqual(MeadowMovementRules.minimumRouteCoins(distance:375.00000001,available:375,capacity:375),0)
    }
    private func session(_ size:Int=10)throws->MeadowCampaignSession {
        try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:size,seed:31827)))
    }
    func testRouteDistanceAndPolylineShrinkByExactlyActualMovementWithoutMutatingSave()throws {
        let s=try session(),start=s.engine.state.players[0].nodeID
        let target=s.engine.state.map.nodes.max{a,b in
            s.routeDistance(s.engine.state.map.shortestPath(from:start,to:a.id)!)<s.routeDistance(s.engine.state.map.shortestPath(from:start,to:b.id)!)
        }!.id
        try s.beginTravel(to:target)
        let before=s.snapshot,read=try XCTUnwrap(s.routeReadout)
        XCTAssertEqual(read.remainingDistance,s.routeDistance(s.travel!.path),accuracy:1e-8)
        XCTAssertEqual(s.snapshot,before)
        let initial=s.movementRemaining
        try s.advanceTravel(distance:17.25)
        let next=try XCTUnwrap(s.routeReadout)
        XCTAssertEqual(next.remainingDistance,read.remainingDistance-17.25,accuracy:1e-8)
        XCTAssertEqual(s.movementRemaining,initial-17.25,accuracy:1e-8)
        XCTAssertEqual(next.points.first,s.position(of:"p1"))
        XCTAssertEqual(next.points.last,s.point(at:target))
        let length=MeadowCampaignSave.length(next.points)
        XCTAssertEqual(length,next.remainingDistance,accuracy:1e-8)
    }
    func testRoadStopAndReverseKeepRealCursorAndExactDestination()throws {
        let s=try session(),start=s.engine.state.players[0].nodeID,next=s.engine.state.map.neighbors(start)[0]
        let points=try XCTUnwrap(MeadowCampaignSave.road(s.snapshot.layout,from:start,to:next))
        let a=points[0],b=points[1],goal=MeadowWorldPoint((a.x+b.x)/2,(a.y+b.y)/2)
        let segment=hypot(b.x-a.x,b.y-a.y)
        try s.beginTravel(toRoadPoint:goal)
        XCTAssertEqual(s.routeReadout!.remainingDistance,segment/2,accuracy:1e-8)
        try s.advanceTravel(distance:segment/4)
        let position=s.position(of:"p1"),back=MeadowWorldPoint(a.x+(b.x-a.x)/8,a.y+(b.y-a.y)/8)
        try s.beginTravel(toRoadPoint:back)
        XCTAssertEqual(s.position(of:"p1").x,position.x,accuracy:1e-8)
        XCTAssertEqual(s.position(of:"p1").y,position.y,accuracy:1e-8)
        XCTAssertEqual(s.routeReadout!.remainingDistance,segment/8,accuracy:1e-8)
        XCTAssertEqual(s.routeReadout!.points.last!.x,back.x,accuracy:1e-8)
        try s.advanceTravel(distance:segment)
        let stopped=try XCTUnwrap(s.routeReadout)
        XCTAssertTrue(stopped.arrived);XCTAssertTrue(stopped.paused)
        XCTAssertEqual(stopped.remainingDistance,0,accuracy:1e-8)
        XCTAssertEqual(stopped.additionalCoins,0)
        XCTAssertEqual(stopped.points.count,1)
        let restored=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded()))
        XCTAssertEqual(restored.routeReadout,stopped)
    }
    func testZeroMovementStillAllowsReadOnlyRouteEstimatesAndWarnsAboutCoins()throws {
        let s=try session();var save=s.snapshot
        save.movement?.remaining=0
        for id in s.playerIDs{save.archive.state.units[id]?.coins=0}
        let restored=try MeadowCampaignSession(save:save),before=restored.snapshot
        let options=restored.routeOptions()
        XCTAssertEqual(Set(options.map(\.kind)),Set(["supply","encounter"]))
        XCTAssertTrue(options.allSatisfy{$0.distance>0 && $0.additionalCoins==Int(ceil($0.distance/50))})
        XCTAssertEqual(restored.snapshot,before)
        XCTAssertThrowsError(try restored.beginTravel(to:options[0].nodeID))
    }
    func testOptionsUseSavedClaimAndMonsterStateAndIgnoreRewardReplanning()throws {
        let s=try session(),before=s.snapshot
        let options=s.routeOptions()
        XCTAssertEqual(s.snapshot,before)
        let cache=try XCTUnwrap(options.first{$0.kind=="supply"})
        try s.configureReward(node:cache.nodeID,reward:NodeReward(coins:111,score:8,items:["largePotion":9]))
        var save=s.snapshot
        save.archive.state.map.nodes=save.archive.state.map.nodes.map{var n=$0;if n.id==cache.nodeID{n.rewardCompleted=true};return n}
        let encounter=try XCTUnwrap(options.first{$0.kind=="encounter"})
        for (id,u) in save.archive.state.units where u.kind == .monster && u.nodeID==encounter.nodeID{save.archive.state.units[id]?.health=0}
        let restored=try MeadowCampaignSession(save:save),actual=restored.snapshot
        XCTAssertFalse(restored.routeOptions().contains{$0.nodeID==cache.nodeID || $0.nodeID==encounter.nodeID})
        XCTAssertEqual(restored.snapshot,actual)
        XCTAssertEqual(restored.engine.state.map.nodes.first{$0.id==cache.nodeID}?.reward?.coins,111)
    }
    func testNoSupplyMapDoesNotInventSupplyAndInventoryIsPerMember()throws {
        var c=MeadowMapConfiguration.suggested(total:4);c.reward=0;c.empty+=1
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c))
        try s.engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:0)))
        let before=s.snapshot
        XCTAssertFalse(s.routeOptions(actor:"p2").contains{$0.kind=="supply"})
        XCTAssertTrue(s.routeOptions(actor:"p1").isEmpty)
        XCTAssertTrue(s.resourceGuidance.contains("P1（倒地）"))
        XCTAssertTrue(s.resourceGuidance.contains("P2："))
        XCTAssertEqual(s.snapshot,before)
    }
    func testPausedRestoreRetainsGeometryAndExposesTrueCoinShortfall()throws {
        let s=try session(),option=try XCTUnwrap(s.routeOptions().first)
        try s.beginTravel(to:option.nodeID)
        var save=s.snapshot;save.movement?.remaining=1
        for id in s.playerIDs{save.archive.state.units[id]?.coins=0}
        let restored=try MeadowCampaignSession(save:save),before=restored.snapshot
        let route=try XCTUnwrap(restored.routeReadout)
        XCTAssertTrue(route.paused);XCTAssertTrue(route.title.contains("暂停"))
        XCTAssertEqual(route.additionalCoins,Int(ceil(max(0,route.remainingDistance-1)/50)))
        XCTAssertEqual(route.coinsMissing,route.additionalCoins)
        XCTAssertTrue(route.detail.contains("尚差"))
        XCTAssertEqual(restored.snapshot,before)
        try restored.refillMovement(usingCoins:false)
        XCTAssertEqual(restored.routeReadout?.points,route.points)
    }
}
