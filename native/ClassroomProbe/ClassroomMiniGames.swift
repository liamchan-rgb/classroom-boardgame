import SwiftUI
import UIKit
import ClassroomGameCore
import MeadowWorldSupport
import MeadowBattleSupport

// MARK: - 课堂小游戏: boss, camp, race, memory, arena (about 10 minutes each)
//
// Built directly on the game's HD-2D battle visual language with 5 dedicated per-game HD-2D scenes:
// - Dedicated 16:9 HD-2D pixel-art scenes (`MiniGameSceneBoss`, `MiniGameSceneCamp`, `MiniGameSceneRace`,
//   `MiniGameSceneMemory`, `MiniGameSceneArena`) processed through CoreImage tilt-shift optical depth-of-field
// - Grounded interactive pixel props (`MiniGameBrazier`, `MiniGameSteppingStone`, `MiniGameArenaRing`,
//   `MiniGameFinishArch`, `MiniGameChestClosed/Open`, `MiniGameCrown`)
// - Full-body animated battle heroes (`PixelHeroAtlas.battle`) & monsters (`MeadowMonsterFrames`) with oblique sunlight shadows
// - Native 3D gem polyhedral dice (`MeadowBattleDiceView`), pixel VFX (`MeadowPixelFX`), battle vitals bars & frosted meadow glass

@MainActor final class MiniGameModel: ObservableObject {
    enum Kind: String, CaseIterable, Identifiable {
        case boss, camp, race, memory, arena
        var id: String { rawValue }
        var title: String {
            switch self { case .boss: "全班打Boss"; case .camp: "守护营地"; case .race: "答题赛跑"; case .memory: "翻牌寻宝"; case .arena: "擂台王" }
        }
        var icon: String {
            switch self { case .boss: "flame.fill"; case .camp: "tent.fill"; case .race: "flag.checkered"; case .memory: "square.grid.3x3.fill"; case .arena: "crown.fill" }
        }
        var rule: String {
            switch self {
            case .boss: "全班齐攻Boss：答对掷骰攻击（★d4 ★★d6 ★★★d10），答对不到一半Boss反击掉1颗心！"
            case .camp: "全对打退怪物1步，答对过半守住不动，不到一半怪物逼近1步；撑过12题营地安全！"
            case .race: "轮到的队答题，答对掷骰前进；踩礼物转转盘，踩闪电再冲3格，踩陷阱下回答错退2格。"
            case .memory: "轮流翻两张牌，英文和中文配对后大声读出来，读对拿走宝箱并再翻一次！"
            case .arena: "擂主与挑战者同答一题：挑战者独对或答对★★★即登台；连胜3场转转盘！"
            }
        }
    }
    struct Student: Identifiable {
        enum AttackStyle { case melee, bow, magic }
        let id: String; let name: String; let look: PixelHeroLook; let seat: Int; let style: AttackStyle
    }
    enum MemoryFXKind: Equatable { case flip, pairReady, claimed, mismatch }
    struct MemoryFXEvent: Equatable { let id: Int; let indices: [Int]; let kind: MemoryFXKind; let sideID: String? }

    static let memoryPairsKey = "classroom.memoryPairs"
    static var preferredMemoryPairs: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: memoryPairsKey)
            return stored > 0 ? min(12, max(2, stored)) : 8
        }
        set { UserDefaults.standard.set(min(12, max(2, newValue)), forKey: memoryPairsKey) }
    }

    let kind: Kind
    let students: [Student]
    let isTeamMode: Bool
    /// Side id → colour index (teams by their order, students by seat).
    let tints: [String: Int]
    /// Student id → colour index (matches team color when in team mode, else seat color).
    let studentTints: [String: Int]
    let memoryAvailablePairs: Int
    private let memoryPool: [(english: String, meaning: String)]
    private let memorySides: [MiniGameSide]
    @Published var boss: BossRaid?
    @Published var camp: CampDefense?
    var campWaveSpecies: [String] = ["slime", "wolf", "caveTroll"]
    @Published var race: RaceTrack?
    @Published var memory: MemoryMatch?
    @Published var hoveredMemoryCard: Int?
    @Published var memoryFX: MemoryFXEvent?
    @Published var arena: ArenaKing?
    /// Bumped each time a round is applied (the TV animates on it).
    @Published var beat = 0
    /// The line under the board: what just happened.
    @Published var banner: String?
    @Published var rewarded = false
    @Published private(set) var hasPendingRound = false
    private var dice: MiniGameDice
    private var memoryFXCounter = 0
    private var pendingID = 0
    private var pending: (id: Int, round: MiniGameRound, token: Int?)?

    private static let miniGameFXClips: [String] = [
        "melee_heavy_cleave_51", "melee_heavy_cleave_36", "melee_spear_sweep", "shield_bash_wave",
        "impacts_hit_spark_10", "impacts_hit_spark_55", "impacts_crit_hit_3", "impacts_blunt_hit_6",
        "projectiles_arrow_42", "holy_orb_proj", "fire_fireball_47", "wind_thunder_bolt",
        "lightning_bolt_strike", "skybreaker_lance", "fire_flame_pillar", "fire_fire_breath_5",
        "status_burning_7", "ice_breath_cone", "frost_nova_ring", "frost_fang_bite", "frost_shard_burst",
        "astral_eclipse_beam", "shadow_dark_explosion", "cap_spore_slam", "bomb_lob_proj",
        "bomb_firework_blast", "bomb_star_smoke", "nature_vine_whip", "thorn_root_sweep",
        "thorn_vine_erupt", "nature_boulder_smash", "nature_quake_rift", "iron_bastion_wall",
        "astral_dome_barrier", "wind_dash_step", "wind_spark_impact", "tribal_drum_chant",
        "holy_sunburst_16", "holy_sunburst_39", "holy_blessing_17", "oath_banner_plant",
        "warlord_roar_wave", "seraph_aegis_descend", "sonic_anthem_burst", "collectGold", "collectLegendary"
    ]

    init(kind: Kind, state: GameState, playerIDs: [String], seats: (String) -> Int, bank: [QuizQuestion], course: [Int], memoryPairs: Int? = nil) {
        self.kind = kind
        let seed = UInt64(Date().timeIntervalSince1970 * 1000)
        dice = MiniGameDice(seed: seed)
        let ordered = state.players.filter { !$0.host }.sorted { (seats($0.id), $0.id) < (seats($1.id), $1.id) }
        students = ordered.map { u in
            let look = PixelHeroLook.battle(unit: u, slot: playerIDs.firstIndex(of: u.id) ?? 0)
            let w = (u.equipment.weapon ?? "").lowercased()
            let style: Student.AttackStyle =
                (w.contains("bow") || w.contains("slingshot")) ? .bow
                : (w.contains("staff") || w.contains("wand") || w.contains("scepter") || w.contains("codex") || w.contains("harp") || w.contains("lute")) ? .magic
                : .melee
            return Student(id: u.id, name: u.shortName, look: look, seat: seats(u.id), style: style)
        }
        let activeTeams = state.teams.filter { team in ordered.contains { $0.teamID == team.id } }
        isTeamMode = activeTeams.count >= 2
        var sides = MiniGameSide.sides(state)
        if !isTeamMode { sides.sort { seats($0.id) < seats($1.id) } }
        var t: [String: Int] = [:]
        for (i, s) in sides.enumerated() { t[s.id] = state.teams.firstIndex { $0.id == s.id } ?? i }
        for s in ordered { t[s.id] = t[s.id] ?? max(0, seats(s.id) - 1) }
        tints = t
        var st: [String: Int] = [:]
        for u in ordered {
            if isTeamMode, let tid = u.teamID, let teamIdx = state.teams.firstIndex(where: { $0.id == tid }) {
                st[u.id] = teamIdx
            } else if isTeamMode, let soloIdx = t[u.id] {
                st[u.id] = soloIdx
            } else {
                st[u.id] = max(0, seats(u.id) - 1)
            }
        }
        studentTints = st
        let pool = MemoryMatch.candidates(bank, among: course)
        memoryPool = pool
        memoryAvailablePairs = min(12, pool.count)
        memorySides = sides
        // Prewarm full-body battle sprites & all mini-game pixel VFX in background for zero first-hit hitch.
        PixelHeroAtlas.prepare(battle: students.map(\.look))
        MeadowPixelFX.prewarm()
        DispatchQueue.global(qos: .utility).async {
            let clips = Self.miniGameFXClips.compactMap { MeadowPixelFX.clips[$0] }
            DispatchQueue.main.async {
                for c in clips { _ = MeadowPixelFX.images(c) }
            }
        }
        switch kind {
        case .boss:
            let bossPool = ["mushroomKing", "caveTroll", "goblinWarlord", "thornTreant", "ruinDragon", "frostPhoenix", "eclipseBehemoth", "crystalGolem", "frostAlphaWolf"]
            let chosen = dice.shuffle(bossPool)[0]
            MeadowMonsterFrames.retain([chosen])
            boss = BossRaid(monster: chosen, students: ordered.count)
        case .camp:
            let wave1 = dice.shuffle(["slime", "hopShroom", "acornBandit", "bubbleCrab"])[0]
            let wave2 = dice.shuffle(["wolf", "goblinArcher", "stingWasp", "brambleSprite", "goblinShaman", "stoneGuardian", "emberLizard", "shadowOwl", "runeKnight"])[0]
            let wave3 = dice.shuffle(["crystalGolem", "frostAlphaWolf", "mushroomKing", "caveTroll", "goblinWarlord", "thornTreant", "ruinDragon", "frostPhoenix", "eclipseBehemoth"])[0]
            campWaveSpecies = [wave1, wave2, wave3]
            MeadowMonsterFrames.retain(Set(campWaveSpecies))
            camp = CampDefense()
        case .race: race = RaceTrack(sides: sides, seed: seed)
        case .memory:
            let count = MemoryMatch.clampPairs(memoryPairs ?? Self.preferredMemoryPairs, available: pool.count)
            let pairs = dice.shuffle(pool).prefix(count)
            memory = MemoryMatch(pairs: Array(pairs), sides: sides, seed: seed)
        case .arena: arena = ArenaKing(players: ordered.map(\.id))
        }
    }

    func configureMemoryPairs(_ requested: Int) {
        guard kind == .memory, memoryAvailablePairs >= 2 else { return }
        let clamped = MemoryMatch.clampPairs(requested, available: memoryAvailablePairs)
        Self.preferredMemoryPairs = clamped
        let seed = UInt64(Date().timeIntervalSince1970 * 1000) ^ UInt64(clamped * 997)
        dice = MiniGameDice(seed: seed)
        let pairs = dice.shuffle(memoryPool).prefix(clamped)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
            memory = MemoryMatch(pairs: Array(pairs), sides: memorySides, seed: seed)
            hoveredMemoryCard = nil
            rewarded = false
            banner = "已切换为 \(clamped * 2) 张卡牌（\(clamped) 组词对），直接点击舞台卡牌翻开！"
            beat += 1
        }
    }
    func name(_ id: String) -> String { students.first { $0.id == id }?.name ?? race?.sides.first { $0.id == id }?.name ?? memory?.sides.first { $0.id == id }?.name ?? id }
    func student(_ id: String) -> Student? { students.first { $0.id == id } }
    func tint(_ id: String) -> Color { MiniGamePalette.side(tints[id] ?? 0) }
    func studentTint(_ id: String) -> Color { MiniGamePalette.side(studentTints[id] ?? 0) }
    static func monsterName(_ id: String) -> String {
        switch id {
        case "slime": "捣蛋史莱姆"
        case "wolf": "森林狼"
        case "goblinArcher": "哥布林弓手"
        case "stoneGuardian": "石像守卫"
        case "caveTroll": "洞穴巨魔"
        case "ruinDragon": "遗迹魔龙"
        case "hopShroom": "蹦跳菇灵"
        case "acornBandit": "橡果盗贼鼠"
        case "bubbleCrab": "溪畔泡泡蟹"
        case "stingWasp": "毒刺大黄蜂"
        case "brambleSprite": "荆棘藤蔓妖"
        case "goblinShaman": "哥布林萨满"
        case "emberLizard": "灰烬火蜥蜴"
        case "shadowOwl": "影翼夜枭"
        case "runeKnight": "符文铠甲兵"
        case "crystalGolem": "晶核魔像"
        case "frostAlphaWolf": "暗霜狼王"
        case "mushroomKing": "巨冠菇王"
        case "goblinWarlord": "哥布林战酋"
        case "thornTreant": "千年古树精"
        case "frostPhoenix": "冰晶霜凰"
        case "eclipseBehemoth": "蚀星古巨像"
        default: "怪物"
        }
    }

    var finished: Bool {
        switch kind {
        case .boss: boss?.outcome != nil
        case .camp: camp?.outcome != nil
        case .race: race?.winner != nil
        case .memory: memory?.finished == true
        case .arena: false
        }
    }
    /// The students who get the winners' bonus.
    var winners: [String] {
        switch kind {
        case .boss: return boss?.outcome == .won ? students.map(\.id) : []
        case .camp: return camp?.outcome == .won ? students.map(\.id) : []
        case .race: return race.flatMap { r in r.sides.first { $0.id == r.winner }?.members } ?? []
        case .memory:
            guard let m = memory, m.finished else { return [] }
            let top = m.sides.map { m.pairs(of: $0.id) }.max() ?? 0
            return m.sides.filter { m.pairs(of: $0.id) == top }.flatMap(\.members)
        case .arena:
            guard let a = arena else { return [] }
            let top = a.wins.values.max() ?? 0
            return top > 0 ? students.map(\.id).filter { a.wins[$0] == top } : []
        }
    }
    /// Who answers the next question (turn games), for the teacher's bar.
    var answering: String? {
        switch kind {
        case .race:
            race?.current.map { s in
                let isTeamSide = isTeamMode && (s.members.count > 1 || s.id != s.members.first)
                return isTeamSide ? "\(s.name)（\(s.members.map(name).joined(separator: "、"))）" : s.name
            }
        case .arena: arena.map { "\(name($0.champion)) 对 \(name($0.challenger))" }
        default: nil
        }
    }

    /// A question was answered: applied once the answer card is gone (or straight away when none shows).
    func queue(_ round: MiniGameRound, quiz token: Int?, fallback: Double = 3.2) {
        guard !finished, kind != .memory else { return }
        if let p = pending { pending = nil; hasPendingRound = false; apply(p.round) }
        if token == nil { apply(round); return }
        pendingID += 1
        let entryID = pendingID
        pending = (entryID, round, token)
        hasPendingRound = true
        DispatchQueue.main.asyncAfter(deadline: .now() + max(2.2, fallback)) { [weak self] in
            guard let self, let p = self.pending, p.id == entryID else { return }
            self.pending = nil; self.hasPendingRound = false
            self.apply(p.round)
        }
    }
    func flush(quiz token: Int?) {
        guard let p = pending, token == nil || token != p.token else { return }
        pending = nil; hasPendingRound = false
        apply(p.round)
    }
    func flushNow() { flush(quiz: nil) }
    private func apply(_ q: MiniGameRound) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            switch kind {
            case .boss:
                boss?.resolve(q, dice: &dice)
                if let b = boss {
                    let total = b.lastHits.reduce(0) { $0 + $1.damage }
                    banner = b.outcome == .won ? "Boss 倒下了！全班胜利！" : b.outcome == .lost ? "心都没了……下次再来！"
                        : [total > 0 ? "\(b.lastHits.count) 人攻击，造成 \(total) 点伤害" : nil, b.lastCounter ? "Boss 反击！失去 1 颗心" : nil].compactMap { $0 }.joined(separator: " · ")
                    if banner?.isEmpty != false { banner = "没有造成伤害" }
                }
            case .camp:
                camp?.resolve(q)
                if let c = camp {
                    banner = c.outcome == .won ? "撑过了 \(CampDefense.rounds) 题，营地安全！" : c.outcome == .lost ? "怪物冲进营地了……" : ["全对！把怪物打退一步", "守住了！怪物停在原地", "怪物逼近一步！"][c.lastMove + 1]
                }
            case .race:
                guard race?.resolve(q, dice: &dice) == true else { return }
                if let r = race { banner = raceLine(r) }
            case .arena:
                guard let before = arena else { return }
                guard arena?.resolve(q) == true else {
                    if q.singleStudent, let only = q.answers.first, let a = arena,
                       only.player == a.champion || only.player == a.challenger {
                        let other = only.player == a.champion ? a.challenger : a.champion
                        banner = "已记录 \(name(only.player)) \(only.right ? "答对" : "答错")，等待 \(name(other)) 作答…"
                    }
                    return
                }
                if let a = arena {
                    switch a.last {
                    case .dethroned: banner = "挑战成功！\(name(a.champion)) 成为新擂主"
                    case .defended: banner = "\(name(a.champion)) 守擂成功，连胜 \(a.streak) 场" + (a.bonus ? " · 转一次转盘！" : "")
                    case .nobody: banner = "都没答对，\(name(before.champion)) 继续守擂"
                    case nil: break
                    }
                }
            case .memory: return
            }
            beat += 1
        }
    }
    private func raceLine(_ r: RaceTrack) -> String {
        if let w = r.winner { return "\(name(w)) 冲过终点！" }
        return r.events.map { e -> String in
            switch e {
            case .missed(let s): "\(name(s)) 没答对，原地不动"
            case .moved(let s, let roll, _): "\(name(s)) 掷出 \(roll)"
            case .trapFailed(let s, _): "\(name(s)) 没逃出陷阱，后退 2 格"
            case .landed(_, .boost): "闪电格！再冲 3 格"
            case .landed(_, .trap): "掉进陷阱：下回合要答对才能前进"
            case .landed(let s, .reward): "\(name(s)) 踩到礼物格，转一次转盘！"
            case .landed: ""
            }
        }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // Memory: direct click on stage cards to flip & teacher judges the reading.
    private func emitMemoryFX(_ indices: [Int], kind: MemoryFXKind, sideID: String? = nil) {
        memoryFXCounter += 1
        memoryFX = MemoryFXEvent(id: memoryFXCounter, indices: indices, kind: kind, sideID: sideID)
    }
    func flip(_ i: Int) {
        guard var m = memory, m.canFlip(i) else { return }
        hoveredMemoryCard = nil
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { m.flip(i); memory = m }
        switch m.phase {
        case .judging:
            banner = "配对成功！\(m.current.map { name($0.id) } ?? "")大声读出来"
            emitMemoryFX(m.faceUp, kind: .pairReady, sideID: m.current?.id)
            beat += 1
        case .mismatch:
            banner = "没配上，记住位置哦"
            emitMemoryFX(m.faceUp, kind: .mismatch)
            beat += 1
            let up = m.faceUp
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                guard let self, self.memory?.faceUp == up else { return }
                self.turnBack()
            }
        case .picking:
            emitMemoryFX([i], kind: .flip)
            banner = nil
        }
    }
    func turnBack() {
        guard var m = memory, m.phase == .mismatch else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            m.turnBack(); memory = m
            banner = "轮到 \(m.current.map { name($0.id) } ?? "") 翻牌"
        }
    }
    func judge(right: Bool) {
        guard var m = memory, m.phase == .judging else { return }
        let matchedIndices = m.faceUp
        let winnerSideID = m.current?.id
        withAnimation(.spring(response: 0.48, dampingFraction: 0.75)) {
            let who = m.current.map { name($0.id) } ?? ""
            m.judge(right: right); memory = m; beat += 1
            if right { emitMemoryFX(matchedIndices, kind: .claimed, sideID: winnerSideID) }
            banner = m.finished ? "宝箱全部找到了！" : right ? "\(who) 拿走宝箱，再翻一次！" : "读错了，宝箱合上，轮到 \(m.current.map { name($0.id) } ?? "")"
        }
    }
}

