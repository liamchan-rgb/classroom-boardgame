import XCTest
import ClassroomGameCore
@testable import MeadowWorldSupport

final class EncounterPlannerTests:XCTestCase {
    func testEverySupportedSizeAndExtremeQuotaUsesOnlyRegisteredCategories()throws {
        let catalog=try MeadowCampaignSession.catalog()
        var seen=Set<String>(),sizes=Set<Int>()
        for total in 4...30 {
            for seed:UInt64 in [0,317,31827,UInt64.max] {
                for mode in 0...2 {
                    var c=MeadowMapConfiguration.suggested(total:total,seed:seed)
                    if mode==1{c.combat=total-1;c.boss=0;c.reward=0;c.empty=0}
                    if mode==2{c.combat=0;c.boss=total-1;c.reward=0;c.empty=0}
                    let layout=try MeadowMapGenerator.generate(c),plan=MeadowEncounterPlanner.plan(layout)
                    XCTAssertEqual(plan.count,c.combat+c.boss);XCTAssertEqual(Set(plan.map(\.nodeID)).count,plan.count)
                    for e in plan {
                        let node=try XCTUnwrap(layout.map.nodes.first{$0.id==e.nodeID})
                        XCTAssertTrue(e.distance.isFinite && e.distance>0)
                        XCTAssertTrue((1...3).contains(e.templates.count))
                        if node.kind == .boss{XCTAssertEqual(e.templates.count,1)}
                        for id in e.templates{XCTAssertEqual(try catalog.monster(id).boss,node.kind == .boss);seen.insert(id)}
                        if node.kind == .combat{sizes.insert(e.templates.count)}
                    }
                }
            }
        }
        XCTAssertEqual(seen,Set(["slime","wolf","goblinArcher","stoneGuardian","caveTroll","ruinDragon"]))
        XCTAssertEqual(sizes,Set([1,2,3]))
    }

    func testRoadDistanceBandsAndBossProgression()throws {
        var c=MeadowMapConfiguration.suggested(total:20,seed:14)
        c.combat=12;c.boss=4;c.reward=2;c.empty=1
        let layout=try MeadowMapGenerator.generate(c),plan=MeadowEncounterPlanner.plan(layout)
        let combat=plan.filter{$0.band != "boss"}.sorted{$0.distance<$1.distance}
        XCTAssertEqual(combat.first?.templates,["slime"])
        XCTAssertEqual(combat.filter{$0.band=="middle"}.count,5)
        XCTAssertEqual(combat.filter{$0.band=="deep"}.count,6)
        let bosses=plan.filter{$0.band=="boss"}.sorted{$0.distance<$1.distance}
        XCTAssertEqual(bosses.first?.templates,["caveTroll"])
        XCTAssertEqual(bosses.last?.templates,["ruinDragon"])
        XCTAssertTrue(bosses.dropLast().allSatisfy{$0.templates==["caveTroll"]})
    }

    func testSameSeedAndReorderedStorageHaveSamePlanWithoutChangingLayoutOrDice()throws {
        let layout=try MeadowMapGenerator.generate(.suggested(total:30,seed:UInt64.max))
        let plan=MeadowEncounterPlanner.plan(layout)
        var map=layout.map;map.nodes.reverse();map.roads.reverse()
        let reordered=GeneratedMeadowMap(generatorVersion:layout.generatorVersion,configuration:layout.configuration,map:map,roads:Array(layout.roads.reversed()),props:layout.props,coordinateHeight:layout.coordinateHeight,spawn:layout.spawn)
        XCTAssertEqual(MeadowEncounterPlanner.plan(reordered),plan)
        XCTAssertEqual(try MeadowMapGenerator.generate(layout.configuration),layout)
        let session=try MeadowCampaignSession.new(layout:layout)
        XCTAssertEqual(session.engine.state.random,RandomState(seed:layout.configuration.seed ^ 0x43414d504149474e))
        XCTAssertEqual(session.snapshot.layout,layout)
        for e in plan {
            for (i,id) in e.templates.enumerated(){XCTAssertEqual(session.engine.state.units["m-\(e.nodeID)-\(i+1)"]?.templateID,id)}
        }
    }

    func testManualEditsAndLegacyDeerSurviveSaveAndResumeWithoutReplanning()throws {
        let layout=try MeadowMapGenerator.generate(.suggested(total:10))
        let s=try MeadowCampaignSession.new(layout:layout)
        let combat=try XCTUnwrap(layout.map.nodes.first{$0.kind == .combat})
        let boss=try XCTUnwrap(layout.map.nodes.first{$0.kind == .boss})
        try s.configureEncounter(node:combat.id,templates:["meadowStag","meadowStag"])
        try s.configureEncounter(node:boss.id,templates:["meadowElderStag"])
        var save=s.snapshot
        // Legacy format has no movement/selection fields. Stored roster, HP,
        // history and RNG must be preserved, irrespective of the new planner.
        save.movement=nil;save.selectedPlayerID=nil
        let resumed=try MeadowCampaignSession(save:.decoded(save.encoded()))
        XCTAssertEqual(resumed.engine.archive,save.archive)
        XCTAssertEqual(resumed.snapshot.formatVersion,1)
        XCTAssertEqual(resumed.engine.state.units["m-\(combat.id)-2"]?.templateID,"meadowStag")
        XCTAssertEqual(resumed.engine.state.units["m-\(boss.id)-1"]?.templateID,"meadowElderStag")
        try resumed.configureEncounter(node:combat.id,templates:["stoneGuardian","wolf","goblinArcher"])
        let again=try MeadowCampaignSession(save:.decoded(resumed.snapshot.encoded()))
        XCTAssertEqual(again.engine.archive,resumed.engine.archive)
    }

    func testPreviewExactlyDescribesSpawnedRosterAndEmptyMap()throws {
        var c=MeadowMapConfiguration.suggested(total:10)
        let layout=try MeadowMapGenerator.generate(c),catalog=try MeadowCampaignSession.catalog()
        XCTAssertEqual(MeadowEncounterPlanner.plan(layout).map{ "\($0.nodeID):"+$0.templates.joined(separator:",") },
                       ["1:wolf,goblinArcher","2:slime","4:ruinDragon","6:goblinArcher","9:slime,wolf,goblinArcher"])
        let summary=try MeadowEncounterPlanner.summary(layout,catalog:catalog)
        for e in MeadowEncounterPlanner.plan(layout) {
            let names=try e.templates.map{try catalog.monster($0).name}.joined(separator:" + ")
            XCTAssertTrue(summary.contains("#\(e.nodeID) · "+names))
        }
        c.combat=0;c.boss=0;c.reward=9;c.empty=0
        let empty=try MeadowMapGenerator.generate(c)
        XCTAssertTrue(MeadowEncounterPlanner.plan(empty).isEmpty)
        XCTAssertTrue(try MeadowEncounterPlanner.summary(empty,catalog:catalog).contains("无战斗"))
    }
}
