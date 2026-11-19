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
        XCTAssertEqual(bank[0].tags,["水果"]);XCTAssertEqual(bank[0].reward,15);XCTAssertEqual(bank[0].timeLimit,60)
        XCTAssertEqual(bank[1].parts[0].options,["梨"]);XCTAssertNil(bank[1].difficulty)
        XCTAssertEqual(bank[2].prompt,"Tom {{1}} to school and {{2}} a cat.");XCTAssertEqual(bank[2].parts.count,2)
        XCTAssertEqual(Set(bank[2].parts[0].options),["went","goed","go"]);XCTAssertEqual(bank[2].parts[0].options[bank[2].parts[0].answer],"went")
        XCTAssertEqual(bank[2].parts[1].options,["saw"]);XCTAssertEqual(bank[2].timeLimit,90);XCTAssertEqual(bank[2].difficulty,2)
        XCTAssertEqual(bank[2].tags,["过去式","动词"])
        XCTAssertEqual(bank[3].passage,"Tom has a red ball.\nHe plays with it every day.");XCTAssertEqual(bank[3].parts.map(\.answer),[0,0])
        XCTAssertEqual(bank[3].difficulty,3);XCTAssertEqual(bank[3].reward,60);XCTAssertEqual(bank[3].timeLimit,120)
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
    func testRecordsPicksAndPaysByShareTimeAndDifficulty()throws {
        let hard=QuizQuestion(prompt:"R",options:[],answer:0,kind:.reading,difficulty:3,passage:"P",
                              items:[QuizItem(prompt:"a",options:["x","y"],answer:0),QuizItem(prompt:"b",options:["x","y"],answer:1)])
        let s=try quizSession([hard]);let node=try arrive(s)
        let before=s.engine.state.units["p1"]!
        // Half right, slowly: half the coins, no points, no drop.
        let a=try s.recordQuiz(actor:"p1",question:0,picks:[0,nil],texts:[nil,"不知道"],seconds:100)
        XCTAssertEqual(a.correct,[true,false]);XCTAssertEqual(a.coins,30);XCTAssertEqual(a.score,0);XCTAssertNil(a.drop);XCTAssertEqual(a.node,node.id)
        XCTAssertEqual(s.engine.state.units["p1"]!.coins,before.coins+30);XCTAssertEqual(s.quizLog[0].texts,[nil,"不知道"])
        // All right in under half the time: full coins + half, 3 points, and a drop from the hard table.
        let mate=s.engine.state.units["p2"]!
        let b=try s.recordQuiz(actor:"p2",question:0,picks:[0,1],seconds:20)
        XCTAssertEqual(b.coins,90);XCTAssertEqual(b.score,3);let drop=try XCTUnwrap(b.drop)
        XCTAssertEqual(s.engine.state.units["p2"]!.inventory[drop],(mate.inventory[drop] ?? 0)+(b.dropCount ?? 0))
        XCTAssertFalse(s.siteAvailable(actor:"p1"))
        // Undo takes the record (and the drop) back.
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
        XCTAssertEqual(p1.wrongWords[0].meaning,"苹果");XCTAssertEqual(p1.wrongWords[0].said,["答错"]);XCTAssertEqual(p1.wrongWords[2].said,["see"])
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
        XCTAssertNil(s.personalQuizQuestion(for:"p1"))
        try s.appendQuizBank(try QuizBankParser.parse(Data(mixed.utf8)))
        XCTAssertEqual(s.quizBank.count,4)
        let i=try XCTUnwrap(s.personalQuizQuestion(for:"p1",kind:.flashcard));XCTAssertEqual(s.quizBank[i].type,.flashcard)
        XCTAssertNotEqual(s.personalQuizQuestion(for:"p1",kind:.flashcard,skip:1),i)
        let nodes=s.engine.state.map.nodes,coins=s.engine.state.units["p1"]!.coins
        let q=s.quizBank[i]
        let a=try s.recordQuiz(actor:"p1",question:i,picks:[q.parts[0].answer],seconds:40,free:true)
        XCTAssertEqual(a.node,-1);XCTAssertEqual(s.engine.state.map.nodes,nodes);XCTAssertGreaterThan(s.engine.state.units["p1"]!.coins,coins)
        // A used shared question is not dealt again (to anyone), but can be asked again on purpose.
        XCTAssertNotEqual(s.personalQuizQuestion(for:"p2",kind:.flashcard),i);XCTAssertEqual(s.lastAskedQuestion(),i)
        try s.recordQuiz(actor:"p1",question:i,picks:[nil],seconds:3,free:true)
        XCTAssertEqual(s.quizLog.count,2)
        let restored=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded()))
        XCTAssertEqual(restored.quizBank.count,4);XCTAssertEqual(restored.quizLog,s.quizLog)
    }
    func testExclusiveFirstThenSharedManualRewardsAndPractice()throws {
        let text="""
        类型：闪卡
        对象：小明
        正面：elephant
        背面：大象

        类型：闪卡
        对象：2
        正面：tiger
        背面：老虎

        类型：闪卡
        对象：全班
        正面：cat
        背面：猫

        类型：闪卡
        正面：dog
        背面：狗
        难度：2
        """
        let bank=try QuizBankParser.parse(Data(text.utf8))
        XCTAssertEqual(bank.map(\.isShared),[false,false,true,true]);XCTAssertEqual(bank[0].audience,["小明"])
        var c=MeadowMapConfiguration.suggested(total:10,seed:31827);c.combat=0;c.boss=0;c.reward=0;c.empty=9;c.extraRoads=0
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c),studentNames:["小明","小红"],quizBank:bank)
        // Own question first (by name for p1, by number for p2), then shared ones.
        XCTAssertEqual(s.personalQuizQuestion(for:"p1"),0);XCTAssertEqual(s.personalQuizQuestion(for:"p2"),1)
        try s.recordQuiz(actor:"p1",question:0,picks:[bank[0].parts[0].answer],seconds:5,free:true)
        let next=try XCTUnwrap(s.personalQuizQuestion(for:"p1"));XCTAssertTrue(bank[next].isShared)
        XCTAssertNotEqual(s.personalQuizQuestion(for:"p1"),1)  // never someone else's own question
        // Shared question to the class: the teacher's coins, points for right, nothing from the drop table.
        let shared=try XCTUnwrap(s.sharedQuizQuestion());XCTAssertTrue(bank[shared].isShared)
        let before=s.engine.state.units["p2"]!
        let right=try s.recordQuiz(actor:"p2",question:shared,picks:[bank[shared].parts[0].answer],seconds:999,free:true,manualCoins:25,shared:true)
        XCTAssertEqual(right.coins,25);XCTAssertEqual(right.score,bank[shared].points);XCTAssertNil(right.drop);XCTAssertEqual(right.shared,true)
        XCTAssertEqual(s.engine.state.units["p2"]!.coins,before.coins+25)
        let wrong=try s.recordQuiz(actor:"p1",question:shared,picks:[nil],seconds:5,free:true,manualCoins:2,shared:true)
        XCTAssertEqual(wrong.coins,2);XCTAssertEqual(wrong.score,0)
        XCTAssertNotEqual(s.sharedQuizQuestion(),shared)
        // Flash-card practice: endless, recorded, no reward; unseen cards first, never the card just shown.
        let card=try XCTUnwrap(s.practiceCard(for:"p1"));XCTAssertNotEqual(card,1)
        let coins=s.engine.state.units["p1"]!.coins
        let p=try s.recordQuiz(actor:"p1",question:card,picks:[nil],seconds:2,free:true,practice:true)
        XCTAssertEqual(p.coins,0);XCTAssertEqual(s.engine.state.units["p1"]!.coins,coins)
        XCTAssertNotEqual(s.practiceCard(for:"p1",after:card),card)
    }
    func testPortionsDefaultToStudentNumbersAndTheTeacherReassigns()throws {
        let text="""
        类型：闪卡
        份：1
        正面：cat
        背面：猫

        类型：闪卡
        份：第2份
        正面：dog
        背面：狗

        类型：闪卡
        份：２
        正面：pig
        背面：猪

        类型：闪卡
        份：9
        正面：cow
        背面：牛

        类型：闪卡
        正面：sun
        背面：太阳
        """
        let bank=try QuizBankParser.parse(Data(text.utf8))
        XCTAssertEqual(bank.map(\.portion),["1","2","2","9",nil]);XCTAssertEqual(bank.map(\.isShared),[false,false,false,false,true])
        var c=MeadowMapConfiguration.suggested(total:10,seed:31827);c.combat=0;c.boss=0;c.reward=0;c.empty=9;c.extraRoads=0
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c),studentNames:["小明","小红"],quizBank:bank)
        XCTAssertEqual(s.quizPortions.map(\.name),["1","2","9"]);XCTAssertEqual(s.quizPortions.map(\.count),[1,2,1])
        // Default: portion n → student n; a portion with no such student belongs to nobody (not dealt as shared).
        XCTAssertEqual(s.portionOwner("1"),"p1");XCTAssertEqual(s.portionOwner("2"),"p2");XCTAssertNil(s.portionOwner("9"))
        XCTAssertEqual(s.personalQuizQuestion(for:"p1"),0);XCTAssertEqual(s.personalQuizQuestion(for:"p2"),1)
        // The teacher swaps: portion 2 to 小明, portion 1 to nobody; saved with the trip.
        try s.assignQuizPortion("2",to:"p1");try s.assignQuizPortion("1",to:nil)
        XCTAssertEqual(s.personalQuizQuestion(for:"p1"),1);XCTAssertEqual(s.personalQuizQuestion(for:"p2"),4)
        let restored=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded()))
        XCTAssertEqual(restored.portionOwner("2"),"p1");XCTAssertNil(restored.portionOwner("1"))
        XCTAssertThrowsError(try s.assignQuizPortion("2",to:"p99"))
        // The bundled sample bank parses and has portions.
    }
    func testBundledSampleBankHasPortionsAndSharedQuestions()throws {
        let url=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("../../../../ClassroomProbe/Resources/quiz-sample.txt").standardized
        let bank=try QuizBankParser.parse(Data(contentsOf:url))
        XCTAssertTrue(bank.contains{$0.portion != nil});XCTAssertTrue(bank.contains{$0.isShared})
        XCTAssertTrue(Set(bank.map(\.type)).isSuperset(of:[.choice,.flashcard,.fill,.reading]))
    }
    func testTimedChallengeDealsOwnQuestionsByChosenDifficulty()throws {
        let text="""
        类型：闪卡
        份：1
        正面：cat
        背面：猫

        类型：闪卡
        份：1
        难度：2
        正面：tiger
        背面：老虎

        类型：闪卡
        份：1
        难度：3
        正面：rhinoceros
        背面：犀牛

        类型：闪卡
        份：2
        难度：3
        正面：whale
        背面：鲸

        类型：闪卡
        难度：3
        正面：sun
        背面：太阳
        """
        let bank=try QuizBankParser.parse(Data(text.utf8))
        var c=MeadowMapConfiguration.suggested(total:10,seed:31827);c.combat=0;c.boss=0;c.reward=0;c.empty=9;c.extraRoads=0
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c),studentNames:["小明","小红"],quizBank:bank)
        XCTAssertEqual(s.challengeLeft(for:"p1"),[1,1,1]);XCTAssertEqual(s.challengeLeft(for:"p2"),[0,0,1])
        // Only the student's own portion, at the level they chose (unmarked = ★); shared ones never come up.
        XCTAssertEqual(s.challengeQuestion(for:"p1",difficulty:1),0);XCTAssertEqual(s.challengeQuestion(for:"p1",difficulty:3),2)
        XCTAssertNil(s.challengeQuestion(for:"p2",difficulty:1))
        let coins=s.engine.state.units["p1"]!.coins
        // A slow but right ★★★ answer: full difficulty reward, no speed bonus, not overtime.
        let a=try s.recordQuiz(actor:"p1",question:2,picks:[0],seconds:200,free:true,challenge:true)
        XCTAssertFalse(a.overtime);XCTAssertEqual(a.coins,QuizRewards.baseCoins[2]);XCTAssertEqual(a.score,3);XCTAssertNotNil(a.drop)
        XCTAssertEqual(s.engine.state.units["p1"]!.coins,coins+a.coins)
        XCTAssertNil(s.challengeQuestion(for:"p1",difficulty:3));XCTAssertEqual(s.challengeLeft(for:"p1"),[1,1,0])
        // Fast answers in a challenge get no bonus either.
        let b=try s.recordQuiz(actor:"p1",question:1,picks:[0],seconds:1,free:true,challenge:true)
        XCTAssertEqual(b.coins,QuizRewards.baseCoins[1])
        // A wrong flash card reads "答错" in the report.
        try s.recordQuiz(actor:"p1",question:0,picks:[nil],seconds:3,free:true,challenge:true)
        XCTAssertEqual(s.quizReport.students[0].wrongWords.first?.said,["答错"])
    }
    func testCoursesKeepQuestionsApartAndAnswersStay()throws {
        func course(_ name:String,_ words:[(String,String)])->[QuizQuestion] {
            words.enumerated().map{i,w in var q=QuizBankParser.flashcard(front:w.0,back:w.1,distractors:[]);q.portion="1";q.difficulty=1+i%3;q.course=name;return q}
        }
        let ch1=course("第一章",[("rabbit","兔子"),("hole","洞"),("key","钥匙")])
        let ch2=course("第二章",[("pool","池塘"),("tears","眼泪"),("fan","扇子")])
        let s=try quizSession([])
        XCTAssertNil(s.personalQuizQuestion(for:"p1"))
        try s.useQuizCourse("第一章",questions:ch1)
        XCTAssertEqual(s.challengeLeft(for:"p1"),[1,1,1]);XCTAssertEqual(s.quizBank.count,3)
        let a=try XCTUnwrap(s.challengeQuestion(for:"p1",difficulty:1));XCTAssertEqual(s.quizBank[a].course,"第一章")
        try s.recordQuiz(actor:"p1",question:a,picks:[0],seconds:3,free:true,challenge:true)
        // Switch: chapter 2 is added, only its questions are dealt; chapter 1's answer stays recorded.
        try s.useQuizCourse("第二章",questions:ch2)
        XCTAssertEqual(s.quizBank.count,6);XCTAssertEqual(s.challengeLeft(for:"p1"),[1,1,1])
        XCTAssertEqual(s.quizBank[try XCTUnwrap(s.challengeQuestion(for:"p1",difficulty:1))].course,"第二章")
        XCTAssertTrue((s.practiceCard(for:"p1")).map{s.quizBank[$0].course=="第二章"} ?? false)
        XCTAssertEqual(s.quizLog.count,1);XCTAssertEqual(s.quizReport.students.first?.lines.first?.question.course,"第一章")
        // Back to chapter 1: nothing added twice, the answered question is not dealt again.
        try s.useQuizCourse("第一章",questions:ch1)
        XCTAssertEqual(s.quizBank.count,6);XCTAssertEqual(s.challengeLeft(for:"p1"),[0,1,1])
        // No course chosen: everything in the trip.
        try s.useQuizCourse(nil,questions:[]);XCTAssertEqual(s.challengeLeft(for:"p1"),[1,2,2])
    }
    func testReimportedCourseReplacesItsOldVersion()throws {
        var old=QuizBankParser.flashcard(front:"cat",back:"狗",distractors:[]);old.portion="1";old.course="第一章"
        var fixed=QuizBankParser.flashcard(front:"cat",back:"猫",distractors:[]);fixed.portion="1";fixed.course="第一章"
        let s=try quizSession([])
        try s.useQuizCourse("第一章",questions:[old]);XCTAssertEqual(s.challengeLeft(for:"p1"),[1,0,0])
        try s.useQuizCourse("第一章",questions:[fixed])
        XCTAssertEqual(s.quizBank.count,2);XCTAssertEqual(s.challengeLeft(for:"p1"),[1,0,0])
        XCTAssertEqual(s.quizBank[try XCTUnwrap(s.challengeQuestion(for:"p1",difficulty:1))].parts[0].options,["猫"])
    }
}