enum MiniGamePalette {
    static let sides: [Color] = [
        Color(red: 0.90, green: 0.34, blue: 0.34),
        Color(red: 0.30, green: 0.56, blue: 0.94),
        Color(red: 0.28, green: 0.70, blue: 0.44),
        Color(red: 0.90, green: 0.68, blue: 0.20),
        Color(red: 0.66, green: 0.42, blue: 0.88),
        Color(red: 0.94, green: 0.54, blue: 0.24),
        Color(red: 0.26, green: 0.72, blue: 0.80)
    ]
    static func side(_ i: Int) -> Color { sides[((i % sides.count) + sides.count) % sides.count] }
    /// Matches `MeadowPreviewPalette.ink` (deep meadow teal ink on frosted glass).
    static let ink = Color(red: 0.09, green: 0.25, blue: 0.31)
    static let gold = Color(red: 0.94, green: 0.76, blue: 0.28)
    static let goldBright = Color(red: 1.0, green: 0.91, blue: 0.56)
    static let goldDeep = Color(red: 0.72, green: 0.50, blue: 0.12)
    /// Matches `MeadowBattleVitalsView` dark forest-ink backing plate & cream-gold bar rim.
    static let battlePlate = Color(red: 0.04, green: 0.07, blue: 0.05)
    static let battleRim = Color(red: 0.98, green: 0.93, blue: 0.77)
    static let battleGhost = Color(red: 1.0, green: 0.93, blue: 0.75)
    static let woodTop = Color(red: 0.36, green: 0.23, blue: 0.13)
    static let woodBottom = Color(red: 0.21, green: 0.13, blue: 0.07)
    static let parchmentTop = Color(red: 0.99, green: 0.97, blue: 0.91)
    static let parchmentBottom = Color(red: 0.94, green: 0.89, blue: 0.78)
    static var goldStroke: LinearGradient {
        LinearGradient(colors: [goldBright, gold, goldDeep], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: Coordinator

extension MeadowTeacherCoordinator {
    func startMiniGame(_ kind: MiniGameModel.Kind, memoryPairs: Int? = nil) {
        guard let c = campaign else { message = "先打开一个行程（学生名单）再玩小游戏。"; revision += 1; return }
        let students = c.engine.state.players.filter { !$0.host }
        if kind == .arena, students.count < 2 { message = "擂台王至少要两名学生。"; revision += 1; return }
        if kind == .memory, MemoryMatch.candidates(c.quizBank, among: c.courseIndices).count < 2 {
            message = "翻牌寻宝需要当前课程至少 2 张★/★★单词闪卡。"; revision += 1; return
        }
        if kind != .memory, c.courseIndices.isEmpty { message = "当前课程没有题，先在题库里选课或导入。"; revision += 1; return }
        if quizActive { abortQuiz() }
        // Freeze underlying map movement & battle AI while the mini-game covers the stage.
        if c.isMoving { try? c.setPaused(true); renderer?.classroomRefresh() }
        cancelEnemyWork()
        skippedPrompt = nil
        let model = MiniGameModel(kind: kind, state: c.engine.state, playerIDs: c.playerIDs, seats: { [weak self] in self?.seatNumber($0) ?? 0 },
                                  bank: c.quizBank, course: c.courseIndices, memoryPairs: memoryPairs)
        model.banner = kind.rule
        withAnimation(.easeOut(duration: 0.3)) { miniGame = model }
        message = "\(kind.title)开始：" + (kind == .memory ? "直接点击舞台上的卡牌即可翻开，顶部可自定义卡牌张数" : "点“出题”或按 ⇧Q 出全班题")
        revision += 1
    }
    func endMiniGame() {
        if var p = skippedPrompt, p.pendingMiniGame != nil {
            p.pendingMiniGame = nil
            skippedPrompt = p
        }
        withAnimation(.easeIn(duration: 0.25)) { miniGame = nil }
        message = "小游戏已结束"; revision += 1
    }
    /// The answers just sent to a question (class or one student) go to the game on screen.
    func feedMiniGame(question index: Int, answers: [MiniGameAnswer], singleStudent: Bool = false) {
        guard let g = miniGame, g.kind != .memory, !g.finished, let c = campaign, c.quizBank.indices.contains(index) else { return }
        if singleStudent, let only = answers.first {
            if g.kind == .race, let side = g.race?.current, !side.members.contains(only.player) {
                message = "答题赛跑当前轮到 \(g.answering ?? side.name)，\(g.name(only.player)) 的个人作答不计入本轮。"
                revision += 1
                return
            }
            if g.kind == .arena, let a = g.arena, only.player != a.champion && only.player != a.challenger {
                message = "擂台当前为 \(g.name(a.champion)) 对 \(g.name(a.challenger))，\(g.name(only.player)) 的个人作答不计入擂台。"
                revision += 1
                return
            }
        }
        let round = MiniGameRound(level: c.quizBank[index].level, answers: answers, singleStudent: singleStudent)
        g.queue(round, quiz: quiz?.token, fallback: (quiz?.hold ?? 1.8) + 1.4)
    }
    /// The question for the next turn: the class question (its panel picks who answered).
    func miniGameAsk() {
        guard let g = miniGame, g.kind != .memory, !g.finished else { return }
        if quiz?.mode == .classwide, quiz?.attempt != nil { quiz = nil }
        openClassQuiz()
    }
    func rewardMiniGameWinners(score: Int = 5) {
        guard let g = miniGame, !g.rewarded else { return }
        let ids = g.winners
        guard !ids.isEmpty else { message = "没有获胜的同学。"; revision += 1; return }
        let names = ids.map(g.name).joined(separator: "、")
        let each = ids.count > 1 ? " 每人" : ""
        if grantBookPlayers(ids, movement: 0, coins: 0, score: score) {
            g.rewarded = true
            g.banner = "获胜奖励：\(names)\(each) +\(score) 积分"
            g.beat += 1
        }
    }
}

/// Toolbar: choose a game, or end the one that is on.
struct MiniGameMenu: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    var prepare: () -> Void = {}
    var body: some View {
        Menu {
            ForEach(MiniGameModel.Kind.allCases) { kind in
                Button { prepare(); game.startMiniGame(kind) } label: { Label(kind.title, systemImage: kind.icon) }
            }
            if game.miniGame != nil {
                Divider()
                Button(role: .destructive) { game.endMiniGame() } label: { Label("结束小游戏", systemImage: "xmark.circle") }
            }
        } label: { Label(game.miniGame?.kind.title ?? "小游戏", systemImage: game.miniGame?.kind.icon ?? "gamecontroller") }
            .buttonStyle(ToolbarIconStyle(tint: game.miniGame != nil ? .orange : GameTheme.primary))
            .disabled(game.campaign == nil)
    }
}

// MARK: Teacher's bar (under the preview)

struct MiniGameBar: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    var body: some View {
        if let model = game.miniGame { MiniGameBarContent(game: game, model: model) }
    }
}

private struct MiniGameBarContent: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    @ObservedObject var model: MiniGameModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(model.kind.title, systemImage: model.kind.icon).font(.headline).foregroundStyle(.orange)
                status.font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    .transaction { $0.animation = nil }
                Spacer(minLength: 4)
                if let m = model.memory {
                    memoryScaleControl(m)
                    if !model.finished {
                        if m.phase == .judging {
                            Button { model.judge(right: true) } label: { Label("读对了", systemImage: "checkmark.circle.fill") }
                                .buttonStyle(GlassIconButtonStyle(tint: .green, prominent: true))
                            Button { model.judge(right: false) } label: { Label("读错了", systemImage: "xmark.circle.fill") }
                                .buttonStyle(GlassIconButtonStyle(tint: .red))
                        } else if m.phase == .mismatch {
                            Button { model.turnBack() } label: { Label("翻回去", systemImage: "arrow.uturn.backward") }
                                .buttonStyle(GlassIconButtonStyle(tint: .orange))
                        }
                    }
                }
                if model.finished {
                    Button { game.rewardMiniGameWinners() } label: { Label(model.rewarded ? "已发奖励" : "获胜者 +5 积分", systemImage: "star.fill") }
                        .buttonStyle(GlassIconButtonStyle(tint: .orange, prominent: !model.rewarded)).disabled(model.rewarded || model.winners.isEmpty)
                    Button { game.startMiniGame(model.kind) } label: { Label("再来一局", systemImage: "arrow.clockwise") }.buttonStyle(GlassIconButtonStyle())
                } else if model.kind == .arena {
                    Button { game.rewardMiniGameWinners() } label: { Label(model.rewarded ? "已发奖励" : "给领先者 +5 积分", systemImage: model.rewarded ? "star.fill" : "star") }
                        .buttonStyle(GlassIconButtonStyle(tint: .orange)).disabled(model.rewarded || model.winners.isEmpty)
                }
                if model.kind != .memory && !model.finished {
                    if game.skippedPrompt?.pendingMiniGame != nil {
                        Label("请先在右侧确认未选学生", systemImage: "exclamationmark.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.orange.opacity(0.14)))
                    } else if model.hasPendingRound || game.quiz?.attempt != nil {
                        Button { if !game.skipQuizReveal() { model.flushNow() } } label: { Label("立即推进", systemImage: "forward.fill") }
                            .buttonStyle(GlassIconButtonStyle(tint: .orange, prominent: true))
                    }
                    Button { game.miniGameAsk() } label: { Label("出题 ⇧Q", systemImage: "questionmark.bubble.fill") }
                        .buttonStyle(GlassIconButtonStyle(prominent: true)).disabled(game.quiz?.mode == .classwide && game.quiz?.attempt == nil)
                }
                Button { game.endMiniGame() } label: { Label("结束", systemImage: "xmark.circle") }.buttonStyle(GlassIconButtonStyle(tint: .red))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8).glassPanel(radius: 18, padding: 0)
    }

    /// Compact custom card-count control for Memory (presets 4–24 cards + ±2 custom stepper; zero bottom number strip!).
    @ViewBuilder private func memoryScaleControl(_ m: MemoryMatch) -> some View {
        let maxPairs = max(2, model.memoryAvailablePairs)
        let currentPairs = m.pairCount
        HStack(spacing: 4) {
            Button { model.configureMemoryPairs(currentPairs - 1) } label: {
                Image(systemName: "minus").font(.caption.weight(.black)).frame(width: 24, height: 24)
            }
            .buttonStyle(GlassIconButtonStyle())
            .disabled(currentPairs <= 2)
            .help("减少 2 张卡牌")

            Menu {
                Section("卡牌规模（当前课程最多 \(maxPairs * 2) 张）") {
                    ForEach(2...maxPairs, id: \.self) { pairs in
                        let dims = MemoryMatch.gridDimensions(cardCount: pairs * 2)
                        Button {
                            model.configureMemoryPairs(pairs)
                        } label: {
                            Label("\(pairs * 2) 张（\(pairs) 组 · \(dims.columns)×\(dims.rows)）", systemImage: pairs == currentPairs ? "checkmark.circle.fill" : "square.grid.2x2")
                        }
                    }
                }
            } label: {
                Label("\(currentPairs * 2) 张", systemImage: "square.grid.2x2.fill")
            }
            .buttonStyle(GlassIconButtonStyle(tint: GameTheme.primary))
            .menuStyle(.button)

            Button { model.configureMemoryPairs(currentPairs + 1) } label: {
                Image(systemName: "plus").font(.caption.weight(.black)).frame(width: 24, height: 24)
            }
            .buttonStyle(GlassIconButtonStyle())
            .disabled(currentPairs >= maxPairs)
            .help("增加 2 张卡牌")
        }
    }
    @ViewBuilder private var status: some View {
        switch model.kind {
        case .boss: if let b = model.boss { Text("Boss \(b.hp)/\(b.maxHP) · ❤️ \(b.hearts) · 第 \(b.round) 题") }
        case .camp: if let c = model.camp { Text("第 \(c.round)/\(CampDefense.rounds) 题 · 第 \(c.wave + 1) 波 · 怪物离营地 \(CampDefense.length - c.position) 步") }
        case .race:
            if let r = model.race {
                if let w = r.winner { Text("\(model.name(w)) 获胜") } else { Text("轮到 \(model.answering ?? "") 答题" + (r.current.map { r.trapped.contains($0.id) } == true ? " · 陷阱中" : "")) }
            }
        case .arena: Text("擂台：\(model.answering ?? "") · 在全班题里记下这两人的答案")
        case .memory:
            if let m = model.memory {
                Text(m.finished ? "全部找到" : "轮到 \(m.current.map { model.name($0.id) } ?? "") · " + (m.phase == .judging ? "读对了吗？" : m.phase == .mismatch ? "没配上" : "直接点击舞台卡牌翻开"))
            }
        }
    }
}

// MARK: Shared Memory Board Geometry (used by both MemoryStage and MiniGameTapLayer)

private struct MemoryBoardLayout {
    let count: Int
    let unit: CGFloat
    let columns: Int
    let rows: Int
    let cardSize: CGSize
    let gap: CGFloat
    let gridOrigin: CGPoint
    let gridSize: CGSize
    let sideX: CGFloat
    let sideWidth: CGFloat

    init(count: Int, unit: CGFloat) {
        self.count = count
        self.unit = unit
        let dims = MemoryMatch.gridDimensions(cardCount: count)
        let cols = dims.columns
        let r = dims.rows
        self.columns = cols
        self.rows = r
        // Fit crisply inside the oak tabletop between lantern/scroll (left) and standings panel (right).
        let sw: CGFloat = 250 * unit
        let splitGap: CGFloat = 22 * unit
        let maxGridW: CGFloat = 824 * unit
        let maxGridH: CGFloat = 486 * unit
        let g: CGFloat = (cols >= 6 ? 9 : r >= 4 ? 11 : 14) * unit
        let idealCW = (maxGridW - CGFloat(cols - 1) * g) / CGFloat(cols)
        let idealCH = (maxGridH - CGFloat(r - 1) * g) / CGFloat(r)
        // Keep pleasant card aspect ratio (~1.42...1.78) without giant bloated or paper-thin tiles.
        let cw = min(idealCW, idealCH * 1.72, 238 * unit)
        let ch = min(idealCH, cw * 0.80, 174 * unit)
        self.cardSize = CGSize(width: cw, height: ch)
        self.gap = g
        let gw = CGFloat(cols) * cw + CGFloat(cols - 1) * g
        let gh = CGFloat(r) * ch + CGFloat(r - 1) * g
        self.gridSize = CGSize(width: gw, height: gh)
        let totalW = gw + splitGap + sw
        // Slightly nudged right so the oak table's top-left brass lantern & bottom-left scroll/satchel breathe cleanly!
        let gx = (1280 * unit - totalW) / 2 + 26 * unit
        let gy = 358 * unit - gh / 2
        self.gridOrigin = CGPoint(x: gx, y: gy)
        self.sideWidth = sw
        self.sideX = gx + gw + splitGap + sw / 2
    }

    func cardCenter(_ index: Int) -> CGPoint {
        let col = index % columns
        let row = index / columns
        let x = gridOrigin.x + CGFloat(col) * (cardSize.width + gap) + cardSize.width / 2
        let y = gridOrigin.y + CGFloat(row) * (cardSize.height + gap) + cardSize.height / 2
        return CGPoint(x: x, y: y)
    }
}

/// Interactive tap layer on teacher preview: blocks map/book bleed-through & enables rock-solid direct card clicking & pointer hover in Memory.
struct MiniGameTapLayer: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    var body: some View {
        if let model = game.miniGame, game.quiz == nil, !game.laser.on {
            MiniGameTapContent(model: model)
        }
    }
}

private struct MiniGameTapContent: UIViewRepresentable {
    @ObservedObject var model: MiniGameModel

    func makeUIView(context: Context) -> MiniGameStageTouchView {
        let view = MiniGameStageTouchView()
        view.model = model
        return view
    }

    func updateUIView(_ view: MiniGameStageTouchView, context: Context) {
        view.model = model
    }
}

/// Native UIKit touch & hover catcher matching `MiniGameStage`'s exact `1280×720` centered coordinate space.
/// Uses direct `touchesBegan`/`touchesEnded` so Mac mouse, trackpad, and iPad touches always register cleanly
/// with zero SwiftUI clear-button or gesture-recognizer interference.
final class MiniGameStageTouchView: UIView {
    weak var model: MiniGameModel?
    private let hoverGesture = UIHoverGestureRecognizer()
    private var pressedCard: Int?
    private var pressedPoint: CGPoint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = true

        hoverGesture.addTarget(self, action: #selector(handleHover(_:)))
        addGestureRecognizer(hoverGesture)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Maps a point in this view's bounds into `MemoryBoardLayout` card index (with forgiving edge padding).
    func memoryCardIndex(at point: CGPoint) -> Int? {
        guard let m = model?.memory, bounds.width > 0, bounds.height > 0 else { return nil }
        let unit = min(bounds.height / 720, bounds.width / 1280)
        let stageW = 1280 * unit, stageH = 720 * unit
        let ox = (bounds.width - stageW) / 2
        let oy = (bounds.height - stageH) / 2
        let local = CGPoint(x: point.x - ox, y: point.y - oy)
        let layout = MemoryBoardLayout(count: m.cards.count, unit: unit)
        for i in m.cards.indices {
            let c = layout.cardCenter(i)
            let rect = CGRect(
                x: c.x - layout.cardSize.width / 2,
                y: c.y - layout.cardSize.height / 2,
                width: layout.cardSize.width,
                height: layout.cardSize.height
            ).insetBy(dx: -4 * unit, dy: -4 * unit)
            if rect.contains(local) { return i }
        }
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pt = touches.first?.location(in: self) else { return }
        pressedPoint = pt
        pressedCard = memoryCardIndex(at: pt)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { pressedCard = nil; pressedPoint = nil }
        guard let pt = touches.first?.location(in: self), let model, let m = model.memory else { return }
        // Ignore accidental long drags; tolerate small trackpad/finger jitter up to 24pt.
        if let start = pressedPoint, hypot(pt.x - start.x, pt.y - start.y) > 24 { return }
        if m.phase == .mismatch {
            model.turnBack()
            let idx = memoryCardIndex(at: pt) ?? pressedCard
            if let idx, model.memory?.canFlip(idx) == true { model.flip(idx) }
            return
        }
        let idx = memoryCardIndex(at: pt) ?? pressedCard
        guard let idx, m.canFlip(idx) else { return }
        model.flip(idx)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        pressedCard = nil
        pressedPoint = nil
    }

    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        guard let model, let m = model.memory else { return }
        switch gesture.state {
        case .began, .changed:
            let pt = gesture.location(in: self)
            if let idx = memoryCardIndex(at: pt), m.canFlip(idx) {
                if model.hoveredMemoryCard != idx { model.hoveredMemoryCard = idx }
            } else if model.hoveredMemoryCard != nil {
                model.hoveredMemoryCard = nil
            }
        default:
            if model.hoveredMemoryCard != nil { model.hoveredMemoryCard = nil }
        }
    }
}

// MARK: - HD-2D Shared Battle-Engine Stage Components

