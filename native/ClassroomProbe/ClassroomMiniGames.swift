import SwiftUI
import UIKit
import ClassroomGameCore
import MeadowWorldSupport
import MeadowBattleSupport

// MARK: - 课堂小游戏: boss, camp, race, memory, arena (about 10 minutes each)
//
// Built directly on the game's own HD-2D battle visual language:
// - 4-layer depth-of-field plates via `MeadowBattlePlateProcessor` (farForest / focus-masked ground / midground / foreground)
// - Native game props (`CampTent`, `WatchTower`, `NodeBossSanctum`, `NodeCombatOutpost`, `NodeRewardCache`, `NodeWaystone`,
//   `OakA`, `OakB`, `Pines`, `RockHigh`, `RockLow`, `Fence`, `Banner`, `Flowers`) + matching pixel props
//   (`MiniGameBrazier`, `MiniGameSteppingStone`, `MiniGameArenaRing`, `MiniGameFinishArch`, `MiniGameChestClosed/Open`, `MiniGameCrown`)
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
    struct Student: Identifiable { let id: String; let name: String; let look: PixelHeroLook; let seat: Int }

    let kind: Kind
    let students: [Student]
    let isTeamMode: Bool
    /// Side id → colour index (teams by their order, students by seat).
    let tints: [String: Int]
    /// Student id → colour index (matches team color when in team mode, else seat color).
    let studentTints: [String: Int]
    @Published var boss: BossRaid?
    @Published var camp: CampDefense?
    @Published var race: RaceTrack?
    @Published var memory: MemoryMatch?
    @Published var arena: ArenaKing?
    /// Bumped each time a round is applied (the TV animates on it).
    @Published var beat = 0
    /// The line under the board: what just happened.
    @Published var banner: String?
    @Published var rewarded = false
    private var dice: MiniGameDice
    private var pending: (round: MiniGameRound, token: Int?)?

    init(kind: Kind, state: GameState, playerIDs: [String], seats: (String) -> Int, bank: [QuizQuestion], course: [Int]) {
        self.kind = kind
        let seed = UInt64(Date().timeIntervalSince1970 * 1000)
        dice = MiniGameDice(seed: seed)
        let ordered = state.players.filter { !$0.host }.sorted { (seats($0.id), $0.id) < (seats($1.id), $1.id) }
        students = ordered.map { u in Student(id: u.id, name: u.shortName, look: .battle(unit: u, slot: playerIDs.firstIndex(of: u.id) ?? 0), seat: seats(u.id)) }
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
            } else {
                st[u.id] = max(0, seats(u.id) - 1)
            }
        }
        studentTints = st
        // Prewarm full-body battle sprites & pixel VFX in background for instant crisp HD-2D rendering.
        PixelHeroAtlas.prepare(battle: students.map(\.look))
        MeadowPixelFX.prewarm()
        switch kind {
        case .boss: boss = BossRaid(monster: dice.shuffle(["caveTroll", "ruinDragon", "stoneGuardian"])[0], students: ordered.count)
        case .camp: camp = CampDefense()
        case .race: race = RaceTrack(sides: sides, seed: seed)
        case .memory:
            let pairs = dice.shuffle(MemoryMatch.candidates(bank, among: course)).prefix(8)
            memory = MemoryMatch(pairs: Array(pairs), sides: sides, seed: seed)
        case .arena: arena = ArenaKing(players: ordered.map(\.id))
        }
    }
    func name(_ id: String) -> String { students.first { $0.id == id }?.name ?? race?.sides.first { $0.id == id }?.name ?? memory?.sides.first { $0.id == id }?.name ?? id }
    func student(_ id: String) -> Student? { students.first { $0.id == id } }
    func tint(_ id: String) -> Color { MiniGamePalette.side(tints[id] ?? 0) }
    func studentTint(_ id: String) -> Color { MiniGamePalette.side(studentTints[id] ?? 0) }
    static func monsterName(_ id: String) -> String {
        switch id {
        case "caveTroll": "洞穴巨魔"
        case "ruinDragon": "遗迹巨龙"
        case "stoneGuardian": "石像守卫"
        case "slime": "史莱姆"
        case "wolf": "森林恶狼"
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
        case .race: race?.current.map { s in isTeamMode ? "\(s.name)（\(s.members.map(name).joined(separator: "、"))）" : s.name }
        case .arena: arena.map { "\(name($0.champion)) 对 \(name($0.challenger))" }
        default: nil
        }
    }

    /// A question was answered: applied once the answer card is gone (or straight away when none shows).
    func queue(_ round: MiniGameRound, quiz token: Int?) {
        guard !finished, kind != .memory else { return }
        if let p = pending { apply(p.round) }
        pending = (round, token)
        if token == nil { flush(quiz: nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            guard let self, let p = self.pending, p.round == round else { return }
            self.pending = nil; self.apply(p.round)
        }
    }
    func flush(quiz token: Int?) {
        guard let p = pending, token == nil || token != p.token else { return }
        pending = nil
        apply(p.round)
    }
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
                race?.resolve(q, dice: &dice)
                if let r = race { banner = raceLine(r) }
            case .arena:
                guard let before = arena else { return }
                arena?.resolve(q)
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

    // Memory: the teacher turns the cards and judges the reading.
    func flip(_ i: Int) {
        guard var m = memory, m.canFlip(i) else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { m.flip(i); memory = m }
        switch m.phase {
        case .judging:
            banner = "配对成功！\(m.current.map { name($0.id) } ?? "")大声读出来"
            beat += 1
        case .mismatch:
            banner = "没配上，记住位置哦"
            beat += 1
            let up = m.faceUp
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
                guard let self, self.memory?.faceUp == up else { return }
                self.turnBack()
            }
        case .picking: banner = nil
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
        withAnimation(.spring(response: 0.48, dampingFraction: 0.75)) {
            let who = m.current.map { name($0.id) } ?? ""
            m.judge(right: right); memory = m; beat += 1
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
    func startMiniGame(_ kind: MiniGameModel.Kind) {
        guard let c = campaign else { message = "先打开一个行程（学生名单）再玩小游戏。"; revision += 1; return }
        let students = c.engine.state.players.filter { !$0.host }
        if kind == .arena, students.count < 2 { message = "擂台王至少要两名学生。"; revision += 1; return }
        if kind == .memory, MemoryMatch.candidates(c.quizBank, among: c.courseIndices).count < 4 {
            message = "翻牌寻宝需要当前课程至少 4 张★/★★单词闪卡。"; revision += 1; return
        }
        if kind != .memory, c.courseIndices.isEmpty { message = "当前课程没有题，先在题库里选课或导入。"; revision += 1; return }
        if quizActive { abortQuiz() }
        let model = MiniGameModel(kind: kind, state: c.engine.state, playerIDs: c.playerIDs, seats: { [weak self] in self?.seatNumber($0) ?? 0 },
                                  bank: c.quizBank, course: c.courseIndices)
        model.banner = kind.rule
        withAnimation(.easeOut(duration: 0.3)) { miniGame = model }
        message = "\(kind.title)开始：" + (kind == .memory ? "直接点舞台上的牌，或在下方点数字翻开" : "点“出题”或按 ⇧Q 出全班题")
        revision += 1
    }
    func endMiniGame() {
        withAnimation(.easeIn(duration: 0.25)) { miniGame = nil }
        message = "小游戏已结束"; revision += 1
    }
    /// The answers just sent to a question (class or one student) go to the game on screen.
    func feedMiniGame(question index: Int, answers: [MiniGameAnswer]) {
        guard let g = miniGame, let c = campaign, c.quizBank.indices.contains(index) else { return }
        g.queue(MiniGameRound(level: c.quizBank[index].level, answers: answers), quiz: quiz?.token)
    }
    /// The question for the next turn: the class question (its panel picks who answered).
    func miniGameAsk() {
        guard let g = miniGame, !g.finished else { return }
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
                if let m = model.memory, !model.finished {
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
                if model.finished {
                    Button { game.rewardMiniGameWinners() } label: { Label(model.rewarded ? "已发奖励" : "获胜者 +5 积分", systemImage: "star.fill") }
                        .buttonStyle(GlassIconButtonStyle(tint: .orange, prominent: !model.rewarded)).disabled(model.rewarded || model.winners.isEmpty)
                    Button { game.startMiniGame(model.kind) } label: { Label("再来一局", systemImage: "arrow.clockwise") }.buttonStyle(GlassIconButtonStyle())
                } else if model.kind == .arena {
                    Button { game.rewardMiniGameWinners() } label: { Label(model.rewarded ? "已发奖励" : "给领先者 +5 积分", systemImage: model.rewarded ? "star.fill" : "star") }
                        .buttonStyle(GlassIconButtonStyle(tint: .orange)).disabled(model.rewarded || model.winners.isEmpty)
                }
                if model.kind != .memory && !model.finished {
                    Button { game.miniGameAsk() } label: { Label("出题 ⇧Q", systemImage: "questionmark.bubble.fill") }
                        .buttonStyle(GlassIconButtonStyle(prominent: true)).disabled(game.quiz?.mode == .classwide && game.quiz?.attempt == nil)
                }
                Button { game.endMiniGame() } label: { Label("结束", systemImage: "xmark.circle") }.buttonStyle(GlassIconButtonStyle(tint: .red))
            }
            if let m = model.memory { MemoryTeacherGrid(model: model, memory: m) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8).glassPanel(radius: 18, padding: 0)
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
                Text(m.finished ? "全部找到" : "轮到 \(m.current.map { model.name($0.id) } ?? "") · " + (m.phase == .judging ? "读对了吗？" : m.phase == .mismatch ? "没配上" : "点牌翻开"))
            }
        }
    }
}

