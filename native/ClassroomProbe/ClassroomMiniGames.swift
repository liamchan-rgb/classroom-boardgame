import SwiftUI
import UIKit
import ClassroomGameCore
import MeadowWorldSupport

// MARK: - 课堂小游戏: boss, camp, race, memory, arena (about 10 minutes each)
//
// The questions are the normal ones (全班题 / 指定答题: recorded, rewarded, in the report); a game only reads who got
// each question right and moves its board on the TV once the answer card has gone. Not saved with the trip.

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
        var backdrop: String {
            switch self {
            case .boss: "MiniGameBgBoss"
            case .camp: "MiniGameBgCamp"
            case .race: "MiniGameBgRace"
            case .memory: "MiniGameBgMemory"
            case .arena: "MiniGameBgArena"
            }
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
        // In case the card stays up for long: no later than a few seconds.
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
    static let ink = Color(red: 0.16, green: 0.13, blue: 0.10)
    static let gold = Color(red: 0.96, green: 0.78, blue: 0.28)
    static let goldBright = Color(red: 1.0, green: 0.90, blue: 0.52)
    static let goldDeep = Color(red: 0.76, green: 0.52, blue: 0.14)
    static let plaqueDark = Color(red: 0.11, green: 0.12, blue: 0.18)
    static let parchmentTop = Color(red: 1.0, green: 0.98, blue: 0.93)
    static let parchmentBottom = Color(red: 0.95, green: 0.89, blue: 0.75)
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

/// The teacher's copy of the memory board: fixed full-width grid (no layout jump when judging buttons appear above).
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
        let cw: CGFloat = (cols == 4 ? 190 : 216) * unit
        let ch: CGFloat = (r >= 4 ? 112 : r == 3 ? 138 : 168) * unit
        let g: CGFloat = (r >= 4 ? 12 : 16) * unit
        self.cardSize = CGSize(width: cw, height: ch)
        self.gap = g
        let gw = CGFloat(cols) * cw + CGFloat(cols - 1) * g
        let gh = CGFloat(r) * ch + CGFloat(r - 1) * g
        self.gridSize = CGSize(width: gw, height: gh)
        let sw = 286 * unit
        let splitGap = 28 * unit
        let totalW = gw + splitGap + sw
        let gx = (1280 * unit - totalW) / 2
        // Safe zone: title ends at y=68, bottom scroll banner starts at y=622 → vertical center y=346.
        let gy = 346 * unit - gh / 2
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

/// Interactive tap interceptor over the teacher's preview when a mini-game is active:
/// prevents taps bleeding into the hidden map/book underneath, and lets teachers directly tap Memory cards on stage!
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
                // Absorb stray clicks so they never pass through to the underlying map or picture book.
                Color.clear.contentShape(Rectangle())
                if let m = model.memory {
                    let layout = MemoryBoardLayout(count: m.cards.count, unit: unit)
                    ZStack(alignment: .topLeading) {
                        ForEach(m.cards.indices, id: \.self) { i in
                            if m.canFlip(i) {
                                Button { model.flip(i) } label: { Color.clear }
                                    .buttonStyle(.plain)
                                    .contentShape(RoundedRectangle(cornerRadius: 16 * unit))
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

// MARK: TV stage (1280 × 720 design, scaled by `unit`)

struct MiniGameStage: View {
    @ObservedObject var model: MiniGameModel
    var body: some View {
        GeometryReader { g in
            let unit = min(g.size.height / 720, g.size.width / 1280)
            let bgAlign: Alignment = (model.kind == .arena || model.kind == .camp) ? .bottom : .center
            ZStack {
                if model.kind == .memory {
                    Image(model.kind.backdrop)
                        .resizable()
                        .frame(width: g.size.width, height: g.size.height)
                } else {
                    Image(model.kind.backdrop)
                        .resizable()
                        .scaledToFill()
                        .frame(width: g.size.width, height: g.size.height, alignment: bgAlign)
                        .clipped()
                }
                // Subtle cinematic vignette so HUD & text always stay razor-sharp.
                RadialGradient(colors: [.clear, Color.black.opacity(0.24)], center: .center, startRadius: min(g.size.width, g.size.height) * 0.38, endRadius: max(g.size.width, g.size.height) * 0.78)
                MiniGameBoard(model: model, unit: unit).frame(width: 1280 * unit, height: 720 * unit)
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
        }
        .transition(.opacity)
    }
}

private struct MiniGameBoard: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var bannerPulse = false
    var body: some View {
        ZStack {
            Group {
                switch model.kind {
                case .boss: BossStage(model: model, unit: unit)
                case .camp: CampStage(model: model, unit: unit)
                case .race: RaceStage(model: model, unit: unit)
                case .memory: MemoryStage(model: model, unit: unit)
                case .arena: ArenaStage(model: model, unit: unit)
                }
            }
            VStack(spacing: 0) {
                titleCrest.padding(.top, 14 * unit)
                Spacer()
                if let line = model.banner {
                    scrollBanner(line)
                        .padding(.bottom, 16 * unit)
                        .padding(.horizontal, 52 * unit)
                }
            }
            if model.finished { MiniGameFinale(model: model, unit: unit) }
        }
        .onChange(of: model.beat) { _, _ in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) { bannerPulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.easeOut(duration: 0.25)) { bannerPulse = false }
            }
        }
    }
    private var titleCrest: some View {
        HStack(spacing: 10 * unit) {
            if model.kind == .memory {
                Image("MiniGameChestOpen").resizable().interpolation(.none).scaledToFit().frame(width: 34 * unit, height: 34 * unit)
            } else if model.kind == .arena {
                Image("MiniGameCrown").resizable().interpolation(.none).scaledToFit().frame(width: 34 * unit, height: 34 * unit)
            } else {
                Image(systemName: model.kind.icon)
                    .font(.system(size: 26 * unit, weight: .heavy))
                    .foregroundStyle(MiniGamePalette.goldBright)
            }
            Text(model.kind.title)
                .font(.system(size: 30 * unit, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 2 * unit, y: 1.5 * unit)
        }
        .padding(.horizontal, 24 * unit)
        .padding(.vertical, 8 * unit)
        .background(
            Capsule()
                .fill(LinearGradient(colors: [MiniGamePalette.plaqueDark.opacity(0.92), Color(red: 0.18, green: 0.16, blue: 0.24).opacity(0.88)], startPoint: .top, endPoint: .bottom))
        )
        .overlay(Capsule().stroke(MiniGamePalette.goldStroke, lineWidth: 2.5 * unit))
        .shadow(color: .black.opacity(0.35), radius: 8 * unit, y: 4 * unit)
    }
    private func scrollBanner(_ line: String) -> some View {
        Text(line)
            .font(.system(size: 27 * unit, weight: .heavy, design: .rounded))
            .foregroundStyle(MiniGamePalette.ink)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.65)
            .contentTransition(.opacity)
            .padding(.horizontal, 28 * unit)
            .padding(.vertical, 11 * unit)
            .background(
                RoundedRectangle(cornerRadius: 20 * unit, style: .continuous)
                    .fill(LinearGradient(colors: [MiniGamePalette.parchmentTop, MiniGamePalette.parchmentBottom], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20 * unit, style: .continuous)
                    .stroke(MiniGamePalette.goldStroke, lineWidth: 3 * unit)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17 * unit, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 1 * unit)
                    .padding(3 * unit)
            )
            .shadow(color: .black.opacity(0.32), radius: 10 * unit, y: 4 * unit)
            .scaleEffect(bannerPulse ? 1.04 : 1.0)
    }
}

private struct MiniGameFinale: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var pop = false
    var body: some View {
        let won = model.kind == .boss ? model.boss?.outcome == .won : model.kind == .camp ? model.camp?.outcome == .won : true
        ZStack {
            Color.black.opacity(0.28)
            VStack(spacing: 14 * unit) {
                if won {
                    Image(model.kind == .memory ? "MiniGameChestOpen" : "MiniGameCrown")
                        .resizable().interpolation(.none).scaledToFit()
                        .frame(width: 96 * unit, height: 96 * unit)
                        .shadow(color: MiniGamePalette.gold.opacity(0.75), radius: 14 * unit)
                } else {
                    Image(systemName: "shield.slash.fill")
                        .font(.system(size: 68 * unit, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text(won ? "胜利！" : "下次再来")
                    .font(.system(size: 82 * unit, weight: .black, design: .rounded))
                    .foregroundStyle(won ? AnyShapeStyle(MiniGamePalette.goldStroke) : AnyShapeStyle(Color.white))
                    .shadow(color: .black.opacity(0.55), radius: 6 * unit, y: 4 * unit)
                if won, !model.winners.isEmpty, model.kind != .boss, model.kind != .camp {
                    HStack(spacing: 12 * unit) {
                        ForEach(model.winners.prefix(4), id: \.self) { id in
                            MiniGameFace(student: model.student(id), size: 54 * unit, tint: model.studentTint(id))
                        }
                    }
                    Text(model.winners.map(model.name).joined(separator: "、"))
                        .font(.system(size: 32 * unit, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3 * unit)
                }
            }
            .padding(.horizontal, 52 * unit)
            .padding(.vertical, 34 * unit)
            .background(
                RoundedRectangle(cornerRadius: 32 * unit, style: .continuous)
                    .fill(LinearGradient(colors: [MiniGamePalette.plaqueDark.opacity(0.94), Color(red: 0.18, green: 0.14, blue: 0.24).opacity(0.92)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 32 * unit, style: .continuous).stroke(MiniGamePalette.goldStroke, lineWidth: 4 * unit))
            .shadow(color: .black.opacity(0.55), radius: 24 * unit, y: 10 * unit)
            .scaleEffect(pop ? 1 : 0.45)
            .opacity(pop ? 1 : 0)
            .offset(y: -26 * unit)
        }
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.62).delay(0.25)) { pop = true } }
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
            Circle().fill(LinearGradient(colors: [tint.opacity(0.98), tint.opacity(0.75)], startPoint: .top, endPoint: .bottom))
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
        .shadow(color: .black.opacity(0.32), radius: size * 0.08, y: size * 0.05)
        .onAppear(perform: load)
    }
    private func load() {
        guard let look = student?.look else { return }
        if let hit = PixelHeroAtlas.portrait(look, ready: { image = PixelHeroAtlas.portrait(look) }) { image = hit }
    }
}

/// A student's whole pixel figure (arena).
private struct MiniGameFigure: View {
    let student: MiniGameModel.Student?
    let height: CGFloat
    var mirrored = false
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
            } else {
                MiniGameFace(student: student, size: height * 0.46)
            }
        }
        .frame(height: height)
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        .shadow(color: .black.opacity(0.35), radius: height * 0.03, y: height * 0.02)
        .onAppear {
            guard let look = student?.look else { return }
            if let hit = PixelHeroAtlas.fullBody(look, ready: { image = PixelHeroAtlas.fullBody(look) }) { image = hit }
        }
    }
}

/// An animated monster (idle loop; `hurtAt` plays the hurt frames, `dead` the death).
private struct MiniGameMonster: View {
    let id: String
    let height: CGFloat
    var hurtAt: Date?
    var dead = false
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let image: UIImage? = {
                if dead { return MeadowMonsterFrames.image(id, index: 39, death: true) }
                if let at = hurtAt, case let age = context.date.timeIntervalSince(at), age >= 0, age < 0.6 {
                    return MeadowMonsterFrames.image(id, index: 48 + min(7, Int(age / 0.6 * 8)))
                }
                return MeadowMonsterFrames.image(id, index: Int(t.truncatingRemainder(dividingBy: 2.4) / 2.4 * 12) % 12)
            }()
            if let image {
                Image(uiImage: image).resizable().interpolation(.none).scaledToFit().frame(height: height)
            } else {
                Image(systemName: "pawprint.fill").font(.system(size: height * 0.5)).foregroundStyle(.brown)
            }
        }
    }
}

