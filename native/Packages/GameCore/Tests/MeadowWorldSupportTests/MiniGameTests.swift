import XCTest
import ClassroomGameCore
@testable import MeadowWorldSupport

final class MiniGameTests: XCTestCase {
    private func round(_ level: Int, _ answers: [(String, Bool)]) -> MiniGameRound {
        MiniGameRound(level: level, answers: answers.map { MiniGameAnswer(player: $0.0, right: $0.1) })
    }

    func testDiceAreSeededAndInRange() {
        var a = MiniGameDice(seed: 7), b = MiniGameDice(seed: 7)
        let x = (0..<50).map { _ in a.roll(6) }, y = (0..<50).map { _ in b.roll(6) }
        XCTAssertEqual(x, y)
        XCTAssertTrue(x.allSatisfy { (1...6).contains($0) })
        XCTAssertEqual(Set(x).count, 6)
    }

    func testBossTakesDiceDamageByDifficultyAndCountersWhenFewAreRight() {
        var boss = BossRaid(monster: "caveTroll", students: 3), dice = MiniGameDice(seed: 1)
        XCTAssertEqual(boss.maxHP, 54)
        boss.resolve(round(3, [("p1", true), ("p2", true), ("p3", false)]), dice: &dice)
        XCTAssertEqual(boss.lastHits.map(\.sides), [10, 10])
        XCTAssertTrue(boss.lastHits.allSatisfy { (1...10).contains($0.damage) })
        XCTAssertEqual(boss.hp, 54 - boss.lastHits.reduce(0) { $0 + $1.damage })
        XCTAssertFalse(boss.lastCounter)
        XCTAssertEqual(boss.hearts, 5)
        // One right out of three: the boss hits back.
        boss.resolve(round(1, [("p1", true), ("p2", false), ("p3", false)]), dice: &dice)
        XCTAssertEqual(boss.lastHits.first?.sides, 4)
        XCTAssertTrue(boss.lastCounter)
        XCTAssertEqual(boss.hearts, 4)
        // Nobody answered: a heart too.
        boss.resolve(round(2, []), dice: &dice)
        XCTAssertTrue(boss.lastCounter)
        XCTAssertEqual(boss.hearts, 3)
        for _ in 0..<3 { boss.resolve(round(2, []), dice: &dice) }
        XCTAssertEqual(boss.outcome, .lost)
        let hp = boss.hp
        boss.resolve(round(3, [("p1", true)]), dice: &dice)
        XCTAssertEqual(boss.hp, hp, "nothing happens after the end")
    }

    func testBossFallsAndTheKillingBlowIsNotCountered() {
        var boss = BossRaid(monster: "slime", students: 1), dice = MiniGameDice(seed: 3)
        var guardCount = 0
        while boss.outcome == nil && guardCount < 100 {
            boss.resolve(round(3, [("p1", true)]), dice: &dice); guardCount += 1
        }
        XCTAssertEqual(boss.outcome, .won)
        XCTAssertEqual(boss.hp, 0)
        XCTAssertEqual(boss.hearts, 5)
    }

    func testCampMonsterMovesByShareOfRightAnswers() {
        XCTAssertEqual(CampDefense.move(round(1, [("a", true), ("b", true)])), -1)
        XCTAssertEqual(CampDefense.move(round(1, [("a", true), ("b", false)])), 0)
        XCTAssertEqual(CampDefense.move(round(1, [("a", true), ("b", false), ("c", false)])), 1)
        XCTAssertEqual(CampDefense.move(round(1, [])), 1)
        var camp = CampDefense()
        camp.resolve(round(1, [("a", true)]))
        XCTAssertEqual(camp.position, 0, "cannot go behind the start")
        for _ in 0..<5 { camp.resolve(round(1, [("a", false)])) }
        XCTAssertEqual(camp.position, 5)
        XCTAssertNil(camp.outcome)
        camp.resolve(round(1, []))
        XCTAssertEqual(camp.outcome, .lost)
        var safe = CampDefense()
        for _ in 0..<CampDefense.rounds { safe.resolve(round(2, [("a", true), ("b", false)])) }
        XCTAssertEqual(safe.outcome, .won)
        XCTAssertEqual(safe.wave, 2)
    }

