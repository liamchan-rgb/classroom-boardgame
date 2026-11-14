import XCTest
import ClassroomGameCore
@testable import MeadowWorldSupport

final class QuizTests:XCTestCase {
    let sample="""
    # 注释
    1. 光合作用主要在植物的哪个部位进行？
    A. 根
    B、叶
    C) 茎
    D：花
    答案：B
    金币：15
    解析：叶绿体。

    第2题 3 × 7 = ?
    A. 18
    B. 21
    答案: b
    """
    func testPlainTextBankParses()throws {
        let bank=try QuizBankParser.parse(Data(sample.utf8))
        XCTAssertEqual(bank.count,2)
        XCTAssertEqual(bank[0].prompt,"光合作用主要在植物的哪个部位进行？");XCTAssertEqual(bank[0].options,["根","叶","茎","花"])
        XCTAssertEqual(bank[0].answer,1);XCTAssertEqual(bank[0].reward,15);XCTAssertEqual(bank[0].explanation,"叶绿体。")
        XCTAssertEqual(bank[1].prompt,"3 × 7 = ?");XCTAssertEqual(bank[1].answer,1);XCTAssertEqual(bank[1].reward,QuizQuestion.defaultCoins)
    }
    func testJSONBankParsesLettersAndIndexes()throws {
        let json=#"{"questions":[{"prompt":"Q1","options":["a","b"],"answer":"B"},{"prompt":"Q2","options":["x","y","z"],"answer":2,"coins":30}]}"#
        let bank=try QuizBankParser.parse(Data(json.utf8))
        XCTAssertEqual(bank.map(\.answer),[1,2]);XCTAssertEqual(bank[1].reward,30)
        XCTAssertEqual(try QuizBankParser.parse(Data(#"[{"prompt":"Q","options":["a","b"],"answer":0}]"#.utf8)).count,1)
    }
    func testBadBanksAreRejectedWithTheQuestionNumber()throws {
        XCTAssertThrowsError(try QuizBankParser.parse(Data("题目\nA. x\nB. y".utf8)))
        XCTAssertThrowsError(try QuizBankParser.parse(Data("题目\nA. x\nC. y\n答案：A".utf8)))
        XCTAssertThrowsError(try QuizBankParser.parse(Data("题目\nA. x\n答案：A".utf8)))
        XCTAssertThrowsError(try QuizBankParser.parse(Data("".utf8)))
        do {_=try QuizBankParser.parse(Data((sample+"\n\n坏题\nA. x\nB. y\n答案：E").utf8));XCTFail()}
        catch {XCTAssertTrue(error.localizedDescription.contains("第3题"))}
    }
    private func quizSession(_ bank:[QuizQuestion])throws->MeadowCampaignSession {
        var c=MeadowMapConfiguration.suggested(total:10,seed:31827);c.combat=0;c.boss=0;c.reward=0;c.empty=9;c.extraRoads=0
        return try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c),quizBank:bank)
    }
    func testFindEventsBecomeQuizzesAndPayOnlyForRightAnswers()throws {
        let bank=try QuizBankParser.parse(Data(sample.utf8)),s=try quizSession(bank)
        let nodes=s.engine.state.map.nodes.filter{$0.kind == .empty && s.siteKind(node:$0.id) == .satchel}
        XCTAssertFalse(nodes.isEmpty)
        for n in nodes {XCTAssertNotNil(s.quizQuestion(node:n.id))}
        XCTAssertNil(s.engine.state.map.nodes.first{s.siteKind(node:$0.id) == .spring}.flatMap{s.quizQuestion(node:$0.id)})
        let target=nodes[0]
        try s.beginTravel(to:target.id)
        while s.travel != nil {if !s.isMoving{try s.refillMovement(usingCoins:false);try s.setPaused(false)};try s.advanceTravel(distance:100000)}
        let q=try XCTUnwrap(s.quizQuestion(node:target.id)),coins=s.engine.state.units["p1"]!.coins,score=s.engine.state.units["p1"]!.score
        XCTAssertTrue(try s.answerQuiz(actor:"p1",choice:q.answer))
        XCTAssertEqual(s.engine.state.units["p1"]!.coins,coins+q.reward);XCTAssertEqual(s.engine.state.units["p1"]!.score,score+1)
        XCTAssertThrowsError(try s.answerQuiz(actor:"p2",choice:q.answer))
        let restored=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded()))
        XCTAssertEqual(restored.quizBank,bank)
    }
    func testWrongAnswerResolvesWithoutRewardAndNoBankKeepsFinds()throws {
        let bank=try QuizBankParser.parse(Data(sample.utf8)),s=try quizSession(bank)
        let target=s.engine.state.map.nodes.first{$0.kind == .empty && s.siteKind(node:$0.id) == .satchel}!
        try s.beginTravel(to:target.id)
        while s.travel != nil {if !s.isMoving{try s.refillMovement(usingCoins:false);try s.setPaused(false)};try s.advanceTravel(distance:100000)}
        let q=try XCTUnwrap(s.quizQuestion(node:target.id)),coins=s.engine.state.units["p1"]!.coins
        XCTAssertFalse(try s.answerQuiz(actor:"p1",choice:(q.answer+1)%q.options.count))
        XCTAssertEqual(s.engine.state.units["p1"]!.coins,coins);XCTAssertFalse(s.siteAvailable(actor:"p1"))
        let plain=try quizSession([]);XCTAssertNil(plain.snapshot.quizBank)
        XCTAssertNil(plain.quizQuestion(node:target.id))
        var bad=s.snapshot;bad.quizBank=[QuizQuestion(prompt:"x",options:["a"],answer:0)]
        XCTAssertThrowsError(try bad.validate())
    }
}