/// Loads & caches each mini-game's dedicated 16:9 HD-2D scene with CoreImage tilt-shift optical depth-of-field
/// (soft out-of-focus distant forest/horizon & near foreground bokeh, razor-sharp playable ground plane — matching
/// `MeadowBattlePlateProcessor` without reusing `MeadowCampWide*`!).
private enum HD2DSceneCache {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])
    private static let cache = NSCache<NSString, UIImage>()

    static func scene(for kind: MiniGameModel.Kind) -> UIImage? {
        let name: String = switch kind {
        case .boss: "MiniGameSceneBoss"
        case .camp: "MiniGameSceneCamp"
        case .race: "MiniGameSceneRace"
        case .memory: "MiniGameSceneMemory"
        case .arena: "MiniGameSceneArena"
        }
        let key = "hd2d:\(name)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let source = UIImage(named: name) else { return nil }
        if kind == .memory {
            cache.setObject(source, forKey: key)
            return source
        }
        guard let cg = source.cgImage,
              let processed = applyTiltShift(cg, scale: source.scale, kind: kind) else {
            cache.setObject(source, forKey: key)
            return source
        }
        cache.setObject(processed, forKey: key)
        return processed
    }

    /// Subtle HD-2D diorama tilt-shift: keeps playable ground band 100% sharp while gently softening distant treeline & very bottom edge.
    private static func applyTiltShift(_ cg: CGImage, scale: CGFloat, kind: MiniGameModel.Kind) -> UIImage? {
        let extent = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let input = CIImage(cgImage: cg)
        let blurRadius: CGFloat = kind == .race ? 1.8 : 2.6
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return nil }
        blurFilter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        blurFilter.setValue(blurRadius, forKey: kCIInputRadiusKey)
        guard let blurred = blurFilter.outputImage?.cropped(to: extent),
              let mask = focusMask(width: cg.width, height: cg.height, kind: kind),
              let blend = CIFilter(name: "CIBlendWithMask") else { return nil }
        blend.setValue(input, forKey: kCIInputImageKey)
        blend.setValue(blurred, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: kCIInputMaskImageKey)
        guard let out = blend.outputImage?.cropped(to: extent),
              let result = context.createCGImage(out, from: extent) else { return nil }
        return UIImage(cgImage: result, scale: scale, orientation: .up)
    }

    /// White (255) = razor-sharp playable ground plane; black (0) = soft HD-2D depth-of-field bokeh.
    private static func focusMask(width: Int, height: Int, kind: MiniGameModel.Kind) -> CIImage? {
        guard width > 0, height > 0 else { return nil }
        // Focus band authored from top (0.0) to bottom (1.0)
        let (farEnd, sharpStart, sharpEnd, nearStart): (CGFloat, CGFloat, CGFloat, CGFloat) =
            kind == .race ? (0.24, 0.36, 0.87, 0.97) : (0.36, 0.50, 0.86, 0.97)
        var pixels = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let y = CGFloat(row) / CGFloat(max(1, height - 1))
            let focus: CGFloat
            if y < farEnd || y > nearStart {
                focus = 0
            } else if y < sharpStart {
                let t = (y - farEnd) / max(0.001, sharpStart - farEnd)
                focus = t * t * (3 - 2 * t)
            } else if y <= sharpEnd {
                focus = 1
            } else {
                let t = (y - sharpEnd) / max(0.001, nearStart - sharpEnd)
                focus = 1 - t * t * (3 - 2 * t)
            }
            let value = UInt8((min(1, max(0, focus)) * 255).rounded())
            let start = row * width
            pixels.replaceSubrange(start..<(start + width), with: repeatElement(value, count: width))
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let maskCG = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { return nil }
        return CIImage(cgImage: maskCG)
    }
}

/// Full-bleed soft blurred ambient fill behind the pixel-locked 16:9 stage (matching `MeadowBattleLandscapeView.cameraBackdrop`)
/// so ultrawide Mac teacher windows and narrower quiz-dock panes have zero black bars AND zero vertical coordinate drift!
private struct HD2DAmbientBackdrop: View {
    let kind: MiniGameModel.Kind
    let size: CGSize
    var body: some View {
        ZStack {
            Color(red: 0.09, green: 0.12, blue: 0.09)
            if let img = HD2DSceneCache.scene(for: kind) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .blur(radius: 18)
                    .scaleEffect(1.06)
                    .overlay(Color.black.opacity(0.24))
                    .clipped()
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .allowsHitTesting(false)
    }
}

/// Pixel-locked 16:9 (`1280*unit × 720*unit`) dedicated HD-2D scene with CoreImage tilt-shift bokeh & subtle atmospheric polish.
/// Shares exact coordinate space with `MiniGameWorldLayer` so actors, stones, braziers, arches & lanterns never shift across aspect ratios!
private struct HD2DMeadowBackdrop: View {
    let kind: MiniGameModel.Kind
    let size: CGSize
    var featherEdges = false
    var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.15, blue: 0.11)
            if let img = HD2DSceneCache.scene(for: kind) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
            // Subtle cohesive warm/twilight atmospheric polish
            if kind == .boss {
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.07, blue: 0.22).opacity(0.14), .clear, Color(red: 0.03, green: 0.04, blue: 0.09).opacity(0.22)],
                    startPoint: .top, endPoint: .bottom
                )
            } else if kind != .memory {
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.92, blue: 0.70).opacity(0.08), .clear, Color(red: 0.04, green: 0.07, blue: 0.04).opacity(0.12)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .mask {
            if featherEdges {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .white, location: 0.025),
                        .init(color: .white, location: 0.975),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            } else {
                Rectangle()
            }
        }
    }
}

/// Scene-tailored animated HD-2D atmosphere: volumetric light shafts, brazier fire tongues, fluttering flags,
/// wind-blown petals/leaves, warm lantern candle flicker & dappled tabletop canopy light, and restrained optical vignette.
private struct HD2DAtmosphereOverlay: View {
    let kind: MiniGameModel.Kind
    let size: CGSize

    var body: some View {
        let unit = min(size.height / 720, size.width / 1280)
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 24)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                Canvas { g, canvasSize in
                    // 1. Soft diagonal volumetric sun/moon shafts
                    let rayColor: Color = kind == .boss
                        ? Color(red: 0.72, green: 0.78, blue: 1.0)
                        : Color(red: 1.0, green: 0.91, blue: 0.68)
                    let rayAlpha: Double = kind == .boss ? 0.055 : (kind == .memory ? 0.045 : 0.085)
                    for i in 0..<4 {
                        let phase = sin(t * 0.28 + Double(i) * 1.7)
                        let x0 = canvasSize.width * (0.04 + Double(i) * 0.24) + phase * 26 * unit
                        let w = canvasSize.width * (0.10 + Double(i % 2) * 0.05)
                        var path = Path()
                        path.move(to: CGPoint(x: x0, y: -20))
                        path.addLine(to: CGPoint(x: x0 + w, y: -20))
                        path.addLine(to: CGPoint(x: x0 + w + canvasSize.height * 0.36, y: canvasSize.height + 20))
                        path.addLine(to: CGPoint(x: x0 + canvasSize.height * 0.36, y: canvasSize.height + 20))
                        path.closeSubpath()
                        let alpha = rayAlpha * (0.72 + 0.28 * sin(t * 0.52 + Double(i) * 1.1))
                        g.fill(path, with: .linearGradient(
                            Gradient(colors: [rayColor.opacity(alpha), rayColor.opacity(alpha * 0.45), .clear]),
                            startPoint: CGPoint(x: x0, y: 0),
                            endPoint: CGPoint(x: x0 + canvasSize.height * 0.36, y: canvasSize.height)
                        ))
                    }

                    // 2. Scene-specific living world motion
                    switch kind {
                    case .boss:
                        // Pulsing amethyst crystal gleam on sanctum arch keystone (x:1004, y:118)
                        let pulse = 0.65 + 0.35 * sin(t * 2.4)
                        let cPt = CGPoint(x: 1004 * unit, y: 118 * unit)
                        let cRad = 96 * unit * (0.9 + 0.14 * pulse)
                        g.fill(Path(ellipseIn: CGRect(x: cPt.x - cRad, y: cPt.y - cRad, width: cRad * 2, height: cRad * 2)),
                               with: .radialGradient(Gradient(colors: [Color(red: 0.80, green: 0.48, blue: 1.0).opacity(0.32 * pulse), .clear]), center: cPt, startRadius: 4 * unit, endRadius: cRad))
                        // Animated live flames & rising sparks on both mossy stone braziers
                        let braziers: [CGPoint] = [CGPoint(x: 708 * unit, y: 446 * unit), CGPoint(x: 1172 * unit, y: 462 * unit)]
                        for (bi, bp) in braziers.enumerated() {
                            let flick = 0.78 + 0.22 * sin(t * 9.5 + Double(bi) * 2.1) * cos(t * 5.3 + Double(bi))
                            let haloR = 72 * unit * flick
                            g.fill(Path(ellipseIn: CGRect(x: bp.x - haloR, y: bp.y - haloR, width: haloR * 2, height: haloR * 2)),
                                   with: .radialGradient(Gradient(colors: [Color(red: 1.0, green: 0.72, blue: 0.24).opacity(0.34 * flick), Color.orange.opacity(0.10 * flick), .clear]), center: bp, startRadius: 4 * unit, endRadius: haloR))
                            for f in 0..<7 {
                                let seed = Double(bi * 11 + f) * 4.7
                                let age = (t * (1.5 + Double(f % 3) * 0.45) + seed).truncatingRemainder(dividingBy: 1.0)
                                let fx = bp.x + CGFloat(sin(age * 9.0 + seed) * 10.0) * unit + CGFloat(f - 3) * 2.4 * unit
                                let fy = bp.y - CGFloat(age * 52.0) * unit
                                let fr = CGFloat(max(1.5, (1.0 - age) * 7.5)) * unit
                                let fCol = age < 0.35 ? Color(red: 1.0, green: 0.94, blue: 0.62) : age < 0.72 ? Color(red: 1.0, green: 0.56, blue: 0.16) : Color(red: 0.90, green: 0.24, blue: 0.10)
                                g.fill(Path(ellipseIn: CGRect(x: fx - fr, y: fy - fr * 1.25, width: fr * 2, height: fr * 2.5)), with: .color(fCol.opacity((1.0 - age) * 0.85)))
                            }
                        }
                        // Drifting low twilight mist wisps across ruins flagstones
                        for m in 0..<5 {
                            let mx = ((t * (18 + Double(m) * 4) + Double(m) * 290).truncatingRemainder(dividingBy: 1580) - 150) * Double(unit)
                            let my = (530.0 + Double(m % 3) * 48.0 + sin(t * 0.7 + Double(m)) * 12.0) * Double(unit)
                            let mw = (210.0 + Double(m % 2) * 80.0) * Double(unit)
                            let mh = 42.0 * Double(unit)
                            g.fill(Path(ellipseIn: CGRect(x: mx - mw / 2, y: my - mh / 2, width: mw, height: mh)),
                                   with: .color(Color(red: 0.56, green: 0.66, blue: 0.94).opacity(0.065)))
                        }

                    case .memory:
                        // Warm breathing candlelight glow right over the top-left brass lantern (x:126, y:120)
                        let flick = 0.84 + 0.16 * sin(t * 7.2) * cos(t * 4.1)
                        let lPt = CGPoint(x: 126 * unit, y: 120 * unit)
                        let lRad = 155 * unit * flick
                        g.fill(Path(ellipseIn: CGRect(x: lPt.x - lRad, y: lPt.y - lRad, width: lRad * 2, height: lRad * 2)),
                               with: .radialGradient(Gradient(colors: [Color(red: 1.0, green: 0.82, blue: 0.36).opacity(0.34 * flick), Color(red: 1.0, green: 0.58, blue: 0.18).opacity(0.10 * flick), .clear]), center: lPt, startRadius: 6 * unit, endRadius: lRad))
                        // Soft dappled canopy light spots swaying gently on the oak table edges
                        for i in 0..<7 {
                            let sx = (220.0 + Double(i) * 145.0 + sin(t * 0.65 + Double(i) * 1.4) * 18.0) * Double(unit)
                            let sy = (118.0 + Double(i % 2) * 36.0 + cos(t * 0.55 + Double(i)) * 10.0) * Double(unit)
                            let sr = (28.0 + Double(i % 3) * 12.0) * Double(unit)
                            let a = 0.055 + 0.03 * sin(t * 1.1 + Double(i) * 1.9)
                            g.fill(Path(ellipseIn: CGRect(x: sx - sr, y: sy - sr * 0.6, width: sr * 2, height: sr * 1.2)), with: .color(Color(red: 1.0, green: 0.92, blue: 0.62).opacity(a)))
                        }

                    case .camp, .race, .arena:
                        // Wind-blown sunlit leaves, flower petals & dandelion fluff drifting gently rightward across the meadow!
                        let petalCount = kind == .race ? 24 : 18
                        for i in 0..<petalCount {
                            let seed = Double(i) * 17.3 + 2.7
                            let vx = 42.0 + Double(i % 4) * 16.0
                            let x = ((t * vx + seed * 93.0).truncatingRemainder(dividingBy: 1380.0) - 50.0) * Double(unit)
                            let baseY = (70.0 + (sin(seed * 1.9) * 0.5 + 0.5) * 560.0)
                            let y = (baseY + sin(t * (1.8 + Double(i % 3) * 0.5) + seed) * 26.0 + (t * 10.0).truncatingRemainder(dividingBy: 90.0) * 0.2) * Double(unit)
                            let rot = Angle(radians: t * (2.4 + Double(i % 3)) + seed)
                            let isPetal = i % 3 != 0
                            let color: Color = {
                                if kind == .race && i % 4 == 0 { return [Color(red: 1.0, green: 0.45, blue: 0.52), Color(red: 1.0, green: 0.84, blue: 0.28), Color(red: 0.42, green: 0.84, blue: 1.0)][i % 3] }
                                return isPetal
                                    ? (i % 2 == 0 ? Color(red: 1.0, green: 0.96, blue: 0.82) : Color(red: 1.0, green: 0.84, blue: 0.88))
                                    : Color(red: 0.54, green: 0.86, blue: 0.36)
                            }()
                            let w = CGFloat(isPetal ? 5.5 : 7.5) * unit
                            let h = CGFloat(isPetal ? 3.5 : 4.0) * unit
                            var ctxCopy = g
                            ctxCopy.translateBy(x: x, y: y)
                            ctxCopy.rotate(by: rot)
                            ctxCopy.fill(Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h)), with: .color(color.opacity(0.76)))
                        }
                    }

                    // 3. Floating golden sunlight dust motes (or glowing twilight fire embers in Boss)
                    let moteCount = kind == .boss ? 26 : (kind == .memory ? 16 : 18)
                    for i in 0..<moteCount {
                        let seed = Double(i) * 13.7 + 1.3
                        let speed = kind == .boss ? 20.0 : 9.5
                        let cycle = (t * (speed + Double(i % 5) * 3.0) + seed * 37).truncatingRemainder(dividingBy: Double(canvasSize.height + 60))
                        let y = Double(canvasSize.height + 30) - cycle
                        let baseX = (sin(seed * 2.13) * 0.5 + 0.5) * Double(canvasSize.width)
                        let x = baseX + sin(t * 0.85 + seed) * 26.0 * Double(unit)
                        let r = CGFloat(2.0 + Double(i % 3) * 1.1) * unit
                        let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 2.4 + seed * 1.9))
                        let edgeFade = min(1.0, min(y / Double(60 * unit), (Double(canvasSize.height) - y) / Double(60 * unit)))
                        let a = max(0, twinkle * edgeFade * (kind == .boss ? 0.82 : 0.58))
                        let color: Color = kind == .boss
                            ? (i % 3 == 0 ? Color(red: 1.0, green: 0.82, blue: 0.36) : Color(red: 1.0, green: 0.48, blue: 0.18))
                            : Color(red: 1.0, green: 0.95, blue: 0.72)
                        let glowRect = CGRect(x: x - Double(r * 2.4), y: y - Double(r * 2.4), width: Double(r * 4.8), height: Double(r * 4.8))
                        g.fill(Path(ellipseIn: glowRect), with: .color(color.opacity(a * 0.30)))
                        let coreRect = CGRect(x: x - Double(r), y: y - Double(r), width: Double(r * 2), height: Double(r * 2))
                        g.fill(Path(ellipseIn: coreRect), with: .color(color.opacity(a)))
                    }
                }
            }

            // 4. Restrained HD-2D diorama vignette (matches MeadowPostProcess)
            RadialGradient(
                colors: [.clear, .clear, Color(red: 0.03, green: 0.05, blue: 0.04).opacity(kind == .boss ? 0.38 : (kind == .memory ? 0.24 : 0.20))],
                center: .center,
                startRadius: min(size.width, size.height) * 0.38,
                endRadius: max(size.width, size.height) * 0.76
            )
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .allowsHitTesting(false)
    }
}

/// Real game scenery prop (`NodeBossSanctum`, `CampTent`, `WatchTower`, `MiniGameBrazier`, `OakA`, `Pines`, etc.)
/// with optional HD-2D depth-of-field blur & directional oblique cast shadow (upper-left sun → down-right shadow).
private struct HD2DProp: View {
    let name: String
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    var mirrored = false
    var depthBlur: CGFloat = 0
    var shadow = true
    var tint: Color = .white

    var body: some View {
        ZStack(alignment: .bottom) {
            if shadow {
                Ellipse()
                    .fill(RadialGradient(colors: [Color(red: 0.02, green: 0.04, blue: 0.02).opacity(0.46), Color(red: 0.02, green: 0.04, blue: 0.02).opacity(0.18), .clear], center: .center, startRadius: 2, endRadius: (width ?? height ?? 120) * 0.5))
                    .frame(width: (width ?? height ?? 120) * 0.88, height: (width ?? height ?? 120) * 0.16)
                    .offset(x: (width ?? height ?? 120) * 0.10, y: 4)
            }
            Image(name)
                .resizable()
                .interpolation(depthBlur > 0.2 ? .medium : .none)
                .scaledToFit()
                .frame(width: width, height: height)
                .colorMultiply(tint)
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                .blur(radius: depthBlur)
        }
    }
}

