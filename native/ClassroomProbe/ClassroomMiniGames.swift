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
        var rule: String {
            switch self {
            case .boss: "全班一起打Boss：答对的人掷骰子攻击（★d4 ★★d6 ★★★d10），答对不到一半Boss反击，掉一颗心。"
            case .camp: "怪物每题走近一步：全对打退一步，一半以上答对守住，撑过12题营地安全。"
            case .race: "轮到的队答题，答对掷骰前进；礼物格转转盘，陷阱格下回合答错退2格，闪电格再冲3格。"
            case .memory: "轮流翻两张牌，英文和中文配上了要大声读出来，读对拿走宝箱并再翻一次。"
            case .arena: "擂主和挑战者答同一道题：挑战者答对而擂主答错，或答对★★★题，就上擂台；连胜3场转转盘。"
            }
        }
    }
    struct Student: Identifiable { let id: String; let name: String; let look: PixelHeroLook; let seat: Int }

    let kind: Kind
    let students: [Student]
    /// Side id → colour index (teams by their order, students by seat).
    let tints: [String: Int]
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
        var sides = MiniGameSide.sides(state)
        if sides.first.map({ $0.members.count == 1 }) == true { sides.sort { seats($0.id) < seats($1.id) } }
        var t: [String: Int] = [:]
        for (i, s) in sides.enumerated() { t[s.id] = state.teams.firstIndex { $0.id == s.id } ?? i }
        for s in ordered { t[s.id] = t[s.id] ?? (seats(s.id) - 1) }
        tints = t
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
        case .race: race?.current.map { s in s.members.count == 1 ? s.name : "\(s.name)（\(s.members.map(name).joined(separator: "、"))）" }
        case .arena: arena.map { "\(name($0.champion)) 对 \(name($0.challenger))" }
        default: nil
        }
    }

    /// A question was answered: applied once the answer card is gone (or straight away when none shows).
    func queue(_ round: MiniGameRound, quiz token: Int?) {
        guard !finished else { return }
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
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
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
            case .memory: break
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
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { m.flip(i); memory = m }
        switch m.phase {
        case .judging: banner = "配对成功！\(m.current.map { name($0.id) } ?? "")大声读出来"
        case .mismatch:
            banner = "没配上"
            let up = m.faceUp
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                guard let self, self.memory?.faceUp == up else { return }
                self.turnBack()
            }
        case .picking: banner = nil
        }
    }
    func turnBack() {
        guard var m = memory, m.phase == .mismatch else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { m.turnBack(); memory = m; banner = "轮到 \(m.current.map { name($0.id) } ?? "")" }
    }
    func judge(right: Bool) {
        guard var m = memory, m.phase == .judging else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            let who = m.current.map { name($0.id) } ?? ""
            m.judge(right: right); memory = m; beat += 1
            banner = m.finished ? "宝箱全部找到了！" : right ? "\(who) 拿走宝箱，再翻一次！" : "读错了，宝箱合上，轮到 \(m.current.map { name($0.id) } ?? "")"
        }
    }
}