/// Ground contact shadow oval so pixel characters & monsters sit solidly on the scene floor.
private struct GroundShadow: View {
    let width: CGFloat
    let height: CGFloat
    var body: some View {
        Ellipse()
            .fill(RadialGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.22), .clear], center: .center, startRadius: 2, endRadius: width * 0.5))
            .frame(width: width, height: height)
    }
}

/// Glossy RPG ruby heart with gold rim (and dark empty socket when lost).
private struct RPGHeartView: View {
    let filled: Bool
    let bursting: Bool
    let unit: CGFloat
    var body: some View {
        ZStack {
            if filled {
                Image(systemName: "heart.fill")
                    .font(.system(size: 32 * unit, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.36, blue: 0.42), Color(red: 0.80, green: 0.10, blue: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        Image(systemName: "heart")
                            .font(.system(size: 32 * unit, weight: .semibold))
                            .foregroundStyle(MiniGamePalette.goldBright.opacity(0.85))
                    )
                    .shadow(color: Color.red.opacity(0.55), radius: 5 * unit, y: 2 * unit)
            } else {
                Image(systemName: "heart.slash.fill")
                    .font(.system(size: 30 * unit, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.24))
                    .overlay(
                        Image(systemName: "heart.slash")
                            .font(.system(size: 30 * unit, weight: .regular))
                            .foregroundStyle(Color.black.opacity(0.45))
                    )
            }
        }
        .scaleEffect(bursting ? 1.32 : 1.0)
        .rotationEffect(.degrees(bursting ? -12 : 0))
    }
}

// MARK: 1. 全班打Boss

private struct BossStage: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var hurtAt: Date?
    @State private var shake = false
    @State private var hitFlash = false
    @State private var counterFlash = false
    @State private var shatteredHeart: Int?
    @State private var showHits = false
    @State private var hitsFloat = false
    @State private var attacking = false
    @State private var animToken = 0