/// Directional oblique silhouette shadow matching `MeadowBattleGroundingView` (upper-left sun casting down-right).
private struct ObliqueShadowView: View {
    let image: UIImage?
    let width: CGFloat
    let height: CGFloat
    var mirrored = false
    var body: some View {
        ZStack(alignment: .bottom) {
            // Soft planted-foot contact occlusion
            Ellipse()
                .fill(RadialGradient(colors: [Color(red: 0.02, green: 0.035, blue: 0.018).opacity(0.62), .clear], center: .center, startRadius: 1, endRadius: width * 0.34))
                .frame(width: width * 0.64, height: height * 0.11)
                .offset(y: height * 0.03)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color(red: 0.03, green: 0.045, blue: 0.025).opacity(0.32))
                    .scaledToFit()
                    .frame(width: width, height: height)
                    .scaleEffect(x: mirrored ? -1 : 1, y: -0.22, anchor: .bottom)
                    .transformEffect(CGAffineTransform(a: 1, b: 0, c: 0.42, d: 1, tx: -height * 0.24, ty: 0))
                    .blur(radius: 2.2)
                    .offset(x: width * 0.14, y: height * 0.03)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Full-body animated pixel battle hero using the game's real `PixelHeroAtlas.battle(look)` sprites
/// (live breathing `ready` stance, real weapon `attack`, `victory`, `hurt` animations + weapon FX + oblique shadow!).
private struct HD2DBattleHero: View {
    enum Action: Equatable { case ready, attack, victory, hurt }
    let student: MiniGameModel.Student
    let height: CGFloat
    var mirrored = false
    var action: Action = .ready
    var actionAt: Date? = nil
    var ringColor: Color? = nil

    @State private var sprite: PixelHeroAtlas.BattleSprite?
    @State private var fallback: UIImage?

    var body: some View {
        let boxW = height * (256.0 / 320.0)
        TimelineView(.animation(minimumInterval: 1.0 / 15)) { ctx in
            let frame = currentFrame(at: ctx.date)
            ZStack(alignment: .bottom) {
                if let ringColor {
                    // Subtle battle target/team ground ring matching `MeadowTargetMarkerView`
                    Ellipse()
                        .fill(ringColor.opacity(0.18))
                        .overlay(Ellipse().stroke(ringColor.opacity(0.75), lineWidth: max(1.5, height * 0.014)))
                        .frame(width: boxW * 0.66, height: boxW * 0.20)
                        .offset(y: -height * 0.09)
                }
                if let frame {
                    ObliqueShadowView(image: frame.canvas, width: boxW * 0.92, height: boxW * 0.92, mirrored: mirrored)
                        .offset(y: -height * 0.11)
                    Image(uiImage: frame.tall)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: boxW, height: height)
                        .overlay(alignment: .topLeading) {
                            if !frame.fx.isEmpty {
                                let phase = frame.fx[Int(ctx.date.timeIntervalSinceReferenceDate * 8) % frame.fx.count]
                                let k = boxW / 256.0
                                Image(uiImage: phase.image)
                                    .resizable()
                                    .interpolation(.none)
                                    .frame(width: phase.rect.width * k, height: phase.rect.height * k)
                                    .offset(x: phase.rect.minX * k, y: phase.rect.minY * k)
                            }
                        }
                        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                } else if let fallback {
                    ObliqueShadowView(image: fallback, width: boxW * 0.65, height: height * 0.68, mirrored: mirrored)
                        .offset(y: -height * 0.10)
                    Image(uiImage: fallback)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(height: height * 0.68)
                        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                        .offset(y: -height * 0.10)
                } else {
                    MiniGameFace(student: student, size: height * 0.34, tint: ringColor ?? .white)
                        .offset(y: -height * 0.25)
                }
            }
            .frame(width: boxW, height: height)
        }
        .onAppear(perform: load)
        .onChange(of: student.id) { _, _ in load() }
    }

    private func load() {
        let look = student.look
        if PixelHeroAtlas.isBattleReady(look) {
            sprite = PixelHeroAtlas.battle(look)
        } else {
            if let f = PixelHeroAtlas.fullBody(look, ready: { fallback = PixelHeroAtlas.fullBody(look) }) { fallback = f }
            PixelHeroAtlas.prepare(battle: [look]) {
                sprite = PixelHeroAtlas.battle(look)
            }
        }
    }

    private func currentFrame(at date: Date) -> PixelHeroAtlas.BattleSprite.Frame? {
        guard let sprite else { return nil }
        func pick(_ name: String, _ idx: Int) -> PixelHeroAtlas.BattleSprite.Frame? {
            guard let list = sprite.frames[name], !list.isEmpty else { return nil }
            return list[min(list.count - 1, max(0, idx))]
        }
        if let at = actionAt, action != .ready {
            let age = date.timeIntervalSince(at)
            if age >= 0 {
                switch action {
                case .attack where age < 0.85:
                    if let list = sprite.frames[sprite.attack], !list.isEmpty {
                        return list[min(list.count - 1, Int(age / 0.85 * Double(list.count)))]
                    }
                case .victory where age < 1.3:
                    if let list = sprite.frames["victory"], !list.isEmpty {
                        return list[min(list.count - 1, Int(age / 0.9 * Double(list.count)))]
                    }
                case .hurt where age < 0.55:
                    if let list = sprite.frames["hurt"], !list.isEmpty {
                        return list[min(list.count - 1, Int(age / 0.55 * Double(list.count)))]
                    }
                default: break
                }
            }
        }
        let t = date.timeIntervalSinceReferenceDate
        let readyCount = max(1, sprite.frames["ready"]?.count ?? 2)
        return pick("ready", Int(t * 2.2) % readyCount)
    }
}

/// Real animated battle monster (`MeadowMonsterFrames` + `MonsterVisualSpec`) supporting full idle, attack, cast,
/// hurt, and 40-frame death dissolution animations with oblique sunlight shadow + crisp hit flash.
private struct HD2DMonster: View {
    let id: String
    let height: CGFloat
    var mirrored = false
    var hurtAt: Date? = nil
    var attackAt: Date? = nil
    var castAt: Date? = nil
    var deadAt: Date? = nil
    var dead = false

    var body: some View {
        let spec = MonsterVisualSpec.find(id) ?? MonsterVisualSpec(id: id)
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
            let now = context.date
            let t = now.timeIntervalSinceReferenceDate
            let hurtAge = hurtAt.map { now.timeIntervalSince($0) }
            let attackAge = attackAt.map { now.timeIntervalSince($0) }
            let castAge = castAt.map { now.timeIntervalSince($0) }
            let flashOn = !dead && (hurtAge.map { $0 >= 0 && $0 < 0.14 } ?? false)
            let isDeath = dead
            let deathAge = deadAt.map { now.timeIntervalSince($0) } ?? MonsterVisualSpec.deathDuration
            let image: UIImage? = {
                if isDeath {
                    let idx = MonsterVisualSpec.deathFrame(deathAge)
                    return MeadowMonsterFrames.image(id, index: idx, death: true)
                }
                let idx = spec.frame(time: t, attackAge: attackAge, castAge: castAge, hurtAge: hurtAge)
                return MeadowMonsterFrames.image(id, index: idx)
            }()
            // Death frames are 512×320 vs motion 384×256: keep consistent ground scale during dissolution.
            let drawH = isDeath ? height * (320.0 / 256.0) : height
            let lungeX: CGFloat = {
                guard !dead, let a = attackAge, a >= 0 && a < 0.65 else { return 0 }
                let k = sin((a / 0.65) * .pi)
                return (mirrored ? 1 : -1) * CGFloat(k) * height * 0.14
            }()
            ZStack(alignment: .bottom) {
                if let image {
                    if !isDeath || deathAge < MonsterVisualSpec.deathDuration * 0.7 {
                        ObliqueShadowView(image: image, width: height * 1.45, height: height, mirrored: mirrored)
                            .opacity(isDeath ? max(0, 1 - deathAge / (MonsterVisualSpec.deathDuration * 0.7)) : 1)
                            .offset(x: lungeX, y: -height * 0.04)
                    }
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(height: drawH)
                        .overlay {
                            if flashOn {
                                Image(uiImage: image)
                                    .resizable()
                                    .renderingMode(.template)
                                    .interpolation(.none)
                                    .scaledToFit()
                                    .frame(height: drawH)
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                        .offset(x: lungeX)
                } else {
                    Image(systemName: "pawprint.fill").font(.system(size: height * 0.45)).foregroundStyle(.brown)
                }
            }
        }
    }
}

/// Anchored, dual-layer (`back` + `front`) `MeadowPixelFX` player matching `MeadowPixelFXPlayer`'s exact `(ox, oy)`
/// registration and horizontal mirroring (`direction: -1`) so every mini-game VFX lands at pinpoint coordinates.
private struct HD2DPixelFXEffect: View {
    enum Layer { case back, front, both }
    let clipID: String
    let playedAt: Date?
    /// Exact anchor point in stage coordinates (e.g., actor foot or exact impact point).
    let anchor: CGPoint
    /// Scale multiplier in stage points per FX pixel (standard battle parity ≈ 1.85...2.4 * unit).
    let pixelScale: CGFloat
    /// +1 faces right, -1 mirrors horizontally to face left (for monster casts!).
    var direction: CGFloat = 1
    var delay: Double = 0
    var fps: Double = 20
    var layer: Layer = .both