enum MiniGamePalette {
    static let sides: [Color] = [Color(red: 0.90, green: 0.36, blue: 0.36), Color(red: 0.36, green: 0.56, blue: 0.92), Color(red: 0.32, green: 0.70, blue: 0.44),
                                 Color(red: 0.88, green: 0.68, blue: 0.22), Color(red: 0.66, green: 0.44, blue: 0.88), Color(red: 0.94, green: 0.56, blue: 0.26), Color(red: 0.30, green: 0.72, blue: 0.80)]
    static func side(_ i: Int) -> Color { sides[((i % sides.count) + sides.count) % sides.count] }
    static let ink = Color(red: 0.13, green: 0.20, blue: 0.24)
    static let gold = Color(red: 0.96, green: 0.76, blue: 0.24)
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
        message = "\(kind.title)开始：" + (kind == .memory ? "在下方点牌翻开" : "点“出题”或按 ⇧Q 出全班题")
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
        if grantBookPlayers(ids, movement: 0, coins: 0, score: score) { g.rewarded = true; g.banner = "获胜奖励：\(ids.map(g.name).joined(separator: "、")) 每人 +\(score) 积分" }
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
                Spacer(minLength: 4)
                if model.finished {
                    Button { game.rewardMiniGameWinners() } label: { Label(model.rewarded ? "已发奖励" : "获胜者 +5 积分", systemImage: "star.fill") }
                        .buttonStyle(GlassIconButtonStyle(tint: .orange, prominent: !model.rewarded)).disabled(model.rewarded || model.winners.isEmpty)
                    Button { game.startMiniGame(model.kind) } label: { Label("再来一局", systemImage: "arrow.clockwise") }.buttonStyle(GlassIconButtonStyle())
                } else if model.kind == .arena {
                    Button { game.rewardMiniGameWinners() } label: { Label("给领先者 +5 积分", systemImage: "star") }
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
        case .camp: if let c = model.camp { Text("第 \(c.round)/\(CampDefense.rounds) 题 · 怪物离营地 \(CampDefense.length - c.position) 步") }
        case .race:
            if let r = model.race {
                if let w = r.winner { Text("\(model.name(w)) 获胜") } else { Text("轮到 \(model.answering ?? "") 答题" + (r.current.map { r.trapped.contains($0.id) } == true ? " · 陷阱中" : "")) }
            }
        case .arena: Text("擂台：\(model.answering ?? "") · 在全班题里记下这两人的答案")
        case .memory:
            if let m = model.memory {
                Text(m.finished ? "全部找到" : "轮到 \(m.current.map { model.name($0.id) } ?? "") · " + (m.phase == .judging ? "读对了吗？" : m.phase == .mismatch ? "没配上" : "点两张牌"))
            }
        }
    }
}

/// The teacher's copy of the memory board: tap to turn a card; after a pair, judge the reading.
private struct MemoryTeacherGrid: View {
    @ObservedObject var model: MiniGameModel
    let memory: MemoryMatch
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: max(4, (memory.cards.count + 1) / 2))
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(memory.cards.indices, id: \.self) { i in
                    let card = memory.cards[i], up = memory.faceUp.contains(i), done = memory.matched(i)
                    Button { model.flip(i) } label: {
                        Text(up || done ? card.text : "\(i + 1)").font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .foregroundStyle(done ? .white : MiniGamePalette.ink)
                            .background(RoundedRectangle(cornerRadius: 7).fill(done ? model.tint(memory.owner[card.pair] ?? "") : up ? Color.yellow.opacity(0.55) : Color.white.opacity(0.6)))
                    }.buttonStyle(.plain).disabled(!memory.canFlip(i))
                }
            }
            if memory.phase == .judging {
                VStack(spacing: 6) {
                    Button { model.judge(right: true) } label: { Label("读对了", systemImage: "checkmark.circle.fill") }.buttonStyle(GlassIconButtonStyle(tint: .green, prominent: true))
                    Button { model.judge(right: false) } label: { Label("读错了", systemImage: "xmark.circle.fill") }.buttonStyle(GlassIconButtonStyle(tint: .red))
                }
            } else if memory.phase == .mismatch {
                Button { model.turnBack() } label: { Label("翻回去", systemImage: "arrow.uturn.backward") }.buttonStyle(GlassIconButtonStyle())
            }
        }
    }
}

// MARK: TV stage (1280 × 720 design, scaled by `unit`)

struct MiniGameStage: View {
    @ObservedObject var model: MiniGameModel
    var body: some View {
        GeometryReader { g in
            // The board is laid out on a 1280 × 720 canvas, fitted into whatever shape shows it (TV, a narrower preview).
            let unit = min(g.size.height / 720, g.size.width / 1280)
            ZStack {
                LinearGradient(colors: [Color(red: 0.62, green: 0.84, blue: 0.95), Color(red: 0.80, green: 0.93, blue: 0.86), Color(red: 0.55, green: 0.78, blue: 0.45)], startPoint: .top, endPoint: .bottom)
                MiniGameBoard(model: model, unit: unit).frame(width: 1280 * unit, height: 720 * unit)
            }.frame(width: g.size.width, height: g.size.height)
        }
        .transition(.opacity)
    }
}