    func testRaceTrackLayout() {
        for seed in UInt64(1)...40 {
            let cells = RaceTrack.track(seed: seed)
            XCTAssertEqual(cells.count, RaceTrack.length + 1)
            XCTAssertEqual(cells[0], .plain)
            XCTAssertEqual(cells[RaceTrack.length], .finish)
            XCTAssertEqual(cells.filter { $0 == .trap }.count, 2)
            XCTAssertEqual(cells.filter { $0 == .boost }.count, 2)
            XCTAssertEqual(cells.filter { $0 == .reward }.count, 3)
            XCTAssertEqual(cells.filter { $0 != .plain && $0 != .finish }.count, 7)
            for (i, c) in cells.enumerated() where c == .boost { XCTAssertEqual(cells[i + 3], .plain) }
        }
    }

    func testRaceTurnsRollsTrapsAndWinner() {
        let sides = [MiniGameSide(id: "red", name: "红队", members: ["p1", "p2"]), MiniGameSide(id: "blue", name: "蓝队", members: ["p3"])]
        var race = RaceTrack(sides: sides, seed: 5), dice = MiniGameDice(seed: 9)
        XCTAssertEqual(race.current?.id, "red")
        // Only the side's own members count.
        race.resolve(round(1, [("p3", true), ("p1", false)]), dice: &dice)
        XCTAssertEqual(race.events, [.missed(side: "red")])
        XCTAssertEqual(race.positions["red"], 0)
        XCTAssertEqual(race.current?.id, "blue")
        race.resolve(round(1, [("p3", true)]), dice: &dice)
        guard case .moved(side: "blue", let roll, _) = race.events.first else { return XCTFail("\(race.events)") }
        XCTAssertTrue((1...6).contains(roll))
        XCTAssertGreaterThan(race.positions["blue"] ?? 0, 0)
        // A trap: wrong next time → back 2.
        race.trapped.insert("red"); race.positions["red"] = 5
        race.resolve(round(3, [("p2", false)]), dice: &dice)
        XCTAssertEqual(race.events, [.trapFailed(side: "red", to: 3)])
        XCTAssertFalse(race.trapped.contains("red"))
        // Near the end a right answer wins.
        race.positions["blue"] = RaceTrack.length - 1
        race.resolve(round(1, [("p3", true)]), dice: &dice)
        XCTAssertEqual(race.winner, "blue")
        XCTAssertEqual(race.standings.first?.id, "blue")
    }

    func testMemoryMatchPairsJudgingAndTurns() {
        let sides = [MiniGameSide(id: "a", name: "A", members: ["p1"]), MiniGameSide(id: "b", name: "B", members: ["p2"])]
        var game = MemoryMatch(pairs: [("cat", "猫"), ("dog", "狗")], sides: sides, seed: 2)
        XCTAssertEqual(game.cards.count, 4)
        let cat = game.cards.indices.filter { game.cards[$0].pair == 0 }, dog = game.cards.indices.filter { game.cards[$0].pair == 1 }
        // Mismatch: turn back, next side.
        game.flip(cat[0]); game.flip(dog[0])
        XCTAssertEqual(game.phase, .mismatch)
        XCTAssertFalse(game.canFlip(cat[1]), "two cards up already")
        game.turnBack()
        XCTAssertEqual(game.current?.id, "b")
        // A pair said right: kept, same side again.
        game.flip(cat[0]); game.flip(cat[1])
        XCTAssertEqual(game.phase, .judging)
        game.judge(right: true)
        XCTAssertEqual(game.pairs(of: "b"), 1)
        XCTAssertEqual(game.current?.id, "b")
        XCTAssertFalse(game.canFlip(cat[0]))
        // A pair said wrong: back, next side.
        game.flip(dog[0]); game.flip(dog[1]); game.judge(right: false)
        XCTAssertEqual(game.current?.id, "a")
        XCTAssertFalse(game.finished)
        game.flip(dog[1]); game.flip(dog[0]); game.judge(right: true)
        XCTAssertTrue(game.finished)
        XCTAssertEqual(game.pairs(of: "a"), 1)
    }

