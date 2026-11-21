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
        XCTAssertEqual(bank[0].answer,1);XCTAssertEqual(bank[0].reward,10);XCTAssertEqual(bank[0].explanation,"叶绿体。")
        XCTAssertEqual(bank[1].prompt,"3 × 7 = ?");XCTAssertEqual(bank[1].answer,1);XCTAssertEqual(bank[1].reward,QuizQuestion.defaultCoins)
    }
    func testJSONBankParsesLettersAndIndexes()throws {
        let json=#"{"questions":[{"prompt":"Q1","options":["a","b"],"answer":"B"},{"prompt":"Q2","options":["x","y","z"],"answer":2,"coins":30}]}"#
        let bank=try QuizBankParser.parse(Data(json.utf8))
        XCTAssertEqual(bank.map(\.answer),[1,2]);XCTAssertEqual(bank[1].reward,10)  // 金币 no longer changes the reward
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
        // Each student answers for themselves: the teammate gets the next question; then the event closes.
        XCTAssertThrowsError(try s.answerQuiz(actor:"p1",choice:q.answer))
        let next=try XCTUnwrap(s.quizTurn(actor:"p2"));XCTAssertNotEqual(next.question,q)
        try s.answerQuiz(actor:"p2",choice:nil)
        XCTAssertNil(s.quizTurn(actor:"p2"));XCTAssertFalse(s.siteAvailable(actor:"p1"))
        XCTAssertEqual(s.quizLog.map(\.player),["p1","p2"]);XCTAssertEqual(s.quizLog[1].picks,[nil])
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
        XCTAssertEqual(s.engine.state.units["p1"]!.coins,coins);XCTAssertTrue(s.siteAvailable(actor:"p1"))
        try s.answerQuiz(actor:"p2",choice:nil);XCTAssertFalse(s.siteAvailable(actor:"p1"))
        let plain=try quizSession([]);XCTAssertNil(plain.snapshot.quizBank)
        XCTAssertNil(plain.quizQuestion(node:target.id))
        var bad=s.snapshot;bad.quizBank=[QuizQuestion(prompt:"x",options:["a"],answer:0)]
        XCTAssertThrowsError(try bad.validate())
    }

    let mixed="""
    类型：闪卡
    难度：1
    正面：apple
    背面：苹果
    标签：水果

    类型：闪卡
    正面：pear
    背面：梨
    干扰：犁

    Tom {{went|goed|go}} to school and {{saw}} a cat.
    难度：中等
    时间：1:30
    标签：过去式, 动词

    类型：阅读
    难度：★★★
    文章：Tom has a red ball.
    He plays with it every day.
    问：What color is the ball?
    A. red
    B. blue
    答案：A
    问：When does he play?
    A. every day
    B. never
    C. on Sunday
    答案：A
    """
    func testMixedKindsParse()throws {
        let bank=try QuizBankParser.parse(Data(mixed.utf8))
        XCTAssertEqual(bank.map(\.type),[.flashcard,.flashcard,.fill,.reading])
        // Flash cards: graded right / wrong, so the back is the only option (distractors are ignored).
        let apple=bank[0].parts[0];XCTAssertEqual(apple.options,["苹果"]);XCTAssertEqual(apple.answer,0)
        XCTAssertEqual(bank[0].tags,["水果"]);XCTAssertEqual(bank[0].reward,10);XCTAssertEqual(bank[0].timeLimit,60)
        XCTAssertEqual(bank[1].parts[0].options,["梨"]);XCTAssertNil(bank[1].difficulty)
        XCTAssertEqual(bank[2].prompt,"Tom {{1}} to school and {{2}} a cat.");XCTAssertEqual(bank[2].parts.count,2)
        XCTAssertEqual(Set(bank[2].parts[0].options),["went","goed","go"]);XCTAssertEqual(bank[2].parts[0].options[bank[2].parts[0].answer],"went")
        XCTAssertEqual(bank[2].parts[1].options,["saw"]);XCTAssertEqual(bank[2].timeLimit,90);XCTAssertEqual(bank[2].difficulty,2)
        XCTAssertEqual(bank[2].tags,["过去式","动词"])
        XCTAssertEqual(bank[3].passage,"Tom has a red ball.\nHe plays with it every day.");XCTAssertEqual(bank[3].parts.map(\.answer),[0,0])
        XCTAssertEqual(bank[3].difficulty,3);XCTAssertEqual(bank[3].reward,30);XCTAssertEqual(bank[3].timeLimit,120)
        // Same bank → same option order every time (the teacher's buttons never move).
        XCTAssertEqual(try QuizBankParser.parse(Data(mixed.utf8)),bank)
        let json=#"[{"type":"fill","prompt":"1+1={{2|3}}","difficulty":"难"},{"front":"cat","back":"猫","distractors":["狗"]},{"type":"reading","passage":"P","questions":[{"prompt":"q","options":["x","y"],"answer":"B"}],"seconds":45,"tags":["t"]}]"#
        let j=try QuizBankParser.parse(Data(json.utf8))
        XCTAssertEqual(j.map(\.type),[.fill,.flashcard,.reading]);XCTAssertEqual(j[0].difficulty,3);XCTAssertEqual(j[2].parts[0].answer,1);XCTAssertEqual(j[2].timeLimit,45)
        XCTAssertThrowsError(try QuizBankParser.parse(Data("类型：阅读\n文章：x\n问：q\nA. a\n答案：A".utf8)))
        XCTAssertThrowsError(try QuizBankParser.parse(Data("Tom {{ went".utf8)))
    }
    private func arrive(_ s:MeadowCampaignSession)throws->MapNode {
        let target=s.engine.state.map.nodes.first{$0.kind == .empty && s.siteKind(node:$0.id) == .satchel}!
        try s.beginTravel(to:target.id)
        while s.travel != nil {if !s.isMoving{try s.refillMovement(usingCoins:false);try s.setPaused(false)};try s.advanceTravel(distance:100000)}
        return target
    }
    func testRightAnswersPayByDifficultyWithAMovementStep()throws {
        let hard=QuizQuestion(prompt:"R",options:[],answer:0,kind:.reading,difficulty:3,passage:"P",
                              items:[QuizItem(prompt:"a",options:["x","y"],answer:0),QuizItem(prompt:"b",options:["x","y"],answer:1)])
        let easy=QuizQuestion(prompt:"c",options:[],answer:0,kind:.flashcard,difficulty:1,items:[QuizItem(options:["猫"],answer:0)])
        let s=try quizSession([hard,easy]);let node=try arrive(s)
        let before=s.engine.state.units["p1"]!
        try s.grantSupplies(actors:["p1"],movementSteps:0,coins:1)  // (a bar with room for steps)
        let bar=s.movement(team:before.teamID).remaining
        // Half right: nothing (no coins, points or step).
        let a=try s.recordQuiz(actor:"p1",question:0,picks:[0,nil],texts:[nil,"不知道"],seconds:100)
        XCTAssertEqual(a.correct,[true,false]);XCTAssertEqual(a.coins,0);XCTAssertEqual(a.score,0);XCTAssertNil(a.drop);XCTAssertEqual(a.node,node.id)
        XCTAssertEqual(s.quizLog[0].texts,[nil,"不知道"]);XCTAssertEqual(s.movement(team:before.teamID).remaining,bar)
        // All right, ★★★: 30 coins, 3 points, no drop, one step for the team (up to a full bar).
        let mate=s.engine.state.units["p2"]!
        let b=try s.recordQuiz(actor:"p2",question:0,picks:[0,1],seconds:20)
        XCTAssertEqual(b.coins,30);XCTAssertEqual(b.score,3);XCTAssertNil(b.drop)
        XCTAssertEqual(s.engine.state.units["p2"]!.coins,mate.coins+30)
        let cap=s.movement(team:mate.teamID).capacity
        XCTAssertEqual(s.movement(team:mate.teamID).remaining,min(cap,bar+MeadowMovementRules.distancePerStep),accuracy:0.001)
        XCTAssertFalse(s.siteAvailable(actor:"p1"))
        // Flash-card practice pays too: ★ = 10 coins, 1 point.
        let c=try s.recordQuiz(actor:"p1",question:1,picks:[0],seconds:2,free:true,practice:true)
        XCTAssertEqual(c.coins,10);XCTAssertEqual(c.score,1)
        let restored=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded()))
        XCTAssertEqual(restored.quizLog,s.quizLog)
    }
    func testOvertimePaysNothingButIsRecorded()throws {
        let q=QuizQuestion(prompt:"c",options:[],answer:0,kind:.flashcard,difficulty:1,seconds:30,items:[QuizItem(options:["猫","狗"],answer:0)])
        let s=try quizSession([q]);_=try arrive(s)
        let coins=s.engine.state.units["p1"]!.coins
        let a=try s.recordQuiz(actor:"p1",question:0,picks:[0],seconds:45)
        XCTAssertTrue(a.overtime);XCTAssertEqual(a.coins,0);XCTAssertEqual(a.score,0);XCTAssertEqual(s.engine.state.units["p1"]!.coins,coins)
        XCTAssertEqual(a.correct,[true])
        XCTAssertThrowsError(try s.recordQuiz(actor:"p2",question:0,picks:[0,1],seconds:1))
    }
    func testReportCountsPartsTimesAndCommonWrongAnswers()throws {
        let bank=try QuizBankParser.parse(Data(mixed.utf8))
        func a(_ p:String,_ q:Int,_ picks:[Int?],_ texts:[String?]?=nil,_ sec:Double)->QuizAttempt {
            let parts=bank[q].parts
            return QuizAttempt(player:p,playerName:p.uppercased(),node:q,question:q,picks:picks,texts:texts ?? picks.map{_ in nil},
                               correct:parts.indices.map{picks[$0]==parts[$0].answer},seconds:sec,limit:bank[q].timeLimit,at:1_800_000_000+sec)
        }
        let fill=bank[2].parts[0],goed=fill.options.firstIndex(of:"goed")!
        let log=[a("p2",2,[goed,0],nil,40),a("p1",2,[fill.answer,nil],[nil,"see"],30),a("p1",3,[0,1],nil,100),a("p3",2,[goed,nil],nil,20)]
        let r=QuizReport(log:log,bank:bank,order:["p1","p2","p3"],names:["p1":"小明"])
        XCTAssertEqual(r.students.map(\.id),["p1","p2","p3"]);XCTAssertEqual(r.students[0].name,"小明");XCTAssertEqual(r.students[1].name,"P2")
        XCTAssertEqual(r.students[0].right,2);XCTAssertEqual(r.students[0].total,4);XCTAssertEqual(r.students[0].averageSeconds,65)
        XCTAssertEqual(r.students[0].lines[0].answers[1].said,"see");XCTAssertEqual(r.students[2].lines[0].answers[1].said,"不会")
        XCTAssertEqual(r.students[0].byKind.map(\.name),["填空","阅读"]);XCTAssertEqual(r.students[0].byTag.map(\.name),["过去式","动词"])
        XCTAssertEqual(r.students[0].mistakes.count,2)
        // The fill-in: 6 blanks answered, 2 right; "goed" in blank 1 said twice is the common slip; hardest comes first.
        let fillStat=try XCTUnwrap(r.questions.first{$0.index==2})
        XCTAssertEqual(fillStat.attempts,3);XCTAssertEqual(fillStat.right,2);XCTAssertEqual(fillStat.total,6)
        XCTAssertEqual(fillStat.commonWrong?.said,"第1空：goed");XCTAssertEqual(fillStat.commonWrong?.count,2)
        XCTAssertEqual(r.questions.first?.index,2);XCTAssertEqual(r.attempts,4);XCTAssertEqual(r.total,8)
        XCTAssertEqual(QuizReport.summary(bank[2]),"Tom （1） to school and （2） a cat.")
    }
    func testDocumentedSampleBankParses()throws {
        let url=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("../../../../../docs/question-bank-sample.txt").standardized
        let bank=try QuizBankParser.parse(Data(contentsOf:url))
        XCTAssertTrue(Set(bank.map(\.type)).isSuperset(of:[.choice,.flashcard,.fill,.reading]))
    }
    func testAnsweringRightLaterMovesMistakesToCorrected()throws {
        let bank=try QuizBankParser.parse(Data(mixed.utf8))
        func a(_ p:String,_ q:Int,_ picks:[Int?])->QuizAttempt {
            let parts=bank[q].parts
            return QuizAttempt(player:p,playerName:p,node:-1,question:q,picks:picks,texts:picks.map{_ in nil},
                               correct:parts.indices.map{picks[$0]==parts[$0].answer},seconds:5,limit:60,at:1_800_000_000)
        }
        let apple=bank[0].parts[0],fill=bank[2].parts
        let goed=fill[0].options.firstIndex(of:"goed")!
        let allRight=fill.map{Optional($0.answer)}
        // apple wrong then right (corrected); the fill question wrong twice then right (corrected, shown once);
        // the reading question wrong, still wrong.
        let log=[a("p1",0,[nil]),a("p1",2,[goed,nil]),a("p1",2,[goed,fill[1].answer]),a("p1",3,[1,1]),a("p1",0,[apple.answer]),a("p1",2,allRight)]
        let s=QuizReport(log:log,bank:bank,order:["p1"]).students[0]
        XCTAssertEqual(s.mistakes.map(\.attempt.question),[3])
        XCTAssertEqual(s.corrected.map(\.attempt.question),[0,2])
        XCTAssertEqual(s.corrected[1].answers[0].said,"goed")  // the first wrong answer is shown
        XCTAssertTrue(s.wrongWords.isEmpty)
        XCTAssertEqual(Set(s.correctedWords.map(\.word)),["apple","went","saw"])
        // Missed again after correcting: back to the mistakes.
        let again=QuizReport(log:log+[a("p1",0,[nil])],bank:bank,order:["p1"]).students[0]
        XCTAssertEqual(again.wrongWords.map(\.word),["apple"]);XCTAssertEqual(again.mistakes.map(\.attempt.question),[0,3])
    }
    func testSkippedStudentsAndWholeDecksInTheReport()throws {
        let text="""
        类型：闪卡
        份：1
        正面：apple
        背面：苹果

        类型：闪卡
        份：1
        正面：pear
        背面：梨

        类型：闪卡
        正面：cat
        背面：猫

        类型：选择
        难度：1
        标签：单词
        Shoes go on your ___.
        A. hands
        B. feet
        答案：B
        """
        let bank=try QuizBankParser.parse(Data(text.utf8))
        var c=MeadowMapConfiguration.suggested(total:10,seed:31827);c.combat=0;c.boss=0;c.reward=0;c.empty=9;c.extraRoads=0
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c),studentNames:["小明","小红"],quizBank:bank)
        // 小明 answers the class question; 小红 was not picked and is put in the mistakes.
        try s.recordQuiz(actor:"p1",question:3,picks:[1],seconds:5,free:true,shared:true)
        try s.recordQuiz(actor:"p2",question:3,picks:[nil],seconds:0,free:true,shared:true,skipped:true)
        try s.recordQuiz(actor:"p1",question:0,picks:[nil],seconds:3,free:true,practice:true)
        try s.recordQuiz(actor:"p1",question:0,picks:[0],seconds:3,free:true,practice:true)
        let r=s.quizReport
        let p2=try XCTUnwrap(r.students.first{$0.id=="p2"})
        XCTAssertEqual(p2.mistakes.first?.answers.first?.said,"未作答")
        XCTAssertEqual(p2.wrongWords.first?.word,"feet");XCTAssertEqual(p2.wrongWords.first?.said,[])  // never "说成 未作答"
        XCTAssertNil(r.words.first{$0.word=="feet"}?.commonWrong)
        // One bank: every student's list is every flash card of the course, asked or not (old 份 lines are ignored).
        let p1=try XCTUnwrap(r.students.first{$0.id=="p1"})
        XCTAssertEqual(p1.vocabulary.map(\.word),["apple","pear","cat"])
        XCTAssertEqual(p1.vocabulary.map(\.status),[.corrected,.untested,.untested])
        XCTAssertEqual(p2.vocabulary.map(\.word),["apple","pear","cat"])
        // The class list: every flash card of the course, asked or not.
        XCTAssertEqual(r.cards.map(\.word),["apple","pear","cat"])
        XCTAssertEqual(r.cards[0].asked,2);XCTAssertEqual(r.cards[0].right,1);XCTAssertEqual(r.cards[0].missedBy,["小明"])
        XCTAssertEqual(r.cards[1].asked,0)
    }
    func testReportListsWrongWords()throws {
        let bank=try QuizBankParser.parse(Data(mixed.utf8))
        func a(_ p:String,_ q:Int,_ picks:[Int?],_ texts:[String?]?=nil)->QuizAttempt {
            let parts=bank[q].parts
            return QuizAttempt(player:p,playerName:p,node:-1,question:q,picks:picks,texts:texts ?? picks.map{_ in nil},
                               correct:parts.indices.map{picks[$0]==parts[$0].answer},seconds:5,limit:60,at:1_800_000_000)
        }
        let apple=bank[0].parts[0]
        let fill=bank[2].parts[0],goed=fill.options.firstIndex(of:"goed")!
        let log=[a("p1",0,[nil]),a("p1",2,[goed,nil],[nil,"see"]),a("p2",0,[apple.answer]),a("p2",2,[goed,0]),a("p1",3,[1,1])]
        let r=QuizReport(log:log,bank:bank,order:["p1","p2"],names:["p1":"小明","p2":"小红"])
        let p1=r.students[0]
        XCTAssertEqual(p1.wrongWords.map(\.word),["apple","went","saw"])
        XCTAssertEqual(p1.wrongWords[0].meaning,"苹果");XCTAssertEqual(p1.wrongWords[0].said,[])  // "答错" is not a wrong answer to quote;XCTAssertEqual(p1.wrongWords[2].said,["see"])
        XCTAssertEqual(p1.wordsAsked,3)  // the reading questions are not word items (no 单词 tag)
        XCTAssertEqual(r.words.first?.word,"went");XCTAssertEqual(r.words.first?.wrong,2);XCTAssertEqual(r.words.first?.asked,2)
        XCTAssertEqual(r.words.first?.students,["小明","小红"]);XCTAssertEqual(r.words.first?.commonWrong,"goed")
        XCTAssertEqual(Set(r.words.map(\.word)),["went","apple","saw"])
        // A Chinese front: the English back is the word.
        let zh=QuizQuestion(prompt:"苹果",options:[],answer:0,kind:.flashcard,items:[QuizItem(options:["apple","pear"],answer:0)])
        XCTAssertEqual(QuizReport.word(zh,part:0),QuizReport.Word(word:"apple",meaning:"苹果"))
        var tagged=QuizQuestion(prompt:"选出 big 的反义词",options:["small","tall"],answer:0);tagged.tags=["单词"]
        XCTAssertEqual(QuizReport.word(tagged,part:0)?.word,"small");tagged.tags=nil;XCTAssertNil(QuizReport.word(tagged,part:0))
    }
    func testFreeQuizAnywhereDoesNotTouchTheMapAndBanksAppend()throws {
        let s=try quizSession([])
        XCTAssertNil(s.drawQuestion(.random,for:"p1"))
        try s.appendQuizBank(try QuizBankParser.parse(Data(mixed.utf8)))
        XCTAssertEqual(s.quizBank.count,4)
        let i=try XCTUnwrap(s.drawQuestion(.random,for:"p1",kind:.flashcard));XCTAssertEqual(s.quizBank[i].type,.flashcard)
        let nodes=s.engine.state.map.nodes,coins=s.engine.state.units["p1"]!.coins
        let q=s.quizBank[i]
        let a=try s.recordQuiz(actor:"p1",question:i,picks:[q.parts[0].answer],seconds:40,free:true)
        XCTAssertEqual(a.node,-1);XCTAssertEqual(s.engine.state.map.nodes,nodes);XCTAssertGreaterThan(s.engine.state.units["p1"]!.coins,coins)
        XCTAssertTrue(s.quizAskedBefore(i))
        try s.recordQuiz(actor:"p1",question:i,picks:[nil],seconds:3,free:true)
        XCTAssertEqual(s.quizLog.count,2)
        let restored=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded()))
        XCTAssertEqual(restored.quizBank.count,4);XCTAssertEqual(restored.quizLog,s.quizLog)
    }
    /// A generator with a fixed sequence, so random draws are repeatable in tests.
    private struct Seeded:RandomNumberGenerator {
        var state:UInt64
        mutating func next()->UInt64 {state=state &* 6364136223846793005 &+ 1442695040888963407;return state}
    }
    func testOneBankDrawsAtRandomWithFreshQuestionsFirst()throws {
        // Old 对象/份 lines still parse but no longer split the bank.
        let text="""
        类型：闪卡
        对象：小明
        正面：elephant
        背面：大象

        类型：闪卡
        份：2
        难度：2
        正面：tiger
        背面：老虎

        类型：闪卡
        难度：3
        正面：rhinoceros
        背面：犀牛

        类型：选择
        难度：2
        Which is a fruit?
        A. apple
        B. chair
        答案：A
        """
        let bank=try QuizBankParser.parse(Data(text.utf8))
        var c=MeadowMapConfiguration.suggested(total:10,seed:31827);c.combat=0;c.boss=0;c.reward=0;c.empty=9;c.extraRoads=0
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c),studentNames:["小明","小红"],quizBank:bank)
        XCTAssertEqual(s.quizPool(.random),[0,1,2,3]);XCTAssertEqual(s.quizPool(.difficulty(1)),[0]);XCTAssertEqual(s.quizPool(.difficulty(2)),[1,3])
        XCTAssertEqual(s.quizPool(.difficulty(2),kind:.choice),[3])
        var g=Seeded(state:7)
        // Every question comes up for each student before any repeats.
        var seen=Set<Int>()
        for _ in 0..<4 {
            let i=try XCTUnwrap(s.drawQuestion(.random,for:"p2",using:&g));XCTAssertFalse(seen.contains(i));seen.insert(i)
            try s.recordQuiz(actor:"p2",question:i,picks:Array(repeating:0,count:bank[i].parts.count),seconds:5,free:true,challenge:true)
        }
        XCTAssertEqual(seen,[0,1,2,3])
        // All had: any may come again (and is known as asked before); 小明 still gets fresh ones; the class (nil) none fresh.
        XCTAssertNotNil(s.drawQuestion(.random,for:"p2",using:&g));XCTAssertTrue(s.quizAskedBefore(0))
        XCTAssertNotNil(s.drawQuestion(.difficulty(3),for:"p1",using:&g))
        // 换一题: not the one on screen, unless it is the only one.
        for _ in 0..<10 {XCTAssertEqual(s.drawQuestion(.difficulty(2),for:"p1",excluding:[1],using:&g),3)}
        XCTAssertEqual(s.drawQuestion(.difficulty(1),for:"p1",excluding:[0],using:&g),0)
        XCTAssertNil(s.drawQuestion(.difficulty(3),for:"p1",kind:.choice,using:&g))
        // Flash cards: one deck for every student and the class.
        XCTAssertEqual(s.classFlashDeck,[0,1,2]);XCTAssertEqual(s.practiceDeck(for:"p1"),[0,1,2]);XCTAssertEqual(s.practiceDeck(for:"p2"),[0,1,2])
        // The class list in the report: by difficulty.
        XCTAssertEqual(s.quizReport.cards.map(\.word),["elephant","tiger","rhinoceros"]);XCTAssertEqual(s.quizReport.cards.map(\.difficulty),[1,2,3])
        // Each student's own list leaves the ★★★ cards out.
        XCTAssertEqual(s.quizReport.students.first{$0.id=="p1"}?.vocabulary.map(\.word),["elephant","tiger"])
    }
    func testRepeatedQuestionsShuffleOptionsAndRecordTheRealAnswer()throws {
        let text="""
        类型：选择
        Which is a fruit?
        A. apple
        B. chair
        C. desk
        D. door
        答案：A

        类型：填空
        Tom {{went|goed|go}} home and {{saw|seed}} a cat.
        """
        let bank=try QuizBankParser.parse(Data(text.utf8)),s=try quizSession(bank)
        var g=Seeded(state:3)
        for _ in 0..<20 {
            let sh=bank[0].shuffledOptions(using:&g)
            XCTAssertNotEqual(sh.question.options,bank[0].options);XCTAssertEqual(Set(sh.question.options),Set(bank[0].options))
            XCTAssertEqual(sh.question.options[sh.question.answer],"apple")
            XCTAssertEqual(sh.original([sh.question.answer]),[0])
        }
        let fill=bank[1].shuffledOptions(using:&g)
        XCTAssertEqual(fill.question.parts.map{$0.options[$0.answer]},["went","saw"])
        XCTAssertEqual(fill.question.prompt,bank[1].prompt)
        // The student said the right words on the shuffled card: recorded right, in the bank's option order.
        let picks=fill.original(fill.question.parts.map{$0.answer})
        XCTAssertEqual(picks,bank[1].parts.map{$0.answer})
        let a=try s.recordQuiz(actor:"p1",question:1,picks:picks,seconds:5,free:true)
        XCTAssertEqual(a.correct,[true,true])
        // Flash cards are left as they are.
        let card=QuizBankParser.flashcard(front:"cat",back:"猫",distractors:[])
        XCTAssertEqual(card.shuffledOptions(using:&g).question,card)
    }
    func testBundledSampleBankHasEveryKindAndNoPortions()throws {
        let url=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("../../../../ClassroomProbe/Resources/quiz-sample.txt").standardized
        let bank=try QuizBankParser.parse(Data(contentsOf:url))
        XCTAssertFalse(bank.contains{$0.portion != nil || $0.audience != nil})
        XCTAssertTrue(Set(bank.map(\.type)).isSuperset(of:[.choice,.flashcard,.fill,.reading]))
        XCTAssertEqual(Set(bank.compactMap(\.difficulty)),[1,2,3])
    }
    func testChallengeAnswersPayByDifficultyWithoutSpeedBonus()throws {
        let text="""
        类型：闪卡
        正面：cat
        背面：猫

        类型：闪卡
        难度：2
        正面：tiger
        背面：老虎

        类型：闪卡
        难度：3
        正面：rhinoceros
        背面：犀牛
        """
        let bank=try QuizBankParser.parse(Data(text.utf8)),s=try quizSession(bank)
        let coins=s.engine.state.units["p1"]!.coins
        // A slow but right ★★★ answer: full difficulty reward, no speed bonus, not overtime.
        let a=try s.recordQuiz(actor:"p1",question:2,picks:[0],seconds:200,free:true,challenge:true)
        XCTAssertFalse(a.overtime);XCTAssertEqual(a.coins,QuizRewards.baseCoins[2]);XCTAssertEqual(a.score,3);XCTAssertNil(a.drop)
        XCTAssertEqual(s.engine.state.units["p1"]!.coins,coins+a.coins)
        // Fast answers in a challenge get no bonus either.
        let b=try s.recordQuiz(actor:"p1",question:1,picks:[0],seconds:1,free:true,challenge:true)
        XCTAssertEqual(b.coins,QuizRewards.baseCoins[1])
        // A wrong flash card reads "答错" in the report.
        try s.recordQuiz(actor:"p1",question:0,picks:[nil],seconds:3,free:true,challenge:true)
        XCTAssertEqual(s.quizReport.students[0].wrongWords.first?.said,[])
        // Shared to the class: the teacher's coins, points for right, nothing from the drop table.
        let shared=try s.recordQuiz(actor:"p1",question:1,picks:[0],seconds:999,free:true,participation:5,shared:true)
        XCTAssertEqual(shared.coins,20);XCTAssertEqual(shared.score,2);XCTAssertNil(shared.drop)
        // Wrong to the class: the participation prize only.
        let missed=try s.recordQuiz(actor:"p1",question:1,picks:[nil],seconds:3,free:true,participation:5,shared:true)
        XCTAssertEqual(missed.coins,5);XCTAssertEqual(missed.score,0)
    }
    func testWordsSaidRightInHarderQuestionsCountAsPassed()throws {
        let text="""
        类型：闪卡
        难度：1
        正面：帽子
        背面：hat

        类型：闪卡
        难度：1
        正面：鼻子
        背面：nose

        类型：闪卡
        难度：2
        正面：手套
        背面：glove

        类型：闪卡
        难度：1
        正面：青蛙
        背面：frog

        类型：闪卡
        难度：3
        正面：我的帽子戴在鼻子上。
        背面：My hat goes on my nose.

        类型：填空
        难度：2
        Your {{gloves|shoes}} go on your hands.
        """
        let bank=try QuizBankParser.parse(Data(text.utf8)),s=try quizSession(bank)
        try s.recordQuiz(actor:"p1",question:1,picks:[nil],seconds:3,free:true,shared:true,practice:true)  // nose: wrong on its own
        try s.recordQuiz(actor:"p1",question:4,picks:[0],seconds:3,free:true,challenge:true)              // ★★★ sentence right
        try s.recordQuiz(actor:"p1",question:5,picks:[bank[5].parts[0].answer],seconds:3,free:true)        // ★★ fill right: gloves
        let v=try XCTUnwrap(s.quizReport.students.first{$0.id=="p1"}).vocabulary
        let status=Dictionary(uniqueKeysWithValues:v.map{($0.word,$0.status)})
        XCTAssertEqual(status["hat"],.right)        // never asked alone, said right in the ★★★ sentence
        XCTAssertEqual(status["nose"],.corrected)   // wrong alone, then right in the sentence
        XCTAssertEqual(status["frog"],.untested)
        // glove (★★) is in a ★★ fill-in: not harder, so still not tested on its own.
        XCTAssertEqual(status["glove"],.untested)
        XCTAssertTrue(QuizReport.Words("Tom looked after the dogs.").contains("look after"))
        XCTAssertTrue(QuizReport.Words("Tom looked after the dogs.").contains("dog"))
        XCTAssertFalse(QuizReport.Words("Tom looked after the dogs.").contains("cat"))
    }
    func testAppPromptRulesMatchTheDocumentedPrompt()throws {
        let here=URL(fileURLWithPath:#filePath).deletingLastPathComponent()
        let doc=try String(contentsOf:here.appendingPathComponent("../../../../../docs/question-bank-llm-prompt.md").standardized,encoding:.utf8)
        let app=try String(contentsOf:here.appendingPathComponent("../../../../ClassroomProbe/Resources/quiz-prompt-rules.txt").standardized,encoding:.utf8)
        let start=try XCTUnwrap(doc.range(of:"### 难度与题型（必须遵守）")),end=try XCTUnwrap(doc.range(of:"\n---\n\n## 使用提示"))
        // The app's editor builds its prompts on the same rules as the document (copy them over when either changes).
        XCTAssertEqual(String(doc[start.lowerBound..<end.lowerBound]).trimmingCharacters(in:.whitespacesAndNewlines),app.trimmingCharacters(in:.whitespacesAndNewlines))
    }
    func testBankTurnsBackIntoTextThatImportsTheSame()throws {
        let url=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("../../../../ClassroomProbe/Resources/quiz-sample.txt").standardized
        var bank=try QuizBankParser.parse(Data(contentsOf:url))
        bank[0].explanation="苹果\n是水果";bank[0].seconds=45
        let text=QuizBankParser.text(bank,course:"示例")
        XCTAssertTrue(text.hasPrefix("# 课程：示例\n\n"))
        let again=try QuizBankParser.parse(Data(text.utf8))
        XCTAssertEqual(again.count,bank.count)
        for (a,b) in zip(again,bank) {
            XCTAssertEqual(a.type,b.type);XCTAssertEqual(a.prompt,b.prompt);XCTAssertEqual(a.difficulty,b.difficulty);XCTAssertEqual(a.tags,b.tags)
            XCTAssertEqual(a.passage,b.passage);XCTAssertEqual(a.seconds,b.seconds)
            // The same right answers among the same options (fill-in options come back in their own order).
            XCTAssertEqual(a.parts.map{$0.options[$0.answer]},b.parts.map{$0.options[$0.answer]})
            XCTAssertEqual(a.parts.map{Set($0.options)},b.parts.map{Set($0.options)})
        }
        XCTAssertEqual(again[0].explanation,"苹果 是水果")
    }
    func testUnaskedAndMistakenQuestionsComeFirst()throws {
        let bank=(1...4).map{QuizBankParser.flashcard(front:"w\($0)",back:"词\($0)",distractors:[])}
        let s=try quizSession(bank)
        XCTAssertEqual(s.unaskedQuestions(for:"p1"),[0,1,2,3])
        try s.recordQuiz(actor:"p1",question:0,picks:[0],seconds:2,free:true,practice:true)
        try s.recordQuiz(actor:"p1",question:1,picks:[nil],seconds:2,free:true,practice:true)
        try s.recordQuiz(actor:"p2",question:2,picks:[0],seconds:2,free:true,shared:true)
        XCTAssertEqual(s.unaskedQuestions(for:"p1"),[2,3]);XCTAssertEqual(s.mistakenQuestions(for:"p1"),[1])
        XCTAssertEqual(s.unaskedQuestions(for:nil),[3]);XCTAssertEqual(s.mistakenQuestions(for:nil),[1])
        // 小明: never the one he already got right while others are left.
        for _ in 0..<20 {XCTAssertNotEqual(s.drawQuestion(.random,for:"p1"),0)}
        // The class: only the unasked one and the one still wrong.
        for _ in 0..<20 {XCTAssertTrue([1,3].contains(s.drawQuestion(.random,for:nil)!))}
        // Right later: no longer a mistake.
        try s.recordQuiz(actor:"p1",question:1,picks:[0],seconds:2,free:true,practice:true)
        XCTAssertEqual(s.mistakenQuestions(for:"p1"),[])
    }
    func testTeacherCorrectsAndRemovesAnswerRecords()throws {
        let bank=[QuizBankParser.flashcard(front:"cat",back:"猫",distractors:[]),QuizQuestion(prompt:"2+2?",options:["3","4"],answer:1)]
        let s=try quizSession(bank)
        try s.recordQuiz(actor:"p1",question:0,picks:[nil],seconds:2,free:true,shared:true)  // recorded wrong by mistake
        try s.recordQuiz(actor:"p1",question:1,picks:[1],seconds:2,free:true,shared:true)
        try s.recordQuiz(actor:"p2",question:1,picks:[1],seconds:2,free:true,shared:true)  // p2 never answered this
        let coins=s.engine.state.units["p1"]!.coins
        XCTAssertEqual(s.quizReport.students.first{$0.id=="p1"}?.wrongWords.map(\.word),["cat"])
        // Corrected to right: the report follows; rewards stay as they were.
        try s.setQuizRecord(at:0,right:true)
        XCTAssertEqual(s.quizLog[0].correct,[true]);XCTAssertEqual(s.quizLog[0].picks,[0])
        XCTAssertEqual(s.quizReport.students.first{$0.id=="p1"}?.wrongWords,[])
        XCTAssertEqual(s.engine.state.units["p1"]!.coins,coins)
        // And back to wrong.
        try s.setQuizRecord(at:1,right:false)
        XCTAssertEqual(s.quizLog[1].picks,[nil]);XCTAssertEqual(s.quizReport.students.first{$0.id=="p1"}?.mistakes.count,1)
        // A record that should not be there: out of the report.
        try s.removeQuizRecord(at:2)
        XCTAssertEqual(s.quizLog.count,2);XCTAssertNil(s.quizReport.students.first{$0.id=="p2" && !$0.lines.isEmpty})
        XCTAssertThrowsError(try s.removeQuizRecord(at:5))
        // Saved and reopened the same.
        let restored=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded()))
        XCTAssertEqual(restored.quizLog,s.quizLog)
    }
    /// The history is saved as changes (only changed characters, the answer log as "keep k, then these"), so a long
    /// class does not save every answer again in every entry; it reads back exactly, edits and removals included.
    func testHistoryIsSavedCompactlyAndReadsBackExactly()throws {
        let bank=(0..<12).map{QuizBankParser.flashcard(front:"w\($0)",back:"词\($0)",distractors:[])}
        let s=try quizSession(bank)
        for k in 0..<12 {try s.recordQuiz(actor:k%2==0 ? "p1":"p2",question:k,picks:[k%3==0 ? nil:0],seconds:2,free:true,shared:true)}
        try s.setQuizRecord(at:3,right:true);try s.removeQuizRecord(at:1)
        let bytes=try s.snapshot.encoded()
        let back=try MeadowCampaignSave.decoded(bytes)
        XCTAssertEqual(back.archive,s.snapshot.archive)
        XCTAssertEqual(back.archive.history.map(\.before),s.engine.history.map(\.before))
        // Every history state written in full would repeat the growing answer log; stored as changes it is not.
        let full=try JSONSerialization.jsonObject(with:bytes) as! [String:Any]
        let history=(full["archive"] as! [String:Any])["history"] as! [[String:Any]]
        XCTAssertTrue(history.dropFirst().allSatisfy{$0["before"]==nil || ($0["before"] as? [String:Any])?["delta"] as? Bool==true})
        XCTAssertTrue(history.dropFirst().allSatisfy{($0["after"] as? [String:Any])?["delta"] as? Bool==true})
        // Files written before (full states) still read, and are much bigger.
        let legacy=try checkLegacyHistoryReads(full,s)
        XCTAssertGreaterThan(legacy,bytes.count)
    }
    private func checkLegacyHistoryReads(_ full:[String:Any],_ s:MeadowCampaignSession)throws->Int {
        var legacy=full
        var legacyArchive=legacy["archive"] as! [String:Any]
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        var rows:[Any]=[]
        for receipt in s.engine.history {rows.append(try JSONSerialization.jsonObject(with:encoder.encode(receipt)))}
        legacyArchive["history"]=rows
        legacy["archive"]=legacyArchive
        let legacyBytes=try JSONSerialization.data(withJSONObject:legacy)
        let legacySave=try MeadowCampaignSave.decoded(legacyBytes)
        XCTAssertEqual(legacySave.archive,s.snapshot.archive)
        return legacyBytes.count
    }
    /// A challenge given to the wrong student: all its answers come back off in one go (records, coins, points and
    /// movement steps), or move to the right student and pay them instead.
    func testChallengeForTheWrongStudentCanBeUndoneOrMoved()throws {
        let bank=(0..<3).map{QuizBankParser.flashcard(front:"w\($0)",back:"词\($0)",distractors:[])}
        let s=try quizSession(bank)
        _=try arrive(s)  // the bar is not full, so steps show
        let start=s.engine.state,move=s.movement(team:s.engine.state.units["p1"]!.teamID).remaining,logCount=s.quizLog.count
        let mark=s.quizRunMark()
        var ids:[String]=[]
        for k in 0..<3 {let id=UUID().uuidString;try s.recordQuiz(actor:"p1",question:k,picks:[0],seconds:3,free:true,challenge:true,id:id);ids.append(id)}
        XCTAssertGreaterThan(s.engine.state.units["p1"]!.coins,start.units["p1"]!.coins)
        XCTAssertTrue(s.canUndoQuizRun(mark,ids:ids))
        // Moved to p2: p1 is back where it was, p2 has the three answers and their rewards.
        let moved=try s.moveQuizRun(mark,ids:ids,to:"p2")
        XCTAssertEqual(moved.count,3)
        XCTAssertEqual(s.engine.state.units["p1"]!.coins,start.units["p1"]!.coins);XCTAssertEqual(s.engine.state.units["p1"]!.score,start.units["p1"]!.score)
        XCTAssertEqual(s.quizLog.suffix(3).map(\.player),["p2","p2","p2"]);XCTAssertEqual(s.quizLog.count,logCount+3)
        XCTAssertEqual(s.engine.state.units["p2"]!.coins,start.units["p2"]!.coins+30)
        // And taken back altogether: as before the challenge, movement included.
        try s.undoQuizRun(mark,ids:moved)
        XCTAssertEqual(s.engine.state.units,start.units);XCTAssertEqual(s.quizLog.count,logCount)
        XCTAssertEqual(s.movement(team:s.engine.state.units["p1"]!.teamID).remaining,move,accuracy:0.001)
        // Something else done after the run: no longer undone as a whole.
        let mark2=s.quizRunMark(),id=UUID().uuidString
        try s.recordQuiz(actor:"p1",question:0,picks:[0],seconds:3,free:true,challenge:true,id:id)
        try s.recordQuiz(actor:"p2",question:1,picks:[0],seconds:3,free:true,shared:true)
        XCTAssertFalse(s.canUndoQuizRun(mark2,ids:[id]));XCTAssertThrowsError(try s.undoQuizRun(mark2,ids:[id]))
    }
    func testOneMovementStepPerQuestionPerTeam()throws {
        let s=try quizSession([QuizBankParser.flashcard(front:"cat",back:"猫",distractors:[]),QuizBankParser.flashcard(front:"dog",back:"狗",distractors:[])])
        _=try arrive(s)  // walking uses up part of the bar
        let team=s.engine.state.units["p1"]!.teamID
        XCTAssertEqual(s.engine.state.units["p2"]!.teamID,team)
        let step=MeadowMovementRules.distancePerStep,cap=s.movement(team:team).capacity
        let start=s.movement(team:team).remaining
        XCTAssertLessThan(start,cap-2*step)
        try s.recordQuiz(actor:"p1",question:0,picks:[0],seconds:2,free:true,shared:true)
        XCTAssertEqual(s.movement(team:team).remaining,start+step,accuracy:0.001)
        // A teammate right on the same question: coins and points, no second step.
        try s.recordQuiz(actor:"p2",question:0,picks:[0],seconds:2,free:true,shared:true)
        XCTAssertEqual(s.movement(team:team).remaining,start+step,accuracy:0.001)
        XCTAssertEqual(s.quizLog.last?.coins,10);XCTAssertEqual(s.quizLog.last?.score,1)
        // Another question: a step again.
        try s.recordQuiz(actor:"p2",question:1,picks:[0],seconds:2,free:true,shared:true)
        XCTAssertEqual(s.movement(team:team).remaining,start+2*step,accuracy:0.001)
        // The same flash card asked again later (a new round): right again pays its step again, once per team.
        let again=Date().addingTimeInterval(5)
        try s.recordQuiz(actor:"p1",question:0,picks:[0],seconds:2,at:again,free:true,practice:true,askedAt:again)
        XCTAssertEqual(s.movement(team:team).remaining,start+3*step,accuracy:0.001)
        try s.recordQuiz(actor:"p2",question:0,picks:[0],seconds:2,at:again.addingTimeInterval(1),free:true,practice:true,askedAt:again)
        XCTAssertEqual(s.movement(team:team).remaining,start+3*step,accuracy:0.001)
    }
    func testCorrectedFlashCardKeepsItsAnswers()throws {
        var card=QuizBankParser.flashcard(front:"nose",back:"突出部分",distractors:[]);card.difficulty=1;card.course="第一章"
        let s=try quizSession([])
        try s.useQuizCourse("第一章",questions:[card])
        try s.recordQuiz(actor:"p1",question:0,picks:[nil],seconds:3,free:true,shared:true,practice:true)
        try s.recordQuiz(actor:"p1",question:0,picks:[0],seconds:3,free:true,shared:true,practice:true)
        // The teacher fixes the meaning and the difficulty: same place in the bank, the answers stay.
        var fixed=card;fixed.items=[QuizItem(options:["鼻子"],answer:0)];fixed.difficulty=2
        try s.replaceQuizQuestion(at:0,with:fixed)
        XCTAssertEqual(s.quizBank,[fixed]);XCTAssertEqual(s.quizPool(.random),[0]);XCTAssertEqual(s.quizLog.count,2)
        let r=s.quizReport
        XCTAssertEqual(r.cards.first?.meaning,"鼻子");XCTAssertEqual(r.cards.first?.asked,2);XCTAssertEqual(r.cards.first?.difficulty,2)
        XCTAssertEqual(r.students.first{$0.id=="p1"}?.vocabulary.first?.status,.corrected)
        // Reopening the trip and switching to the course with the fixed card adds nothing.
        let restored=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded()))
        XCTAssertEqual(restored.quizBank,[fixed])
        try restored.useQuizCourse("第一章",questions:[fixed]);XCTAssertEqual(restored.quizBank.count,1)
        // Not another kind of question.
        XCTAssertThrowsError(try s.replaceQuizQuestion(at:0,with:QuizQuestion(prompt:"nose?",options:["a","b"],answer:0)))
        // A choice question's right option may change in place (same number of options).
        let choice=QuizQuestion(prompt:"2+2?",options:["3","4"],answer:0)
        try s.appendQuizBank([choice])
        var fixedChoice=choice;fixedChoice.answer=1
        XCTAssertNoThrow(try s.replaceQuizQuestion(at:1,with:fixedChoice))
        var more=choice;more.options=["3","4","5"]
        XCTAssertThrowsError(try s.replaceQuizQuestion(at:1,with:more))
    }
    func testCoursesKeepQuestionsApartAndAnswersStay()throws {
        func course(_ name:String,_ words:[(String,String)])->[QuizQuestion] {
            words.enumerated().map{i,w in var q=QuizBankParser.flashcard(front:w.0,back:w.1,distractors:[]);q.difficulty=1+i%3;q.course=name;return q}
        }
        let ch1=course("第一章",[("rabbit","兔子"),("hole","洞"),("key","钥匙")])
        let ch2=course("第二章",[("pool","池塘"),("tears","眼泪"),("fan","扇子")])
        let s=try quizSession([])
        XCTAssertNil(s.drawQuestion(.random,for:"p1"))
        try s.useQuizCourse("第一章",questions:ch1)
        XCTAssertEqual(s.quizPool(.random).count,3);XCTAssertEqual(s.quizBank.count,3)
        let a=try XCTUnwrap(s.drawQuestion(.difficulty(1),for:"p1"));XCTAssertEqual(s.quizBank[a].course,"第一章")
        try s.recordQuiz(actor:"p1",question:a,picks:[0],seconds:3,free:true,challenge:true)
        // Switch: chapter 2 is added, only its questions are dealt; chapter 1's answer stays recorded.
        try s.useQuizCourse("第二章",questions:ch2)
        XCTAssertEqual(s.quizBank.count,6);XCTAssertEqual(s.quizPool(.random),[3,4,5])
        XCTAssertEqual(s.quizBank[try XCTUnwrap(s.drawQuestion(.difficulty(1),for:"p1"))].course,"第二章")
        XCTAssertEqual(s.classFlashDeck,[3,4,5])
        XCTAssertEqual(s.quizLog.count,1);XCTAssertEqual(s.quizReport.students.first?.lines.first?.question.course,"第一章")
        // Back to chapter 1: nothing added twice; the answered question comes after the fresh ones.
        try s.useQuizCourse("第一章",questions:ch1)
        XCTAssertEqual(s.quizBank.count,6)
        for _ in 0..<10 {XCTAssertNotEqual(s.drawQuestion(.random,for:"p1"),a)}
        // No course chosen: everything in the trip.
        try s.useQuizCourse(nil,questions:[]);XCTAssertEqual(s.quizPool(.random).count,6)
    }
    func testReimportedCourseReplacesItsOldVersion()throws {
        var old=QuizBankParser.flashcard(front:"cat",back:"狗",distractors:[]);old.course="第一章"
        var fixed=QuizBankParser.flashcard(front:"cat",back:"猫",distractors:[]);fixed.course="第一章"
        let s=try quizSession([])
        try s.useQuizCourse("第一章",questions:[old]);XCTAssertEqual(s.quizPool(.random).count,1)
        try s.useQuizCourse("第一章",questions:[fixed])
        XCTAssertEqual(s.quizBank.count,2);XCTAssertEqual(s.quizPool(.random).count,1)
        XCTAssertEqual(s.quizBank[try XCTUnwrap(s.drawQuestion(.random,for:"p1"))].parts[0].options,["猫"])
    }
}