private struct MiniGameBoard: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
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
            VStack {
                HStack(spacing: 12 * unit) {
                    Image(systemName: model.kind.icon).font(.system(size: 30 * unit, weight: .heavy))
                    Text(model.kind.title).font(.system(size: 34 * unit, weight: .heavy, design: .rounded))
                }.foregroundStyle(.white).padding(.horizontal, 22 * unit).padding(.vertical, 8 * unit)
                    .background(Capsule().fill(MiniGamePalette.ink.opacity(0.72))).padding(.top, 14 * unit)
                Spacer()
                if let line = model.banner {
                    Text(line).font(.system(size: 30 * unit, weight: .heavy, design: .rounded)).foregroundStyle(MiniGamePalette.ink)
                        .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.6)
                        .padding(.horizontal, 28 * unit).padding(.vertical, 12 * unit)
                        .background(RoundedRectangle(cornerRadius: 22 * unit, style: .continuous).fill(.white.opacity(0.9)))
                        .overlay(RoundedRectangle(cornerRadius: 22 * unit, style: .continuous).stroke(MiniGamePalette.gold, lineWidth: 3 * unit))
                        .id(model.beat).transition(.scale(scale: 0.8).combined(with: .opacity))
                        .padding(.bottom, 18 * unit).padding(.horizontal, 60 * unit)
                }
            }
            if model.finished { MiniGameFinale(model: model, unit: unit) }
        }
    }
}

private struct MiniGameFinale: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var pop = false
    var body: some View {
        let won = model.kind == .boss ? model.boss?.outcome == .won : model.kind == .camp ? model.camp?.outcome == .won : true
        VStack(spacing: 10 * unit) {
            Text(won ? "胜利！" : "失败了").font(.system(size: 92 * unit, weight: .black, design: .rounded))
                .foregroundStyle(won ? MiniGamePalette.gold : .white).shadow(color: .black.opacity(0.35), radius: 6 * unit, y: 4 * unit)
            if won, !model.winners.isEmpty, model.kind != .boss, model.kind != .camp {
                Text(model.winners.map(model.name).joined(separator: "、")).font(.system(size: 34 * unit, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            }
        }
        .padding(40 * unit).background(RoundedRectangle(cornerRadius: 36 * unit).fill(.black.opacity(0.35)))
        .scaleEffect(pop ? 1 : 0.4).opacity(pop ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.55).delay(0.4)) { pop = true } }
        .offset(y: -40 * unit)
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
            Circle().fill(tint.opacity(0.9))
            if let image {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFill().frame(width: size * 0.9, height: size * 0.9).clipShape(Circle())
            } else {
                Text(String(student?.name.prefix(1) ?? "?")).font(.system(size: size * 0.45, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size).overlay(Circle().stroke(.white, lineWidth: size * 0.06))
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
                MiniGameFace(student: student, size: height * 0.5)
            }
        }
        .frame(height: height).scaleEffect(x: mirrored ? -1 : 1, y: 1)
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
            if let image { Image(uiImage: image).resizable().interpolation(.none).scaledToFit().frame(height: height) }
            else { Image(systemName: "pawprint.fill").font(.system(size: height * 0.5)).foregroundStyle(.brown) }
        }
    }
}

// MARK: Boss