    func testMemoryCandidatesAreShortEasyFlashCardsOnce() {
        let card = { (p: String, a: String, d: Int) in QuizQuestion(prompt: p, options: [], answer: 0, kind: .flashcard, difficulty: d, items: [QuizItem(options: [a], answer: 0)]) }
        let bank = [card("cat", "猫", 1), card("狗", "dog", 2), card("Cat", "猫咪", 1), card("kitty", "猫", 1), card("I like to read books.", "我喜欢读书。", 3),
                    QuizQuestion(prompt: "2+2", options: ["4", "5"], answer: 0), card("a very long phrase indeed", "很长", 2)]
        let pairs = MemoryMatch.candidates(bank, among: Array(bank.indices))
        XCTAssertEqual(pairs.map(\.english), ["cat", "dog"])
        XCTAssertEqual(pairs.map(\.meaning), ["猫", "狗"])
    }

    func testArenaWinnerStaysChallengerWinsOnHardQuestions() {
        var arena = ArenaKing(players: ["a", "b", "c"])!
        XCTAssertNil(ArenaKing(players: ["a"]))
        XCTAssertEqual([arena.champion, arena.challenger], ["a", "b"])
        // Both right on ★★: the champion keeps the stage.
        arena.resolve(round(2, [("a", true), ("b", true)]))
        XCTAssertEqual(arena.last, .defended)
        XCTAssertEqual([arena.champion, arena.challenger], ["a", "c"])
        XCTAssertEqual(arena.line, ["b"])
        XCTAssertEqual(arena.streak, 1)
        // Both right on ★★★: the challenger takes it.
        arena.resolve(round(3, [("a", true), ("c", true)]))
        XCTAssertEqual(arena.last, .dethroned)
        XCTAssertEqual([arena.champion, arena.challenger], ["c", "b"])
        XCTAssertEqual(arena.streak, 1)
        // Both wrong: nobody wins, the champion stays.
        arena.resolve(round(1, [("c", false)]))
        XCTAssertEqual(arena.last, .nobody)
        XCTAssertEqual(arena.champion, "c")
        XCTAssertEqual(arena.wins["c"], 1)
        // Three in a row → a spin.
        arena.resolve(round(1, [("c", true)]))
        XCTAssertFalse(arena.bonus)
        arena.resolve(round(1, [("c", true)]))
        XCTAssertEqual(arena.streak, 3)
        XCTAssertTrue(arena.bonus)
        XCTAssertEqual(arena.ranking(["a", "b", "c"]), ["c", "a", "b"])
    }

    func testSkippedStudentsAdjustBossAndCampAccuracyOnlyWhenRecorded() {
        let partial = round(2, [("p1", true)])
        let ignored = partial.applyingSkipped(["p2", "p3"], recordAsWrong: false)
        XCTAssertEqual(ignored.answers.count, 1)
        let recorded = partial.applyingSkipped(["p1", "p2", "p3"], recordAsWrong: true)
        XCTAssertEqual(recorded.answers.count, 3)
        XCTAssertEqual(recorded.rightCount, 1)

        var bossRecord = BossRaid(monster: "caveTroll", students: 3), dice1 = MiniGameDice(seed: 11)
        bossRecord.resolve(recorded, dice: &dice1)
        XCTAssertEqual(bossRecord.lastHits.count, 1)
        XCTAssertTrue(bossRecord.lastCounter)
        XCTAssertEqual(bossRecord.hearts, 4)

        var bossIgnore = BossRaid(monster: "caveTroll", students: 3), dice2 = MiniGameDice(seed: 11)
        bossIgnore.resolve(ignored, dice: &dice2)
        XCTAssertEqual(bossIgnore.lastHits.count, 1)
        XCTAssertFalse(bossIgnore.lastCounter)
        XCTAssertEqual(bossIgnore.hearts, 5)

        XCTAssertEqual(CampDefense.move(recorded), 1)
        XCTAssertEqual(CampDefense.move(ignored), -1)
    }

    func testRaceSingleStudentIgnoresOtherSidesWithoutPenalizingCurrentTurn() {
        let sides = [MiniGameSide(id: "red", name: "红队", members: ["p1", "p2"]), MiniGameSide(id: "blue", name: "蓝队", members: ["p3"])]
        var race = RaceTrack(sides: sides, seed: 5), dice = MiniGameDice(seed: 9)
        race.trapped.insert("red"); race.positions["red"] = 5
        // Single-student quiz for blue member p3 while red is up: ignored, red is neither trapped nor skipped.
        let nonTurn = MiniGameRound(level: 2, answers: [MiniGameAnswer(player: "p3", right: true)], singleStudent: true)
        XCTAssertFalse(race.resolve(nonTurn, dice: &dice))
        XCTAssertEqual(race.current?.id, "red")
        XCTAssertEqual(race.positions["red"], 5)
        XCTAssertTrue(race.trapped.contains("red"))
        // Single-student quiz for red member p2: resolves normally and escapes trap.
        let ownTurn = MiniGameRound(level: 2, answers: [MiniGameAnswer(player: "p2", right: true)], singleStudent: true)
        XCTAssertTrue(race.resolve(ownTurn, dice: &dice))
        XCTAssertFalse(race.trapped.contains("red"))
        XCTAssertEqual(race.current?.id, "blue")
    }

