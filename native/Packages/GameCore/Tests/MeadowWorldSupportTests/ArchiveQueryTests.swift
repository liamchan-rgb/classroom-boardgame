import XCTest
@testable import ClassroomGameCore
@testable import MeadowWorldSupport

final class ArchiveQueryTests:XCTestCase {
    func session()throws->MeadowCampaignSession {try .new(layout:MeadowMapGenerator.generate(.suggested(total:4,seed:719)),studentNames:["Élan","林"])}
    func journey(_ slot:Int,date:Double,title:String="第一课",save:MeadowCampaignSave)throws->MeadowJourneyIndex {
        let entry=MeadowSaveSlot(title:title,value:save);var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(entry)) as! [String:Any];object["savedAt"]=date
        return .init(slot:slot,entry:try JSONDecoder().decode(MeadowSaveSlot<MeadowCampaignSave>.self,from:JSONSerialization.data(withJSONObject:object)))
    }
    func row(_ sequence:Int,command:GameCommand,before:GameState,after:GameState?=nil,catalog:GameCatalog)->MeadowHistoryIndex {
        .init(entry:.init(id:"record-\(sequence)",sequence:sequence,command:command,dice:[],events:[],before:before,after:after ?? before),catalog:catalog)
    }
    func testJourneySearchFindsTitleNamesTeamAndSeed()throws {
        let c=try session(),r=try journey(4,date:10,save:c.snapshot)
        for term in ["第一课","林","ELAN","林间小队","719"]{var q=MeadowJourneyQuery();q.text=term;XCTAssertEqual(q.apply([r]).map(\.slot),[4],term)}
    }
    func testJourneyCombinesTokensAndTreatsWhitespaceAsEmpty()throws {
        let c=try session(),r=try journey(4,date:10,save:c.snapshot);var q=MeadowJourneyQuery();q.text="  第一课   林 \n";XCTAssertEqual(q.apply([r]),[r]);q.text="第一课 missing";XCTAssertTrue(q.apply([r]).isEmpty);q.text=" \n ";XCTAssertEqual(q.apply([r]),[r])
    }
    func testJourneyStatusAndPlayerCountCompose()throws {
        let c=try session();var battle=c.snapshot;battle.archive.state.battle=BattleState(kind:.pve,queue:["p1","p2"])
        let exploring=try journey(2,date:10,save:c.snapshot),fighting=try journey(7,date:20,save:battle)
        var q=MeadowJourneyQuery();q.state = .battle;q.players=2;XCTAssertEqual(q.apply([exploring,fighting]).map(\.slot),[7]);q.players=6;XCTAssertTrue(q.apply([exploring,fighting]).isEmpty)
    }
    func testCompletedJourneyIsClassifiedSeparately()throws {
        let c=try session();for p in c.engine.state.players{try c.engine.apply(.setHealth(unit:p.id,value:0,killer:nil))};try c.completeCampaign()
        XCTAssertEqual(MeadowJourneyState.of(c.snapshot),.completed)
        var q=MeadowJourneyQuery();q.state = .exploring;XCTAssertTrue(q.apply([try journey(2,date:10,save:c.snapshot)]).isEmpty)
    }
    func testJourneyOrdersAreStableAndKeepOriginalSlots()throws {
        let c=try session(),rows=try [journey(7,date:20,save:c.snapshot),journey(2,date:10,save:c.snapshot),journey(5,date:20,save:c.snapshot)]
        var q=MeadowJourneyQuery();XCTAssertEqual(q.apply(rows).map(\.slot),[5,7,2]);q.order = .oldest;XCTAssertEqual(q.apply(rows).map(\.slot),[2,5,7]);q.order = .slot;XCTAssertEqual(q.apply(rows).map(\.slot),[2,5,7])
    }
    func testHistoryCategoriesCoverCombatTravelResourceTeamAppearanceConfiguration()throws {
        let commands:[(GameCommand,MeadowHistoryCategory)]=[(.attack(actor:"p1",target:"p2"),.combat),(.campaignMove(actors:["p1"],node:1),.travel),(.grantPlayerResources(actors:["p1"],ap:0,coins:1),.resources),(.addHost(id:"p7",name:"老师",classID:"ranger",team:"party",node:0),.team),(.applyPlayerProfile(unit:"p1",name:"林",appearance:.init()),.appearance),(.resetNodeReward(node:2),.configuration)]
        for (command,category) in commands{XCTAssertEqual(MeadowHistoryCategory.of(command),category)}
    }
    func testUnchangedAttackParticipantsStillMatch()throws {
        let c=try session(),r=row(4,command:.attack(actor:"p1",target:"p2"),before:c.engine.state,catalog:c.engine.catalog)
        XCTAssertTrue(r.participants.isSuperset(of:["p1","p2"]));var q=MeadowHistoryQuery();q.participant="p2";q.category = .combat;XCTAssertEqual(q.apply([r]).map(\.id),["record-4"])
    }
    func testCastAndEndTurnUseCommandActorsWithoutEvents()throws {
        let c=try session(),heal=row(1,command:.cast(actor:"p1",skill:"unknown",target:.unit("p2")),before:c.engine.state,catalog:c.engine.catalog),end=row(2,command:.endTurn(actor:"p1",timedOut:false),before:c.engine.state,catalog:c.engine.catalog)
        XCTAssertTrue(heal.participants.contains("p2"));XCTAssertTrue(end.participants.contains("p1"));XCTAssertEqual(heal.title,"释放技能")
    }
    func testHistorySearchRetainsOldAndNewNames()throws {
        let c=try session();var after=c.engine.state;after.units["p1"]?.name="新名字"
        let r=row(8,command:.applyPlayerProfile(unit:"p1",name:"新名字",appearance:.init()),before:c.engine.state,after:after,catalog:c.engine.catalog)
        for term in ["ELAN","新名字","p1","8","#8","更新人物"]{var q=MeadowHistoryQuery();q.text=term;XCTAssertEqual(q.apply([r]).map(\.sequence),[8],term)}
    }
    func testTeamRenameIncludesUnchangedMembers()throws {
        let c=try session();var after=c.engine.state;after.teams[0].name="新队名"
        let r=row(3,command:.configureTeams(names:["party":"新队名"],members:[:]),before:c.engine.state,after:after,catalog:c.engine.catalog)
        XCTAssertTrue(r.participants.isSuperset(of:["p1","p2"]))
    }
    func testHistoryFiltersAndOrderingDoNotRenumberRecords()throws {
        let c=try session(),a=row(2,command:.grantPlayerResources(actors:["p1"],ap:0,coins:1),before:c.engine.state,catalog:c.engine.catalog),b=row(9,command:.attack(actor:"p1",target:"p2"),before:c.engine.state,catalog:c.engine.catalog),d=row(12,command:.attack(actor:"p2",target:"p1"),before:c.engine.state,catalog:c.engine.catalog)
        var q=MeadowHistoryQuery();q.category = .combat;q.participant="p1";XCTAssertEqual(q.apply([a,b,d]).map(\.sequence),[12,9]);q.newestFirst=false;XCTAssertEqual(q.apply([a,b,d]).map(\.id),["record-9","record-12"])
    }
    func testNoMatchAndResetRestoreFullList()throws {
        let c=try session(),r=row(7,command:.endTurn(actor:"p1",timedOut:false),before:c.engine.state,catalog:c.engine.catalog)
        var q=MeadowHistoryQuery();q.text="不存在";XCTAssertTrue(q.apply([r]).isEmpty);q=MeadowHistoryQuery();XCTAssertEqual(q.apply([r]),[r])
    }
    func testIndexAndQueriesNeverMutateCampaignOrRNG()throws {
        let c=try session();let op=try c.engine.apply(.grantPlayerResources(actors:["p1"],ap:0,coins:1)),before=c.snapshot
        let r=MeadowHistoryIndex(entry:op,catalog:c.engine.catalog);_ = MeadowHistoryQuery().apply([r]);_ = MeadowJourneyQuery().apply([try journey(1,date:0,save:c.snapshot)])
        XCTAssertEqual(c.snapshot,before)
    }
    func testFilteredRollbackUsesOriginalIDAndRemovesHiddenOperations()throws {
        let c=try session();let first=try c.engine.apply(.grantPlayerResources(actors:["p1"],ap:0,coins:1));try c.engine.apply(.applyPlayerProfile(unit:"p1",name:"新名字",appearance:.init()));try c.engine.apply(.grantPlayerResources(actors:["p2"],ap:0,coins:2))
        var q=MeadowHistoryQuery();q.category = .resources;q.participant="p1";let rows=q.apply(c.engine.history.map{.init(entry:$0,catalog:c.engine.catalog)})
        XCTAssertEqual(rows.map(\.id),[first.id]);let restored=try c.snapshot.rollingBack(after:rows[0].id);XCTAssertEqual(restored.archive.history.map(\.id),[first.id]);XCTAssertNotEqual(restored.archive.state.units["p1"]?.name,"新名字")
    }
}
