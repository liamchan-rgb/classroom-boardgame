import XCTest
import ClassroomGameCore
@testable import MeadowWorldSupport

final class DifficultyTests:XCTestCase {
    private func layout()throws->GeneratedMeadowMap {
        var c=MeadowMapConfiguration.suggested(total:4,seed:317)
        c.combat=3;c.boss=0;c.reward=0;c.empty=0;c.extraRoads=0
        return try MeadowMapGenerator.generate(c)
    }
    private func monsters(_ s:MeadowCampaignSession)->[GameUnit] {s.engine.state.units.values.filter{$0.kind == .monster}.sorted{$0.id<$1.id}}
    private func stats(_ s:MeadowCampaignSession,_ u:GameUnit)throws->Attributes {try GameRules.attributes(u,catalog:s.engine.catalog)}

    func testLevelsScaleMonsterHealthAndDamageOnly()throws {
        let normal=try MeadowCampaignSession.new(layout:layout())
        let hard=try MeadowCampaignSession.new(layout:layout(),difficulty:.hard)
        XCTAssertNil(normal.engine.state.difficulty);XCTAssertEqual(hard.engine.state.difficulty,.hard)
        for (a,b) in zip(monsters(normal),monsters(hard)) {
            let base=try stats(normal,a),scaled=try stats(hard,b)
            XCTAssertEqual(scaled.maximumHealth,(base.maximumHealth*150+50)/100);XCTAssertEqual(b.health,scaled.maximumHealth)
            XCTAssertEqual(scaled.damage,base.damage+2);XCTAssertEqual(scaled.baseAP,base.baseAP)
        }
        XCTAssertEqual(normal.engine.state.players,hard.engine.state.players)
    }
    func testSwitchKeepsWoundShareAndRoundTripsAndRestores()throws {
        let s=try MeadowCampaignSession.new(layout:layout())
        let first=monsters(s)[0],max=try stats(s,first).maximumHealth
        try s.engine.apply(.setHealth(unit:first.id,value:max/2,killer:nil))
        let random=s.engine.state.random
        try s.setDifficulty(.nightmare)
        let wounded=s.engine.state.units[first.id]!,newMax=try stats(s,wounded).maximumHealth
        XCTAssertEqual(newMax,max*2);XCTAssertEqual(wounded.health,(max/2*newMax+max/2)/max)
        XCTAssertEqual(try stats(s,wounded).damage,try s.engine.catalog.monster(wounded.templateID).attributes.damage+4)
        XCTAssertEqual(s.engine.state.random,random)
        let restored=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded()))
        XCTAssertEqual(restored.difficulty,.nightmare);XCTAssertEqual(restored.engine.state.units,s.engine.state.units)
        try s.setDifficulty(.normal)
        XCTAssertNil(s.engine.state.difficulty)
        for u in monsters(s) {XCTAssertEqual(u.baseAttributes,try s.engine.catalog.monster(u.templateID).attributes)}
    }
    func testNewEncountersFollowLevelAndBattleRefusesSwitch()throws {
        let s=try MeadowCampaignSession.new(layout:layout(),difficulty:.easy)
        let node=monsters(s)[0].nodeID,template=monsters(s)[0].templateID
        try s.configureEncounter(node:node,templates:[template])
        let placed=s.engine.state.units["m-\(node)-1"]!,base=try s.engine.catalog.monster(template).attributes
        XCTAssertEqual(placed.baseAttributes.maximumHealth,(base.maximumHealth*75+50)/100);XCTAssertEqual(placed.health,placed.baseAttributes.maximumHealth)
        try s.engine.apply(.startBattle(kind:.pve,monsters:[placed.id]))
        let before=s.snapshot
        XCTAssertThrowsError(try s.setDifficulty(.hard));XCTAssertEqual(s.snapshot,before)
    }
    func testOldSavesWithoutLevelLoadAsNormal()throws {
        let s=try MeadowCampaignSession.new(layout:layout())
        let bytes=try s.snapshot.encoded()
        XCTAssertFalse(String(decoding:bytes,as:UTF8.self).contains("difficulty"))
        XCTAssertEqual(try MeadowCampaignSession(save:.decoded(bytes)).difficulty,.normal)
    }
}