    func testArenaSingleStudentStagesDuelistsAndIgnoresSpectators() {
        var arena = ArenaKing(players: ["a", "b", "c"])!
        // Spectator c answering individually does not disturb champion a vs challenger b.
        XCTAssertFalse(arena.resolve(MiniGameRound(level: 2, answers: [MiniGameAnswer(player: "c", right: true)], singleStudent: true)))
        XCTAssertEqual([arena.champion, arena.challenger], ["a", "b"])
        XCTAssertEqual(arena.round, 0)
        // Champion a answers right alone: buffered until challenger b also answers.
        XCTAssertFalse(arena.resolve(MiniGameRound(level: 2, answers: [MiniGameAnswer(player: "a", right: true)], singleStudent: true)))
        XCTAssertEqual(arena.staged["a"], true)
        XCTAssertEqual(arena.round, 0)
        // Challenger b answers wrong: duel now resolves cleanly with a defending.
        XCTAssertTrue(arena.resolve(MiniGameRound(level: 2, answers: [MiniGameAnswer(player: "b", right: false)], singleStudent: true)))
        XCTAssertTrue(arena.staged.isEmpty)
        XCTAssertEqual(arena.last, .defended)
        XCTAssertEqual([arena.champion, arena.challenger], ["a", "c"])
        // Next duel: challenger c answers right first, then champion a answers wrong -> c dethrones a.
        XCTAssertFalse(arena.resolve(MiniGameRound(level: 1, answers: [MiniGameAnswer(player: "c", right: true)], singleStudent: true)))
        XCTAssertTrue(arena.resolve(MiniGameRound(level: 1, answers: [MiniGameAnswer(player: "a", right: false)], singleStudent: true)))
        XCTAssertEqual(arena.last, .dethroned)
        XCTAssertEqual(arena.champion, "c")
        // Classwide round overrides any stale staged single-student answer.
        XCTAssertFalse(arena.resolve(MiniGameRound(level: 1, answers: [MiniGameAnswer(player: "c", right: false)], singleStudent: true)))
        XCTAssertTrue(arena.resolve(round(2, [("c", true), ("b", false)])))
        XCTAssertTrue(arena.staged.isEmpty)
        XCTAssertEqual(arena.last, .defended)
    }

    func testSidesKeepsUnassignedStudentsInTeamMode() throws {
        var config = MeadowMapConfiguration.suggested(total: 4, seed: 317)
        config.combat = 0; config.boss = 0; config.reward = 3; config.empty = 0; config.extraRoads = 0
        let session = try MeadowCampaignSession.new(layout: try MeadowMapGenerator.generate(config))
        var state = session.engine.state
        state.teams = [GameTeam(id: "t1", name: "红队"), GameTeam(id: "t2", name: "蓝队")]
        var p1 = state.units["p1"]!; p1.name = "Alice"; p1.teamID = "t1"; p1.host = false
        var p2 = state.units["p2"]!; p2.name = "Bob"; p2.teamID = "t2"; p2.host = false
        var p3 = p1; p3.id = "p3"; p3.name = "Charlie"; p3.teamID = nil; p3.host = false
        var host = p1; host.id = "p7"; host.name = "Teacher"; host.teamID = "t1"; host.host = true
        state.units = ["p1": p1, "p2": p2, "p3": p3, "p7": host]
        let sides = MiniGameSide.sides(state)
        XCTAssertEqual(sides.map(\.id), ["t1", "t2", "p3"])
        XCTAssertEqual(sides[0].members, ["p1"])
        XCTAssertEqual(sides[1].members, ["p2"])
        XCTAssertEqual(sides[2].members, ["p3"])
    }
}