    var body: some View {
        if let b = model.boss {
            ZStack {
                if counterFlash {
                    RadialGradient(colors: [.clear, Color.red.opacity(0.42)], center: .center, startRadius: 200 * unit, endRadius: 720 * unit)
                        .transition(.opacity)
                }

                // 1) Top RPG Boss HUD (y = 78 .. 154)
                HStack(spacing: 22 * unit) {
                    HStack(spacing: 6 * unit) {
                        ForEach(0..<BossRaid.hearts, id: \.self) { i in
                            RPGHeartView(filled: i < b.hearts, bursting: shatteredHeart == i, unit: unit)
                        }
                    }
                    VStack(alignment: .leading, spacing: 5 * unit) {
                        HStack {
                            Text(MiniGameModel.monsterName(b.monster))
                                .font(.system(size: 21 * unit, weight: .heavy, design: .rounded))
                                .foregroundStyle(MiniGamePalette.goldBright)
                            Spacer()
                            Text("HP  \(b.hp) / \(b.maxHP)")
                                .font(.system(size: 21 * unit, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                        }
                        .frame(width: 520 * unit)
                        GeometryReader { g in
                            let ratio = CGFloat(b.hp) / CGFloat(max(1, b.maxHP))
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.black.opacity(0.55))
                                Capsule()
                                    .fill(LinearGradient(colors: [Color(red: 0.96, green: 0.22, blue: 0.22), Color(red: 1.0, green: 0.56, blue: 0.16)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: g.size.width * ratio)
                                    .overlay(alignment: .top) {
                                        Capsule().fill(.white.opacity(0.28)).frame(height: 8 * unit).padding(.horizontal, 4 * unit).padding(.top, 2 * unit)
                                    }
                            }
                        }
                        .frame(width: 520 * unit, height: 24 * unit)
                        .overlay(Capsule().stroke(MiniGamePalette.goldStroke, lineWidth: 2.5 * unit))
                    }
                }
                .padding(.horizontal, 24 * unit)
                .padding(.vertical, 11 * unit)
                .background(
                    RoundedRectangle(cornerRadius: 20 * unit, style: .continuous)
                        .fill(MiniGamePalette.plaqueDark.opacity(0.84))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20 * unit, style: .continuous)
                        .stroke(MiniGamePalette.goldStroke, lineWidth: 2 * unit)
                )
                .shadow(color: .black.opacity(0.45), radius: 12 * unit, y: 5 * unit)
                .position(x: 640 * unit, y: 116 * unit)

                // 2) Boss Monster grounded on the mossy flagstone battleground (feet ~476, cleanly above heroes!)
                GroundShadow(width: 260 * unit, height: 38 * unit)
                    .position(x: 640 * unit, y: 472 * unit)
                if hitFlash {
                    Circle()
                        .fill(RadialGradient(colors: [MiniGamePalette.goldBright.opacity(0.85), Color.orange.opacity(0.35), .clear], center: .center, startRadius: 8 * unit, endRadius: 150 * unit))
                        .frame(width: 300 * unit, height: 300 * unit)
                        .position(x: 640 * unit, y: 342 * unit)
                        .transition(.opacity)
                }
                MiniGameMonster(id: b.monster, height: 300 * unit, hurtAt: hurtAt, dead: b.outcome == .won)
                    .scaleEffect(x: -1, y: 1)
                    .offset(x: shake ? 14 * unit : 0)
                    .shadow(color: .black.opacity(0.45), radius: 10 * unit, y: 6 * unit)
                    .position(x: 640 * unit, y: 334 * unit)

                // 3) Transient floating damage numbers above Boss shoulders (auto-fade after 1.9s)
                if showHits, !b.lastHits.isEmpty {
                    HStack(spacing: 12 * unit) {
                        ForEach(Array(b.lastHits.enumerated()), id: \.offset) { _, h in
                            VStack(spacing: 2 * unit) {
                                Text("-\(h.damage)")
                                    .font(.system(size: 42 * unit, weight: .black, design: .rounded))
                                    .foregroundStyle(MiniGamePalette.goldBright)
                                    .shadow(color: Color(red: 0.75, green: 0.08, blue: 0.08), radius: 2 * unit, y: 2 * unit)
                                    .shadow(color: .black.opacity(0.8), radius: 3 * unit)
                                Text("\(model.name(h.player)) · d\(h.sides)")
                                    .font(.system(size: 14 * unit, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 9 * unit).padding(.vertical, 3 * unit)
                                    .background(Capsule().fill(MiniGamePalette.plaqueDark.opacity(0.88)))
                                    .overlay(Capsule().stroke(MiniGamePalette.gold.opacity(0.8), lineWidth: 1.5 * unit))
                            }
                        }
                    }
                    .position(x: 640 * unit, y: hitsFloat ? 186 * unit : 226 * unit)
                    .opacity(hitsFloat ? 0.96 : 1)
                    .transition(.opacity)
                }

                // 4) Hero Party Row (y = 515 .. 605, strictly clear of Boss & Banner!)
                HStack(spacing: 18 * unit) {
                    ForEach(model.students) { s in
                        let hit = b.lastHits.first { $0.player == s.id }
                        let lunging = attacking && hit != nil
                        VStack(spacing: 4 * unit) {
                            MiniGameFace(student: s, size: 62 * unit, tint: model.studentTint(s.id))
                                .overlay(Circle().stroke(lunging ? MiniGamePalette.goldBright : .clear, lineWidth: 3.5 * unit))
                                .shadow(color: lunging ? MiniGamePalette.gold.opacity(0.85) : .clear, radius: 10 * unit)
                                .overlay(alignment: .topTrailing) {
                                    if lunging, let hit {
                                        Text("-\(hit.damage)")
                                            .font(.system(size: 14 * unit, weight: .black, design: .rounded))
                                            .foregroundStyle(MiniGamePalette.ink)
                                            .padding(.horizontal, 6 * unit).padding(.vertical, 2 * unit)
                                            .background(Capsule().fill(MiniGamePalette.goldBright))
                                            .offset(x: 8 * unit, y: -6 * unit)
                                    }
                                }
                            Text(s.name)
                                .font(.system(size: 15 * unit, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 10 * unit).padding(.vertical, 2.5 * unit)
                                .background(Capsule().fill(Color.black.opacity(0.65)))
                                .overlay(Capsule().stroke(model.studentTint(s.id).opacity(0.75), lineWidth: 1.5 * unit))
                        }
                        .offset(y: lunging ? -18 * unit : 0)
                    }
                }
                .position(x: 640 * unit, y: 560 * unit)
            }
            .frame(width: 1280 * unit, height: 720 * unit)
            .onChange(of: model.beat) { _, _ in
                guard let b = model.boss else { return }
                animToken += 1
                let token = animToken
                if !b.lastHits.isEmpty {
                    hurtAt = Date()
                    withAnimation(.easeOut(duration: 0.14)) { hitFlash = true }
                    withAnimation(.default.repeatCount(5, autoreverses: true).speed(4)) { shake = true }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { attacking = true }
                    hitsFloat = false
                    withAnimation(.easeOut(duration: 0.15)) { showHits = true }
                    withAnimation(.easeOut(duration: 1.4)) { hitsFloat = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeOut(duration: 0.25)) { hitFlash = false }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { shake = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                        guard animToken == token else { return }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { attacking = false }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        guard animToken == token else { return }
                        withAnimation(.easeOut(duration: 0.4)) { showHits = false }
                    }
                }
                if b.lastCounter {
                    let lostIndex = b.hearts
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { shatteredHeart = lostIndex }
                    withAnimation(.easeOut(duration: 0.15)) { counterFlash = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            counterFlash = false
                            if shatteredHeart == lostIndex { shatteredHeart = nil }
                        }
                    }
                }
            }
        }
    }
}

// MARK: 2. 守护营地

private struct CampStage: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var hurtAt: Date?
    @State private var cheer = false
    @State private var campWarn = false
    @State private var waveCallout: String?
    @State private var lastWave = 0

    var body: some View {
        if let c = model.camp {
            let cell = 148 * unit
            let left = 294 * unit
            let trailY = 512 * unit
            let dist = CampDefense.length - c.position
            let species = ["slime", "wolf", "caveTroll"][c.wave]
            let monsterH: CGFloat = (c.wave == 2 ? 235 : c.wave == 1 ? 198 : 176) * unit
            let monsterX = dist > 0 ? (left + CGFloat(dist - 1) * cell + cell / 2) : 225 * unit
            let monsterY = trailY - monsterH * 0.56

            ZStack(alignment: .topLeading) {
                // 1) Compact Unified Wave & Progress HUD (y = 82 .. 148)
                HStack(spacing: 16 * unit) {
                    Text("第 \(c.wave + 1) 波 · \(MiniGameModel.monsterName(species))")
                        .font(.system(size: 18 * unit, weight: .heavy, design: .rounded))
                        .foregroundStyle(MiniGamePalette.goldBright)
                        .padding(.horizontal, 12 * unit).padding(.vertical, 5 * unit)
                        .background(Capsule().fill(Color.white.opacity(0.12)))

                    HStack(spacing: 6 * unit) {
                        ForEach(0..<CampDefense.rounds, id: \.self) { i in
                            Circle()
                                .fill(i < c.round ? MiniGamePalette.goldBright : Color.white.opacity(0.28))
                                .frame(width: 17 * unit, height: 17 * unit)
                                .overlay(Circle().stroke(i == c.round ? MiniGamePalette.goldBright : Color.white.opacity(0.4), lineWidth: 1.5 * unit))
                        }
                    }
                    Text("第 \(c.round)/\(CampDefense.rounds) 题")
                        .font(.system(size: 20 * unit, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)

                    Text(dist == 0 ? "营地失守" : "离营地 \(dist) 步")
                        .font(.system(size: 20 * unit, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14 * unit).padding(.vertical, 5 * unit)
                        .background(Capsule().fill(dist <= 2 ? Color(red: 0.86, green: 0.20, blue: 0.20) : Color(red: 0.20, green: 0.62, blue: 0.36)))
                }
                .padding(.horizontal, 20 * unit)
                .padding(.vertical, 10 * unit)
                .background(Capsule().fill(MiniGamePalette.plaqueDark.opacity(0.84)))
                .overlay(Capsule().stroke(MiniGamePalette.goldStroke, lineWidth: 2 * unit))
                .shadow(color: .black.opacity(0.35), radius: 10 * unit, y: 4 * unit)
                .position(x: 640 * unit, y: 114 * unit)

                // 2) Transient Wave Transition Ribbon
                if let callout = waveCallout {
                    Text(callout)
                        .font(.system(size: 28 * unit, weight: .black, design: .rounded))
                        .foregroundStyle(MiniGamePalette.goldBright)
                        .padding(.horizontal, 26 * unit).padding(.vertical, 10 * unit)
                        .background(Capsule().fill(Color(red: 0.56, green: 0.10, blue: 0.12).opacity(0.92)))
                        .overlay(Capsule().stroke(MiniGamePalette.goldStroke, lineWidth: 2.5 * unit))
                        .shadow(color: .black.opacity(0.45), radius: 12 * unit, y: 4 * unit)
                        .position(x: 640 * unit, y: 214 * unit)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                // 3) 6 Numbered Stepping Stones along the dirt trail (step 1 near camp → step 6 forest edge)
                ForEach(1...CampDefense.length, id: \.self) { step in
                    let cx = left + CGFloat(step - 1) * cell + cell / 2
                    let active = step == dist
                    let danger = step <= 2
                    let stoneFill: Color = danger ? Color(red: 0.88, green: 0.34, blue: 0.28) : (step == 3 ? Color(red: 0.90, green: 0.64, blue: 0.24) : Color(red: 0.86, green: 0.77, blue: 0.58))
                    ZStack {
                        RoundedRectangle(cornerRadius: 18 * unit, style: .continuous)
                            .fill(stoneFill.opacity(active ? 0.92 : 0.72))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18 * unit, style: .continuous)
                                    .stroke(active ? MiniGamePalette.goldBright : Color.white.opacity(0.55), lineWidth: (active ? 3.5 : 2) * unit)
                            )
                            .shadow(color: .black.opacity(0.28), radius: 5 * unit, y: 3 * unit)
                        HStack(spacing: 4 * unit) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13 * unit, weight: .bold))
                                .foregroundStyle(danger ? .white.opacity(0.75) : MiniGamePalette.ink.opacity(0.45))
                            Text("\(step)")
                                .font(.system(size: 24 * unit, weight: .black, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(danger ? .white : MiniGamePalette.ink.opacity(0.85))
                        }
                    }
                    .frame(width: cell - 16 * unit, height: 58 * unit)
                    .position(x: cx, y: trailY)
                }

                // 4) Camp Sanctuary + Defending Student Squad (Left Clearing)
                GroundShadow(width: 210 * unit, height: 34 * unit)
                    .position(x: 158 * unit, y: 492 * unit)
                Image("CampTent")
                    .resizable().interpolation(.none).scaledToFit()
                    .frame(width: 218 * unit)
                    .shadow(color: campWarn ? Color.red.opacity(0.75) : Color.black.opacity(0.35), radius: campWarn ? 16 * unit : 8 * unit, y: 4 * unit)
                    .offset(x: campWarn ? -5 * unit : 0)
                    .position(x: 158 * unit, y: 422 * unit)

                Text("营地")
                    .font(.system(size: 18 * unit, weight: .heavy, design: .rounded))
                    .foregroundStyle(MiniGamePalette.goldBright)
                    .padding(.horizontal, 14 * unit).padding(.vertical, 4 * unit)
                    .background(Capsule().fill(MiniGamePalette.plaqueDark.opacity(0.88)))
                    .overlay(Capsule().stroke(MiniGamePalette.goldStroke, lineWidth: 1.5 * unit))
                    .position(x: 158 * unit, y: 506 * unit)

                HStack(spacing: -8 * unit) {
                    ForEach(model.students.prefix(6)) { s in
                        MiniGameFace(student: s, size: 44 * unit, tint: model.studentTint(s.id))
                            .offset(y: cheer ? -10 * unit : 0)
                    }
                }
                .position(x: 158 * unit, y: 564 * unit)

                // 5) Monster centered EXACTLY over its stepping stone (cleanly above the step numeral!)
                GroundShadow(width: (c.wave == 2 ? 160 : 124) * unit, height: 22 * unit)
                    .position(x: monsterX, y: trailY - 14 * unit)
                MiniGameMonster(id: species, height: monsterH, hurtAt: hurtAt, dead: c.outcome == .won)
                    .shadow(color: .black.opacity(0.38), radius: 8 * unit, y: 4 * unit)
                    .position(x: monsterX, y: monsterY)
            }
            .frame(width: 1280 * unit, height: 720 * unit)
            .onChange(of: model.beat) { _, _ in
                guard let c = model.camp else { return }
                if c.lastMove < 1 {
                    hurtAt = Date()
                    if c.lastMove == -1 {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { cheer = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                            withAnimation(.easeOut(duration: 0.25)) { cheer = false }
                        }
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

// MARK: 3. 答题赛跑

private struct RaceStage: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var shownRoll: (side: String, roll: Int)?

    var body: some View {
        if let r = model.race {
            let lanes = max(1, r.sides.count)
            let top = 114 * unit
            let bottom = 110 * unit
            let laneAreaH = 720 * unit - top - bottom
            let laneH = min(140 * unit, laneAreaH / CGFloat(lanes))
            let laneW = 1216 * unit
            let laneLeft = (1280 * unit - laneW) / 2
            let plateW = 132 * unit
            let trackLeft = laneLeft + plateW + 10 * unit
            let trackW = laneW - plateW - 20 * unit
            let cellW = trackW / CGFloat(RaceTrack.length + 1)

            ZStack(alignment: .topLeading) {
                // 1) Compact Always-Visible Legend Strip (y = 88)
                HStack(spacing: 16 * unit) {
                    legendItem("gift.fill", color: .pink, text: "礼物转盘")
                    legendItem("bolt.fill", color: MiniGamePalette.gold, text: "闪电 +3")
                    legendItem("exclamationmark.triangle.fill", color: .orange, text: "陷阱答错 -2")
                    legendItem("flag.checkered", color: .white, text: "冲线获胜")
                }
                .padding(.horizontal, 18 * unit).padding(.vertical, 6 * unit)
                .background(Capsule().fill(MiniGamePalette.plaqueDark.opacity(0.78)))
                .overlay(Capsule().stroke(MiniGamePalette.gold.opacity(0.6), lineWidth: 1.5 * unit))
                .position(x: 640 * unit, y: 88 * unit)

                // 2) Transient Pipped RPG Die Roll Pop-Up (top-right corner, clears automatically)
                if let rolled = shownRoll {
                    HStack(spacing: 10 * unit) {
                        RaceDieFace(value: rolled.roll, size: 52 * unit)
                        VStack(alignment: .leading, spacing: 1 * unit) {
                            Text(model.name(rolled.side))
                                .font(.system(size: 14 * unit, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.85))
                            Text("+\(rolled.roll) 格")
                                .font(.system(size: 22 * unit, weight: .black, design: .rounded))
                                .foregroundStyle(MiniGamePalette.goldBright)
                        }
                    }
                    .padding(.horizontal, 14 * unit).padding(.vertical, 8 * unit)
                    .background(RoundedRectangle(cornerRadius: 16 * unit, style: .continuous).fill(MiniGamePalette.plaqueDark.opacity(0.92)))
                    .overlay(RoundedRectangle(cornerRadius: 16 * unit, style: .continuous).stroke(MiniGamePalette.goldStroke, lineWidth: 2.5 * unit))
                    .shadow(color: .black.opacity(0.4), radius: 10 * unit, y: 4 * unit)
                    .position(x: 1146 * unit, y: 56 * unit)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }

                // 3) Centered Symmetric Race Lanes with Dedicated Left Nameplates
                ForEach(Array(r.sides.enumerated()), id: \.element.id) { lane, side in
                    let y = top + (laneAreaH - laneH * CGFloat(lanes)) / 2 + CGFloat(lane) * laneH
                    let midY = y + laneH / 2
                    let current = r.current?.id == side.id && r.winner == nil
                    let at = r.positions[side.id] ?? 0
                    let sideColor = model.tint(side.id)
                    let cellH = min(74 * unit, laneH - 22 * unit)

                    // Lane frosted track panel
                    RoundedRectangle(cornerRadius: 16 * unit, style: .continuous)
                        .fill(Color.white.opacity(current ? 0.86 : 0.68))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16 * unit, style: .continuous)
                                .fill(sideColor.opacity(current ? 0.18 : 0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16 * unit, style: .continuous)
                                .stroke(current ? MiniGamePalette.goldStroke : LinearGradient(colors: [.white.opacity(0.7)], startPoint: .top, endPoint: .bottom), lineWidth: (current ? 4 : 1.5) * unit)
                        )
                        .shadow(color: current ? MiniGamePalette.gold.opacity(0.45) : Color.black.opacity(0.18), radius: (current ? 10 : 5) * unit, y: 3 * unit)
                        .frame(width: laneW, height: laneH - 10 * unit)
                        .position(x: 640 * unit, y: midY)

                    // Left Team/Player Nameplate (never overlaps lane top border!)
                    HStack(spacing: 6 * unit) {
                        RoundedRectangle(cornerRadius: 4 * unit)
                            .fill(sideColor)
                            .frame(width: 6 * unit, height: max(28 * unit, laneH - 36 * unit))
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
                    .frame(width: plateW - 12 * unit)
                    .position(x: laneLeft + plateW / 2 + 4 * unit, y: midY)

                    // 21 Symmetric Track Tiles
                    ForEach(0...RaceTrack.length, id: \.self) { i in
                        let passed = i > 0 && i <= at
                        cellView(r.cells[i], index: i, passed: passed, sideColor: sideColor)
                            .frame(width: cellW - 4 * unit, height: cellH)
                            .position(x: trackLeft + CGFloat(i) * cellW + cellW / 2, y: midY)
                    }

                    // Runner Token centered squarely on tile `at`
                    let tokenSize = side.members.count > 1 ? min(44 * unit, laneH - 32 * unit) : min(60 * unit, laneH - 22 * unit)
                    token(side, size: tokenSize, trapped: r.trapped.contains(side.id), active: current)
                        .position(x: trackLeft + CGFloat(at) * cellW + cellW / 2, y: midY)
                }
            }
            .frame(width: 1280 * unit, height: 720 * unit)
            .onChange(of: model.beat) { _, _ in
                guard let r = model.race else { return }
                for e in r.events {
                    if case .moved(let side, let roll, _) = e {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { shownRoll = (side, roll) }
                        let expected = (side, roll)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                            if shownRoll?.side == expected.0 && shownRoll?.roll == expected.1 {
                                withAnimation(.easeOut(duration: 0.3)) { shownRoll = nil }
                            }
                        }
                        break
                    }
                }
            }
        }
    }

    private func legendItem(_ symbol: String, color: Color, text: String) -> some View {
        HStack(spacing: 5 * unit) {
            Image(systemName: symbol).font(.system(size: 14 * unit, weight: .bold)).foregroundStyle(color)
            Text(text).font(.system(size: 14 * unit, weight: .bold, design: .rounded)).foregroundStyle(.white)
        }
    }

    @ViewBuilder private func cellView(_ cell: RaceTrack.Cell, index: Int, passed: Bool, sideColor: Color) -> some View {
        let symbol: String? = switch cell { case .reward: "gift.fill"; case .trap: "exclamationmark.triangle.fill"; case .boost: "bolt.fill"; case .finish: "flag.checkered"; case .plain: nil }
        let color: Color = switch cell {
        case .reward: Color(red: 0.92, green: 0.32, blue: 0.56)
        case .trap: Color(red: 0.92, green: 0.48, blue: 0.14)
        case .boost: Color(red: 0.94, green: 0.72, blue: 0.12)
        case .finish: MiniGamePalette.plaqueDark
        case .plain: .white
        }
        RoundedRectangle(cornerRadius: 8 * unit, style: .continuous)
            .fill(cell == .plain ? (passed ? sideColor.opacity(0.24) : Color.white.opacity(0.84)) : color.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 8 * unit, style: .continuous)
                    .stroke(cell == .finish ? MiniGamePalette.gold : (cell == .plain ? Color.black.opacity(0.08) : Color.white.opacity(0.55)), lineWidth: (cell == .finish ? 2 : 1) * unit)
            )
            .overlay {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 19 * unit, weight: .bold))
                        .foregroundStyle(cell == .finish ? MiniGamePalette.goldBright : .white)
                        .shadow(color: .black.opacity(0.25), radius: 1 * unit)
                } else {
                    Text(index == 0 ? "起" : "\(index)")
                        .font(.system(size: 13 * unit, weight: .heavy, design: .rounded))
                        .foregroundStyle(passed ? sideColor : MiniGamePalette.ink.opacity(0.42))
                }
            }
    }

    private func token(_ side: MiniGameSide, size: CGFloat, trapped: Bool, active: Bool) -> some View {
        HStack(spacing: -size * 0.34) {
            ForEach(side.members.prefix(3), id: \.self) { id in
                MiniGameFace(student: model.student(id), size: size, tint: model.tint(side.id))
            }
        }
        .scaleEffect(active ? 1.06 : 1.0)
        .overlay(alignment: .bottomTrailing) {
            if trapped {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18 * unit, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4 * unit)
                    .background(Circle().fill(Color.orange))
                    .overlay(Circle().stroke(.white, lineWidth: 1.5 * unit))
                    .offset(x: 6 * unit, y: 6 * unit)
            }
        }
    }
}