    var body: some View {
        if let playedAt, let clip = MeadowPixelFX.clips[clipID] {
            let all = MeadowPixelFX.images(clip)
            if !all.isEmpty {
                let duration = Double(clip.n) / max(1, fps)
                let w = CGFloat(clip.w) * pixelScale
                let h = CGFloat(clip.h) * pixelScale
                let dir: CGFloat = direction < 0 ? -1 : 1
                let originX = dir > 0
                    ? anchor.x - CGFloat(clip.ox) * pixelScale
                    : anchor.x - CGFloat(clip.w - clip.ox) * pixelScale
                let originY = anchor.y - CGFloat(clip.oy) * pixelScale
                TimelineView(.animation(minimumInterval: 1.0 / 24)) { ctx in
                    let age = ctx.date.timeIntervalSince(playedAt) - delay
                    if age >= 0 && age < duration {
                        let f = min(clip.n - 1, Int(age * fps))
                        let backIdx: Int? = (clip.back && (layer == .back || layer == .both)) ? f : nil
                        let frontIdx: Int? = (clip.front && (layer == .front || layer == .both)) ? ((clip.back ? clip.n : 0) + f) : nil
                        ZStack {
                            if let bi = backIdx, bi < all.count {
                                Image(uiImage: UIImage(cgImage: all[bi]))
                                    .resizable().interpolation(.none)
                                    .frame(width: w, height: h)
                                    .scaleEffect(x: dir, y: 1)
                            }
                            if let fi = frontIdx, fi < all.count {
                                Image(uiImage: UIImage(cgImage: all[fi]))
                                    .resizable().interpolation(.none)
                                    .frame(width: w, height: h)
                                    .scaleEffect(x: dir, y: 1)
                            }
                        }
                        .frame(width: w, height: h)
                        .position(x: originX + w / 2, y: originY + h / 2)
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }
}

/// Real flying `MeadowPixelFX` projectile travelling from exact `from` chest/muzzle point to exact `to` hit point
/// with optional parabolic arc and automatic tangent rotation (handles both hero → monster and monster → hero!).
private struct HD2DPixelFXProjectile: View {
    let clipID: String
    let playedAt: Date?
    let from: CGPoint
    let to: CGPoint
    let pixelScale: CGFloat
    var delay: Double = 0
    var flight: Double = 0.28
    var arc: CGFloat = 18
    var fps: Double = 20

    var body: some View {
        if let playedAt, let clip = MeadowPixelFX.clips[clipID] {
            let all = MeadowPixelFX.images(clip)
            if !all.isEmpty {
                let w = CGFloat(clip.w) * pixelScale
                let h = CGFloat(clip.h) * pixelScale
                let dir: CGFloat = to.x >= from.x ? 1 : -1
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                    let age = ctx.date.timeIntervalSince(playedAt) - delay
                    if age >= 0 && age <= flight {
                        let k = CGFloat(age / max(0.01, flight))
                        let x = from.x + (to.x - from.x) * k
                        let y = from.y + (to.y - from.y) * k - sin(k * .pi) * arc
                        let dx = to.x - from.x
                        let dy = (to.y - from.y) - cos(k * .pi) * .pi * arc
                        let tilt = atan2(dy, abs(dx)) * (dir > 0 ? 1 : -1) * 0.45
                        let f = Int(age * fps) % max(1, clip.n)
                        let idx = (clip.back && clip.front ? clip.n : 0) + f
                        if idx < all.count {
                            // Align head `(ox, oy)` right onto `(x, y)`
                            let offX = dir > 0 ? (w / 2 - CGFloat(clip.ox) * pixelScale) : (CGFloat(clip.ox) * pixelScale - w / 2)
                            let offY = h / 2 - CGFloat(clip.oy) * pixelScale
                            Image(uiImage: UIImage(cgImage: all[idx]))
                                .resizable().interpolation(.none)
                                .frame(width: w, height: h)
                                .scaleEffect(x: dir, y: 1)
                                .rotationEffect(.radians(Double(tilt)))
                                .position(x: x + offX, y: y + offY)
                        }
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }
}

/// Real native 3D gem polyhedral dice strip (`MeadowBattleDiceView`) in the battle stage's frosted `dicePlate`.
private struct HD2DDiceStrip: View {
    let dice: [BattleDie]
    let startedAt: Date?
    let unit: CGFloat

    var body: some View {
        if let startedAt, !dice.isEmpty {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                let age = ctx.date.timeIntervalSince(startedAt)
                if age >= 0 && age < 3.0 {
                    let count = min(6, dice.count)
                    let shown = Array(dice.prefix(count))
                    let rawW = MeadowBattleDiceView.width(count: shown.count)
                    let scale = 0.88 * unit
                    let fadeOut = age > 2.45 ? max(0, 1 - (age - 2.45) / 0.45) : 1.0
                    let fadeIn = min(1, age / 0.16)
                    ZStack {
                        RoundedRectangle(cornerRadius: 18 * unit, style: .continuous)
                            .fill(Color.white.opacity(0.24))
                            .overlay(RoundedRectangle(cornerRadius: 18 * unit, style: .continuous).stroke(Color.white.opacity(0.62), lineWidth: 1.5 * unit))
                            .shadow(color: .black.opacity(0.24), radius: 10 * unit, y: 4 * unit)
                        BattleDiceRepresentable(dice: shown, age: age)
                            .frame(width: rawW, height: 84)
                            .scaleEffect(scale)
                    }
                    .frame(width: rawW * scale + 28 * unit, height: 82 * unit)
                    .opacity(fadeIn * fadeOut)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

private struct BattleDiceRepresentable: UIViewRepresentable {
    let dice: [BattleDie]
    let age: Double
    func makeUIView(context: Context) -> MeadowBattleDiceView { MeadowBattleDiceView() }
    func updateUIView(_ view: MeadowBattleDiceView, context: Context) {
        view.dice = dice
        view.time = age
        view.visibleAge = age
        view.locked = age >= 0.48
        view.resolvedAge = age >= 0.48 ? age - 0.48 : nil
        view.confirmationAge = age >= 0.48 ? age - 0.48 : nil
        view.exitAge = age >= 2.4 ? age - 2.4 : nil
        view.setNeedsDisplay()
    }
}

/// Authentic `MeadowBattleVitalsView`-styled health bar (dark forest-ink plate, chunky green/amber/red fill,
/// cream-gold rim `battleRim`, top gloss sheen, and pale cream delayed ghost-damage drain!).
private struct BattleVitalsBar: View {
    let name: String
    let hp: Int
    let maxHP: Int
    let width: CGFloat
    let unit: CGFloat
    @State private var ghostRatio: CGFloat = 1.0

    var body: some View {
        let ratio = CGFloat(max(0, min(maxHP, hp))) / CGFloat(max(1, maxHP))
        let barColor: Color = ratio > 0.5
            ? Color(red: 0.30, green: 0.85, blue: 0.36)
            : ratio > 0.25 ? Color(red: 0.98, green: 0.70, blue: 0.20) : Color(red: 0.95, green: 0.26, blue: 0.22)
        VStack(spacing: 4 * unit) {
            HStack(spacing: 6 * unit) {
                Text(name)
                    .font(.system(size: 19 * unit, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 4 * unit)
                HStack(alignment: .firstTextBaseline, spacing: 2 * unit) {
                    Text("\(max(0, hp))")
                        .font(.system(size: 21 * unit, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("/\(maxHP)")
                        .font(.system(size: 15 * unit, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.78))
                }
            }
            .padding(.horizontal, 10 * unit)
            .padding(.vertical, 4 * unit)
            .background(RoundedRectangle(cornerRadius: 7 * unit, style: .continuous).fill(MiniGamePalette.battlePlate.opacity(0.84)))

            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6 * unit, style: .continuous).fill(MiniGamePalette.battlePlate.opacity(0.90))
                    RoundedRectangle(cornerRadius: 5 * unit, style: .continuous)
                        .fill(MiniGamePalette.battleGhost.opacity(0.95))
                        .frame(width: g.size.width * max(ratio, ghostRatio))
                    RoundedRectangle(cornerRadius: 5 * unit, style: .continuous)
                        .fill(barColor)
                        .frame(width: g.size.width * ratio)
                        .overlay(alignment: .top) {
                            Rectangle().fill(Color.white.opacity(0.24)).frame(height: g.size.height * 0.38)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 5 * unit, style: .continuous))
                }
            }
            .frame(height: 17 * unit)
            .overlay(RoundedRectangle(cornerRadius: 6 * unit, style: .continuous).stroke(MiniGamePalette.battleRim.opacity(0.92), lineWidth: 1.8 * unit))
        }
        .frame(width: width)
        .onAppear { ghostRatio = ratio }
        .onChange(of: hp) { oldVal, newVal in
            let prev = CGFloat(max(0, min(maxHP, oldVal))) / CGFloat(max(1, maxHP))
            let next = CGFloat(max(0, min(maxHP, newVal))) / CGFloat(max(1, maxHP))
            if next < prev {
                ghostRatio = max(ghostRatio, prev)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    withAnimation(.easeIn(duration: 0.5)) { ghostRatio = next }
                }
            } else {
                withAnimation(.easeOut(duration: 0.35)) { ghostRatio = next }
            }
        }
    }
}

/// Floating battle damage numbers using `MeadowBattleNumber` spring-overshoot + rise + sway + late fade math.
private struct BattleFloatingNumbers: View {
    let hits: [BossRaid.Hit]
    let startedAt: Date?
    let model: MiniGameModel
    let unit: CGFloat

    var body: some View {
        if let startedAt, !hits.isEmpty {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                let age = ctx.date.timeIntervalSince(startedAt)
                if age >= 0 && age < MeadowBattleNumber.life + 0.45 {
                    ZStack {
                        ForEach(Array(hits.enumerated()), id: \.offset) { idx, h in
                            let localAge = age - Double(idx) * 0.08
                            if localAge >= 0 && localAge < MeadowBattleNumber.life {
                                let sc = MeadowBattleNumber.scale(age: localAge, kind: .damage, rank: h.sides >= 10 ? 2 : h.sides >= 6 ? 1 : 0)
                                let rise = MeadowBattleNumber.rise(age: localAge, kind: .damage) * unit * 1.15
                                let sway = MeadowBattleNumber.sway(age: localAge, seed: idx + 3) * unit
                                let alpha = MeadowBattleNumber.alpha(age: localAge)
                                let spreadX = (CGFloat(idx) - CGFloat(hits.count - 1) / 2) * 76 * unit
                                VStack(spacing: 1 * unit) {
                                    Text("-\(h.damage)")
                                        .font(.system(size: CGFloat(MeadowBattleNumber.fontSize(kind: .damage, rank: h.sides >= 10 ? 2 : h.sides >= 6 ? 1 : 0)) * 0.86 * unit, weight: .black, design: .rounded))
                                        .foregroundStyle(h.sides >= 10 ? MiniGamePalette.goldBright : .white)
                                        .shadow(color: Color(red: 0.10, green: 0.06, blue: 0.03), radius: 2 * unit, y: 2 * unit)
                                        .shadow(color: Color(red: 0.65, green: 0.08, blue: 0.06).opacity(0.85), radius: 4 * unit)
                                    Text(model.name(h.player))
                                        .font(.system(size: 13 * unit, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7 * unit).padding(.vertical, 2 * unit)
                                        .background(Capsule().fill(MiniGamePalette.battlePlate.opacity(0.82)))
                                }
                                .scaleEffect(CGFloat(sc))
                                .opacity(alpha)
                                .offset(x: spreadX + CGFloat(sway), y: -CGFloat(rise))
                            }
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// A student's pixel face (baked in the background; initials meanwhile).
struct MiniGameFace: View {
    let student: MiniGameModel.Student?
    let size: CGFloat
    var tint: Color = .white
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            if let image {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFill()
                    .frame(width: size * 0.88, height: size * 0.88).clipShape(Circle())
            } else {
                Text(String(student?.name.prefix(1) ?? "?"))
                    .font(.system(size: size * 0.44, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.white, lineWidth: max(2, size * 0.065)))
        .shadow(color: .black.opacity(0.28), radius: size * 0.08, y: size * 0.05)
        .onAppear(perform: load)
    }
    private func load() {
        guard let look = student?.look else { return }
        if let hit = PixelHeroAtlas.portrait(look, ready: { image = PixelHeroAtlas.portrait(look) }) { image = hit }
    }
}

/// Glossy crimson RPG heart with cream-gold battle rim.
private struct RPGHeartView: View {
    let filled: Bool
    let bursting: Bool
    let unit: CGFloat
    var body: some View {
        ZStack {
            if filled {
                Image(systemName: "heart.fill")
                    .font(.system(size: 28 * unit, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.36, blue: 0.40), Color(red: 0.82, green: 0.12, blue: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        Image(systemName: "heart")
                            .font(.system(size: 28 * unit, weight: .semibold))
                            .foregroundStyle(MiniGamePalette.battleRim.opacity(0.88))
                    )
                    .shadow(color: Color.red.opacity(0.45), radius: 4 * unit, y: 2 * unit)
            } else {
                Image(systemName: "heart.slash.fill")
                    .font(.system(size: 26 * unit, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.25))
            }
        }
        .scaleEffect(bursting ? 1.32 : 1.0)
        .rotationEffect(.degrees(bursting ? -12 : 0))
    }
}

// MARK: - TV stage (1280 × 720 HD-2D canvas, scaled by `unit`)

struct MiniGameStage: View {
    @ObservedObject var model: MiniGameModel
    var body: some View {
        GeometryReader { g in
            let unit = min(g.size.height / 720, g.size.width / 1280)
            let stageSize = CGSize(width: 1280 * unit, height: 720 * unit)
            let isUltrawide = g.size.width > stageSize.width + 6
            ZStack {
                // Layer 0: Full-bleed soft blurred ambient fill for ultrawide / tall viewports (zero black bars, zero coordinate drift!)
                HD2DAmbientBackdrop(kind: model.kind, size: g.size)

                // Layers 1-4: Pixel-locked 16:9 HD-2D Stage (`1280*unit × 720*unit`)
                ZStack {
                    // Layer 1: Dedicated HD-2D per-game scene with CoreImage tilt-shift optical depth-of-field
                    HD2DMeadowBackdrop(kind: model.kind, size: stageSize, featherEdges: isUltrawide)

                    // Layer 2: Grounded interactive props, full-body animated heroes, monsters, shadows & pixel VFX
                    MiniGameWorldLayer(model: model, unit: unit)
                        .frame(width: stageSize.width, height: stageSize.height)

                    // Layer 3: Drifting volumetric sun/moon shafts, embers/motes & optical vignette
                    HD2DAtmosphereOverlay(kind: model.kind, size: stageSize)

                    // Layer 4: Crisp UI HUD (unblurred, matching `MeadowPartyStageView` glass captions & vitals)
                    MiniGameChromeLayer(model: model, unit: unit)
                        .frame(width: stageSize.width, height: stageSize.height)
                }
                .frame(width: stageSize.width, height: stageSize.height)
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
        }
        .transition(.opacity)
    }
}

private struct MiniGameWorldLayer: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    var body: some View {
        switch model.kind {
        case .boss: BossStage(model: model, unit: unit)
        case .camp: CampStage(model: model, unit: unit)
        case .race: RaceStage(model: model, unit: unit)
        case .memory: MemoryStage(model: model, unit: unit)
        case .arena: ArenaStage(model: model, unit: unit)
        }
    }
}

/// Authentic Meadow frosted-glass title pill, bottom announcement banner (zero ghosting), and finale plaque.
private struct MiniGameChromeLayer: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var bannerPulse = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                titlePill.padding(.top, 14 * unit)
                Spacer()
                if let line = model.banner {
                    meadowBanner(line)
                        .padding(.bottom, 16 * unit)
                        .padding(.horizontal, 52 * unit)
                }
            }
            if model.finished { MiniGameFinale(model: model, unit: unit) }
        }
        .onChange(of: model.beat) { _, _ in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) { bannerPulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                withAnimation(.easeOut(duration: 0.25)) { bannerPulse = false }
            }
        }
    }

    private var titlePill: some View {
        HStack(spacing: 9 * unit) {
            if model.kind == .memory {
                Image("MiniGameChestOpen").resizable().interpolation(.none).scaledToFit().frame(width: 30 * unit, height: 30 * unit)
            } else if model.kind == .arena {
                Image("MiniGameCrown").resizable().interpolation(.none).scaledToFit().frame(width: 30 * unit, height: 30 * unit)
            } else {
                Image(systemName: model.kind.icon)
                    .font(.system(size: 22 * unit, weight: .heavy))
                    .foregroundStyle(MiniGamePalette.goldDeep)
            }
            Text(model.kind.title)
                .font(.system(size: 27 * unit, weight: .heavy, design: .rounded))
                .foregroundStyle(MiniGamePalette.ink)
        }
        .padding(.horizontal, 22 * unit)
        .padding(.vertical, 7 * unit)
        .background(Capsule().fill(Color.white.opacity(0.84)))
        .overlay(Capsule().stroke(.white, lineWidth: 1.8 * unit))
        .shadow(color: MiniGamePalette.gold.opacity(0.32), radius: 10 * unit)
        .shadow(color: .black.opacity(0.22), radius: 8 * unit, y: 3 * unit)
    }

    private func meadowBanner(_ line: String) -> some View {
        let topColor = Color.white.opacity(0.92)
        let botColor = Color(red: 0.96, green: 0.98, blue: 0.97).opacity(0.88)
        let bg = LinearGradient(colors: [topColor, botColor], startPoint: .top, endPoint: .bottom)
        let scale: CGFloat = bannerPulse ? 1.035 : 1.0
        let label = Text(line)
            .font(.system(size: 25 * unit, weight: .heavy, design: .rounded))
            .foregroundStyle(MiniGamePalette.ink)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.65)
            .contentTransition(.opacity)
        let pill = label
            .padding(.horizontal, 26 * unit)
            .padding(.vertical, 10 * unit)
            .background(Capsule().fill(bg))
            .overlay(Capsule().stroke(Color.white, lineWidth: 2 * unit))
        return pill
            .shadow(color: Color.black.opacity(0.24), radius: 10 * unit, y: 4 * unit)
            .scaleEffect(scale)
    }
}

private struct MiniGameFinale: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var pop = false
    var body: some View {
        let won = model.kind == .boss ? model.boss?.outcome == .won : model.kind == .camp ? model.camp?.outcome == .won : true
        ZStack {
            Color.black.opacity(0.24)
            VStack(spacing: 12 * unit) {
                if won {
                    Image(model.kind == .memory ? "MiniGameChestOpen" : "MiniGameCrown")
                        .resizable().interpolation(.none).scaledToFit()
                        .frame(width: 92 * unit, height: 92 * unit)
                        .shadow(color: MiniGamePalette.gold.opacity(0.75), radius: 14 * unit)
                } else {
                    Image(systemName: "shield.slash.fill")
                        .font(.system(size: 62 * unit, weight: .bold))
                        .foregroundStyle(MiniGamePalette.ink.opacity(0.7))
                }
                Text(won ? "胜利！" : "下次再来")
                    .font(.system(size: 76 * unit, weight: .black, design: .rounded))
                    .foregroundStyle(won ? AnyShapeStyle(LinearGradient(colors: [MiniGamePalette.goldDeep, Color(red: 0.86, green: 0.56, blue: 0.12)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(MiniGamePalette.ink))
                if won, !model.winners.isEmpty, model.kind != .boss, model.kind != .camp {
                    HStack(spacing: 12 * unit) {
                        ForEach(model.winners.prefix(4), id: \.self) { id in
                            MiniGameFace(student: model.student(id), size: 54 * unit, tint: model.studentTint(id))
                        }
                    }
                    Text(model.winners.map(model.name).joined(separator: "、"))
                        .font(.system(size: 30 * unit, weight: .heavy, design: .rounded))
                        .foregroundStyle(MiniGamePalette.ink)
                }
            }
            .padding(.horizontal, 52 * unit)
            .padding(.vertical, 32 * unit)
            .background(RoundedRectangle(cornerRadius: 28 * unit, style: .continuous).fill(Color.white.opacity(0.90)))
            .overlay(RoundedRectangle(cornerRadius: 28 * unit, style: .continuous).stroke(.white, lineWidth: 2.5 * unit))
            .shadow(color: MiniGamePalette.gold.opacity(0.45), radius: 22 * unit)
            .shadow(color: .black.opacity(0.35), radius: 20 * unit, y: 10 * unit)
            .scaleEffect(pop ? 1 : 0.45)
            .opacity(pop ? 1 : 0)
            .offset(y: -26 * unit)
        }
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.62).delay(0.25)) { pop = true } }
    }
}

// MARK: - 1. 全班打Boss (HD-2D Twilight Boss Sanctum Battle — Left Party vs Right Boss!)

private struct BossStage: View {
    private struct ShotCue: Identifiable {
        let id: Int
        let from: CGPoint
        let clip: String
        let delay: Double
        let arc: CGFloat
    }
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var hurtAt: Date?
    @State private var deadAt: Date?
    @State private var bossCastAt: Date?
    @State private var bossAttackAt: Date?
    @State private var fxAt: Date?
    @State private var counterFXAt: Date?
    @State private var victoryFXAt: Date?
    @State private var maxHitSides = 4
    @State private var shots: [ShotCue] = []
    @State private var shotStartAt: Date?
    @State private var diceAt: Date?
    @State private var numbersAt: Date?
    @State private var attackAt: Date?
    @State private var heroHurtAt: Date?
    @State private var shake = false
    @State private var counterFlash = false
    @State private var shatteredHeart: Int?
    @State private var dashingIDs: Set<String> = []
    @State private var rolledDice: [BattleDie] = []

    /// Species-authentic counterattack VFX (cast with direction = -1 from Boss toward hero party!).
    private func bossCounterCue(_ monster: String) -> (anchor: String, clip: String, followClip: String?, projectile: String?) {
        switch monster {
        case "ruinDragon": return ("casterMouth", "fire_fire_breath_5", "status_burning_7", nil)
        case "frostPhoenix": return ("casterMouth", "ice_breath_cone", "frost_nova_ring", nil)
        case "eclipseBehemoth": return ("casterChest", "astral_eclipse_beam", "shadow_dark_explosion", nil)
        case "mushroomKing": return ("partyCenter", "cap_spore_slam", "thorn_spore_cloud", nil)
        case "goblinWarlord": return ("partyCenter", "bomb_firework_blast", "bomb_star_smoke", "bomb_lob_proj")
        case "thornTreant": return ("partyCenter", "thorn_root_sweep", "nature_vine_whip", nil)
        case "frostAlphaWolf": return ("partyCenter", "frost_fang_bite", "frost_shard_burst", nil)
        case "crystalGolem": return ("casterFoot", "nature_boulder_smash", "impacts_ground_slam_57", nil)
        default: return ("partyCenter", "nature_quake_rift", "impacts_ground_slam_57", nil)
        }
    }

    var body: some View {
        if let b = model.boss {
            let spec = MonsterVisualSpec.find(b.monster) ?? MonsterVisualSpec(id: b.monster)
            let bossH = (288.0 * spec.scale) * unit
            // Keep Boss feet solidly grounded on the stone courtyard flagstones (`footY ≈ 574`).
            let bossFoot = CGPoint(x: 946 * unit, y: 576 * unit)
            let bossCenterY = bossFoot.y - bossH * 0.44
            let bossHitPt = CGPoint(
                x: bossFoot.x + CGFloat(spec.hitAnchor.x - 178.5) * (bossH / 256.0) * 0.85,
                y: bossFoot.y - bossH * 0.42
            )
            let bossMouthPt = CGPoint(x: bossFoot.x - bossH * 0.30, y: bossFoot.y - bossH * 0.48)
            let spots = partyFormation(count: model.students.count)
            let partyCenter = CGPoint(
                x: spots.isEmpty ? 320 * unit : spots.map(\.x).reduce(0, +) / CGFloat(spots.count),
                y: spots.isEmpty ? 520 * unit : spots.map(\.y).reduce(0, +) / CGFloat(spots.count) + 52 * unit
            )
            let cue = bossCounterCue(b.monster)
            let fxScale = 2.05 * unit

            ZStack(alignment: .topLeading) {
                // 1) Twin Glowing Pixel Stone Braziers planted solidly on the mossy ruins flagstones flanking the Boss
                brazierWithGlow(x: 708 * unit, y: 484 * unit, height: 118 * unit)
                brazierWithGlow(x: 1172 * unit, y: 500 * unit, height: 122 * unit)

                // 2) Left Tactical Party Formation — REAL Full-Body Animated Battle Heroes grounded on left flagstones!
                ForEach(Array(model.students.enumerated()), id: \.element.id) { idx, s in
                    let p = spots[idx]
                    let isAttacker = dashingIDs.contains(s.id)
                    let action: HD2DBattleHero.Action = {
                        if b.outcome == .won { return .victory }
                        if isAttacker { return .attack }
                        if heroHurtAt != nil { return .hurt }
                        return .ready
                    }()
                    let triggerDate: Date? = isAttacker ? attackAt : (heroHurtAt ?? (b.outcome == .won ? hurtAt : nil))
                    let heroH = (model.students.count > 4 ? 174 : 196) * unit
                    let dashShift: CGFloat = isAttacker ? (s.style == .melee ? 92 * unit : 28 * unit) : 0
                    HD2DBattleHero(
                        student: s,
                        height: heroH,
                        mirrored: false,
                        action: action,
                        actionAt: triggerDate,
                        ringColor: model.studentTint(s.id)
                    )
                    .overlay(alignment: .bottom) {
                        Text(s.name)
                            .font(.system(size: 14 * unit, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 9 * unit).padding(.vertical, 2.5 * unit)
                            .background(RoundedRectangle(cornerRadius: 6 * unit).fill(MiniGamePalette.battlePlate.opacity(0.86)))
                            .overlay(RoundedRectangle(cornerRadius: 6 * unit).stroke(model.studentTint(s.id).opacity(0.92), lineWidth: 1.5 * unit))
                            .offset(y: 4 * unit)
                    }
                    .position(x: p.x + dashShift, y: p.y)
                    .zIndex(Double(p.y))
                }

                // 3) Right Boss Monster with back-layer VFX behind it and front-layer impact FX directly on torso!
                HD2DPixelFXEffect(
                    clipID: maxHitSides >= 10 ? "fire_flame_pillar" : "melee_heavy_cleave_51",
                    playedAt: fxAt, anchor: bossFoot, pixelScale: fxScale, direction: 1, layer: .back
                )
                .zIndex(460)

                HD2DMonster(
                    id: b.monster, height: bossH, mirrored: false,
                    hurtAt: hurtAt, attackAt: bossAttackAt, castAt: bossCastAt, deadAt: deadAt, dead: b.outcome == .won
                )
                .offset(x: shake ? 14 * unit : 0)
                .position(x: bossFoot.x, y: bossCenterY)
                .zIndex(480)

                // Hero flying weapon projectiles (arrows / holy orbs / fireballs / wind bolts -> exact Boss torso!)
                ForEach(shots) { shot in
                    HD2DPixelFXProjectile(
                        clipID: shot.clip, playedAt: shotStartAt,
                        from: shot.from, to: bossHitPt,
                        pixelScale: 1.85 * unit, delay: shot.delay, flight: 0.24, arc: shot.arc
                    )
                    .zIndex(515)
                }

                // Escalating Star-Level Hero Impact VFX anchored squarely on Boss foot/torso
                HD2DPixelFXEffect(
                    clipID: maxHitSides >= 10 ? "skybreaker_lance" : maxHitSides >= 6 ? "lightning_bolt_strike" : "melee_heavy_cleave_51",
                    playedAt: fxAt, anchor: bossFoot, pixelScale: fxScale, direction: 1, layer: .front
                )
                .zIndex(520)
                HD2DPixelFXEffect(
                    clipID: maxHitSides >= 6 ? "impacts_crit_hit_3" : "impacts_hit_spark_55",
                    playedAt: fxAt, anchor: CGPoint(x: bossHitPt.x, y: bossHitPt.y + 42 * unit), pixelScale: 1.95 * unit, direction: 1
                )
                .zIndex(530)

                // Boss Victory Dissolution Sunburst + Legendary Collect
                HD2DPixelFXEffect(clipID: "holy_sunburst_39", playedAt: victoryFXAt, anchor: bossHitPt, pixelScale: 2.3 * unit)
                    .zIndex(540)
                HD2DPixelFXEffect(clipID: "collectLegendary", playedAt: victoryFXAt, anchor: bossFoot, pixelScale: 2.1 * unit, delay: 0.14)
                    .zIndex(545)

                // Authentic Species Boss Counterattack VFX (direction: -1 facing LEFT toward heroes!)
                if let proj = cue.projectile {
                    HD2DPixelFXProjectile(
                        clipID: proj, playedAt: counterFXAt,
                        from: bossMouthPt, to: CGPoint(x: partyCenter.x, y: partyCenter.y - 52 * unit),
                        pixelScale: 2.0 * unit, delay: 0.08, flight: 0.30, arc: 46 * unit
                    )
                    .zIndex(550)
                }
                let primaryAnchor: CGPoint = {
                    switch cue.anchor {
                    case "casterMouth": return bossMouthPt
                    case "casterChest": return CGPoint(x: bossFoot.x - 42 * unit, y: bossFoot.y - 36 * unit)
                    case "casterFoot": return CGPoint(x: bossFoot.x - 24 * unit, y: bossFoot.y - 10 * unit)
                    default: return partyCenter
                    }
                }()
                let primaryDelay = cue.projectile != nil ? 0.36 : 0.14
                HD2DPixelFXEffect(
                    clipID: cue.clip, playedAt: counterFXAt,
                    anchor: primaryAnchor, pixelScale: 2.05 * unit, direction: -1, delay: primaryDelay
                )
                .zIndex(555)
                if let follow = cue.followClip {
                    HD2DPixelFXEffect(
                        clipID: follow, playedAt: counterFXAt,
                        anchor: partyCenter, pixelScale: 1.9 * unit, direction: -1, delay: primaryDelay + 0.12
                    )
                    .zIndex(560)
                }

                // Floating Battle Damage Numbers right above Boss head
                BattleFloatingNumbers(hits: b.lastHits, startedAt: numbersAt, model: model, unit: unit)
                    .position(x: bossFoot.x - 10 * unit, y: bossFoot.y - bossH * 0.92)
                    .zIndex(600)

                // 4) Top-Left Class Hearts & Top-Right Battle-Style Boss Vitals HUD
                HStack(spacing: 6 * unit) {
                    Text("全班生命")
                        .font(.system(size: 15 * unit, weight: .heavy, design: .rounded))
                        .foregroundStyle(MiniGamePalette.battleRim)
                        .padding(.trailing, 4 * unit)
                    ForEach(0..<BossRaid.hearts, id: \.self) { i in
                        RPGHeartView(filled: i < b.hearts, bursting: shatteredHeart == i, unit: unit)
                    }
                }
                .padding(.horizontal, 16 * unit).padding(.vertical, 9 * unit)
                .background(RoundedRectangle(cornerRadius: 14 * unit, style: .continuous).fill(MiniGamePalette.battlePlate.opacity(0.86)))
                .overlay(RoundedRectangle(cornerRadius: 14 * unit, style: .continuous).stroke(MiniGamePalette.battleRim.opacity(0.68), lineWidth: 1.5 * unit))
                .position(x: 192 * unit, y: 52 * unit)
                .zIndex(700)

                BattleVitalsBar(name: MiniGameModel.monsterName(b.monster), hp: b.hp, maxHP: b.maxHP, width: 320 * unit, unit: unit)
                    .position(x: 1094 * unit, y: 56 * unit)
                    .zIndex(700)

                // Native 3D Gem Polyhedral Dice Roll Strip (d4 / d6 / d10 right from `MeadowBattleDiceView`!)
                HD2DDiceStrip(dice: rolledDice, startedAt: diceAt, unit: unit)
                    .position(x: 640 * unit, y: 122 * unit)
                    .zIndex(750)

                if counterFlash {
                    RadialGradient(colors: [.clear, Color.red.opacity(0.36)], center: .center, startRadius: 210 * unit, endRadius: 720 * unit)
                        .transition(.opacity)
                        .zIndex(800)
                }
            }
            .frame(width: 1280 * unit, height: 720 * unit)
            .onChange(of: model.beat) { _, _ in
                guard let b = model.boss else { return }
                let now = Date()
                let spots = partyFormation(count: model.students.count)
                if !b.lastHits.isEmpty {
                    let colors = ["red", "yellow", "green", "blue"]
                    rolledDice = b.lastHits.enumerated().map { idx, h in
                        BattleDie(colors[idx % colors.count], sides: h.sides, value: h.damage, label: "D\(h.sides)")
                    }
                    maxHitSides = b.lastHits.map(\.sides).max() ?? 4
                    diceAt = now
                    attackAt = now
                    // Build authentic weapon-matched projectiles for ranged/magic attackers
                    var newShots: [ShotCue] = []
                    for (k, h) in b.lastHits.enumerated() {
                        if let sIdx = model.students.firstIndex(where: { $0.id == h.player }), sIdx < spots.count {
                            let s = model.students[sIdx]
                            let chest = CGPoint(x: spots[sIdx].x + 36 * unit, y: spots[sIdx].y - 12 * unit)
                            let clip: String = switch s.style {
                            case .bow: h.sides >= 10 ? "wind_thunder_bolt" : "projectiles_arrow_42"
                            case .magic: h.sides >= 10 ? "fire_fireball_47" : "holy_orb_proj"
                            case .melee: h.sides >= 6 ? "wind_thunder_bolt" : "holy_orb_proj"
                            }
                            if s.style != .melee || k == 0 {
                                newShots.append(ShotCue(id: k, from: chest, clip: clip, delay: Double(k) * 0.05, arc: s.style == .bow ? 14 * unit : 22 * unit))
                            }
                        }
                    }
                    shots = newShots
                    shotStartAt = now
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                        dashingIDs = Set(b.lastHits.map(\.player))
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                        hurtAt = Date()
                        fxAt = Date()
                        numbersAt = Date()
                        if b.outcome == .won {
                            deadAt = Date()
                            victoryFXAt = Date()
                        }
                        withAnimation(.default.repeatCount(5, autoreverses: true).speed(4)) { shake = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) { shake = false }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { dashingIDs = [] }
                    }
                }
                if b.lastCounter {
                    let lostIndex = b.hearts
                    let delay = b.lastHits.isEmpty ? 0.05 : 0.72
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        let cNow = Date()
                        bossCastAt = cNow
                        bossAttackAt = cNow
                        counterFXAt = cNow
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                            heroHurtAt = Date()
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { shatteredHeart = lostIndex }
                            withAnimation(.easeOut(duration: 0.15)) { counterFlash = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    counterFlash = false
                                    heroHurtAt = nil
                                    if shatteredHeart == lostIndex { shatteredHeart = nil }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func brazierWithGlow(x: CGFloat, y: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1.0, green: 0.68, blue: 0.22).opacity(0.45), Color.orange.opacity(0.14), .clear], center: .center, startRadius: 6 * unit, endRadius: 90 * unit))
                .frame(width: 180 * unit, height: 180 * unit)
                .offset(y: -34 * unit)
            HD2DProp(name: "MiniGameBrazier", height: height, depthBlur: 0, shadow: true)
        }
        .position(x: x, y: y)
        .zIndex(Double(y))
    }

    /// Staggered left-side tactical battle positions grounded on the left ruins flagstones (zero nameplate overlap even with quiz dock open!).
    private func partyFormation(count: Int) -> [CGPoint] {
        switch count {
        case 1: return [CGPoint(x: 345 * unit, y: 486 * unit)]
        case 2: return [CGPoint(x: 232 * unit, y: 448 * unit), CGPoint(x: 425 * unit, y: 514 * unit)]
        case 3: return [CGPoint(x: 184 * unit, y: 428 * unit), CGPoint(x: 442 * unit, y: 472 * unit), CGPoint(x: 296 * unit, y: 534 * unit)]
        case 4: return [CGPoint(x: 175 * unit, y: 424 * unit), CGPoint(x: 388 * unit, y: 438 * unit), CGPoint(x: 260 * unit, y: 534 * unit), CGPoint(x: 478 * unit, y: 538 * unit)]
        default:
            return (0..<count).map { i in
                let col = i % 2
                let row = i / 2
                let rows = max(1, (count + 1) / 2)
                let x = (col == 0 ? 182.0 : 408.0) + Double(row % 2) * 44.0
                let y = 412.0 + Double(row) * (132.0 / Double(max(1, rows - 1)))
                return CGPoint(x: x * unit, y: y * unit)
            }
        }
    }
}

// MARK: - 2. 守护营地 (Dedicated Sunlit Camp Fortification & Horizontal Dirt Defense Road!)

private struct CampStage: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var hurtAt: Date?
    @State private var deadAt: Date?
    @State private var monsterAttackAt: Date?
    @State private var pushbackFXAt: Date?
    @State private var shieldFXAt: Date?
    @State private var breachFXAt: Date?
    @State private var waveSpawnFXAt: Date?
    @State private var heroAttackAt: Date?
    @State private var cheerAt: Date?
    @State private var campWarn = false
    @State private var waveCallout: String?
    @State private var lastWave = 0

    var body: some View {
        if let c = model.camp {
            let cell = 132 * unit
            let left = 420 * unit
            // `MiniGameSceneCamp`'s sunlit dirt road runs cleanly through y ≈ 495...558
            let trailY = 532 * unit
            let dist = CampDefense.length - c.position
            let species = model.campWaveSpecies[min(c.wave, max(0, model.campWaveSpecies.count - 1))]
            let spec = MonsterVisualSpec.find(species) ?? MonsterVisualSpec(id: species)
            let monsterH: CGFloat = (c.wave == 2 ? 236 : c.wave == 1 ? 198 : 172) * CGFloat(max(0.92, spec.scale)) * unit
            let monsterFootX = dist > 0 ? (left + CGFloat(dist - 1) * cell + cell / 2) : 332 * unit
            let monsterFootY = trailY - 2 * unit
            let monsterCenterY = monsterFootY - monsterH * 0.44
            let monsterChest = CGPoint(x: monsterFootX - monsterH * 0.10, y: monsterFootY - monsterH * 0.44)
            let gateShieldPt = CGPoint(x: 368 * unit, y: trailY + 4 * unit)
            let wave6Foot = CGPoint(x: left + CGFloat(CampDefense.length - 1) * cell + cell / 2, y: monsterFootY)

            ZStack(alignment: .topLeading) {
                // 1) Camp Gate Warning Glow (pulses over the camp timber gate built into `MiniGameSceneCamp` when breached!)
                if campWarn {
                    Circle()
                        .fill(RadialGradient(colors: [Color.red.opacity(0.42), .clear], center: .center, startRadius: 10 * unit, endRadius: 190 * unit))
                        .frame(width: 380 * unit, height: 380 * unit)
                        .position(x: 245 * unit, y: 445 * unit)
                        .zIndex(150)
                }

                // 2) Full-Body Animated Defending Heroes Standing Guard Outside the Open Timber Camp Gate!
                let defenders = Array(model.students.prefix(4))
                ForEach(Array(defenders.enumerated()), id: \.element.id) { idx, s in
                    let dx = (276 + CGFloat(idx) * 34) * unit
                    let dy = (488 + CGFloat(idx % 2) * 28) * unit
                    let heroAct: HD2DBattleHero.Action =
                        c.outcome == .won ? .victory
                        : heroAttackAt != nil ? .attack
                        : cheerAt != nil ? .victory
                        : campWarn ? .hurt : .ready
                    HD2DBattleHero(
                        student: s,
                        height: 168 * unit,
                        mirrored: false,
                        action: heroAct,
                        actionAt: heroAttackAt ?? cheerAt,
                        ringColor: model.studentTint(s.id)
                    )
                    .position(x: dx, y: dy)
                    .zIndex(Double(dy))
                }

                // 3) 6 Real Pixel-Art Stepping Stones (`MiniGameSteppingStone`) seated squarely along the dirt road!
                ForEach(1...CampDefense.length, id: \.self) { step in
                    let cx = left + CGFloat(step - 1) * cell + cell / 2
                    let active = step == dist
                    let danger = step <= 2
                    ZStack {
                        Image("MiniGameSteppingStone")
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: cell - 10 * unit)
                            .colorMultiply(danger ? Color(red: 1.0, green: 0.78, blue: 0.74) : .white)
                            .shadow(color: active ? MiniGamePalette.gold.opacity(0.75) : .black.opacity(0.28), radius: (active ? 10 : 4) * unit, y: 3 * unit)
                        Text("\(step)")
                            .font(.system(size: 19 * unit, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10 * unit).padding(.vertical, 2 * unit)
                            .background(Capsule().fill(danger ? Color(red: 0.84, green: 0.22, blue: 0.20).opacity(0.92) : MiniGamePalette.battlePlate.opacity(0.82)))
                            .overlay(Capsule().stroke(active ? MiniGamePalette.goldBright : MiniGamePalette.battleRim.opacity(0.75), lineWidth: 1.5 * unit))
                            .offset(y: 16 * unit)
                    }
                    .position(x: cx, y: trailY)
                    .zIndex(310)
                }

                // 4) Approaching Monster on its Stepping Stone + Real Multi-Phase PixelFX!
                HD2DPixelFXEffect(clipID: "tribal_drum_chant", playedAt: waveSpawnFXAt, anchor: wave6Foot, pixelScale: 1.9 * unit, direction: -1, layer: .back)
                    .zIndex(430)

                VStack(spacing: -10 * unit) {
                    Text("第 \(c.wave + 1) 波 · \(MiniGameModel.monsterName(species))")
                        .font(.system(size: 15 * unit, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11 * unit).padding(.vertical, 3 * unit)
                        .background(RoundedRectangle(cornerRadius: 6 * unit).fill(MiniGamePalette.battlePlate.opacity(0.86)))
                        .overlay(RoundedRectangle(cornerRadius: 6 * unit).stroke(MiniGamePalette.battleRim.opacity(0.82), lineWidth: 1.4 * unit))
                    HD2DMonster(
                        id: species, height: monsterH, mirrored: false,
                        hurtAt: hurtAt, attackAt: monsterAttackAt, deadAt: deadAt, dead: c.outcome == .won
                    )
                }
                .position(x: monsterFootX, y: monsterCenterY)
                .zIndex(450)

                // Defender pushback projectile + shield bash wave landing right on monster!
                HD2DPixelFXProjectile(
                    clipID: "wind_thunder_bolt", playedAt: pushbackFXAt,
                    from: CGPoint(x: 342 * unit, y: 472 * unit), to: monsterChest,
                    pixelScale: 1.9 * unit, delay: 0.04, flight: 0.22, arc: 12 * unit
                )
                .zIndex(510)
                HD2DPixelFXEffect(
                    clipID: "shield_bash_wave", playedAt: pushbackFXAt,
                    anchor: CGPoint(x: monsterFootX - 36 * unit, y: monsterFootY - 6 * unit),
                    pixelScale: 1.95 * unit, direction: 1, delay: 0.20
                )
                .zIndex(520)
                HD2DPixelFXEffect(
                    clipID: "wind_spark_impact", playedAt: pushbackFXAt,
                    anchor: monsterChest, pixelScale: 1.9 * unit, direction: 1, delay: 0.24
                )
                .zIndex(525)

                // Hold-the-line defensive barrier rising right in front of camp gate defenders!
                HD2DPixelFXEffect(
                    clipID: "iron_bastion_wall", playedAt: shieldFXAt,
                    anchor: gateShieldPt, pixelScale: 2.2 * unit, direction: 1
                )
                .zIndex(525)
                HD2DPixelFXEffect(
                    clipID: "astral_dome_barrier", playedAt: shieldFXAt,
                    anchor: CGPoint(x: 274 * unit, y: trailY + 2 * unit), pixelScale: 2.0 * unit, direction: 1, delay: 0.08
                )
                .zIndex(528)

                // Monster advance slam facing LEFT toward camp gate!
                HD2DPixelFXEffect(
                    clipID: "nature_quake_rift", playedAt: breachFXAt,
                    anchor: CGPoint(x: max(360 * unit, monsterFootX - 58 * unit), y: monsterFootY + 4 * unit),
                    pixelScale: 1.9 * unit, direction: -1, delay: 0.14
                )
                .zIndex(530)
                HD2DPixelFXEffect(
                    clipID: "melee_heavy_cleave_36", playedAt: breachFXAt,
                    anchor: CGPoint(x: monsterFootX - 18 * unit, y: monsterFootY),
                    pixelScale: 1.95 * unit, direction: -1, delay: 0.10
                )
                .zIndex(532)

                // New Wave arrival smoke & drum ring
                HD2DPixelFXEffect(clipID: "shadow_dark_explosion", playedAt: waveSpawnFXAt, anchor: wave6Foot, pixelScale: 1.75 * unit, direction: -1)
                    .zIndex(535)

                // 5) Frosted Meadow-Glass Progress & Distance HUD (top center, below title pill)
                HStack(spacing: 14 * unit) {
                    HStack(spacing: 5 * unit) {
                        ForEach(0..<CampDefense.rounds, id: \.self) { i in
                            Circle()
                                .fill(i < c.round ? MiniGamePalette.gold : Color.black.opacity(0.14))
                                .frame(width: 15 * unit, height: 15 * unit)
                                .overlay(Circle().stroke(i == c.round ? MiniGamePalette.goldDeep : Color.white.opacity(0.8), lineWidth: 1.5 * unit))
                        }
                    }
                    Text("第 \(c.round)/\(CampDefense.rounds) 题")
                        .font(.system(size: 18 * unit, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(MiniGamePalette.ink)
                    Text(dist == 0 ? "营地失守" : "离营地 \(dist) 步")
                        .font(.system(size: 18 * unit, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13 * unit).padding(.vertical, 4 * unit)
                        .background(Capsule().fill(dist <= 2 ? Color(red: 0.86, green: 0.22, blue: 0.20) : Color(red: 0.16, green: 0.56, blue: 0.36)))
                }
                .padding(.horizontal, 18 * unit).padding(.vertical, 8 * unit)
                .background(Capsule().fill(Color.white.opacity(0.86)))
                .overlay(Capsule().stroke(.white, lineWidth: 1.5 * unit))
                .shadow(color: .black.opacity(0.20), radius: 8 * unit, y: 3 * unit)
                .position(x: 640 * unit, y: 98 * unit)
                .zIndex(700)

                // Transient Wave Callout Ribbon
                if let callout = waveCallout {
                    Text(callout)
                        .font(.system(size: 26 * unit, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24 * unit).padding(.vertical, 9 * unit)
                        .background(Capsule().fill(Color(red: 0.68, green: 0.14, blue: 0.16).opacity(0.92)))
                        .overlay(Capsule().stroke(MiniGamePalette.battleRim, lineWidth: 2 * unit))
                        .shadow(color: .black.opacity(0.35), radius: 10 * unit, y: 4 * unit)
                        .position(x: 640 * unit, y: 196 * unit)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .zIndex(760)
                }
            }
            .frame(width: 1280 * unit, height: 720 * unit)
            .onChange(of: model.beat) { _, _ in
                guard let c = model.camp else { return }
                let now = Date()
                if c.lastMove == -1 {
                    heroAttackAt = now
                    pushbackFXAt = now
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        hurtAt = Date()
                        if c.outcome == .won { deadAt = Date() }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                        heroAttackAt = nil
                        cheerAt = Date()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { cheerAt = nil }
                    }
                } else if c.lastMove == 0 {
                    shieldFXAt = now
                    if c.outcome == .won { deadAt = now }
                } else {
                    monsterAttackAt = now
                    breachFXAt = now
                    withAnimation(.default.repeatCount(3, autoreverses: true).speed(4)) { campWarn = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { campWarn = false }
                }
                if c.wave != lastWave {
                    lastWave = c.wave
                    waveSpawnFXAt = Date()
                    let nextSpecies = model.campWaveSpecies[min(c.wave, max(0, model.campWaveSpecies.count - 1))]
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        waveCallout = "第 \(c.wave + 1) 波 · \(MiniGameModel.monsterName(nextSpecies))来袭！"
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                        withAnimation(.easeOut(duration: 0.35)) { waveCallout = nil }
                    }
                }
            }
        }
    }
}

// MARK: - 3. 答题赛跑 (HD-2D Sunlit Meadow Festival Racetrack + Finish Arch + Native 3D Gem d6!)

private struct RaceStage: View {
    private struct RaceFXCue: Identifiable {
        let id: Int
        let clip: String
        let anchor: CGPoint
        let scale: CGFloat
        let delay: Double
    }
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var rolledDice: [BattleDie] = []
    @State private var diceAt: Date?
    @State private var fxAt: Date?
    @State private var fxCues: [RaceFXCue] = []
    @State private var runningSideID: String?

    var body: some View {
        if let r = model.race {
            let lanes = max(1, r.sides.count)
            // Always leave breathing room for sunlit festival sky/bunting & finish arch while maximizing lane legibility.
            let top: CGFloat = (lanes <= 3 ? 210 : lanes <= 5 ? 148 : 118) * unit
            let bottom: CGFloat = (lanes <= 3 ? 98 : 88) * unit
            let laneAreaH = 720 * unit - top - bottom
            let laneH = min(136 * unit, laneAreaH / CGFloat(lanes))
            let firstLaneY = top + (laneAreaH - laneH * CGFloat(lanes)) / 2
            let laneW = 1196 * unit
            let laneLeft = 36 * unit
            let plateW = 132 * unit
            let trackLeft = laneLeft + plateW + 10 * unit
            let trackW = laneW - plateW - 18 * unit
            let cellW = trackW / CGFloat(RaceTrack.length + 1)
            let finishX = trackLeft + CGFloat(RaceTrack.length) * cellW + cellW / 2
            let leadPos = r.positions.values.max() ?? 0

            ZStack(alignment: .topLeading) {
                // 1) Frosted Meadow-Glass Special Tile Legend Strip
                HStack(spacing: 14 * unit) {
                    legendChest("礼物转盘")
                    legendItem("bolt.fill", color: MiniGamePalette.goldDeep, text: "闪电 +3")
                    legendItem("exclamationmark.triangle.fill", color: .orange, text: "陷阱答错 -2")
                    legendItem("flag.checkered", color: MiniGamePalette.ink, text: "冲线获胜")
                }
                .padding(.horizontal, 16 * unit).padding(.vertical, 5 * unit)
                .background(Capsule().fill(Color.white.opacity(0.86)))
                .overlay(Capsule().stroke(.white, lineWidth: 1.4 * unit))
                .shadow(color: .black.opacity(0.18), radius: 6 * unit, y: 2 * unit)
                .position(x: 640 * unit, y: 82 * unit)
                .zIndex(700)

                // 2) Translucent Frosted-Glass Lanes Letting Sunlit HD-2D Grass Shine Through
                ForEach(Array(r.sides.enumerated()), id: \.element.id) { lane, side in
                    let y = firstLaneY + CGFloat(lane) * laneH
                    let midY = y + laneH / 2
                    let current = r.current?.id == side.id && r.winner == nil
                    let at = r.positions[side.id] ?? 0
                    let leading = leadPos > 0 && at == leadPos
                    let sideColor = model.tint(side.id)
                    let cellH = min(72 * unit, laneH - 18 * unit)

                    RoundedRectangle(cornerRadius: 16 * unit, style: .continuous)
                        .fill(Color.white.opacity(current ? 0.84 : 0.66))
                        .overlay(RoundedRectangle(cornerRadius: 16 * unit, style: .continuous).fill(sideColor.opacity(current ? 0.14 : 0.06)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16 * unit, style: .continuous)
                                .stroke(current ? AnyShapeStyle(MiniGamePalette.goldStroke) : AnyShapeStyle(Color.white.opacity(0.8)), lineWidth: (current ? 3.5 : 1.5) * unit)
                        )
                        .shadow(color: current ? MiniGamePalette.gold.opacity(0.45) : .black.opacity(0.16), radius: (current ? 10 : 5) * unit, y: 3 * unit)
                        .frame(width: laneW, height: laneH - 8 * unit)
                        .position(x: laneLeft + laneW / 2, y: midY)
                        .zIndex(200)

                    // Left Team Nameplate with leader crown badge
                    HStack(spacing: 6 * unit) {
                        RoundedRectangle(cornerRadius: 4 * unit)
                            .fill(sideColor)
                            .frame(width: 6 * unit, height: max(26 * unit, laneH - 30 * unit))
                        VStack(alignment: .leading, spacing: 2 * unit) {
                            HStack(spacing: 4 * unit) {
                                if leading {
                                    Image("MiniGameCrown").resizable().interpolation(.none).scaledToFit()
                                        .frame(width: 16 * unit, height: 16 * unit)
                                } else if current {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 11 * unit, weight: .black))
                                        .foregroundStyle(MiniGamePalette.goldDeep)
                                }
                                Text(side.name)
                                    .font(.system(size: min(20, max(14, laneH / unit * 0.21)) * unit, weight: .heavy, design: .rounded))
                                    .foregroundStyle(MiniGamePalette.ink)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                            }
                            Text("\(at) / \(RaceTrack.length)")
                                .font(.system(size: 13 * unit, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(sideColor)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: plateW - 8 * unit)
                    .position(x: laneLeft + plateW / 2 + 4 * unit, y: midY)
                    .zIndex(260)

                    // 21 Symmetric Track Tiles
                    ForEach(0...RaceTrack.length, id: \.self) { i in
                        let passed = i > 0 && i <= at
                        cellView(r.cells[i], index: i, passed: passed, sideColor: sideColor)
                            .frame(width: cellW - 4 * unit, height: cellH)
                            .position(x: trackLeft + CGFloat(i) * cellW + cellW / 2, y: midY)
                            .zIndex(240)
                    }

                    // Crisp Larger Pixel Hero Runner Token grounded directly on tile `at`
                    let runnerH = min(106 * unit, max(72 * unit, laneH * 0.94))
                    runnerToken(side, height: runnerH, trapped: r.trapped.contains(side.id), active: current, sprinting: runningSideID == side.id)
                        .position(x: trackLeft + CGFloat(at) * cellW + cellW / 2, y: midY - runnerH * 0.10)
                        .zIndex(Double(300 + lane))
                }

                // 3) Wooden Festival Finish-Line Arch planted cleanly above the finish column (scales cleanly for any team count!)
                let archH = min(132 * unit, max(62 * unit, firstLaneY - 72 * unit))
                if archH >= 60 * unit {
                    HD2DProp(name: "MiniGameFinishArch", height: archH, depthBlur: 0, shadow: true)
                        .position(x: finishX, y: firstLaneY + 8 * unit - archH / 2)
                        .zIndex(190)
                }

                // Pinpoint Tile-Anchored PixelFX (wind dash / lightning boost / reward burst / trap vines / finish firework!)
                ForEach(fxCues) { cue in
                    HD2DPixelFXEffect(clipID: cue.clip, playedAt: fxAt, anchor: cue.anchor, pixelScale: cue.scale, delay: cue.delay)
                        .zIndex(560)
                }

                // 4) Real Native 3D Gem d6 Dice Roll (`MeadowBattleDiceView`) at Top-Right!
                HD2DDiceStrip(dice: rolledDice, startedAt: diceAt, unit: unit)
                    .position(x: 1130 * unit, y: 62 * unit)
                    .zIndex(760)
            }
            .frame(width: 1280 * unit, height: 720 * unit)
            .onChange(of: model.beat) { _, _ in
                guard let r = model.race else { return }
                let now = Date()
                var cues: [RaceFXCue] = []
                var nextID = 0
                func tilePoint(side: String, at tile: Int) -> CGPoint? {
                    guard let lane = r.sides.firstIndex(where: { $0.id == side }) else { return nil }
                    let y = firstLaneY + CGFloat(lane) * laneH + laneH / 2 + min(26 * unit, laneH * 0.24)
                    let x = trackLeft + CGFloat(min(RaceTrack.length, max(0, tile))) * cellW + cellW / 2
                    return CGPoint(x: x, y: y)
                }
                for e in r.events {
                    switch e {
                    case .moved(let side, let roll, let to):
                        let color = (model.tints[side] ?? 0) == 0 ? "red" : (model.tints[side] ?? 0) == 1 ? "blue" : "yellow"
                        rolledDice = [BattleDie(color, sides: 6, value: roll, label: "D6")]
                        diceAt = now
                        runningSideID = side
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { if runningSideID == side { runningSideID = nil } }
                        if let pt = tilePoint(side: side, at: to) {
                            nextID += 1; cues.append(RaceFXCue(id: nextID, clip: "wind_dash_step", anchor: pt, scale: 1.35 * unit, delay: 0.04))
                        }
                    case .landed(let side, let cell):
                        let finalPos = r.positions[side] ?? 0
                        if cell == .boost, let pt = tilePoint(side: side, at: max(0, finalPos - 3)), let destPt = tilePoint(side: side, at: finalPos) {
                            nextID += 1; cues.append(RaceFXCue(id: nextID, clip: "lightning_bolt_strike", anchor: pt, scale: 1.2 * unit, delay: 0.14))
                            nextID += 1; cues.append(RaceFXCue(id: nextID, clip: "wind_dash_step", anchor: destPt, scale: 1.65 * unit, delay: 0.28))
                        } else if cell == .reward, let pt = tilePoint(side: side, at: finalPos) {
                            nextID += 1; cues.append(RaceFXCue(id: nextID, clip: "collectLegendary", anchor: pt, scale: 1.75 * unit, delay: 0.16))
                            nextID += 1; cues.append(RaceFXCue(id: nextID, clip: "holy_sunburst_16", anchor: CGPoint(x: pt.x, y: pt.y - 24 * unit), scale: 1.55 * unit, delay: 0.22))
                        } else if cell == .trap, let pt = tilePoint(side: side, at: finalPos) {
                            nextID += 1; cues.append(RaceFXCue(id: nextID, clip: "thorn_vine_erupt", anchor: pt, scale: 1.8 * unit, delay: 0.16))
                        }
                    case .trapFailed(let side, let to):
                        if let pt = tilePoint(side: side, at: to) {
                            nextID += 1; cues.append(RaceFXCue(id: nextID, clip: "thorn_vine_erupt", anchor: pt, scale: 1.85 * unit, delay: 0.06))
                        }
                    case .missed: break
                    }
                }
                if let winner = r.winner, let winPt = tilePoint(side: winner, at: RaceTrack.length) {
                    nextID += 1; cues.append(RaceFXCue(id: nextID, clip: "bomb_firework_blast", anchor: CGPoint(x: winPt.x, y: winPt.y - 54 * unit), scale: 1.85 * unit, delay: 0.22))
                    nextID += 1; cues.append(RaceFXCue(id: nextID, clip: "holy_sunburst_39", anchor: CGPoint(x: winPt.x, y: winPt.y - 26 * unit), scale: 2.0 * unit, delay: 0.28))
                }
                if !cues.isEmpty {
                    fxCues = cues
                    fxAt = now
                }
            }
        }
    }

    private func legendChest(_ text: String) -> some View {
        HStack(spacing: 5 * unit) {
            Image("MiniGameChestClosed").resizable().interpolation(.none).scaledToFit().frame(width: 18 * unit, height: 18 * unit)
            Text(text).font(.system(size: 13 * unit, weight: .bold, design: .rounded)).foregroundStyle(MiniGamePalette.ink)
        }
    }

    private func legendItem(_ symbol: String, color: Color, text: String) -> some View {
        HStack(spacing: 4 * unit) {
            Image(systemName: symbol).font(.system(size: 13 * unit, weight: .bold)).foregroundStyle(color)
            Text(text).font(.system(size: 13 * unit, weight: .bold, design: .rounded)).foregroundStyle(MiniGamePalette.ink)
        }
    }

    @ViewBuilder private func cellView(_ cell: RaceTrack.Cell, index: Int, passed: Bool, sideColor: Color) -> some View {
        let color: Color = switch cell {
        case .reward: Color(red: 0.92, green: 0.34, blue: 0.56)
        case .trap: Color(red: 0.90, green: 0.46, blue: 0.14)
        case .boost: Color(red: 0.94, green: 0.72, blue: 0.14)
        case .finish: MiniGamePalette.battlePlate
        case .plain: .white
        }
        RoundedRectangle(cornerRadius: 8 * unit, style: .continuous)
            .fill(cell == .plain ? (passed ? sideColor.opacity(0.24) : Color.white.opacity(0.86)) : color.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 8 * unit, style: .continuous)
                    .stroke(cell == .finish ? MiniGamePalette.battleRim : (cell == .plain ? Color.black.opacity(0.08) : Color.white.opacity(0.55)), lineWidth: (cell == .finish ? 2 : 1) * unit)
            )
            .overlay {
                switch cell {
                case .reward:
                    Image("MiniGameChestClosed").resizable().interpolation(.none).scaledToFit().frame(width: 28 * unit, height: 28 * unit)
                case .trap:
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 18 * unit, weight: .bold)).foregroundStyle(.white)
                case .boost:
                    Image(systemName: "bolt.fill").font(.system(size: 19 * unit, weight: .bold)).foregroundStyle(.white)
                case .finish:
                    Image(systemName: "flag.checkered").font(.system(size: 18 * unit, weight: .bold)).foregroundStyle(MiniGamePalette.goldBright)
                case .plain:
                    Text(index == 0 ? "起" : "\(index)")
                        .font(.system(size: 13 * unit, weight: .heavy, design: .rounded))
                        .foregroundStyle(passed ? sideColor : MiniGamePalette.ink.opacity(0.45))
                }
            }
    }

    private func runnerToken(_ side: MiniGameSide, height: CGFloat, trapped: Bool, active: Bool, sprinting: Bool) -> some View {
        HStack(spacing: -height * 0.24) {
            ForEach(side.members.prefix(3), id: \.self) { id in
                if let student = model.student(id) {
                    RaceHeroSprite(student: student, height: side.members.count > 1 ? height * 0.86 : height, tint: model.tint(side.id), sprinting: sprinting)
                }
            }
        }
        .scaleEffect(active ? 1.07 : 1.0)
        .overlay(alignment: .bottomTrailing) {
            if trapped {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16 * unit, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4 * unit)
                    .background(Circle().fill(Color.orange))
                    .overlay(Circle().stroke(.white, lineWidth: 1.5 * unit))
                    .offset(x: 4 * unit, y: 4 * unit)
            }
        }
    }
}

/// Animated side-facing full-body pixel runner for Quiz Race (live breathing + sprint stride bounce).
private struct RaceHeroSprite: View {
    let student: MiniGameModel.Student
    let height: CGFloat
    let tint: Color
    var sprinting = false
    @State private var sprite: PixelHeroAtlas.BattleSprite?
    @State private var fallback: UIImage?

    var body: some View {
        let boxW = height * (256.0 / 320.0)
        TimelineView(.animation(minimumInterval: 1.0 / 12)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let bounce = sprinting ? abs(sin(t * 14)) * height * 0.08 : 0
            let readyList = sprite?.frames["ready"] ?? []
            let frame = readyList.isEmpty ? nil : readyList[Int(t * (sprinting ? 8 : 2.2)) % readyList.count]
            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(tint.opacity(0.28))
                    .overlay(Ellipse().stroke(tint.opacity(0.9), lineWidth: 1.6))
                    .frame(width: boxW * 0.68, height: boxW * 0.22)
                    .offset(y: -height * 0.08)
                if let frame {
                    Image(uiImage: frame.tall)
                        .resizable().interpolation(.none).scaledToFit()
                        .frame(width: boxW, height: height)
                        .shadow(color: .black.opacity(0.32), radius: 3, y: 2)
                        .offset(y: -bounce)
                } else if let fallback {
                    Image(uiImage: fallback)
                        .resizable().interpolation(.none).scaledToFit()
                        .frame(height: height * 0.72)
                        .offset(y: -height * 0.08 - bounce)
                } else {
                    MiniGameFace(student: student, size: height * 0.56, tint: tint)
                        .offset(y: -height * 0.14 - bounce)
                }
            }
            .frame(width: boxW, height: height)
        }
        .onAppear {
            if PixelHeroAtlas.isBattleReady(student.look) {
                sprite = PixelHeroAtlas.battle(student.look)
            } else {
                if let f = PixelHeroAtlas.fullBody(student.look, ready: { fallback = PixelHeroAtlas.fullBody(student.look) }) { fallback = f }
                PixelHeroAtlas.prepare(battle: [student.look]) { sprite = PixelHeroAtlas.battle(student.look) }
            }
        }
    }
}

// MARK: - 4. 翻牌寻宝 (Direct-Click Oak Table Cards + Adaptive 4–24 Scale + Pinpoint Per-Card PixelFX!)

private struct MemoryStage: View {
    private struct CardBurst: Identifiable {
        let id: Int
        let clip: String
        let anchor: CGPoint
        let scale: CGFloat
        let delay: Double
    }
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var fxAt: Date?
    @State private var bursts: [CardBurst] = []
    @State private var mismatchShake = false

    var body: some View {
        if let m = model.memory {
            let layout = MemoryBoardLayout(count: m.cards.count, unit: unit)
            ZStack(alignment: .topLeading) {
                // 1) Warm Antique-Gold Recessed Parchment Card Mat seated harmoniously on `MiniGameSceneMemory`'s oak tabletop
                let matPad = 15 * unit
                RoundedRectangle(cornerRadius: 20 * unit, style: .continuous)
                    .fill(LinearGradient(colors: [MiniGamePalette.parchmentTop.opacity(0.92), MiniGamePalette.parchmentBottom.opacity(0.88)], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20 * unit, style: .continuous)
                            .stroke(MiniGamePalette.goldStroke, lineWidth: 2.5 * unit)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16 * unit, style: .continuous)
                            .stroke(MiniGamePalette.woodBottom.opacity(0.28), lineWidth: 1.2 * unit)
                            .padding(5 * unit)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 14 * unit, y: 6 * unit)
                    .frame(width: layout.gridSize.width + matPad * 2, height: layout.gridSize.height + matPad * 2)
                    .position(x: layout.gridOrigin.x + layout.gridSize.width / 2, y: layout.gridOrigin.y + layout.gridSize.height / 2)

                // 2) Card Grid — exact coordinates shared with MiniGameTapLayer (direct click to flip!)
                ForEach(m.cards.indices, id: \.self) { i in
                    let up = m.faceUp.contains(i)
                    let state: MemoryCardView.Highlight = {
                        if m.owner[m.cards[i].pair] != nil { return .matched }
                        if up && m.phase == .judging { return .pairReady }
                        if up && m.phase == .mismatch { return .mismatch }
                        return .normal
                    }()
                    let hovered = model.hoveredMemoryCard == i && m.canFlip(i)
                    MemoryCardView(
                        card: m.cards[i],
                        number: i + 1,
                        up: up,
                        owner: m.owner[m.cards[i].pair].map(model.tint),
                        highlight: state,
                        hovered: hovered,
                        shaking: state == .mismatch && mismatchShake,
                        size: layout.cardSize,
                        unit: unit
                    )
                    .position(layout.cardCenter(i))
                    .zIndex(hovered ? 420 : (up ? 380 : 300))
                }

                // 3) Right-Side Frosted Meadow-Glass Treasure Standings + Scale Badge
                VStack(alignment: .leading, spacing: 10 * unit) {
                    HStack(spacing: 6 * unit) {
                        Image("MiniGameChestOpen").resizable().interpolation(.none).scaledToFit()
                            .frame(width: 22 * unit, height: 22 * unit)
                        Text("已寻获 \(m.owner.count) / \(m.pairCount) 对")
                            .font(.system(size: 16 * unit, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(MiniGamePalette.ink)
                        Spacer(minLength: 0)
                        Text("\(m.cards.count)张")
                            .font(.system(size: 13 * unit, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8 * unit).padding(.vertical, 2 * unit)
                            .background(Capsule().fill(MiniGamePalette.goldDeep))
                    }
                    .padding(.horizontal, 12 * unit).padding(.vertical, 7 * unit)
                    .frame(width: layout.sideWidth)
                    .background(RoundedRectangle(cornerRadius: 12 * unit, style: .continuous).fill(Color.white.opacity(0.86)))
                    .overlay(RoundedRectangle(cornerRadius: 12 * unit, style: .continuous).stroke(MiniGamePalette.gold.opacity(0.55), lineWidth: 1.5 * unit))

                    ForEach(m.sides) { side in
                        let turn = m.current?.id == side.id && !m.finished
                        let sideColor = model.tint(side.id)
                        let compactRow = m.sides.count >= 6
                        HStack(spacing: 10 * unit) {
                            HStack(spacing: -10 * unit) {
                                ForEach(side.members.prefix(2), id: \.self) { id in
                                    MiniGameFace(student: model.student(id), size: (compactRow ? 32 : 38) * unit, tint: sideColor)
                                }
                            }
                            VStack(alignment: .leading, spacing: 1 * unit) {
                                Text(side.name)
                                    .font(.system(size: (compactRow ? 17 : 20) * unit, weight: .heavy, design: .rounded))
                                    .foregroundStyle(MiniGamePalette.ink)
                                    .lineLimit(1).minimumScaleFactor(0.65)
                                if turn {
                                    Text("当前翻牌")
                                        .font(.system(size: 11.5 * unit, weight: .heavy, design: .rounded))
                                        .foregroundStyle(MiniGamePalette.goldDeep)
                                }
                            }
                            Spacer(minLength: 4 * unit)
                            Image("MiniGameChestOpen")
                                .resizable().interpolation(.none).scaledToFit()
                                .frame(width: (compactRow ? 24 : 28) * unit, height: (compactRow ? 24 : 28) * unit)
                            Text("\(m.pairs(of: side.id))")
                                .font(.system(size: (compactRow ? 23 : 27) * unit, weight: .black, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(MiniGamePalette.ink)
                        }
                        .padding(.horizontal, 13 * unit).padding(.vertical, (compactRow ? 7 : 9) * unit)
                        .frame(width: layout.sideWidth)
                        .background(RoundedRectangle(cornerRadius: 15 * unit, style: .continuous).fill(Color.white.opacity(turn ? 0.92 : 0.74)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15 * unit, style: .continuous)
                                .stroke(turn ? AnyShapeStyle(MiniGamePalette.goldStroke) : AnyShapeStyle(Color.white.opacity(0.8)), lineWidth: (turn ? 3.5 : 1.5) * unit)
                        )
                        .shadow(color: turn ? MiniGamePalette.gold.opacity(0.45) : .black.opacity(0.18), radius: (turn ? 12 : 6) * unit, y: 3 * unit)
                        .scaleEffect(turn ? 1.03 : 1.0)
                    }
                }
                .position(x: layout.sideX, y: 358 * unit)
                .zIndex(340)

                // 4) Pinpoint Per-Card PixelFX bursts (flip spark / pair resonance / treasure chest claim!)
                ForEach(bursts) { b in
                    HD2DPixelFXEffect(clipID: b.clip, playedAt: fxAt, anchor: b.anchor, pixelScale: b.scale, delay: b.delay)
                        .zIndex(540)
                }
            }
            .frame(width: 1280 * unit, height: 720 * unit)
            .onChange(of: model.memoryFX) { _, event in
                guard let event, let m = model.memory else { return }
                let layout = MemoryBoardLayout(count: m.cards.count, unit: unit)
                let now = Date()
                var list: [CardBurst] = []
                var nid = 0
                switch event.kind {
                case .flip:
                    for idx in event.indices {
                        let c = layout.cardCenter(idx)
                        nid += 1; list.append(CardBurst(id: nid, clip: "impacts_hit_spark_10", anchor: CGPoint(x: c.x, y: c.y + 12 * unit), scale: 1.25 * unit, delay: 0))
                    }
                case .pairReady:
                    for (k, idx) in event.indices.enumerated() {
                        let c = layout.cardCenter(idx)
                        nid += 1; list.append(CardBurst(id: nid, clip: "holy_blessing_17", anchor: CGPoint(x: c.x, y: c.y + layout.cardSize.height * 0.42), scale: 1.35 * unit, delay: Double(k) * 0.05))
                    }
                case .claimed:
                    for (k, idx) in event.indices.enumerated() {
                        let c = layout.cardCenter(idx)
                        nid += 1; list.append(CardBurst(id: nid, clip: "collectGold", anchor: CGPoint(x: c.x, y: c.y + 24 * unit), scale: 1.75 * unit, delay: Double(k) * 0.06))
                    }
                    nid += 1; list.append(CardBurst(id: nid, clip: "sonic_anthem_burst", anchor: CGPoint(x: layout.sideX, y: 382 * unit), scale: 1.55 * unit, delay: 0.14))
                case .mismatch:
                    withAnimation(.default.repeatCount(4, autoreverses: true).speed(6)) { mismatchShake = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { mismatchShake = false }
                }
                if !list.isEmpty {
                    bursts = list
                    fxAt = now
                }
            }
        }
    }
}

private struct MemoryCardView: View {
    enum Highlight { case normal, pairReady, mismatch, matched }
    let card: MemoryMatch.Card
    let number: Int
    let up: Bool
    let owner: Color?
    let highlight: Highlight
    var hovered = false
    var shaking = false
    let size: CGSize
    let unit: CGFloat

    var body: some View {
        let shown = up || owner != nil
        let compact = size.width < 145 * unit || size.height < 98 * unit
        let corner = (compact ? 11 : 14) * unit
        let border: AnyShapeStyle = switch highlight {
        case .pairReady: AnyShapeStyle(MiniGamePalette.goldStroke)
        case .mismatch: AnyShapeStyle(Color(red: 0.90, green: 0.28, blue: 0.28))
        case .matched: AnyShapeStyle(Color.white.opacity(0.88))
        case .normal: hovered ? AnyShapeStyle(MiniGamePalette.goldBright) : (shown ? AnyShapeStyle(MiniGamePalette.gold.opacity(0.85)) : AnyShapeStyle(MiniGamePalette.goldStroke))
        }
        let chestSide = min((compact ? 42 : 58) * unit, size.height * 0.56)
        let numSide = min((compact ? 28 : 34) * unit, size.height * 0.36)
        ZStack {
            // Back: deep navy & antique gold treasure chest card with real pixel-art closed chest
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(
                    colors: hovered
                        ? [Color(red: 0.28, green: 0.40, blue: 0.70), Color(red: 0.16, green: 0.25, blue: 0.48)]
                        : [Color(red: 0.20, green: 0.29, blue: 0.54), Color(red: 0.12, green: 0.18, blue: 0.36)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: max(6 * unit, corner - 4 * unit), style: .continuous)
                        .stroke(MiniGamePalette.gold.opacity(hovered ? 0.85 : 0.45), lineWidth: 1.5 * unit)
                        .padding(4 * unit)
                )
                .overlay {
                    HStack(spacing: (compact ? 6 : 10) * unit) {
                        Image("MiniGameChestClosed")
                            .resizable().interpolation(.none).scaledToFit()
                            .frame(width: chestSide, height: chestSide)
                            .shadow(color: .black.opacity(0.45), radius: 4 * unit, y: 2 * unit)
                        Text("\(number)")
                            .font(.system(size: (compact ? 17 : 22) * unit, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(MiniGamePalette.goldBright)
                            .frame(width: numSide, height: numSide)
                            .background(Circle().fill(Color.black.opacity(0.32)))
                            .overlay(Circle().stroke(MiniGamePalette.gold.opacity(0.75), lineWidth: 1.5 * unit))
                    }
                }
                .opacity(shown ? 0 : 1)

            // Front: crisp ivory card with #number + EN/中 tag, or claimed team treasure card
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    owner.map { AnyShapeStyle(LinearGradient(colors: [$0.opacity(0.95), $0.opacity(0.80)], startPoint: .top, endPoint: .bottom)) }
                    ?? AnyShapeStyle(LinearGradient(colors: [Color.white, Color(red: 0.99, green: 0.97, blue: 0.92)], startPoint: .top, endPoint: .bottom))
                )
                .overlay {
                    Text(card.text)
                        .font(.system(size: (compact ? (card.english ? 21 : 23) : (card.english ? 27 : 29)) * unit, weight: .heavy, design: .rounded))
                        .foregroundStyle(owner != nil ? .white : MiniGamePalette.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.40)
                        .padding(.horizontal, (compact ? 8 : 12) * unit)
                        .padding(.top, (compact ? 12 : 15) * unit)
                        .padding(.bottom, 5 * unit)
                }
                .overlay(alignment: .topLeading) {
                    Text("#\(number)")
                        .font(.system(size: (compact ? 10 : 12) * unit, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(owner != nil ? .white.opacity(0.84) : MiniGamePalette.ink.opacity(0.5))
                        .padding(.horizontal, 6 * unit).padding(.vertical, 2 * unit)
                        .background(Capsule().fill(owner != nil ? Color.black.opacity(0.22) : Color.black.opacity(0.06)))
                        .padding(5 * unit)
                }
                .overlay(alignment: .topTrailing) {
                    if owner != nil {
                        Image("MiniGameChestOpen")
                            .resizable().interpolation(.none).scaledToFit()
                            .frame(width: (compact ? 22 : 28) * unit, height: (compact ? 22 : 28) * unit)
                            .padding(5 * unit)
                    } else {
                        Text(card.english ? "EN" : "中")
                            .font(.system(size: (compact ? 9.5 : 11) * unit, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6 * unit).padding(.vertical, 2 * unit)
                            .background(Capsule().fill(card.english ? Color(red: 0.24, green: 0.54, blue: 0.88) : Color(red: 0.86, green: 0.54, blue: 0.16)))
                            .padding(5 * unit)
                    }
                }
                .opacity(shown ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .frame(width: size.width, height: size.height)
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(border, lineWidth: (highlight == .pairReady || highlight == .mismatch ? 4 : hovered ? 3.2 : 2.2) * unit)
        )
        .rotation3DEffect(.degrees(shown ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        .scaleEffect(hovered ? 1.045 : (shown ? (highlight == .pairReady ? 1.03 : 1.0) : 0.97))
        .offset(x: shaking ? 7 * unit : 0, y: hovered ? -3 * unit : 0)
        .shadow(color: (highlight == .pairReady || hovered) ? MiniGamePalette.gold.opacity(0.68) : Color.black.opacity(0.24), radius: (highlight == .pairReady || hovered ? 12 : 5) * unit, y: 3 * unit)
        .animation(.spring(response: 0.36, dampingFraction: 0.78), value: shown)
        .animation(.easeOut(duration: 0.14), value: hovered)
    }
}

// MARK: - 5. 擂台王 (100% Native HD-2D PvP Meadow Tournament on `MiniGameArenaRing`!)

private struct ArenaStage: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var clashAt: Date?
    @State private var fxAt: Date?
    @State private var lastResult: ArenaKing.Result?
    @State private var lastBonus = false
    @State private var champAction: HD2DBattleHero.Action = .ready
    @State private var chalAction: HD2DBattleHero.Action = .ready

    var body: some View {
        if let a = model.arena {
            let champFoot = CGPoint(x: 468 * unit, y: 506 * unit)
            let chalFoot = CGPoint(x: 812 * unit, y: 506 * unit)
            let clashPoint = CGPoint(x: 640 * unit, y: 458 * unit)

            ZStack(alignment: .topLeading) {
                // 1) Focal-Plane Circular Stone & Gold Tournament Stage (`MiniGameArenaRing`) planted solidly on
                // `MiniGameSceneArena`'s flat sunlit packed-earth tournament courtyard!
                HD2DProp(name: "MiniGameArenaRing", width: 720 * unit, depthBlur: 0, shadow: true)
                    .position(x: 640 * unit, y: 482 * unit)
                    .zIndex(280)

                // Back-layer victory / streak aura behind the Champion
                if lastResult == .defended || lastResult == .dethroned {
                    HD2DPixelFXEffect(
                        clipID: lastBonus ? "seraph_aegis_descend" : (lastResult == .dethroned ? "oath_banner_plant" : "warlord_roar_wave"),
                        playedAt: fxAt, anchor: champFoot, pixelScale: 2.05 * unit, delay: 0.18, layer: .back
                    )
                    .zIndex(390)
                }

                // 2) Champion (Left, facing RIGHT) vs Challenger (Right, mirrored facing LEFT) — Real Animated Battle Heroes!
                duelist(id: a.champion, champion: true, streak: a.streak, action: champAction)
                    .id("champ-\(a.champion)")
                    .position(x: champFoot.x, y: 400 * unit)
                    .zIndex(420)

                vsEmblem
                    .position(x: 640 * unit, y: 386 * unit)
                    .zIndex(430)

                duelist(id: a.challenger, champion: false, streak: 0, action: chalAction)
                    .id("chal-\(a.challenger)")
                    .position(x: chalFoot.x, y: 400 * unit)
                    .zIndex(420)

                // 3) Pinpoint Authentic Outcome PixelFX (clash midpoint + champion coronation / streak glory / miss smoke!)
                if lastResult == .dethroned {
                    HD2DPixelFXEffect(clipID: "skybreaker_lance", playedAt: fxAt, anchor: clashPoint, pixelScale: 1.9 * unit, direction: -1)
                        .zIndex(520)
                    HD2DPixelFXEffect(clipID: "holy_sunburst_39", playedAt: fxAt, anchor: CGPoint(x: champFoot.x, y: champFoot.y - 76 * unit), pixelScale: 2.15 * unit, delay: 0.14)
                        .zIndex(525)
                    HD2DPixelFXEffect(clipID: "oath_banner_plant", playedAt: fxAt, anchor: champFoot, pixelScale: 1.95 * unit, delay: 0.18, layer: .front)
                        .zIndex(530)
                } else if lastResult == .defended {
                    HD2DPixelFXEffect(clipID: "melee_heavy_cleave_51", playedAt: fxAt, anchor: CGPoint(x: clashPoint.x - 16 * unit, y: clashPoint.y + 18 * unit), pixelScale: 2.0 * unit, direction: 1)
                        .zIndex(520)
                    HD2DPixelFXEffect(clipID: "impacts_crit_hit_3", playedAt: fxAt, anchor: CGPoint(x: clashPoint.x + 28 * unit, y: clashPoint.y + 18 * unit), pixelScale: 1.85 * unit, delay: 0.08)
                        .zIndex(524)
                    HD2DPixelFXEffect(
                        clipID: lastBonus ? "seraph_aegis_descend" : "warlord_roar_wave",
                        playedAt: fxAt, anchor: champFoot, pixelScale: 2.05 * unit, delay: 0.18, layer: .front
                    )
                    .zIndex(530)
                } else if lastResult == .nobody {
                    HD2DPixelFXEffect(clipID: "bomb_star_smoke", playedAt: fxAt, anchor: CGPoint(x: clashPoint.x, y: clashPoint.y + 38 * unit), pixelScale: 1.85 * unit)
                        .zIndex(520)
                }

                // 4) Top-Left `下一位挑战` & Top-Right `胜场榜` in Frosted Meadow Glass (zero collision with fighters!)
                if !a.line.isEmpty {
                    VStack(alignment: .leading, spacing: 6 * unit) {
                        Text("下一位挑战")
                            .font(.system(size: 14 * unit, weight: .heavy, design: .rounded))
                            .foregroundStyle(MiniGamePalette.ink.opacity(0.75))
                        HStack(spacing: 8 * unit) {
                            ForEach(a.line.prefix(5), id: \.self) { id in
                                VStack(spacing: 2 * unit) {
                                    MiniGameFace(student: model.student(id), size: 42 * unit, tint: model.studentTint(id))
                                    Text(model.name(id))
                                        .font(.system(size: 12 * unit, weight: .bold, design: .rounded))
                                        .foregroundStyle(MiniGamePalette.ink)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14 * unit).padding(.vertical, 10 * unit)
                    .background(RoundedRectangle(cornerRadius: 16 * unit, style: .continuous).fill(Color.white.opacity(0.86)))
                    .overlay(RoundedRectangle(cornerRadius: 16 * unit, style: .continuous).stroke(.white, lineWidth: 1.5 * unit))
                    .shadow(color: .black.opacity(0.18), radius: 8 * unit, y: 3 * unit)
                    .position(x: 20 * unit + (CGFloat(min(5, a.line.count)) * 50 + 28) * unit / 2, y: 58 * unit)
                    .zIndex(700)
                }

                VStack(alignment: .leading, spacing: 5 * unit) {
                    HStack(spacing: 6 * unit) {
                        Image("MiniGameCrown").resizable().interpolation(.none).scaledToFit().frame(width: 20 * unit, height: 20 * unit)
                        Text("胜场榜").font(.system(size: 15 * unit, weight: .heavy, design: .rounded)).foregroundStyle(MiniGamePalette.ink)
                    }
                    ForEach(Array(a.ranking(model.students.map(\.id)).prefix(6).enumerated()), id: \.element) { rank, id in
                        HStack(spacing: 6 * unit) {
                            Text("\(rank + 1)")
                                .font(.system(size: 13 * unit, weight: .black, design: .rounded))
                                .foregroundStyle(rank == 0 ? MiniGamePalette.goldDeep : MiniGamePalette.ink.opacity(0.45))
                                .frame(width: 16 * unit)
                            Text(model.name(id))
                                .lineLimit(1)
                                .foregroundStyle(MiniGamePalette.ink)
                            Spacer()
                            Text("\(a.wins[id] ?? 0)")
                                .monospacedDigit()
                                .foregroundStyle(MiniGamePalette.goldDeep)
                        }
                        .font(.system(size: 15 * unit, weight: .bold, design: .rounded))
                    }
                }
                .frame(width: 176 * unit)
                .padding(.horizontal, 14 * unit).padding(.vertical, 10 * unit)
                .background(RoundedRectangle(cornerRadius: 16 * unit, style: .continuous).fill(Color.white.opacity(0.86)))
                .overlay(RoundedRectangle(cornerRadius: 16 * unit, style: .continuous).stroke(.white, lineWidth: 1.5 * unit))
                .shadow(color: .black.opacity(0.18), radius: 8 * unit, y: 3 * unit)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 14 * unit).padding(.trailing, 20 * unit)
                .zIndex(700)
            }
            .frame(width: 1280 * unit, height: 720 * unit)
            .onChange(of: model.beat) { _, _ in
                guard let a = model.arena else { return }
                let now = Date()
                clashAt = now
                lastResult = a.last
                lastBonus = a.bonus
                switch a.last {
                case .defended:
                    champAction = .attack
                    chalAction = .hurt
                    fxAt = now
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        champAction = .victory
                        chalAction = .ready
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { champAction = .ready }
                    }
                case .dethroned:
                    champAction = .victory
                    chalAction = .ready
                    fxAt = now
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { champAction = .ready }
                case .nobody:
                    champAction = .hurt
                    chalAction = .hurt
                    fxAt = now
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { champAction = .ready; chalAction = .ready }
                case nil: break
                }
            }
        }
    }

    private var vsEmblem: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [MiniGamePalette.gold.opacity(0.45), Color.orange.opacity(0.18), .clear], center: .center, startRadius: 4 * unit, endRadius: 68 * unit))
                .frame(width: 136 * unit, height: 136 * unit)
            Text("VS")
                .font(.system(size: 68 * unit, weight: .black, design: .rounded))
                .italic()
                .foregroundStyle(LinearGradient(colors: [MiniGamePalette.goldBright, Color(red: 1.0, green: 0.44, blue: 0.16), Color(red: 0.84, green: 0.14, blue: 0.16)], startPoint: .top, endPoint: .bottom))
                .shadow(color: MiniGamePalette.battlePlate.opacity(0.9), radius: 3 * unit, y: 3 * unit)
        }
    }

    private func duelist(id: String, champion: Bool, streak: Int, action: HD2DBattleHero.Action) -> some View {
        let crownSize = (48 + CGFloat(min(streak, 5)) * 5) * unit
        return VStack(spacing: -8 * unit) {
            ZStack {
                if champion {
                    Circle()
                        .fill(RadialGradient(colors: [MiniGamePalette.gold.opacity(0.55), .clear], center: .center, startRadius: 4 * unit, endRadius: crownSize * 0.85))
                        .frame(width: crownSize * 1.6, height: crownSize * 1.4)
                    Image("MiniGameCrown")
                        .resizable().interpolation(.none).scaledToFit()
                        .frame(width: crownSize, height: crownSize)
                        .shadow(color: .black.opacity(0.42), radius: 4 * unit, y: 2 * unit)
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 36 * unit, weight: .black))
                        .foregroundStyle(LinearGradient(colors: [MiniGamePalette.goldBright, .orange], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.55), radius: 4 * unit, y: 2 * unit)
                }
            }
            .frame(height: 58 * unit)
            .offset(y: 26 * unit)
            .zIndex(5)

            if let student = model.student(id) {
                HD2DBattleHero(
                    student: student,
                    height: 242 * unit,
                    mirrored: !champion,
                    action: action,
                    actionAt: clashAt,
                    ringColor: champion ? MiniGamePalette.gold : model.studentTint(id)
                )
            }

            // Battle-vitals-styled dark nameplate cleanly over the front stone rim
            VStack(spacing: 1 * unit) {
                Text(model.name(id))
                    .font(.system(size: 24 * unit, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(champion ? (streak > 0 ? "擂主 · 连胜 \(streak)" : "现任擂主") : "挑战者")
                    .font(.system(size: 13 * unit, weight: .heavy, design: .rounded))
                    .foregroundStyle(champion ? MiniGamePalette.goldBright : MiniGamePalette.battleRim)
            }
            .padding(.horizontal, 18 * unit)
            .padding(.vertical, 6 * unit)
            .background(
                RoundedRectangle(cornerRadius: 10 * unit, style: .continuous)
                    .fill(MiniGamePalette.battlePlate.opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10 * unit, style: .continuous)
                    .stroke(champion ? AnyShapeStyle(MiniGamePalette.goldStroke) : AnyShapeStyle(MiniGamePalette.battleRim.opacity(0.82)), lineWidth: 2 * unit)
            )
            .shadow(color: .black.opacity(0.4), radius: 6 * unit, y: 3 * unit)
            .offset(y: 4 * unit)
        }
        .transition(.asymmetric(insertion: .scale(scale: 0.82).combined(with: .opacity), removal: .opacity))
    }
}