private struct BossStage: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var hurtAt: Date?
    @State private var shake = false
    @State private var counterFlash = false
    var body: some View {
        if let b = model.boss {
            ZStack {
                if counterFlash { Color.red.opacity(0.25).transition(.opacity) }
                VStack(spacing: 14 * unit) {
                    Spacer().frame(height: 80 * unit)
                    // Boss HP and the class's hearts.
                    HStack(spacing: 22 * unit) {
                        HStack(spacing: 6 * unit) {
                            ForEach(0..<BossRaid.hearts, id: \.self) { i in
                                Image(systemName: i < b.hearts ? "heart.fill" : "heart.slash").font(.system(size: 34 * unit, weight: .bold))
                                    .foregroundStyle(i < b.hearts ? .red : .gray.opacity(0.6))
                                    .scaleEffect(i == b.hearts && b.lastCounter ? 1.3 : 1)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4 * unit) {
                            Text("Boss  \(b.hp) / \(b.maxHP)").font(.system(size: 24 * unit, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(MiniGamePalette.ink)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.black.opacity(0.25))
                                    Capsule().fill(LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: g.size.width * CGFloat(b.hp) / CGFloat(max(1, b.maxHP)))
                                }
                            }.frame(width: 560 * unit, height: 28 * unit).overlay(Capsule().stroke(.white, lineWidth: 3 * unit))
                        }
                    }.padding(.horizontal, 24 * unit).padding(.vertical, 12 * unit).background(RoundedRectangle(cornerRadius: 20 * unit).fill(.white.opacity(0.7)))
                    MiniGameMonster(id: b.monster, height: 330 * unit, hurtAt: hurtAt, dead: b.outcome == .won)
                        .scaleEffect(x: -1.25, y: 1.25).offset(x: shake ? 14 * unit : 0)
                        .overlay(alignment: .top) { hits(b) }
                    Spacer()
                }
                VStack {
                    Spacer()
                    HStack(spacing: 16 * unit) {
                        ForEach(model.students) { s in
                            let hit = b.lastHits.first { $0.player == s.id }
                            VStack(spacing: 4 * unit) {
                                MiniGameFace(student: s, size: 64 * unit, tint: MiniGamePalette.side(s.seat - 1))
                                Text(s.name).font(.system(size: 16 * unit, weight: .bold, design: .rounded)).foregroundStyle(MiniGamePalette.ink).lineLimit(1)
                            }
                            .offset(y: hit != nil ? -16 * unit : 0)
                        }
                    }.padding(.bottom, 92 * unit)
                }
            }
            .onChange(of: model.beat) { _, _ in
                guard let b = model.boss else { return }
                if !b.lastHits.isEmpty {
                    hurtAt = Date()
                    withAnimation(.default.repeatCount(5, autoreverses: true).speed(4)) { shake = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { shake = false }
                }
                if b.lastCounter {
                    withAnimation(.easeOut(duration: 0.15)) { counterFlash = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { withAnimation(.easeIn(duration: 0.4)) { counterFlash = false } }
                }
            }
        }
    }
    private func hits(_ b: BossRaid) -> some View {
        HStack(spacing: 10 * unit) {
            ForEach(Array(b.lastHits.enumerated()), id: \.offset) { _, h in
                VStack(spacing: 0) {
                    Text("-\(h.damage)").font(.system(size: 40 * unit, weight: .black, design: .rounded)).foregroundStyle(.red).shadow(color: .white, radius: 2)
                    Text("\(model.name(h.player)) · d\(h.sides)").font(.system(size: 14 * unit, weight: .bold, design: .rounded)).foregroundStyle(MiniGamePalette.ink)
                        .padding(.horizontal, 8 * unit).padding(.vertical, 2 * unit).background(Capsule().fill(.white.opacity(0.85)))
                }
            }
        }.id(model.beat).transition(.move(edge: .bottom).combined(with: .opacity)).offset(y: -10 * unit)
    }
}

// MARK: Camp

private struct CampStage: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    @State private var hurtAt: Date?
    var body: some View {
        if let c = model.camp {
            let cell = 150 * unit, left = 140 * unit
            ZStack(alignment: .topLeading) {
                // The path: camp at the left, the monster comes from the right.
                ForEach(0...CampDefense.length, id: \.self) { i in
                    let x = left + CGFloat(CampDefense.length - i) * cell
                    RoundedRectangle(cornerRadius: 16 * unit).fill(Color(red: 0.84, green: 0.72, blue: 0.50).opacity(i == CampDefense.length ? 0 : 0.85))
                        .frame(width: cell - 10 * unit, height: 70 * unit).position(x: x + cell / 2, y: 470 * unit)
                }
                Image("CampTent").resizable().interpolation(.none).scaledToFit().frame(width: 190 * unit)
                    .position(x: left + cell / 2 - 20 * unit, y: 400 * unit)
                Text("营地").font(.system(size: 22 * unit, weight: .heavy, design: .rounded)).foregroundStyle(.white).padding(.horizontal, 12 * unit).padding(.vertical, 4 * unit)
                    .background(Capsule().fill(MiniGamePalette.ink.opacity(0.75))).position(x: left + cell / 2 - 20 * unit, y: 530 * unit)
                let species = ["slime", "wolf", "caveTroll"][c.wave]
                MiniGameMonster(id: species, height: (c.wave == 2 ? 250 : 200) * unit, hurtAt: hurtAt, dead: c.outcome == .won)
                    .position(x: left + CGFloat(CampDefense.length - c.position) * cell + cell / 2 + 40 * unit, y: 380 * unit)
                // Rounds left.
                HStack(spacing: 7 * unit) {
                    ForEach(0..<CampDefense.rounds, id: \.self) { i in
                        Circle().fill(i < c.round ? MiniGamePalette.gold : .white.opacity(0.6)).frame(width: 22 * unit, height: 22 * unit)
                            .overlay(Circle().stroke(MiniGamePalette.ink.opacity(0.3), lineWidth: 2 * unit))
                    }
                    Text("第 \(c.round)/\(CampDefense.rounds) 题").font(.system(size: 24 * unit, weight: .heavy, design: .rounded)).foregroundStyle(MiniGamePalette.ink).padding(.leading, 8 * unit)
                }
                .padding(.horizontal, 20 * unit).padding(.vertical, 10 * unit).background(Capsule().fill(.white.opacity(0.75)))
                .position(x: 640 * unit, y: 120 * unit)
                Text("离营地 \(CampDefense.length - c.position) 步").font(.system(size: 30 * unit, weight: .black, design: .rounded))
                    .foregroundStyle(c.position >= CampDefense.length - 2 ? .red : MiniGamePalette.ink)
                    .position(x: 640 * unit, y: 190 * unit)
            }
            .frame(width: 1280 * unit, height: 720 * unit)
            .onChange(of: model.beat) { _, _ in if (model.camp?.lastMove ?? 1) < 1 { hurtAt = Date() } }
        }
    }
}