/// Crisp 6-sided RPG ivory-and-gold pipped die face.
private struct RaceDieFace: View {
    let value: Int
    let size: CGFloat
    private var pips: [(CGFloat, CGFloat)] {
        switch value {
        case 1: [(0.5, 0.5)]
        case 2: [(0.28, 0.28), (0.72, 0.72)]
        case 3: [(0.28, 0.28), (0.5, 0.5), (0.72, 0.72)]
        case 4: [(0.28, 0.28), (0.72, 0.28), (0.28, 0.72), (0.72, 0.72)]
        case 5: [(0.28, 0.28), (0.72, 0.28), (0.5, 0.5), (0.28, 0.72), (0.72, 0.72)]
        default: [(0.28, 0.24), (0.72, 0.24), (0.28, 0.5), (0.72, 0.5), (0.28, 0.76), (0.72, 0.76)]
        }
    }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [MiniGamePalette.parchmentTop, MiniGamePalette.parchmentBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).stroke(MiniGamePalette.goldStroke, lineWidth: size * 0.06))
            ForEach(Array(pips.enumerated()), id: \.offset) { _, p in
                Circle()
                    .fill(value == 1 || value == 6 ? Color(red: 0.82, green: 0.16, blue: 0.18) : MiniGamePalette.ink)
                    .frame(width: size * 0.19, height: size * 0.19)
                    .position(x: p.0 * size, y: p.1 * size)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: 4. 翻牌寻宝

private struct MemoryStage: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    var body: some View {
        if let m = model.memory {
            let layout = MemoryBoardLayout(count: m.cards.count, unit: unit)
            ZStack(alignment: .topLeading) {
                // Card Grid — exact coordinates shared with MiniGameTapLayer
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

                // Right-Side Treasure Scoreboard Column
                VStack(alignment: .leading, spacing: 12 * unit) {
                    ForEach(m.sides) { side in
                        let turn = m.current?.id == side.id && !m.finished
                        let sideColor = model.tint(side.id)
                        HStack(spacing: 10 * unit) {
                            HStack(spacing: -10 * unit) {
                                ForEach(side.members.prefix(2), id: \.self) { id in
                                    MiniGameFace(student: model.student(id), size: 36 * unit, tint: sideColor)
                                }
                            }
                            VStack(alignment: .leading, spacing: 1 * unit) {
                                Text(side.name)
                                    .font(.system(size: 21 * unit, weight: .heavy, design: .rounded))
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
                                .font(.system(size: 28 * unit, weight: .black, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(MiniGamePalette.ink)
                        }
                        .padding(.horizontal, 14 * unit).padding(.vertical, 10 * unit)
                        .frame(width: layout.sideWidth)
                        .background(
                            RoundedRectangle(cornerRadius: 16 * unit, style: .continuous)
                                .fill(LinearGradient(colors: [MiniGamePalette.parchmentTop.opacity(turn ? 0.98 : 0.84), MiniGamePalette.parchmentBottom.opacity(turn ? 0.96 : 0.76)], startPoint: .top, endPoint: .bottom))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16 * unit, style: .continuous)
                                .stroke(turn ? MiniGamePalette.goldStroke : LinearGradient(colors: [Color(red: 0.56, green: 0.42, blue: 0.24).opacity(0.45)], startPoint: .top, endPoint: .bottom), lineWidth: (turn ? 4 : 2) * unit)
                        )
                        .shadow(color: turn ? MiniGamePalette.gold.opacity(0.45) : Color.black.opacity(0.18), radius: (turn ? 10 : 4) * unit, y: 3 * unit)
                        .scaleEffect(turn ? 1.03 : 1.0)
                    }
                }
                .position(x: layout.sideX, y: 346 * unit)
            }
            .frame(width: 1280 * unit, height: 720 * unit)
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
            // Back: royal navy & gold ornate RPG card with real pixel-art closed chest + golden number coin
            RoundedRectangle(cornerRadius: 15 * unit, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.22, green: 0.30, blue: 0.56), Color(red: 0.13, green: 0.18, blue: 0.38)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 11 * unit, style: .continuous)
                        .stroke(MiniGamePalette.gold.opacity(0.42), lineWidth: 1.5 * unit)
                        .padding(6 * unit)
                )
                .overlay {
                    HStack(spacing: 10 * unit) {
                        Image("MiniGameChestClosed")
                            .resizable().interpolation(.none).scaledToFit()
                            .frame(width: min(64 * unit, size.height * 0.58), height: min(64 * unit, size.height * 0.58))
                            .shadow(color: .black.opacity(0.45), radius: 4 * unit, y: 2 * unit)
                        Text("\(number)")
                            .font(.system(size: 24 * unit, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(MiniGamePalette.goldBright)
                            .frame(width: 38 * unit, height: 38 * unit)
                            .background(Circle().fill(Color.black.opacity(0.32)))
                            .overlay(Circle().stroke(MiniGamePalette.gold.opacity(0.75), lineWidth: 1.5 * unit))
                    }
                }
                .opacity(shown ? 0 : 1)

            // Front: warm parchment word card (with #number + EN/中 tag), or claimed team treasure card
            RoundedRectangle(cornerRadius: 15 * unit, style: .continuous)
                .fill(
                    owner.map { AnyShapeStyle(LinearGradient(colors: [$0.opacity(0.95), $0.opacity(0.80)], startPoint: .top, endPoint: .bottom)) }
                    ?? AnyShapeStyle(LinearGradient(colors: [Color.white, Color(red: 0.99, green: 0.96, blue: 0.90)], startPoint: .top, endPoint: .bottom))
                )
                .overlay {
                    Text(card.text)
                        .font(.system(size: (card.english ? 28 : 30) * unit, weight: .heavy, design: .rounded))
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
                        .foregroundStyle(owner != nil ? .white.opacity(0.8) : MiniGamePalette.ink.opacity(0.5))
                        .padding(.horizontal, 7 * unit).padding(.vertical, 2 * unit)
                        .background(Capsule().fill(owner != nil ? Color.black.opacity(0.22) : Color.black.opacity(0.06)))
                        .padding(7 * unit)
                }
                .overlay(alignment: .topTrailing) {
                    if owner != nil {
                        Image("MiniGameChestOpen")
                            .resizable().interpolation(.none).scaledToFit()
                            .frame(width: 30 * unit, height: 30 * unit)
                            .padding(6 * unit)
                    } else {
                        Text(card.english ? "EN" : "中")
                            .font(.system(size: 11 * unit, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7 * unit).padding(.vertical, 2 * unit)
                            .background(Capsule().fill(card.english ? Color(red: 0.24, green: 0.54, blue: 0.88) : Color(red: 0.86, green: 0.54, blue: 0.16)))
                            .padding(7 * unit)
                    }
                }
                .opacity(shown ? 1 : 0)
        }
        .frame(width: size.width, height: size.height)
        .overlay(
            RoundedRectangle(cornerRadius: 15 * unit, style: .continuous)
                .stroke(border, lineWidth: (highlight == .pairReady || highlight == .mismatch ? 4 : 2.5) * unit)
        )
        // Flat pop transition (no 3D rotation: 180° rotation3DEffect mirrors the window on Mac Catalyst).
        .scaleEffect(shown ? (highlight == .pairReady ? 1.03 : 1.0) : 0.96)
        .shadow(color: highlight == .pairReady ? MiniGamePalette.gold.opacity(0.65) : Color.black.opacity(0.24), radius: (highlight == .pairReady ? 12 : 6) * unit, y: 3 * unit)
    }
}

// MARK: 5. 擂台王

private struct ArenaStage: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    var body: some View {
        if let a = model.arena {
            ZStack {
                // 1) Top-Left: Next-in-line Queue (hidden when 2 players only; zero overlap with bottom banner!)
                if !a.line.isEmpty {
                    VStack(alignment: .leading, spacing: 6 * unit) {
                        Text("下一位挑战")
                            .font(.system(size: 15 * unit, weight: .heavy, design: .rounded))
                            .foregroundStyle(MiniGamePalette.goldBright)
                        HStack(spacing: 8 * unit) {
                            ForEach(a.line.prefix(5), id: \.self) { id in
                                VStack(spacing: 2 * unit) {
                                    MiniGameFace(student: model.student(id), size: 44 * unit, tint: model.studentTint(id))
                                    Text(model.name(id))
                                        .font(.system(size: 12 * unit, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14 * unit).padding(.vertical, 10 * unit)
                    .background(RoundedRectangle(cornerRadius: 16 * unit, style: .continuous).fill(MiniGamePalette.plaqueDark.opacity(0.84)))
                    .overlay(RoundedRectangle(cornerRadius: 16 * unit, style: .continuous).stroke(MiniGamePalette.goldStroke, lineWidth: 2 * unit))
                    .shadow(color: .black.opacity(0.35), radius: 8 * unit, y: 4 * unit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 16 * unit).padding(.leading, 20 * unit)
                }

                // 2) Top-Right: Compact Wins Leaderboard (high in the corner, completely clear of Challenger!)
                VStack(alignment: .leading, spacing: 5 * unit) {
                    HStack(spacing: 6 * unit) {
                        Image("MiniGameCrown").resizable().interpolation(.none).scaledToFit().frame(width: 20 * unit, height: 20 * unit)
                        Text("胜场榜").font(.system(size: 16 * unit, weight: .heavy, design: .rounded)).foregroundStyle(MiniGamePalette.goldBright)
                    }
                    ForEach(Array(a.ranking(model.students.map(\.id)).prefix(6).enumerated()), id: \.element) { rank, id in
                        HStack(spacing: 6 * unit) {
                            Text("\(rank + 1)")
                                .font(.system(size: 13 * unit, weight: .black, design: .rounded))
                                .foregroundStyle(rank == 0 ? MiniGamePalette.goldBright : .white.opacity(0.6))
                                .frame(width: 16 * unit)
                            Text(model.name(id))
                                .lineLimit(1)
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(a.wins[id] ?? 0)")
                                .monospacedDigit()
                                .foregroundStyle(MiniGamePalette.goldBright)
                        }
                        .font(.system(size: 16 * unit, weight: .bold, design: .rounded))
                    }
                }
                .frame(width: 186 * unit)
                .padding(.horizontal, 14 * unit).padding(.vertical, 10 * unit)
                .background(RoundedRectangle(cornerRadius: 16 * unit, style: .continuous).fill(MiniGamePalette.plaqueDark.opacity(0.84)))
                .overlay(RoundedRectangle(cornerRadius: 16 * unit, style: .continuous).stroke(MiniGamePalette.goldStroke, lineWidth: 2 * unit))
                .shadow(color: .black.opacity(0.35), radius: 8 * unit, y: 4 * unit)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 16 * unit).padding(.trailing, 20 * unit)

                // 3) Champion (Left) & Challenger (Right) standing squarely on the Colosseum stone platform
                fighter(a.champion, champion: true, streak: a.streak)
                    .id("champ-\(a.champion)")
                    .position(x: 420 * unit, y: 422 * unit)

                vsEmblem
                    .position(x: 640 * unit, y: 396 * unit)

                fighter(a.challenger, champion: false, streak: 0)
                    .id("chal-\(a.challenger)")
                    .position(x: 860 * unit, y: 422 * unit)
            }
            .frame(width: 1280 * unit, height: 720 * unit)
        }
    }

    private var vsEmblem: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.orange.opacity(0.55), Color.red.opacity(0.2), .clear], center: .center, startRadius: 6 * unit, endRadius: 72 * unit))
                .frame(width: 144 * unit, height: 144 * unit)
            Text("VS")
                .font(.system(size: 74 * unit, weight: .black, design: .rounded))
                .italic()
                .foregroundStyle(LinearGradient(colors: [MiniGamePalette.goldBright, Color(red: 1.0, green: 0.42, blue: 0.16), Color(red: 0.84, green: 0.12, blue: 0.16)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.85), radius: 4 * unit, y: 3 * unit)
                .shadow(color: MiniGamePalette.gold.opacity(0.55), radius: 12 * unit)
        }
    }

    private func fighter(_ id: String, champion: Bool, streak: Int) -> some View {
        let crownSize = (54 + CGFloat(min(streak, 5)) * 6) * unit
        return VStack(spacing: 4 * unit) {
            ZStack {
                if champion {
                    Circle()
                        .fill(RadialGradient(colors: [MiniGamePalette.gold.opacity(0.55), .clear], center: .center, startRadius: 4 * unit, endRadius: crownSize * 0.8))
                        .frame(width: crownSize * 1.6, height: crownSize * 1.4)
                    Image("MiniGameCrown")
                        .resizable().interpolation(.none).scaledToFit()
                        .frame(width: crownSize, height: crownSize)
                        .shadow(color: .black.opacity(0.45), radius: 4 * unit, y: 2 * unit)
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 42 * unit, weight: .black))
                        .foregroundStyle(LinearGradient(colors: [MiniGamePalette.goldBright, .orange], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.65), radius: 4 * unit, y: 2 * unit)
                }
            }
            .frame(height: 68 * unit)

            ZStack(alignment: .bottom) {
                GroundShadow(width: 138 * unit, height: 26 * unit)
                    .offset(y: 6 * unit)
                MiniGameFigure(student: model.student(id), height: 226 * unit, mirrored: !champion)
            }

            // High-contrast RPG nameplate cleanly below feet, never touching any stage border
            VStack(spacing: 2 * unit) {
                Text(model.name(id))
                    .font(.system(size: 28 * unit, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(champion ? (streak > 0 ? "擂主 · 连胜 \(streak)" : "现任擂主") : "挑战者")
                    .font(.system(size: 14 * unit, weight: .heavy, design: .rounded))
                    .foregroundStyle(champion ? MiniGamePalette.goldBright : Color.white.opacity(0.85))
            }
            .padding(.horizontal, 22 * unit)
            .padding(.vertical, 7 * unit)
            .background(
                RoundedRectangle(cornerRadius: 16 * unit, style: .continuous)
                    .fill(
                        champion
                        ? LinearGradient(colors: [Color(red: 0.72, green: 0.32, blue: 0.08).opacity(0.94), Color(red: 0.44, green: 0.16, blue: 0.06).opacity(0.94)], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [MiniGamePalette.plaqueDark.opacity(0.92), Color(red: 0.18, green: 0.22, blue: 0.30).opacity(0.92)], startPoint: .top, endPoint: .bottom)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16 * unit, style: .continuous)
                    .stroke(champion ? MiniGamePalette.goldStroke : LinearGradient(colors: [model.studentTint(id), model.studentTint(id).opacity(0.6)], startPoint: .top, endPoint: .bottom), lineWidth: 2.5 * unit)
            )
            .shadow(color: .black.opacity(0.45), radius: 8 * unit, y: 4 * unit)
            .padding(.top, 8 * unit)
        }
        .transition(.asymmetric(insertion: .scale(scale: 0.82).combined(with: .opacity), removal: .opacity))
    }
}
