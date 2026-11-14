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
    func testPoorOrMovingOrBadTierIsRejectedWithoutChange()throws {
        let s=try session();var save=s.snapshot;save.archive.state.units["p2"]!.coins=10
        let poor=try MeadowCampaignSession(save:save),before=poor.snapshot
        XCTAssertThrowsError(try poor.spinLottery(actor:"p2",tier:0));XCTAssertThrowsError(try poor.spinLottery(actor:"p1",tier:3))
        XCTAssertEqual(poor.snapshot,before)
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