// MARK: Race

private struct RaceStage: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    var body: some View {
        if let r = model.race {
            let lanes = max(1, r.sides.count), top = 100 * unit, bottom = 100 * unit
            let laneH = min(150 * unit, (720 * unit - top - bottom) / CGFloat(lanes))
            let cellW = 1120 * unit / CGFloat(RaceTrack.length + 1), x0 = 100 * unit
            ZStack(alignment: .topLeading) {
                ForEach(Array(r.sides.enumerated()), id: \.element.id) { lane, side in
                    let y = top + (720 * unit - top - bottom - laneH * CGFloat(lanes)) / 2 + CGFloat(lane) * laneH
                    let current = r.current?.id == side.id && r.winner == nil
                    RoundedRectangle(cornerRadius: 14 * unit).fill(model.tint(side.id).opacity(current ? 0.35 : 0.15))
                        .overlay(RoundedRectangle(cornerRadius: 14 * unit).stroke(current ? MiniGamePalette.gold : .clear, lineWidth: 4 * unit))
                        .frame(width: 1200 * unit, height: laneH - 8 * unit).position(x: 640 * unit, y: y + laneH / 2)
                    ForEach(0...RaceTrack.length, id: \.self) { i in
                        cellView(r.cells[i], index: i).frame(width: cellW - 4 * unit, height: min(78 * unit, laneH - 26 * unit))
                            .position(x: x0 + CGFloat(i) * cellW + cellW / 2, y: y + laneH / 2)
                    }
                    let at = r.positions[side.id] ?? 0
                    token(side, size: min(84 * unit, laneH - 30 * unit), trapped: r.trapped.contains(side.id))
                        .position(x: x0 + CGFloat(at) * cellW + cellW / 2, y: y + laneH / 2 - 6 * unit)
                }
            }
            .frame(width: 1280 * unit, height: 720 * unit)
        }
    }
    @ViewBuilder private func cellView(_ cell: RaceTrack.Cell, index: Int) -> some View {
        let symbol: String? = switch cell { case .reward: "gift.fill"; case .trap: "exclamationmark.triangle.fill"; case .boost: "bolt.fill"; case .finish: "flag.checkered"; case .plain: nil }
        let color: Color = switch cell { case .reward: .pink; case .trap: .orange; case .boost: .yellow; case .finish: MiniGamePalette.ink; case .plain: .white }
        RoundedRectangle(cornerRadius: 8 * unit).fill(cell == .plain ? Color.white.opacity(0.7) : color.opacity(0.85))
            .overlay {
                if let symbol { Image(systemName: symbol).font(.system(size: 22 * unit, weight: .bold)).foregroundStyle(.white) }
                else { Text(index == 0 ? "起" : "\(index)").font(.system(size: 13 * unit, weight: .bold, design: .rounded)).foregroundStyle(MiniGamePalette.ink.opacity(0.4)) }
            }
    }
    private func token(_ side: MiniGameSide, size: CGFloat, trapped: Bool) -> some View {
        HStack(spacing: -size * 0.35) {
            ForEach(side.members.prefix(3), id: \.self) { id in MiniGameFace(student: model.student(id), size: size, tint: model.tint(side.id)) }
        }
        .overlay(alignment: .top) {
            Text(side.name).font(.system(size: 14 * unit, weight: .heavy, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                .padding(.horizontal, 8 * unit).padding(.vertical, 2 * unit).background(Capsule().fill(model.tint(side.id))).offset(y: -size * 0.42)
        }
        .overlay(alignment: .bottomTrailing) { if trapped { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 20 * unit)).foregroundStyle(.orange) } }
    }
}