/// Fixed full-width memory card strip for the teacher (zero collapse / jump when judging buttons appear on header row).
private struct MemoryTeacherGrid: View {
    @ObservedObject var model: MiniGameModel
    let memory: MemoryMatch
    var body: some View {
        let cols = max(4, (memory.cards.count + 1) / 2)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: cols)
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(memory.cards.indices, id: \.self) { i in
                let card = memory.cards[i], up = memory.faceUp.contains(i), done = memory.matched(i)
                let clickable = memory.canFlip(i)
                Button { model.flip(i) } label: {
                    HStack(spacing: 4) {
                        if done {
                            Image("MiniGameChestOpen").resizable().interpolation(.none).scaledToFit().frame(width: 15, height: 15)
                        }
                        Text(up || done ? card.text : "\(i + 1)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.55)
                    }
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .foregroundStyle(done ? .white : MiniGamePalette.ink)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(done ? model.tint(memory.owner[card.pair] ?? "").opacity(0.92) : up ? MiniGamePalette.gold.opacity(0.65) : Color.white.opacity(0.75))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(up ? MiniGamePalette.goldDeep : (done ? Color.white.opacity(0.35) : Color.black.opacity(0.08)), lineWidth: up ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
                .allowsHitTesting(clickable)
                .opacity(clickable || done || up ? 1 : 0.55)
            }
        }
        .frame(maxWidth: .infinity)
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
        let cols = count >= 8 ? 4 : (count >= 6 ? 3 : 2)
        let r = max(1, (count + cols - 1) / cols)
        self.columns = cols
        self.rows = r
        let cw: CGFloat = (cols == 4 ? 186 : 212) * unit
        let ch: CGFloat = (r >= 4 ? 108 : r == 3 ? 134 : 164) * unit
        let g: CGFloat = (r >= 4 ? 12 : 16) * unit
        self.cardSize = CGSize(width: cw, height: ch)
        self.gap = g
        let gw = CGFloat(cols) * cw + CGFloat(cols - 1) * g
        let gh = CGFloat(r) * ch + CGFloat(r - 1) * g
        self.gridSize = CGSize(width: gw, height: gh)
        let sw = 282 * unit
        let splitGap = 28 * unit
        let totalW = gw + splitGap + sw
        let gx = (1280 * unit - totalW) / 2
        let gy = 348 * unit - gh / 2
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

/// Interactive tap layer on teacher preview: prevents map/book bleed-through & enables direct card flipping in Memory.
struct MiniGameTapLayer: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    var body: some View {
        if let model = game.miniGame, game.quiz == nil, !game.laser.on {
            MiniGameTapContent(model: model)
        }
    }
}

private struct MiniGameTapContent: View {
    @ObservedObject var model: MiniGameModel
    var body: some View {
        GeometryReader { g in
            let unit = min(g.size.height / 720, g.size.width / 1280)
            ZStack {
                Color.clear.contentShape(Rectangle())
                if let m = model.memory {
                    let layout = MemoryBoardLayout(count: m.cards.count, unit: unit)
                    ZStack(alignment: .topLeading) {
                        ForEach(m.cards.indices, id: \.self) { i in
                            if m.canFlip(i) {
                                Button { model.flip(i) } label: { Color.clear }
                                    .buttonStyle(.plain)
                                    .contentShape(RoundedRectangle(cornerRadius: 15 * unit))
                                    .frame(width: layout.cardSize.width, height: layout.cardSize.height)
                                    .position(layout.cardCenter(i))
                                    .accessibilityLabel("舞台牌 \(i + 1)")
                            }
                        }
                    }
                    .frame(width: 1280 * unit, height: 720 * unit)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

// MARK: - HD-2D Shared Battle-Engine Stage Components

/// Loads & caches the native 4-layer HD-2D wide meadow plates through `MeadowBattlePlateProcessor`
/// (optical far-forest blur, CoreImage tilt-shift focus-masked ground, soft midground, crisp foreground frame).
private enum HD2DPlateCache {
    static var farForest: UIImage? { MeadowBattlePlateProcessor.image(named: "MeadowCampWideFarForest", role: .farForest) }
    static var ground: UIImage? { MeadowBattlePlateProcessor.image(named: "MeadowCampWideGround", role: .ground) }
    static var midground: UIImage? { MeadowBattlePlateProcessor.image(named: "MeadowCampWideMidground", role: .midground) }
    static var foreground: UIImage? { MeadowBattlePlateProcessor.image(named: "MeadowCampWideForeground", role: .foreground) }
}

/// Full-bleed native HD-2D Meadow Battle backdrop (farForest + tilt-shift ground + optional midground)
/// with per-game atmospheric grade matching `MeadowPostProcess`.
private struct HD2DMeadowBackdrop: View {
    let kind: MiniGameModel.Kind
    let size: CGSize
    var body: some View {
        let plateH = max(size.height * 1.10, size.width * 1201 / 2618)
        let plateW = plateH * 2618 / 1201
        let yShift: CGFloat = kind == .race ? -plateH * 0.02 : -plateH * 0.04
        ZStack {
            Color(red: 0.14, green: 0.20, blue: 0.12)
            if let far = HD2DPlateCache.farForest {
                Image(uiImage: far).resizable().frame(width: plateW, height: plateH).offset(y: yShift)
            }
            if let gnd = HD2DPlateCache.ground {
                Image(uiImage: gnd).resizable().frame(width: plateW, height: plateH).offset(y: yShift)
            }
            if kind == .camp || kind == .arena, let mid = HD2DPlateCache.midground {
                Image(uiImage: mid).resizable().frame(width: plateW, height: plateH).offset(y: yShift)
            }
            // Scene-specific HD-2D color grading & optical depth bokeh
            if kind == .boss {
                // Twilight sanctum dusk: deep cool indigo shadows + subtle warm horizon glow
                LinearGradient(
                    colors: [Color(red: 0.09, green: 0.07, blue: 0.22).opacity(0.66), Color(red: 0.14, green: 0.10, blue: 0.26).opacity(0.42), Color(red: 0.08, green: 0.09, blue: 0.16).opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
            } else if kind == .memory {
                // Warm lantern-lit shallow-DoF background behind the wooden treasure table
                Color(red: 0.18, green: 0.13, blue: 0.08).opacity(0.28)
            } else {
                // Warm golden-hour highlights matching MeadowPostProcess.Settings.hd2d
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.90, blue: 0.66).opacity(0.14), .clear, Color(red: 0.05, green: 0.09, blue: 0.05).opacity(0.16)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        }
        .blur(radius: kind == .memory ? 6.5 : 0)
        .scaleEffect(kind == .memory ? 1.05 : 1.0)
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// Foreground HD-2D framing (`MeadowCampWideForeground` oak trunks + wildflowers) + drifting diagonal sunbeams,
/// floating golden sunlit dust motes (or embers for Boss), and subtle HD-2D diorama vignette.
private struct HD2DAtmosphereOverlay: View {
    let kind: MiniGameModel.Kind
    let size: CGSize
    var showForegroundFrame = true

    var body: some View {
        let plateH = max(size.height * 1.10, size.width * 1201 / 2618)
        let plateW = plateH * 2618 / 1201
        let yShift: CGFloat = kind == .race ? -plateH * 0.02 : -plateH * 0.04
        ZStack {
            if showForegroundFrame, let fg = HD2DPlateCache.foreground {
                Image(uiImage: fg)
                    .resizable()
                    .frame(width: plateW, height: plateH)
                    .offset(y: yShift)
                    .colorMultiply(kind == .boss ? Color(red: 0.56, green: 0.54, blue: 0.76) : .white)
                    .opacity(kind == .race ? 0.68 : 0.92)
            }

            // Drifting volumetric sun shafts (from upper-left, matching MeadowPostProcess) & floating motes
            TimelineView(.animation(minimumInterval: 1.0 / 24)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                Canvas { g, canvasSize in
                    // 1. Soft diagonal golden sun shafts (or violet-amber twilight rays in Boss)
                    let rayColor: Color = kind == .boss
                        ? Color(red: 0.78, green: 0.62, blue: 1.0)
                        : Color(red: 1.0, green: 0.89, blue: 0.65)
                    let rayAlpha: Double = kind == .boss ? 0.055 : (kind == .memory ? 0.06 : 0.095)
                    for i in 0..<4 {
                        let phase = sin(t * 0.22 + Double(i) * 1.7)
                        let x0 = canvasSize.width * (0.06 + Double(i) * 0.24) + phase * 28
                        let w = canvasSize.width * (0.11 + Double(i % 2) * 0.05)
                        var path = Path()
                        path.move(to: CGPoint(x: x0, y: -20))
                        path.addLine(to: CGPoint(x: x0 + w, y: -20))
                        path.addLine(to: CGPoint(x: x0 + w + canvasSize.height * 0.36, y: canvasSize.height + 20))
                        path.addLine(to: CGPoint(x: x0 + canvasSize.height * 0.36, y: canvasSize.height + 20))
                        path.closeSubpath()
                        let alpha = rayAlpha * (0.72 + 0.28 * sin(t * 0.45 + Double(i) * 1.1))
                        g.fill(path, with: .linearGradient(
                            Gradient(colors: [rayColor.opacity(alpha), rayColor.opacity(alpha * 0.45), .clear]),
                            startPoint: CGPoint(x: x0, y: 0),
                            endPoint: CGPoint(x: x0 + canvasSize.height * 0.36, y: canvasSize.height)
                        ))
                    }

                    // 2. Floating golden sunlight dust motes (or glowing warm embers in Boss)
                    let moteCount = kind == .boss ? 22 : 16
                    for i in 0..<moteCount {
                        let seed = Double(i) * 13.7 + 1.3
                        let speed = kind == .boss ? 16.0 : 9.0
                        let cycle = (t * (speed + Double(i % 5) * 3.0) + seed * 37).truncatingRemainder(dividingBy: Double(canvasSize.height + 60))
                        let y = Double(canvasSize.height + 30) - cycle
                        let baseX = (sin(seed * 2.13) * 0.5 + 0.5) * Double(canvasSize.width)
                        let x = baseX + sin(t * 0.7 + seed) * 26.0
                        let r = CGFloat(2.0 + Double(i % 3) * 1.2)
                        let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 2.1 + seed * 1.9))
                        let edgeFade = min(1.0, min(y / 60.0, (Double(canvasSize.height) - y) / 60.0))
                        let a = max(0, twinkle * edgeFade * (kind == .boss ? 0.78 : 0.58))
                        let color: Color = kind == .boss
                            ? (i % 3 == 0 ? Color(red: 1.0, green: 0.78, blue: 0.34) : Color(red: 1.0, green: 0.48, blue: 0.18))
                            : Color(red: 1.0, green: 0.95, blue: 0.72)
                        let glowRect = CGRect(x: x - Double(r * 2.2), y: y - Double(r * 2.2), width: Double(r * 4.4), height: Double(r * 4.4))
                        g.fill(Path(ellipseIn: glowRect), with: .color(color.opacity(a * 0.32)))
                        let coreRect = CGRect(x: x - Double(r), y: y - Double(r), width: Double(r * 2), height: Double(r * 2))
                        g.fill(Path(ellipseIn: coreRect), with: .color(color.opacity(a)))
                    }
                }
            }

            // 3. Restrained HD-2D optical vignette (matches MeadowPostProcess vignette: 0.34)
            RadialGradient(
                colors: [.clear, .clear, Color(red: 0.04, green: 0.06, blue: 0.05).opacity(kind == .boss ? 0.44 : 0.26)],
                center: .center,
                startRadius: min(size.width, size.height) * 0.34,
                endRadius: max(size.width, size.height) * 0.74
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

/// Real animated battle monster (`MeadowMonsterFrames`) with oblique sunlight shadow + crisp impact flash.
private struct HD2DMonster: View {
    let id: String
    let height: CGFloat
    var mirrored = false
    var hurtAt: Date?
    var dead = false
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let isHurt: Bool = {
                guard let at = hurtAt, !dead else { return false }
                let age = context.date.timeIntervalSince(at)
                return age >= 0 && age < 0.6
            }()
            let flashOn: Bool = {
                guard let at = hurtAt, !dead else { return false }
                let age = context.date.timeIntervalSince(at)
                return age >= 0 && age < 0.14
            }()
            let image: UIImage? = {
                if dead { return MeadowMonsterFrames.image(id, index: 39, death: true) }
                if let at = hurtAt, isHurt {
                    let age = context.date.timeIntervalSince(at)
                    return MeadowMonsterFrames.image(id, index: 48 + min(7, Int(age / 0.6 * 8)))
                }
                return MeadowMonsterFrames.image(id, index: Int(t.truncatingRemainder(dividingBy: 2.4) / 2.4 * 12) % 12)
            }()
            ZStack(alignment: .bottom) {
                if let image {
                    ObliqueShadowView(image: image, width: height * 1.45, height: height, mirrored: mirrored)
                        .offset(y: -height * 0.04)
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(height: height)
                        .overlay {
                            if flashOn {
                                Image(uiImage: image)
                                    .resizable()
                                    .renderingMode(.template)
                                    .interpolation(.none)
                                    .scaledToFit()
                                    .frame(height: height)
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                } else {
                    Image(systemName: "pawprint.fill").font(.system(size: height * 0.45)).foregroundStyle(.brown)
                }
            }
        }
    }
}

/// Plays a real `MeadowPixelFX` sprite-sheet VFX burst (slashes, hit sparks, sunbursts, coin/treasure sparkles).
private struct HD2DPixelFXBurst: View {
    let clipID: String
    let playedAt: Date?
    let size: CGFloat
    var fps: Double = 18

    var body: some View {
        if let playedAt, let clip = MeadowPixelFX.clips[clipID] {
            let all = MeadowPixelFX.images(clip)
            let start = clip.back && clip.front ? clip.n : 0
            let count = min(clip.n, max(0, all.count - start))
            if count > 0 {
                let duration = Double(count) / fps
                TimelineView(.animation(minimumInterval: 1.0 / 24)) { ctx in
                    let age = ctx.date.timeIntervalSince(playedAt)
                    if age >= 0 && age < duration {
                        let idx = min(count - 1, Int(age * fps))
                        Image(uiImage: UIImage(cgImage: all[start + idx]))
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: size, height: size)
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
            ZStack {
                // Layer 0-2: Native HD-2D multi-layer Meadow Battle plates (farForest + tilt-shift ground + midground)
                HD2DMeadowBackdrop(kind: model.kind, size: g.size)

                // Layer 3: Scene props, full-body animated heroes, monsters, shadows & pixel VFX
                MiniGameWorldLayer(model: model, unit: unit)
                    .frame(width: 1280 * unit, height: 720 * unit)

                // Layer 4: Foreground framing (`MeadowCampWideForeground`) + drifting sunbeams, motes & vignette
                HD2DAtmosphereOverlay(kind: model.kind, size: g.size, showForegroundFrame: model.kind != .memory)

                // Layer 5: Crisp UI HUD (unblurred, matching `MeadowPartyStageView` glass captions & vitals)
                MiniGameChromeLayer(model: model, unit: unit)
                    .frame(width: 1280 * unit, height: 720 * unit)
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
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var hurtAt: Date?
    @State private var fxAt: Date?
    @State private var diceAt: Date?
    @State private var numbersAt: Date?
    @State private var attackAt: Date?
    @State private var heroHurtAt: Date?
    @State private var shake = false
    @State private var counterFlash = false
    @State private var shatteredHeart: Int?
    @State private var dashingIDs: Set<String> = []
    @State private var rolledDice: [BattleDie] = []

    var body: some View {
        if let b = model.boss {
            let duskTint = Color(red: 0.72, green: 0.70, blue: 0.90)
            ZStack(alignment: .topLeading) {
                // 1) Midground Game Architecture & Flora (soft optical depth-of-field blur, matching battle plates)
                HD2DProp(name: "Pines", height: 340 * unit, depthBlur: 1.6, shadow: false, tint: duskTint)
                    .position(x: 84 * unit, y: 245 * unit)
                HD2DProp(name: "OakA", height: 320 * unit, depthBlur: 1.5, shadow: false, tint: duskTint)
                    .position(x: 245 * unit, y: 248 * unit)
                HD2DProp(name: "RockHigh", height: 225 * unit, depthBlur: 1.4, shadow: false, tint: duskTint)
                    .position(x: 565 * unit, y: 295 * unit)
                HD2DProp(name: "Pines", height: 330 * unit, mirrored: true, depthBlur: 1.6, shadow: false, tint: duskTint)
                    .position(x: 1185 * unit, y: 250 * unit)

                // Heroic Boss Sanctum Portal directly behind the Boss!
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.68, green: 0.34, blue: 0.96).opacity(0.45), .clear], center: .center, startRadius: 10 * unit, endRadius: 190 * unit))
                    .frame(width: 380 * unit, height: 380 * unit)
                    .position(x: 930 * unit, y: 270 * unit)
                HD2DProp(name: "NodeBossSanctum", height: 340 * unit, depthBlur: 0.8, shadow: true, tint: Color(red: 0.88, green: 0.85, blue: 0.98))
                    .position(x: 930 * unit, y: 300 * unit)

                // Twin Glowing Pixel Stone Braziers flanking the Boss Sanctum
                brazierWithGlow(x: 695 * unit, y: 405 * unit)
                brazierWithGlow(x: 1152 * unit, y: 405 * unit)

                // 2) Left Tactical Party Formation — REAL Full-Body Animated Battle Heroes facing RIGHT!
                let spots = partyFormation(count: model.students.count)
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
                    let heroH = (model.students.count > 4 ? 174 : 210) * unit
                    HD2DBattleHero(
                        student: s,
                        height: heroH,
                        mirrored: false,
                        action: action,
                        actionAt: triggerDate,
                        ringColor: model.studentTint(s.id)
                    )
                    .overlay(alignment: .bottom) {
                        // Snug battle nameplate right beneath boots (matches map hero plates, never collides with heads!)
                        Text(s.name)
                            .font(.system(size: 14 * unit, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 9 * unit).padding(.vertical, 2.5 * unit)
                            .background(RoundedRectangle(cornerRadius: 6 * unit).fill(MiniGamePalette.battlePlate.opacity(0.86)))
                            .overlay(RoundedRectangle(cornerRadius: 6 * unit).stroke(model.studentTint(s.id).opacity(0.92), lineWidth: 1.5 * unit))
                            .offset(y: 4 * unit)
                    }
                    .position(x: p.x + (isAttacker ? 56 * unit : 0), y: p.y)
                    .zIndex(Double(p.y))
                }

                // 3) Right Boss Monster with Real Oblique Shadow + Native Battle Vitals Bar + Pixel VFX!
                HD2DMonster(id: b.monster, height: 325 * unit, mirrored: false, hurtAt: hurtAt, dead: b.outcome == .won)
                    .offset(x: shake ? 14 * unit : 0)
                    .position(x: 925 * unit, y: 425 * unit)
                    .zIndex(460)

                HD2DPixelFXBurst(clipID: "melee_heavy_cleave_51", playedAt: fxAt, size: 280 * unit)
                    .position(x: 900 * unit, y: 405 * unit)
                    .zIndex(500)
                HD2DPixelFXBurst(clipID: "impacts_hit_spark_55", playedAt: fxAt, size: 240 * unit)
                    .position(x: 930 * unit, y: 395 * unit)
                    .zIndex(510)

                // Floating Battle Damage Numbers (`MeadowBattleNumber` physics!)
                BattleFloatingNumbers(hits: b.lastHits, startedAt: numbersAt, model: model, unit: unit)
                    .position(x: 910 * unit, y: 270 * unit)
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
                .background(RoundedRectangle(cornerRadius: 14 * unit, style: .continuous).fill(MiniGamePalette.battlePlate.opacity(0.84)))
                .overlay(RoundedRectangle(cornerRadius: 14 * unit, style: .continuous).stroke(MiniGamePalette.battleRim.opacity(0.65), lineWidth: 1.5 * unit))
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
                    RadialGradient(colors: [.clear, Color.red.opacity(0.45)], center: .center, startRadius: 180 * unit, endRadius: 720 * unit)
                        .transition(.opacity)
                        .zIndex(800)
                }
            }
            .frame(width: 1280 * unit, height: 720 * unit)
            .onChange(of: model.beat) { _, _ in
                guard let b = model.boss else { return }
                let now = Date()
                if !b.lastHits.isEmpty {
                    let colors = ["red", "yellow", "green", "blue"]
                    rolledDice = b.lastHits.enumerated().map { idx, h in
                        BattleDie(colors[idx % colors.count], sides: h.sides, value: h.damage, label: "D\(h.sides)")
                    }
                    diceAt = now
                    attackAt = now
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                        dashingIDs = Set(b.lastHits.map(\.player))
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        hurtAt = Date()
                        fxAt = Date()
                        numbersAt = Date()
                        withAnimation(.default.repeatCount(5, autoreverses: true).speed(4)) { shake = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) { shake = false }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { dashingIDs = [] }
                    }
                }
                if b.lastCounter {
                    let lostIndex = b.hearts
                    heroHurtAt = now
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { shatteredHeart = lostIndex }
                    withAnimation(.easeOut(duration: 0.15)) { counterFlash = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) {
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

    private func brazierWithGlow(x: CGFloat, y: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1.0, green: 0.68, blue: 0.22).opacity(0.55), Color.orange.opacity(0.18), .clear], center: .center, startRadius: 6 * unit, endRadius: 96 * unit))
                .frame(width: 192 * unit, height: 192 * unit)
                .offset(y: -34 * unit)
            HD2DProp(name: "MiniGameBrazier", height: 132 * unit, depthBlur: 0, shadow: true)
        }
        .position(x: x, y: y)
        .zIndex(Double(y))
    }

    /// Staggered left-side tactical battle positions matching `MeadowBattleFormation` (1–7 heroes).
    private func partyFormation(count: Int) -> [CGPoint] {
        switch count {
        case 1: return [CGPoint(x: 350 * unit, y: 445 * unit)]
        case 2: return [CGPoint(x: 255 * unit, y: 398 * unit), CGPoint(x: 410 * unit, y: 468 * unit)]
        case 3: return [CGPoint(x: 230 * unit, y: 382 * unit), CGPoint(x: 418 * unit, y: 432 * unit), CGPoint(x: 270 * unit, y: 492 * unit)]
        case 4: return [CGPoint(x: 210 * unit, y: 374 * unit), CGPoint(x: 390 * unit, y: 394 * unit), CGPoint(x: 245 * unit, y: 486 * unit), CGPoint(x: 420 * unit, y: 498 * unit)]
        default:
            return (0..<count).map { i in
                let col = i % 2
                let row = i / 2
                let rows = max(1, (count + 1) / 2)
                let x = (col == 0 ? 215.0 : 395.0) + Double(row % 2) * 28.0
                let y = 355.0 + Double(row) * (152.0 / Double(max(1, rows - 1)))
                return CGPoint(x: x * unit, y: y * unit)
            }
        }
    }
}

// MARK: - 2. 守护营地 (100% Native Sunlit Meadow Camp Defense + Pixel Stepping Stones!)

private struct CampStage: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var hurtAt: Date?
    @State private var fxAt: Date?
    @State private var cheerAt: Date?
    @State private var campWarn = false
    @State private var waveCallout: String?
    @State private var lastWave = 0

    var body: some View {
        if let c = model.camp {
            let cell = 136 * unit
            let left = 378 * unit
            let trailY = 524 * unit
            let dist = CampDefense.length - c.position
            let species = ["slime", "wolf", "caveTroll"][c.wave]
            let monsterH: CGFloat = (c.wave == 2 ? 236 : c.wave == 1 ? 196 : 168) * unit
            let monsterX = dist > 0 ? (left + CGFloat(dist - 1) * cell + cell / 2) : 255 * unit
            let monsterY = trailY - monsterH * 0.44 - 12 * unit

            ZStack(alignment: .topLeading) {
                // 1) Left Camp Fortress Built From Real Game Assets (`WatchTower`, `CampTent`, `Fence`, `Banner`, `Flowers`)
                HD2DProp(name: "WatchTower", height: 220 * unit, depthBlur: 1.0, shadow: true)
                    .position(x: 82 * unit, y: 320 * unit)
                    .zIndex(180)
                HD2DProp(name: "CampTent", width: 236 * unit, depthBlur: 0, shadow: true)
                    .offset(x: campWarn ? -5 * unit : 0)
                    .shadow(color: campWarn ? Color.red.opacity(0.6) : .clear, radius: 14 * unit)
                    .position(x: 192 * unit, y: 406 * unit)
                    .zIndex(240)
                HD2DProp(name: "Banner", height: 74 * unit, depthBlur: 0, shadow: false)
                    .position(x: 310 * unit, y: 382 * unit)
                    .zIndex(250)
                HD2DProp(name: "Fence", width: 150 * unit, depthBlur: 0, shadow: true)
                    .position(x: 300 * unit, y: 468 * unit)
                    .zIndex(290)

                // Right Forest Ambush Edge (`Pines`, `RockHigh`)
                HD2DProp(name: "RockHigh", height: 175 * unit, depthBlur: 1.2, shadow: false)
                    .position(x: 1218 * unit, y: 345 * unit)
                    .zIndex(190)
                HD2DProp(name: "Pines", height: 265 * unit, mirrored: true, depthBlur: 1.0, shadow: false)
                    .position(x: 1235 * unit, y: 315 * unit)
                    .zIndex(200)

                // 2) Full-Body Animated Defending Heroes Standing Guard in Front of Camp!
                let defenders = Array(model.students.prefix(4))
                ForEach(Array(defenders.enumerated()), id: \.element.id) { idx, s in
                    let dx = (135 + CGFloat(idx) * 52) * unit
                    let dy = (468 + CGFloat(idx % 2) * 26) * unit
                    HD2DBattleHero(
                        student: s,
                        height: 158 * unit,
                        mirrored: false,
                        action: c.outcome == .won || cheerAt != nil ? .victory : .ready,
                        actionAt: cheerAt,
                        ringColor: model.studentTint(s.id)
                    )
                    .position(x: dx, y: dy)
                    .zIndex(Double(dy))
                }

                // 3) 6 Real Pixel-Art Stepping Stones (`MiniGameSteppingStone`) along the Sunlit Dirt Road!
                ForEach(1...CampDefense.length, id: \.self) { step in
                    let cx = left + CGFloat(step - 1) * cell + cell / 2
                    let active = step == dist
                    let danger = step <= 2
                    ZStack {
                        Image("MiniGameSteppingStone")
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: cell - 6 * unit)
                            .colorMultiply(danger ? Color(red: 1.0, green: 0.78, blue: 0.74) : .white)
                            .shadow(color: active ? MiniGamePalette.gold.opacity(0.7) : .black.opacity(0.28), radius: (active ? 10 : 4) * unit, y: 3 * unit)
                        // Clean step numeral seated near the front face of the flagstone so monster feet never block it!
                        Text("\(step)")
                            .font(.system(size: 19 * unit, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10 * unit).padding(.vertical, 2 * unit)
                            .background(Capsule().fill(danger ? Color(red: 0.84, green: 0.22, blue: 0.20).opacity(0.92) : MiniGamePalette.battlePlate.opacity(0.80)))
                            .overlay(Capsule().stroke(active ? MiniGamePalette.goldBright : MiniGamePalette.battleRim.opacity(0.75), lineWidth: 1.5 * unit))
                            .offset(y: 16 * unit)
                    }
                    .position(x: cx, y: trailY)
                    .zIndex(310)
                }

                // 4) Approaching Monster on its Stepping Stone + Real Pixel VFX + Battle Wave Tag
                VStack(spacing: -8 * unit) {
                    Text("第 \(c.wave + 1) 波 · \(MiniGameModel.monsterName(species))")
                        .font(.system(size: 15 * unit, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11 * unit).padding(.vertical, 3 * unit)
                        .background(RoundedRectangle(cornerRadius: 6 * unit).fill(MiniGamePalette.battlePlate.opacity(0.84)))
                        .overlay(RoundedRectangle(cornerRadius: 6 * unit).stroke(MiniGamePalette.battleRim.opacity(0.8), lineWidth: 1.4 * unit))
                    HD2DMonster(id: species, height: monsterH, mirrored: false, hurtAt: hurtAt, dead: c.outcome == .won)
                }
                .position(x: monsterX, y: monsterY)
                .zIndex(450)

                HD2DPixelFXBurst(clipID: "impacts_hit_spark_55", playedAt: fxAt, size: 220 * unit)
                    .position(x: monsterX, y: monsterY + 18 * unit)
                    .zIndex(520)

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
                .background(Capsule().fill(Color.white.opacity(0.84)))
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
                        .position(x: 640 * unit, y: 205 * unit)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .zIndex(760)
                }
            }
            .frame(width: 1280 * unit, height: 720 * unit)
            .onChange(of: model.beat) { _, _ in
                guard let c = model.camp else { return }
                if c.lastMove < 1 {
                    hurtAt = Date()
                    fxAt = Date()
                    if c.lastMove == -1 {
                        cheerAt = Date()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { cheerAt = nil }
                    }
                } else {
                    withAnimation(.default.repeatCount(3, autoreverses: true).speed(4)) { campWarn = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { campWarn = false }
                }
                if c.wave != lastWave {
                    lastWave = c.wave
                    let nextSpecies = ["slime", "wolf", "caveTroll"][c.wave]
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
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var rolledDice: [BattleDie] = []
    @State private var diceAt: Date?
    @State private var fxAt: Date?
    @State private var fxPos: CGPoint = .zero

    var body: some View {
        if let r = model.race {
            let lanes = max(1, r.sides.count)
            let top = 126 * unit
            let bottom = 114 * unit
            let laneAreaH = 720 * unit - top - bottom
            let laneH = min(142 * unit, laneAreaH / CGFloat(lanes))
            let laneW = 1180 * unit
            let laneLeft = 36 * unit
            let plateW = 128 * unit
            let trackLeft = laneLeft + plateW + 10 * unit
            let trackW = laneW - plateW - 18 * unit
            let cellW = trackW / CGFloat(RaceTrack.length + 1)
            let finishX = trackLeft + CGFloat(RaceTrack.length) * cellW + cellW / 2

            ZStack(alignment: .topLeading) {
                // 1) Midground Meadow Festival Scenery (seated naturally on the upper meadow horizon!)
                HD2DProp(name: "WatchTower", height: 185 * unit, depthBlur: 1.2, shadow: true)
                    .position(x: 118 * unit, y: 186 * unit)
                HD2DProp(name: "CampTent", width: 185 * unit, depthBlur: 1.2, shadow: true)
                    .position(x: 1015 * unit, y: 204 * unit)
                HD2DProp(name: "Banner", height: 64 * unit, depthBlur: 0.6, shadow: false)
                    .position(x: 245 * unit, y: 196 * unit)
                HD2DProp(name: "Banner", height: 64 * unit, mirrored: true, depthBlur: 0.6, shadow: false)
                    .position(x: 895 * unit, y: 196 * unit)

                // 2) Frosted Meadow-Glass Special Tile Legend Strip
                HStack(spacing: 14 * unit) {
                    legendChest("礼物转盘")
                    legendItem("bolt.fill", color: MiniGamePalette.goldDeep, text: "闪电 +3")
                    legendItem("exclamationmark.triangle.fill", color: .orange, text: "陷阱答错 -2")
                    legendItem("flag.checkered", color: MiniGamePalette.ink, text: "冲线获胜")
                }
                .padding(.horizontal, 16 * unit).padding(.vertical, 5 * unit)
                .background(Capsule().fill(Color.white.opacity(0.84)))
                .overlay(Capsule().stroke(.white, lineWidth: 1.4 * unit))
                .shadow(color: .black.opacity(0.18), radius: 6 * unit, y: 2 * unit)
                .position(x: 640 * unit, y: 84 * unit)
                .zIndex(700)

                // 3) Translucent Frosted-Glass Lanes Letting Sunlit HD-2D Grass Shine Through
                ForEach(Array(r.sides.enumerated()), id: \.element.id) { lane, side in
                    let y = top + (laneAreaH - laneH * CGFloat(lanes)) / 2 + CGFloat(lane) * laneH
                    let midY = y + laneH / 2
                    let current = r.current?.id == side.id && r.winner == nil
                    let at = r.positions[side.id] ?? 0
                    let sideColor = model.tint(side.id)
                    let cellH = min(72 * unit, laneH - 22 * unit)

                    RoundedRectangle(cornerRadius: 16 * unit, style: .continuous)
                        .fill(Color.white.opacity(current ? 0.80 : 0.62))
                        .overlay(RoundedRectangle(cornerRadius: 16 * unit, style: .continuous).fill(sideColor.opacity(current ? 0.14 : 0.06)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16 * unit, style: .continuous)
                                .stroke(current ? AnyShapeStyle(MiniGamePalette.goldStroke) : AnyShapeStyle(Color.white.opacity(0.8)), lineWidth: (current ? 3.5 : 1.5) * unit)
                        )
                        .shadow(color: current ? MiniGamePalette.gold.opacity(0.45) : .black.opacity(0.16), radius: (current ? 10 : 5) * unit, y: 3 * unit)
                        .frame(width: laneW, height: laneH - 10 * unit)
                        .position(x: laneLeft + laneW / 2, y: midY)
                        .zIndex(200)

                    // Left Team Nameplate
                    HStack(spacing: 6 * unit) {
                        RoundedRectangle(cornerRadius: 4 * unit)
                            .fill(sideColor)
                            .frame(width: 6 * unit, height: max(28 * unit, laneH - 34 * unit))
                        VStack(alignment: .leading, spacing: 2 * unit) {
                            HStack(spacing: 4 * unit) {
                                if current {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 11 * unit, weight: .black))
                                        .foregroundStyle(MiniGamePalette.goldDeep)
                                }
                                Text(side.name)
                                    .font(.system(size: min(20, max(14, laneH / unit * 0.2)) * unit, weight: .heavy, design: .rounded))
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
                    .frame(width: plateW - 10 * unit)
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

                    // Pixel Hero Runner Token on tile `at`
                    let runnerH = min(84 * unit, laneH - 12 * unit)
                    runnerToken(side, height: runnerH, trapped: r.trapped.contains(side.id), active: current)
                        .position(x: trackLeft + CGFloat(at) * cellW + cellW / 2, y: midY - 6 * unit)
                        .zIndex(Double(300 + lane))
                }

                // 4) Wooden Festival Finish-Line Arch Framing the Finish Column on the Right!
                HD2DProp(name: "MiniGameFinishArch", height: min(170 * unit, max(120 * unit, laneAreaH * 0.34)), depthBlur: 0, shadow: true)
                    .position(x: finishX, y: top + (laneAreaH - laneH * CGFloat(lanes)) / 2 - 22 * unit)
                    .zIndex(190)

                // Pixel VFX burst on boost/reward
                HD2DPixelFXBurst(clipID: "collectGold", playedAt: fxAt, size: 150 * unit)
                    .position(fxPos)
                    .zIndex(550)

                // 5) Real Native 3D Gem d6 Dice Roll (`MeadowBattleDiceView`) at Top-Right!
                HD2DDiceStrip(dice: rolledDice, startedAt: diceAt, unit: unit)
                    .position(x: 1130 * unit, y: 58 * unit)
                    .zIndex(760)
            }
            .frame(width: 1280 * unit, height: 720 * unit)
            .onChange(of: model.beat) { _, _ in
                guard let r = model.race else { return }
                let now = Date()
                for e in r.events {
                    if case .moved(let side, let roll, _) = e {
                        let color = (model.tints[side] ?? 0) == 0 ? "red" : (model.tints[side] ?? 0) == 1 ? "blue" : "yellow"
                        rolledDice = [BattleDie(color, sides: 6, value: roll, label: "D6")]
                        diceAt = now
                    }
                    if case .landed(let side, let cell) = e, cell == .reward || cell == .boost {
                        if let lane = r.sides.firstIndex(where: { $0.id == side }) {
                            let y = top + (laneAreaH - laneH * CGFloat(lanes)) / 2 + CGFloat(lane) * laneH + laneH / 2
                            let at = r.positions[side] ?? 0
                            fxPos = CGPoint(x: trackLeft + CGFloat(at) * cellW + cellW / 2, y: y)
                            fxAt = now
                        }
                    }
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
            .fill(cell == .plain ? (passed ? sideColor.opacity(0.24) : Color.white.opacity(0.84)) : color.opacity(0.92))
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

    private func runnerToken(_ side: MiniGameSide, height: CGFloat, trapped: Bool, active: Bool) -> some View {
        HStack(spacing: -height * 0.24) {
            ForEach(side.members.prefix(3), id: \.self) { id in
                if let student = model.student(id) {
                    RaceHeroSprite(student: student, height: side.members.count > 1 ? height * 0.84 : height, tint: model.tint(side.id))
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

/// Compact side-facing full-body pixel runner for Quiz Race (falls back to portrait while baking).
private struct RaceHeroSprite: View {
    let student: MiniGameModel.Student
    let height: CGFloat
    let tint: Color
    @State private var sprite: PixelHeroAtlas.BattleSprite?
    @State private var fallback: UIImage?

    var body: some View {
        let boxW = height * (256.0 / 320.0)
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(tint.opacity(0.28))
                .overlay(Ellipse().stroke(tint.opacity(0.9), lineWidth: 1.6))
                .frame(width: boxW * 0.68, height: boxW * 0.22)
                .offset(y: -height * 0.08)
            if let frame = sprite?.frames["ready"]?.first {
                Image(uiImage: frame.tall)
                    .resizable().interpolation(.none).scaledToFit()
                    .frame(width: boxW, height: height)
                    .shadow(color: .black.opacity(0.32), radius: 3, y: 2)
            } else if let fallback {
                Image(uiImage: fallback)
                    .resizable().interpolation(.none).scaledToFit()
                    .frame(height: height * 0.72)
                    .offset(y: -height * 0.08)
            } else {
                MiniGameFace(student: student, size: height * 0.56, tint: tint)
                    .offset(y: -height * 0.14)
            }
        }
        .frame(width: boxW, height: height)
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

// MARK: - 4. 翻牌寻宝 (Shallow-DoF Meadow Camp Supply Clearing + Wooden Camp Treasure Table!)

private struct MemoryStage: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var sparkleAt: Date?
    @State private var lastMatchedCount = 0

    var body: some View {
        if let m = model.memory {
            let layout = MemoryBoardLayout(count: m.cards.count, unit: unit)
            ZStack(alignment: .topLeading) {
                // 1) Shallow-DoF Blurred Camp Supply Props in the Sunlit Meadow Clearing Behind the Table
                HD2DProp(name: "NodeRewardCache", height: 220 * unit, depthBlur: 4.5, shadow: false)
                    .position(x: 92 * unit, y: 540 * unit)
                    .opacity(0.85)
                HD2DProp(name: "CampTent", width: 240 * unit, depthBlur: 5.0, shadow: false)
                    .position(x: 1185 * unit, y: 525 * unit)
                    .opacity(0.82)
                HD2DProp(name: "NodeWaystone", height: 170 * unit, depthBlur: 4.5, shadow: false)
                    .position(x: 1190 * unit, y: 185 * unit)
                    .opacity(0.75)

                // 2) Focal-Plane Crafted Camp Wooden Table Mat Holding the 4×4 Cards
                let matPad = 20 * unit
                RoundedRectangle(cornerRadius: 24 * unit, style: .continuous)
                    .fill(LinearGradient(colors: [MiniGamePalette.woodTop, MiniGamePalette.woodBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18 * unit, style: .continuous)
                            .fill(LinearGradient(colors: [MiniGamePalette.parchmentTop.opacity(0.92), MiniGamePalette.parchmentBottom.opacity(0.90)], startPoint: .top, endPoint: .bottom))
                            .padding(10 * unit)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24 * unit, style: .continuous)
                            .stroke(MiniGamePalette.goldStroke, lineWidth: 2.5 * unit)
                    )
                    .shadow(color: .black.opacity(0.42), radius: 18 * unit, y: 8 * unit)
                    .frame(width: layout.gridSize.width + matPad * 2, height: layout.gridSize.height + matPad * 2)
                    .position(x: layout.gridOrigin.x + layout.gridSize.width / 2, y: layout.gridOrigin.y + layout.gridSize.height / 2)

                // 3) Card Grid — exact coordinates shared with MiniGameTapLayer
                ForEach(m.cards.indices, id: \.self) { i in
                    let up = m.faceUp.contains(i)
                    let state: MemoryCardView.Highlight = {
                        if m.owner[m.cards[i].pair] != nil { return .matched }
                        if up && m.phase == .judging { return .pairReady }
                        if up && m.phase == .mismatch { return .mismatch }
                        return .normal
                    }()
                    MemoryCardView(
                        card: m.cards[i],
                        number: i + 1,
                        up: up,
                        owner: m.owner[m.cards[i].pair].map(model.tint),
                        highlight: state,
                        size: layout.cardSize,
                        unit: unit
                    )
                    .position(layout.cardCenter(i))
                }

                // 4) Right-Side Frosted Meadow-Glass Treasure Standings
                VStack(alignment: .leading, spacing: 12 * unit) {
                    ForEach(m.sides) { side in
                        let turn = m.current?.id == side.id && !m.finished
                        let sideColor = model.tint(side.id)
                        HStack(spacing: 10 * unit) {
                            HStack(spacing: -10 * unit) {
                                ForEach(side.members.prefix(2), id: \.self) { id in
                                    MiniGameFace(student: model.student(id), size: 38 * unit, tint: sideColor)
                                }
                            }
                            VStack(alignment: .leading, spacing: 1 * unit) {
                                Text(side.name)
                                    .font(.system(size: 20 * unit, weight: .heavy, design: .rounded))
                                    .foregroundStyle(MiniGamePalette.ink)
                                    .lineLimit(1).minimumScaleFactor(0.65)
                                if turn {
                                    Text("当前翻牌")
                                        .font(.system(size: 12 * unit, weight: .heavy, design: .rounded))
                                        .foregroundStyle(MiniGamePalette.goldDeep)
                                }
                            }
                            Spacer(minLength: 4 * unit)
                            Image("MiniGameChestOpen")
                                .resizable().interpolation(.none).scaledToFit()
                                .frame(width: 30 * unit, height: 30 * unit)
                            Text("\(m.pairs(of: side.id))")
                                .font(.system(size: 27 * unit, weight: .black, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(MiniGamePalette.ink)
                        }
                        .padding(.horizontal, 14 * unit).padding(.vertical, 10 * unit)
                        .frame(width: layout.sideWidth)
                        .background(RoundedRectangle(cornerRadius: 16 * unit, style: .continuous).fill(Color.white.opacity(turn ? 0.90 : 0.72)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16 * unit, style: .continuous)
                                .stroke(turn ? AnyShapeStyle(MiniGamePalette.goldStroke) : AnyShapeStyle(Color.white.opacity(0.8)), lineWidth: (turn ? 3.5 : 1.5) * unit)
                        )
                        .shadow(color: turn ? MiniGamePalette.gold.opacity(0.45) : .black.opacity(0.18), radius: (turn ? 12 : 6) * unit, y: 3 * unit)
                        .scaleEffect(turn ? 1.03 : 1.0)
                    }
                }
                .position(x: layout.sideX, y: 348 * unit)

                // Pixel VFX golden burst when a treasure pair is claimed!
                HD2DPixelFXBurst(clipID: "collectGold", playedAt: sparkleAt, size: 180 * unit)
                    .position(x: layout.sideX, y: 348 * unit)
            }
            .frame(width: 1280 * unit, height: 720 * unit)
            .onChange(of: model.beat) { _, _ in
                let count = model.memory?.owner.count ?? 0
                if count > lastMatchedCount {
                    lastMatchedCount = count
                    sparkleAt = Date()
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
    let size: CGSize
    let unit: CGFloat

    var body: some View {
        let shown = up || owner != nil
        let border: AnyShapeStyle = switch highlight {
        case .pairReady: AnyShapeStyle(MiniGamePalette.goldStroke)
        case .mismatch: AnyShapeStyle(Color(red: 0.90, green: 0.28, blue: 0.28))
        case .matched: AnyShapeStyle(Color.white.opacity(0.85))
        case .normal: shown ? AnyShapeStyle(MiniGamePalette.gold.opacity(0.8)) : AnyShapeStyle(MiniGamePalette.goldStroke)
        }
        ZStack {
            // Back: deep navy & antique gold treasure chest card with real pixel-art closed chest
            RoundedRectangle(cornerRadius: 14 * unit, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.29, blue: 0.54), Color(red: 0.12, green: 0.18, blue: 0.36)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 10 * unit, style: .continuous)
                        .stroke(MiniGamePalette.gold.opacity(0.45), lineWidth: 1.5 * unit)
                        .padding(5 * unit)
                )
                .overlay {
                    HStack(spacing: 10 * unit) {
                        Image("MiniGameChestClosed")
                            .resizable().interpolation(.none).scaledToFit()
                            .frame(width: min(62 * unit, size.height * 0.58), height: min(62 * unit, size.height * 0.58))
                            .shadow(color: .black.opacity(0.45), radius: 4 * unit, y: 2 * unit)
                        Text("\(number)")
                            .font(.system(size: 23 * unit, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(MiniGamePalette.goldBright)
                            .frame(width: 36 * unit, height: 36 * unit)
                            .background(Circle().fill(Color.black.opacity(0.32)))
                            .overlay(Circle().stroke(MiniGamePalette.gold.opacity(0.75), lineWidth: 1.5 * unit))
                    }
                }
                .opacity(shown ? 0 : 1)

            // Front: clean ivory card with #number + EN/中 tag, or claimed team treasure card
            RoundedRectangle(cornerRadius: 14 * unit, style: .continuous)
                .fill(
                    owner.map { AnyShapeStyle(LinearGradient(colors: [$0.opacity(0.95), $0.opacity(0.80)], startPoint: .top, endPoint: .bottom)) }
                    ?? AnyShapeStyle(LinearGradient(colors: [Color.white, Color(red: 0.99, green: 0.97, blue: 0.92)], startPoint: .top, endPoint: .bottom))
                )
                .overlay {
                    Text(card.text)
                        .font(.system(size: (card.english ? 27 : 29) * unit, weight: .heavy, design: .rounded))
                        .foregroundStyle(owner != nil ? .white : MiniGamePalette.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.42)
                        .padding(.horizontal, 12 * unit)
                        .padding(.top, 14 * unit)
                        .padding(.bottom, 6 * unit)
                }
                .overlay(alignment: .topLeading) {
                    Text("#\(number)")
                        .font(.system(size: 12 * unit, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(owner != nil ? .white.opacity(0.82) : MiniGamePalette.ink.opacity(0.5))
                        .padding(.horizontal, 7 * unit).padding(.vertical, 2 * unit)
                        .background(Capsule().fill(owner != nil ? Color.black.opacity(0.22) : Color.black.opacity(0.06)))
                        .padding(6 * unit)
                }
                .overlay(alignment: .topTrailing) {
                    if owner != nil {
                        Image("MiniGameChestOpen")
                            .resizable().interpolation(.none).scaledToFit()
                            .frame(width: 28 * unit, height: 28 * unit)
                            .padding(6 * unit)
                    } else {
                        Text(card.english ? "EN" : "中")
                            .font(.system(size: 11 * unit, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7 * unit).padding(.vertical, 2 * unit)
                            .background(Capsule().fill(card.english ? Color(red: 0.24, green: 0.54, blue: 0.88) : Color(red: 0.86, green: 0.54, blue: 0.16)))
                            .padding(6 * unit)
                    }
                }
                .opacity(shown ? 1 : 0)
        }
        .frame(width: size.width, height: size.height)
        .overlay(
            RoundedRectangle(cornerRadius: 14 * unit, style: .continuous)
                .stroke(border, lineWidth: (highlight == .pairReady || highlight == .mismatch ? 4 : 2.2) * unit)
        )
        .scaleEffect(shown ? (highlight == .pairReady ? 1.03 : 1.0) : 0.96)
        .shadow(color: highlight == .pairReady ? MiniGamePalette.gold.opacity(0.65) : Color.black.opacity(0.24), radius: (highlight == .pairReady ? 12 : 5) * unit, y: 3 * unit)
    }
}

// MARK: - 5. 擂台王 (100% Native HD-2D PvP Meadow Tournament on `MiniGameArenaRing`!)

private struct ArenaStage: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var clashAt: Date?
    @State private var fxAt: Date?
    @State private var champAction: HD2DBattleHero.Action = .ready
    @State private var chalAction: HD2DBattleHero.Action = .ready

    var body: some View {
        if let a = model.arena {
            ZStack(alignment: .topLeading) {
                // 1) Midground Tournament Grounds Built from Real Game Assets (soft optical depth-of-field blur!)
                HD2DProp(name: "NodeCombatOutpost", height: 225 * unit, depthBlur: 1.2, shadow: true)
                    .position(x: 115 * unit, y: 345 * unit)
                    .zIndex(180)
                HD2DProp(name: "WatchTower", height: 245 * unit, depthBlur: 1.2, shadow: true)
                    .position(x: 1165 * unit, y: 335 * unit)
                    .zIndex(180)
                HD2DProp(name: "Fence", width: 170 * unit, depthBlur: 0.6, shadow: true)
                    .position(x: 240 * unit, y: 468 * unit)
                    .zIndex(210)
                HD2DProp(name: "Fence", width: 170 * unit, mirrored: true, depthBlur: 0.6, shadow: true)
                    .position(x: 1040 * unit, y: 468 * unit)
                    .zIndex(210)
                HD2DProp(name: "Banner", height: 84 * unit, depthBlur: 0.5, shadow: false)
                    .position(x: 265 * unit, y: 375 * unit)
                    .zIndex(220)
                HD2DProp(name: "Banner", height: 84 * unit, mirrored: true, depthBlur: 0.5, shadow: false)
                    .position(x: 1015 * unit, y: 375 * unit)
                    .zIndex(220)

                // 2) Focal-Plane Circular Stone & Gold Tournament Stage (`MiniGameArenaRing`)
                HD2DProp(name: "MiniGameArenaRing", width: 720 * unit, depthBlur: 0, shadow: true)
                    .position(x: 640 * unit, y: 472 * unit)
                    .zIndex(280)

                // 3) Champion (Left, facing RIGHT) vs Challenger (Right, mirrored facing LEFT) — Real Animated Battle Heroes!
                duelist(id: a.champion, champion: true, streak: a.streak, action: champAction)
                    .id("champ-\(a.champion)")
                    .position(x: 472 * unit, y: 382 * unit)
                    .zIndex(420)

                vsEmblem
                    .position(x: 640 * unit, y: 378 * unit)
                    .zIndex(430)

                duelist(id: a.challenger, champion: false, streak: 0, action: chalAction)
                    .id("chal-\(a.challenger)")
                    .position(x: 808 * unit, y: 382 * unit)
                    .zIndex(420)

                // Real Pixel VFX Clash Sunburst
                HD2DPixelFXBurst(clipID: "holy_sunburst_39", playedAt: fxAt, size: 240 * unit)
                    .position(x: 472 * unit, y: 365 * unit)
                    .zIndex(520)

                // 4) Top-Left `下一位挑战` & Top-Right `胜场榜` in Frosted Meadow Glass (zero collision with fighters!)
                if !a.line.isEmpty {
                    VStack(alignment: .leading, spacing: 6 * unit) {
                        Text("下一位挑战")
                            .font(.system(size: 14 * unit, weight: .heavy, design: .rounded))
                            .foregroundStyle(MiniGamePalette.ink.opacity(0.72))
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
                    .background(RoundedRectangle(cornerRadius: 16 * unit, style: .continuous).fill(Color.white.opacity(0.84)))
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
                .background(RoundedRectangle(cornerRadius: 16 * unit, style: .continuous).fill(Color.white.opacity(0.84)))
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
                switch a.last {
                case .dethroned, .defended:
                    champAction = .victory
                    chalAction = .ready
                    fxAt = now
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { champAction = .ready }
                case .nobody:
                    champAction = .hurt
                    chalAction = .hurt
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
        let crownSize = (50 + CGFloat(min(streak, 5)) * 6) * unit
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
                        .font(.system(size: 38 * unit, weight: .black))
                        .foregroundStyle(LinearGradient(colors: [MiniGamePalette.goldBright, .orange], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.55), radius: 4 * unit, y: 2 * unit)
                }
            }
            .frame(height: 62 * unit)
            .offset(y: 44 * unit)
            .zIndex(5)

            if let student = model.student(id) {
                HD2DBattleHero(
                    student: student,
                    height: 238 * unit,
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
                    .fill(MiniGamePalette.battlePlate.opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10 * unit, style: .continuous)
                    .stroke(champion ? AnyShapeStyle(MiniGamePalette.goldStroke) : AnyShapeStyle(MiniGamePalette.battleRim.opacity(0.82)), lineWidth: 2 * unit)
            )
            .shadow(color: .black.opacity(0.4), radius: 6 * unit, y: 3 * unit)
            .offset(y: 6 * unit)
        }
        .transition(.asymmetric(insertion: .scale(scale: 0.82).combined(with: .opacity), removal: .opacity))
    }
}
