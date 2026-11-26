import XCTest
import ClassroomGameCore
@testable import MeadowWorldSupport

final class LotteryTests:XCTestCase {
    private func session()throws->MeadowCampaignSession {
        var save=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:10,seed:31827))).snapshot
        save.archive.state.units["p1"]!.coins=5000
        return try MeadowCampaignSession(save:save)
    }
    func testTiersAreValidAndHigherTiersCostMoreAndFavourSets()throws {
        let catalog=try MeadowCampaignSession.catalog()
        var last=0.0
        for (i,tier) in CampaignLottery.tiers.enumerated() {
            if i>0{XCTAssertGreaterThan(tier.cost,CampaignLottery.tiers[i-1].cost)}
            for prize in tier.prizes {if let id=prize.item{XCTAssertNoThrow(try catalog.item(id))};XCTAssertGreaterThan(prize.weight,0)}
            let sets=Double(tier.prizes.filter{p in p.item.flatMap{try? catalog.item($0).setID} != nil}.map(\.weight).reduce(0,+))/Double(tier.totalWeight)
            XCTAssertGreaterThan(sets,last);last=sets
        }
    }
    func testSpinChargesPaysOneRecordedPrizeAndIsIdempotent()throws {
        let s=try session(),before=s.engine.state.units["p1"]!
        let receipt=try s.spinLottery(actor:"p1",tier:2,id:"spin")
        let event=try XCTUnwrap(receipt.events.first{$0.kind=="lottery"})
        let prize=CampaignLottery.tiers[2].prizes[event.amount],after=s.engine.state.units["p1"]!
        if let item=prize.item {XCTAssertEqual(after.inventory[item] ?? 0,(before.inventory[item] ?? 0)+prize.count);XCTAssertEqual(after.coins,before.coins-180)}
        else {XCTAssertEqual(after.coins,before.coins-180+prize.coins)}
        let saved=s.snapshot;try s.spinLottery(actor:"p1",tier:2,id:"spin");XCTAssertEqual(s.snapshot,saved)
    }
    func testCustomWheelPaysWhatTheWeightsAllowAndChecksItself()throws {
        let s=try session(),before=s.engine.state.units["p1"]!
        // Only the second prize can come up (the others weigh 0): 2 revival stones, 15 coins and 3 points.
        let wheel=CustomWheel(name:"课堂转盘",cost:20,prizes:[
            CustomWheelPrize(title:"免作业一次",weight:0),
            CustomWheelPrize(title:"复活石大礼",item:"revivalStone",count:2,coins:15,score:3,weight:5),
            CustomWheelPrize(title:"金币",coins:50,weight:0)])
        let receipt=try s.spinCustomWheel(actor:"p1",wheel:wheel)
        let event=try XCTUnwrap(receipt.events.first{$0.kind=="customWheel"})
        XCTAssertEqual(event.amount,1);XCTAssertEqual(event.detail,"课堂转盘:复活石大礼")
        let after=s.engine.state.units["p1"]!
        XCTAssertEqual(after.inventory["revivalStone"] ?? 0,(before.inventory["revivalStone"] ?? 0)+2)
        XCTAssertEqual(after.coins,before.coins-20+15);XCTAssertEqual(after.score,before.score+3)
        // A text-only prize changes nothing in the game but the cost.
        let text=CustomWheel(name:"奖励",prizes:[CustomWheelPrize(title:"当一天小老师",weight:1),CustomWheelPrize(title:"贴纸",weight:0)])
        let mid=s.engine.state.units["p1"]!
        try s.spinCustomWheel(actor:"p1",wheel:text)
        XCTAssertEqual(s.engine.state.units["p1"]!.coins,mid.coins);XCTAssertEqual(s.engine.state.units["p1"]!.inventory,mid.inventory)
        XCTAssertTrue(text.prizes[0].offGame)
        // Checks: too few prizes, all zero weights, unknown item, not enough coins; nothing changes.
        let saved=s.snapshot
        XCTAssertThrowsError(try s.spinCustomWheel(actor:"p1",wheel:CustomWheel(name:"x",prizes:[CustomWheelPrize(title:"a",weight:1)])))
        XCTAssertThrowsError(try s.spinCustomWheel(actor:"p1",wheel:CustomWheel(name:"x",prizes:[CustomWheelPrize(title:"a",weight:0),CustomWheelPrize(title:"b",weight:0)])))
        XCTAssertThrowsError(try s.spinCustomWheel(actor:"p1",wheel:CustomWheel(name:"x",prizes:[CustomWheelPrize(title:"a",item:"noSuchItem",count:1,weight:1),CustomWheelPrize(title:"b",weight:1)])))
        XCTAssertThrowsError(try s.spinCustomWheel(actor:"p1",wheel:CustomWheel(name:"x",cost:1000,prizes:[CustomWheelPrize(title:"a",weight:1),CustomWheelPrize(title:"b",weight:1)]).withCost(999_0)))
        XCTAssertEqual(s.snapshot,saved)
        XCTAssertEqual(wheel.chance(1),1);XCTAssertEqual(CustomWheel(name:"x",prizes:[CustomWheelPrize(title:"a",weight:1),CustomWheelPrize(title:"b",weight:3)]).chance(1),0.75)
    }
    func testPoorOrMovingOrBadTierIsRejectedWithoutChange()throws {
        let s=try session();var save=s.snapshot;save.archive.state.units["p2"]!.coins=10
        let poor=try MeadowCampaignSession(save:save),before=poor.snapshot
        XCTAssertThrowsError(try poor.spinLottery(actor:"p2",tier:0));XCTAssertThrowsError(try poor.spinLottery(actor:"p1",tier:4))
        XCTAssertEqual(poor.snapshot,before)
        // 4th tier (星穹, 280 coins) succeeds when coins are sufficient.
        let r=try poor.spinLottery(actor:"p1",tier:3)
        XCTAssertEqual(r.after.units["p1"]!.coins,5000-280)
    }
    func testManySpinsCanYieldSetPieces()throws {
        let s=try session();var sets=0
        let catalog=s.engine.catalog
        for _ in 0..<25 {
            let r=try s.spinLottery(actor:"p1",tier:2),e=r.events.first{$0.kind=="lottery"}!
            if let id=CampaignLottery.tiers[2].prizes[e.amount].item,(try catalog.item(id)).setID != nil {sets+=1}
        }
        XCTAssertGreaterThan(sets,0)
    }
}

private extension CustomWheel { func withCost(_ c:Int)->CustomWheel {var w=self;w.cost=c;return w} }