// MARK: Memory

private struct MemoryStage: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    var body: some View {
        if let m = model.memory {
            let columns = m.cards.count > 12 ? 4 : 3
            HStack(alignment: .center, spacing: 30 * unit) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(190 * unit), spacing: 14 * unit), count: columns), spacing: 14 * unit) {
                    ForEach(m.cards.indices, id: \.self) { i in
                        MemoryCardView(card: m.cards[i], number: i + 1, up: m.faceUp.contains(i), owner: m.owner[m.cards[i].pair].map(model.tint), unit: unit)
                    }
                }.frame(width: CGFloat(columns) * 204 * unit)
                VStack(alignment: .leading, spacing: 12 * unit) {
                    ForEach(m.sides) { side in
                        let turn = m.current?.id == side.id && !m.finished
                        HStack(spacing: 10 * unit) {
                            Circle().fill(model.tint(side.id)).frame(width: 22 * unit, height: 22 * unit)
                            Text(side.name).font(.system(size: 24 * unit, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                            Spacer(minLength: 4 * unit)
                            Image(systemName: "shippingbox.fill").foregroundStyle(MiniGamePalette.gold)
                            Text("\(m.pairs(of: side.id))").font(.system(size: 28 * unit, weight: .black, design: .rounded)).monospacedDigit()
                        }
                        .foregroundStyle(MiniGamePalette.ink).padding(.horizontal, 16 * unit).padding(.vertical, 8 * unit).frame(width: 300 * unit)
                        .background(RoundedRectangle(cornerRadius: 14 * unit).fill(.white.opacity(turn ? 0.95 : 0.55)))
                        .overlay(RoundedRectangle(cornerRadius: 14 * unit).stroke(turn ? MiniGamePalette.gold : .clear, lineWidth: 4 * unit))
                    }
                }
            }
            .padding(.top, 40 * unit)
        }
    }
}

private struct MemoryCardView: View {
    let card: MemoryMatch.Card
    let number: Int
    let up: Bool
    let owner: Color?
    let unit: CGFloat
    var body: some View {
        let shown = up || owner != nil
        ZStack {
            // Back: a closed chest and the card's number (the teacher calls it out).
            RoundedRectangle(cornerRadius: 16 * unit).fill(LinearGradient(colors: [Color(red: 0.36, green: 0.46, blue: 0.78), Color(red: 0.24, green: 0.30, blue: 0.58)], startPoint: .top, endPoint: .bottom))
                .overlay {
                    VStack(spacing: 2 * unit) {
                        Image(systemName: "shippingbox.fill").font(.system(size: 34 * unit)).foregroundStyle(MiniGamePalette.gold)
                        Text("\(number)").font(.system(size: 20 * unit, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    }
                }
                .opacity(shown ? 0 : 1)
            RoundedRectangle(cornerRadius: 16 * unit).fill(owner.map { $0.opacity(0.92) } ?? .white)
                .overlay {
                    Text(card.text).font(.system(size: (card.english ? 30 : 32) * unit, weight: .heavy, design: .rounded))
                        .foregroundStyle(owner != nil ? .white : MiniGamePalette.ink).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.4).padding(8 * unit)
                }
                .overlay(alignment: .topTrailing) { if owner != nil { Image(systemName: "star.fill").foregroundStyle(MiniGamePalette.gold).padding(8 * unit) } }
                .opacity(shown ? 1 : 0)
        }
        .frame(width: 190 * unit, height: 120 * unit)
        .overlay(RoundedRectangle(cornerRadius: 16 * unit).stroke(.white, lineWidth: 3 * unit))
        // A flat flip (no 3D rotation: a 180° rotation3DEffect mirrored the whole window on Mac Catalyst).
        .scaleEffect(x: shown ? 1 : 0.94, y: shown ? 1 : 0.94)
        .shadow(color: .black.opacity(0.18), radius: 6 * unit, y: 3 * unit)
    }
}

// MARK: Arena

private struct ArenaStage: View {
    @ObservedObject var model: MiniGameModel
    let unit: CGFloat
    var body: some View {
        if let a = model.arena {
            ZStack {
                // The stage.
                Ellipse().fill(Color(red: 0.70, green: 0.52, blue: 0.34)).frame(width: 900 * unit, height: 160 * unit).offset(y: 90 * unit)
                Ellipse().stroke(MiniGamePalette.gold, lineWidth: 6 * unit).frame(width: 900 * unit, height: 160 * unit).offset(y: 90 * unit)
                HStack(alignment: .bottom, spacing: 180 * unit) {
                    fighter(a.champion, champion: true, streak: a.streak)
                    Text("VS").font(.system(size: 72 * unit, weight: .black, design: .rounded)).foregroundStyle(.red).shadow(color: .white, radius: 3).padding(.bottom, 120 * unit)
                    fighter(a.challenger, champion: false, streak: 0)
                }.offset(y: -50 * unit)
                // Next in line, and the wins so far.
                VStack {
                    Spacer()
                    HStack(spacing: 10 * unit) {
                        Text("下一位").font(.system(size: 18 * unit, weight: .heavy, design: .rounded)).foregroundStyle(MiniGamePalette.ink)
                        ForEach(a.line.prefix(6), id: \.self) { id in MiniGameFace(student: model.student(id), size: 44 * unit, tint: MiniGamePalette.side((model.student(id)?.seat ?? 1) - 1)) }
                    }.padding(.horizontal, 16 * unit).padding(.vertical, 8 * unit).background(Capsule().fill(.white.opacity(0.7))).padding(.bottom, 100 * unit)
                }
                VStack(alignment: .leading, spacing: 6 * unit) {
                    Text("胜场").font(.system(size: 18 * unit, weight: .heavy, design: .rounded))
                    ForEach(a.ranking(model.students.map(\.id)).prefix(6), id: \.self) { id in
                        HStack { Text(model.name(id)).lineLimit(1); Spacer(); Text("\(a.wins[id] ?? 0)").monospacedDigit() }
                            .font(.system(size: 18 * unit, weight: .bold, design: .rounded))
                    }
                }.foregroundStyle(MiniGamePalette.ink).frame(width: 190 * unit).padding(14 * unit)
                    .background(RoundedRectangle(cornerRadius: 16 * unit).fill(.white.opacity(0.7)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.top, 90 * unit).padding(.trailing, 30 * unit)
            }
        }
    }
    private func fighter(_ id: String, champion: Bool, streak: Int) -> some View {
        VStack(spacing: 6 * unit) {
            if champion {
                Image(systemName: "crown.fill").font(.system(size: (40 + CGFloat(min(streak, 6)) * 8) * unit)).foregroundStyle(MiniGamePalette.gold)
                    .shadow(color: .orange, radius: CGFloat(streak) * 2 * unit)
            } else {
                Image(systemName: "bolt.fill").font(.system(size: 40 * unit)).foregroundStyle(.orange)
            }
            MiniGameFigure(student: model.student(id), height: 250 * unit, mirrored: !champion).id(id)
            Text(model.name(id)).font(.system(size: 32 * unit, weight: .heavy, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                .padding(.horizontal, 18 * unit).padding(.vertical, 6 * unit).background(Capsule().fill(champion ? Color.orange : MiniGamePalette.ink.opacity(0.75)))
            Text(champion ? (streak > 0 ? "擂主 · 连胜 \(streak)" : "擂主") : "挑战者").font(.system(size: 18 * unit, weight: .bold, design: .rounded)).foregroundStyle(MiniGamePalette.ink)
        }
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
    }
}
