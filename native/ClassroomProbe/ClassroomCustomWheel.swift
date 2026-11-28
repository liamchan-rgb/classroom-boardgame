import SwiftUI
import UIKit
import ClassroomGameCore
import MeadowWorldSupport

// MARK: - Saved wheels

/// The teacher's own wheels, kept by the app (ClassroomMeadow/wheels.json), the last one used first.
@MainActor final class CustomWheelLibrary: ObservableObject {
    static let shared = CustomWheelLibrary()
    @Published private(set) var wheels: [CustomWheel] = []
    @Published var currentName: String = UserDefaults.standard.string(forKey: "classroom.customWheel") ?? "" {
        didSet { UserDefaults.standard.set(currentName, forKey: "classroom.customWheel") }
    }
    private var url: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ClassroomMeadow/wheels.json") }
    private init() {
        if let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([CustomWheel].self, from: data), !list.isEmpty { wheels = list }
        else { wheels = [Self.sample] }
        // The teacher's three wheels from the old spinner app, added once (deleting one later keeps it deleted).
        if !UserDefaults.standard.bool(forKey: "classroom.wheelPresets1") {
            for w in Self.presets where !wheels.contains(where: { $0.name == w.name }) { wheels.append(w) }
            UserDefaults.standard.set(true, forKey: "classroom.wheelPresets1"); save()
        }
        if !wheels.contains(where: { $0.name == currentName }) { currentName = wheels[0].name }
    }
    /// Removes one prize from the current wheel (the one just won, for a draw without repeats). A wheel keeps at
    /// least two prizes.
    func removePrize(_ index: Int) throws {
        var w = current
        try w.removePrize(index)
        try put(w, replacing: w.name)
    }
    /// Puts a removed slice back (`at` in the removed list), or all of them (`at` nil).
    func restorePrize(_ at: Int?) throws {
        var w = current
        if let at { try w.restorePrize(at) } else { try w.restoreAll() }
        try put(w, replacing: w.name)
    }
    /// Weights from the slice sizes in the screenshots (degrees of the circle); prizes outside the game.
    static let presets: [CustomWheel] = [
        CustomWheel(name: "转盘·Mickey", prizes: [
            .init(title: "稀有黑卡x1", weight: 20), .init(title: "免罚卡", weight: 25), .init(title: "10费攻略分", weight: 15),
            .init(title: "100积分币", weight: 90), .init(title: "谢谢惠顾", weight: 85), .init(title: "（被遮挡的格子，待填写）", weight: 70),
            .init(title: "300积分币", weight: 25), .init(title: "500积分币", weight: 20),
        ]),
        CustomWheel(name: "转盘·Jessica", prizes: [
            .init(title: "黑卡x5", weight: 82), .init(title: "200积分币", weight: 78), .init(title: "（小格，待填写）", weight: 10),
            .init(title: "（细格，待填写）", weight: 2), .init(title: "8折券", weight: 28), .init(title: "复述奖励图片计算", weight: 20),
            .init(title: "当天积分币奖励翻倍", weight: 18), .init(title: "VS", weight: 8), .init(title: "20费攻略分", weight: 95),
            .init(title: "400积分币", weight: 22),
        ]),
        CustomWheel(name: "转盘·Jerry", prizes: [
            .init(title: "一", weight: 3), .init(title: "积分币奖励翻倍", weight: 8), .init(title: "500积分币", weight: 12),
            .init(title: "300积分币", weight: 85), .init(title: "10费攻略分", weight: 90), .init(title: "黑卡x3", weight: 60),
            .init(title: "700积分币", weight: 8), .init(title: "稀有黑卡x2", weight: 12), .init(title: "免罚卡x2", weight: 30),
            .init(title: "20费攻略分", weight: 32),
        ]),
    ]
    var current: CustomWheel { wheels.first { $0.name == currentName } ?? wheels[0] }
    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(wheels).write(to: url, options: .atomic)
    }
    /// Saves a wheel (replacing the one called `oldName`, or one with the same name) and makes it current.
    func put(_ wheel: CustomWheel, replacing oldName: String?) throws {
        try wheel.validate()
        if let old = oldName, let i = wheels.firstIndex(where: { $0.name == old }) {
            if wheel.name != old, wheels.contains(where: { $0.name == wheel.name }) { throw GameError("已有同名转盘「\(wheel.name)」。") }
            wheels[i] = wheel
        } else if let i = wheels.firstIndex(where: { $0.name == wheel.name }) { wheels[i] = wheel }
        else { wheels.append(wheel) }
        currentName = wheel.name; save()
    }
    func remove(_ name: String) {
        guard wheels.count > 1 else { return }
        wheels.removeAll { $0.name == name }; save()
        if currentName == name { currentName = wheels[0].name }
    }
    func unusedName(_ base: String = "新转盘") -> String {
        var n = base, k = 2
        while wheels.contains(where: { $0.name == n }) { n = base + " \(k)"; k += 1 }
        return n
    }
    /// A ready wheel to start from: game rewards and a few classroom ones.
    static let sample = CustomWheel(name: "课堂奖励转盘", cost: 0, prizes: [
        CustomWheelPrize(title: "10 金币", coins: 10, weight: 30),
        CustomWheelPrize(title: "30 金币", coins: 30, weight: 15),
        CustomWheelPrize(title: "+2 积分", score: 2, weight: 15),
        CustomWheelPrize(title: "小药水", item: "smallPotion", count: 1, weight: 15),
        CustomWheelPrize(title: "复活石", item: "revivalStone", count: 1, weight: 5),
        CustomWheelPrize(title: "再转一次", weight: 10),
        CustomWheelPrize(title: "免作业一次", weight: 4),
        CustomWheelPrize(title: "当一天小老师", weight: 6),
    ])
}

/// Every spin of the custom wheels, kept by the app across trips (ClassroomMeadow/wheel-history.json), so a
/// student's draws are listed whichever trip they were in. Matched by the student's name.
@MainActor final class CustomWheelHistory {
    struct Entry: Codable, Equatable {
        var at: Date
        var player: String
        var wheel: String
        var prize: String
    }
    static let shared = CustomWheelHistory()
    private(set) var entries: [Entry] = []
    private var url: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ClassroomMeadow/wheel-history.json") }
    private init() { if let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([Entry].self, from: data) { entries = list } }
    func add(player: String, wheel: String, prize: String) {
        entries.append(Entry(at: Date(), player: player, wheel: wheel, prize: prize))
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }
    func of(_ player: String) -> [Entry] { entries.filter { $0.player == player }.reversed() }
}

/// One student's draws, newest first, with a count of each prize.
struct WheelHistoryView: View {
    let player: String
    let entries: [CustomWheelHistory.Entry]
    var onClose: () -> Void
    private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "M月d日 HH:mm"; return f }()
    struct Count { let prize: String; let n: Int }
    /// How many times each prize came up, most often first.
    static func counts(_ entries: [CustomWheelHistory.Entry]) -> [Count] {
        var tally: [String: Int] = [:]
        for e in entries { tally[e.prize, default: 0] += 1 }
        let list: [Count] = tally.map { Count(prize: $0.key, n: $0.value) }
        return list.sorted { a, b in a.n == b.n ? a.prize < b.prize : a.n > b.n }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(player) 的抽奖记录", systemImage: "clock.arrow.circlepath").font(.title2.bold())
                Text("共 \(entries.count) 次").font(.callout).foregroundStyle(GameTheme.muted)
                Spacer()
                Button { onClose() } label: { Label("关闭", systemImage: "xmark") }.buttonStyle(GlassIconButtonStyle())
            }
            if entries.isEmpty {
                ContentUnavailableView("还没有抽过", systemImage: "chart.pie", description: Text("在自定义转盘里抽到的奖会记在这里（所有行程都算）。"))
            } else {
                FlowRow(spacing: 6) {
                    ForEach(Self.counts(entries), id: \.prize) { c in
                        Text("\(c.prize) ×\(c.n)").font(.callout.bold()).padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(GameTheme.primary.opacity(0.12))).foregroundStyle(GameTheme.primary)
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                            HStack(spacing: 10) {
                                Text(Self.time.string(from: e.at)).font(.callout).monospacedDigit().foregroundStyle(GameTheme.muted).lineLimit(1).fixedSize()
                                Text(e.prize).font(.callout.bold()).foregroundStyle(GameTheme.ink)
                                Spacer()
                                Text(e.wheel).font(.caption).foregroundStyle(GameTheme.muted)
                            }.padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.55)))
                        }
                    }
                }
            }
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(GlassBackdrop())
    }
}

extension CustomWheel {
    /// The wheel's slices: items with their pictures, coins / score in amber, prizes outside the game as words;
    /// rarity from the item and from how unlikely the prize is.
    func slices(catalog: GameCatalog?) -> [WheelSlice] {
        prizes.indices.map { i in
            let p = prizes[i], chance = self.chance(i)
            if let id = p.item {
                let item = try? catalog?.item(id)
                let stat = item.map { MeadowItemRarity.shortStat($0) }
                return WheelSlice(
                    title: p.title,
                    icon: MeadowItemIcon.image(id, item: item, side: 96),
                    badge: p.count > 1 ? "×\(p.count)" : nil,
                    rarity: WheelSlice.rarity(chance: chance, item: MeadowItemRarity.of(id, item: item)),
                    weight: Double(max(0, p.weight)),
                    subtitle: stat?.isEmpty == false ? stat : "已直接发放到行囊"
                )
            }
            if p.coins > 0 {
                return WheelSlice(title: p.title, icon: nil, badge: "\(p.coins)", rarity: WheelSlice.rarity(chance: chance), coins: true, weight: Double(max(0, p.weight)), subtitle: "游戏金币奖励")
            }
            if p.score > 0 {
                return WheelSlice(title: p.title, icon: nil, badge: "+\(p.score)", rarity: WheelSlice.rarity(chance: chance), coins: true, weight: Double(max(0, p.weight)), subtitle: "课堂积分奖励")
            }
            return WheelSlice(title: p.title, icon: nil, badge: nil, rarity: WheelSlice.rarity(chance: chance), weight: Double(max(0, p.weight)), subtitle: "课堂兑现奖励")
        }
    }
}

// MARK: - Wheel screen (copied to the public screen like the shop)

final class CustomWheelViewController: UIViewController {
    private let session: MeadowCampaignSession
    private var actor: String
    var onChange: (() -> Void)?
    private let header = UIView(), stage = UIView()
    private let titleLabel = UILabel(), coinsLabel = UILabel(), result = UILabel()
    private let members = UISegmentedControl()
    private let wheelButton = UIButton(type: .system)
    private let edit = MeadowPreviewPalette.iconButton("slider.horizontal.3", "编辑")
    private let close = MeadowPreviewPalette.iconButton("xmark", "关闭")
    private let spin = MeadowPreviewPalette.iconButton("sparkles", "转！", prominent: true)
    private let history = MeadowPreviewPalette.iconButton("clock.arrow.circlepath", "历史")
    private let removeWon = MeadowPreviewPalette.iconButton("minus.circle", "移除这一格")
    /// The slice just won (on the wheel as it was spun), for 移除这一格.
    private var lastWin: (wheel: String, slot: Int)?
    private let wheel = MeadowPrizeWheelView()
    private let card = WheelPrizeCard()
    private let legendPanel = UIView()
    private let legendTitle = UILabel()
    private let legendScroll = UIScrollView()
    private let legendContent = UIView()
    private var legendRows: [(slot: Int, view: UIView)] = []
    private var library: CustomWheelLibrary { .shared }

    init(session: MeadowCampaignSession, actor: String) {
        self.session = session; self.actor = actor
        super.init(nibName: nil, bundle: nil); modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    // Like the shop: the console's shortcuts (laser L, timer, scoreboard…) keep working over the wheel.
    override var canBecomeFirstResponder: Bool { true }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); becomeFirstResponder() }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if ClassroomGlobalTools.handlePresses?(presses) == true { return }
        super.pressesBegan(presses, with: event)
    }
    private var people: [GameUnit] { session.engine.state.players.filter { $0.isAlive } }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.80, green: 0.88, blue: 0.88, alpha: 1); MeadowGlassBackdrop.install(in: view)
        MeadowPreviewPalette.stylePanel(header, liveBlur: true)
        view.addSubview(header)
        view.addSubview(stage)
        [titleLabel, wheelButton, members, coinsLabel, history, edit, close].forEach(header.addSubview)

        MeadowPreviewPalette.stylePanel(legendPanel, liveBlur: false, level: .thick)
        legendTitle.font = MeadowPreviewPalette.font(17, .heavy)
        legendTitle.textColor = MeadowPreviewPalette.ink
        legendScroll.alwaysBounceVertical = true
        legendScroll.addSubview(legendContent)
        [legendTitle, legendScroll].forEach(legendPanel.addSubview)

        [wheel, spin, removeWon, result, legendPanel, card].forEach(stage.addSubview)
        history.addAction(UIAction { [weak self] _ in self?.openHistory() }, for: .touchUpInside)
        removeWon.addAction(UIAction { [weak self] _ in self?.removeLastWin() }, for: .touchUpInside)
        removeWon.isHidden = true
        titleLabel.attributedText = MeadowGlassText.iconLine("chart.pie.fill", "转盘", size: 24, tint: MeadowPreviewPalette.gold, weight: .heavy)
        wheelButton.titleLabel?.font = MeadowPreviewPalette.font(17, .heavy); wheelButton.tintColor = MeadowPreviewPalette.ink
        wheelButton.showsMenuAsPrimaryAction = true
        wheelButton.backgroundColor = UIColor.white.withAlphaComponent(0.62); wheelButton.layer.cornerRadius = 12
        for state in [UIControl.State.normal, .selected] {
            members.setTitleTextAttributes([.font: MeadowPreviewPalette.font(15, .bold), .foregroundColor: state == .selected ? UIColor.white : MeadowPreviewPalette.ink], for: state)
        }
        members.selectedSegmentTintColor = MeadowPreviewPalette.primary
        for (i, p) in people.enumerated() { members.insertSegment(withTitle: p.shortName, at: i, animated: false) }
        members.addAction(UIAction { [weak self] _ in guard let self else { return }; let list = self.people; if list.indices.contains(self.members.selectedSegmentIndex) { self.actor = list[self.members.selectedSegmentIndex].id }; self.refresh() }, for: .valueChanged)
        edit.addAction(UIAction { [weak self] _ in self?.openEditor(new: false) }, for: .touchUpInside)
        wheel.onHubTap = { [weak self] in self?.go() }
        wheel.onWinFaded = { [weak self] in self?.card.hide() }
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        spin.addAction(UIAction { [weak self] _ in self?.go() }, for: .touchUpInside)
        result.font = MeadowPreviewPalette.font(18, .heavy); result.textColor = MeadowPreviewPalette.ink; result.textAlignment = .center; result.numberOfLines = 2
        loadWheel()
    }

    private func loadWheel() {
        let w = library.current
        let slices = w.slices(catalog: session.engine.catalog)
        wheel.slices = slices; card.hide(); result.text = nil
        lastWin = nil; removeWon.isHidden = true
        wheelButton.setTitle("  \(w.name)  ▾", for: .normal)
        wheelButton.menu = UIMenu(children: library.wheels.map { item in
            UIAction(title: item.name, state: item.name == w.name ? .on : .off) { [weak self] _ in self?.library.currentName = item.name; self?.loadWheel() }
        } + [UIMenu(options: .displayInline, children: [
            UIAction(title: "新建转盘…", image: UIImage(systemName: "plus")) { [weak self] _ in self?.openEditor(new: true) },
            UIAction(title: "编辑当前转盘…", image: UIImage(systemName: "slider.horizontal.3")) { [weak self] _ in self?.openEditor(new: false) },
        ])])
        rebuildLegend(wheel: w, slices: slices)
        refresh()
        view.setNeedsLayout()
    }

    private func rebuildLegend(wheel w: CustomWheel, slices: [WheelSlice]) {
        legendContent.subviews.forEach { $0.removeFromSuperview() }
        legendRows = []
        let hidden = w.removed ?? []
        legendTitle.attributedText = MeadowGlassText.iconLine("list.star", "格子 · 显示 \(w.prizes.count)" + (hidden.isEmpty ? "" : " · 隐藏 \(hidden.count)") + " · 点按隐藏/恢复", size: 15, tint: MeadowPreviewPalette.gold, weight: .heavy)

        let indexed = w.prizes.indices.map { ($0, w.prizes[$0], slices[$0], w.chance($0) * 100.0) }
            .sorted { a, b in a.2.rarity != b.2.rarity ? a.2.rarity > b.2.rarity : a.3 > b.3 }

        for (slot, prize, slice, pct) in indexed {
            let row = UIView()
            row.backgroundColor = slice.rarity.surfaceTint
            row.layer.cornerRadius = 11
            row.layer.cornerCurve = .continuous
            row.layer.borderWidth = 1.2
            row.layer.borderColor = slice.rarity.borderColor.withAlphaComponent(0.75).cgColor
            row.clipsToBounds = true

            let bar = UIView(); bar.backgroundColor = slice.coins ? MeadowPreviewPalette.gold : slice.rarity.badgeColor; bar.tag = 1
            let nameL = UILabel()
            nameL.font = MeadowPreviewPalette.font(14.5, .heavy)
            nameL.textColor = slice.rarity >= .epic ? slice.rarity.inkColor : MeadowPreviewPalette.ink
            nameL.text = prize.title
            nameL.lineBreakMode = .byTruncatingTail
            nameL.tag = 2

            let kindL = UILabel()
            kindL.font = MeadowPreviewPalette.font(11.5, .semibold)
            kindL.textColor = MeadowPreviewPalette.muted
            kindL.text = prize.offGame ? "课堂兑现" : (prize.item != nil ? "装备/道具 ×\(max(1, prize.count))" : (prize.coins > 0 ? "+\(prize.coins) 金币" : "+\(prize.score) 积分"))
            kindL.tag = 3

            let pill = UILabel()
            pill.font = MeadowPreviewPalette.font(10.5, .heavy)
            pill.textColor = .white
            pill.textAlignment = .center
            pill.layer.cornerRadius = 6
            pill.clipsToBounds = true
            pill.backgroundColor = slice.coins ? MeadowPreviewPalette.gold : slice.rarity.badgeColor
            pill.text = slice.coins ? "奖励" : slice.rarity.title
            pill.tag = 4

            let pctL = UILabel()
            pctL.font = UIFont.monospacedDigitSystemFont(ofSize: 13.5, weight: .heavy)
            pctL.textAlignment = .right
            pctL.textColor = slice.rarity.inkColor
            pctL.text = String(format: "%.1f%%", pct)
            pctL.tag = 5

            [bar, nameL, kindL, pill, pctL].forEach(row.addSubview)
            addToggle(to: row) { [weak self] in self?.hideSlice(slot) }
            legendContent.addSubview(row)
            legendRows.append((slot, row))
        }
        // The hidden slices stay listed (greyed): tap one to put it back where it was, or all at once.
        guard !hidden.isEmpty else { return }
        let header = UIView()
        let headL = UILabel(); headL.font = MeadowPreviewPalette.font(13.5, .heavy); headL.textColor = MeadowPreviewPalette.muted
        headL.text = "已隐藏 \(hidden.count) 格 · 点按恢复"; headL.tag = 10
        let all = UIButton(type: .system); all.tag = 11
        all.setTitle("全部恢复", for: .normal); all.titleLabel?.font = MeadowPreviewPalette.font(13.5, .heavy); all.tintColor = MeadowPreviewPalette.primary
        all.addAction(UIAction { [weak self] _ in self?.restore(nil) }, for: .touchUpInside)
        [headL, all].forEach(header.addSubview)
        legendContent.addSubview(header)
        legendRows.append((Int.min, header))
        for (i, gone) in hidden.enumerated().reversed() {
            let row = UIView()
            row.backgroundColor = UIColor.white.withAlphaComponent(0.35)
            row.layer.cornerRadius = 11; row.layer.cornerCurve = .continuous
            row.layer.borderWidth = 1; row.layer.borderColor = UIColor.gray.withAlphaComponent(0.35).cgColor
            row.clipsToBounds = true
            let bar = UIView(); bar.backgroundColor = UIColor.gray.withAlphaComponent(0.4); bar.tag = 1
            let nameL = UILabel(); nameL.font = MeadowPreviewPalette.font(14.5, .heavy); nameL.tag = 2
            nameL.attributedText = NSAttributedString(string: gone.prize.title, attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: MeadowPreviewPalette.muted])
            let kindL = UILabel(); kindL.font = MeadowPreviewPalette.font(11.5, .semibold); kindL.textColor = MeadowPreviewPalette.muted; kindL.tag = 3
            kindL.text = "已隐藏 · 原第 \(gone.index + 1) 格"
            let pill = UILabel(); pill.font = MeadowPreviewPalette.font(10.5, .heavy); pill.textColor = .white; pill.textAlignment = .center
            pill.layer.cornerRadius = 6; pill.clipsToBounds = true; pill.backgroundColor = MeadowPreviewPalette.primary; pill.text = "恢复"; pill.tag = 4
            let mark = UIImageView(image: UIImage(systemName: "eye.slash")); mark.tintColor = MeadowPreviewPalette.muted; mark.contentMode = .scaleAspectFit; mark.tag = 5
            [bar, nameL, kindL, pill, mark].forEach(row.addSubview)
            addToggle(to: row) { [weak self] in self?.restore(i) }
            legendContent.addSubview(row)
            legendRows.append((-1 - i, row))
        }
    }

    /// A clear button over a whole list row (tag 6, laid out to the row's size).
    private func addToggle(to row: UIView, _ action: @escaping () -> Void) {
        let tap = UIButton(type: .custom); tap.tag = 6
        tap.addAction(UIAction { _ in action() }, for: .touchUpInside)
        row.addSubview(tap)
    }

    /// Hides one shown slice from the list (it stays listed below, ready to come back). Two always stay.
    private func hideSlice(_ slot: Int) {
        guard !wheel.spinning else { return }
        let title = library.current.prizes.indices.contains(slot) ? library.current.prizes[slot].title : ""
        do {
            try library.removePrize(slot)
            loadWheel(); onChange?()
            result.text = "已隐藏：\(title)（右侧点按可恢复）"
        } catch { result.text = error.localizedDescription }
    }

    private func highlightLegend(_ slot: Int) {
        for (s, row) in legendRows where s >= 0 {
            let won = s == slot
            row.layer.borderWidth = won ? 2.6 : 1.2
            if won {
                row.layer.borderColor = MeadowPreviewPalette.gold.cgColor
                let targetY = max(0, min(legendScroll.contentSize.height - legendScroll.bounds.height, row.frame.midY - legendScroll.bounds.height / 2))
                legendScroll.setContentOffset(CGPoint(x: 0, y: targetY), animated: true)
            }
        }
    }

    private func refresh() {
        guard let unit = session.engine.state.units[actor] else { return }
        members.selectedSegmentIndex = people.firstIndex { $0.id == actor } ?? 0
        let cost = library.current.cost
        coinsLabel.attributedText = MeadowGlassText.iconLine("bitcoinsign.circle.fill", "\(unit.coins)" + (cost > 0 ? " · 每次 \(cost)" : " · 免费"), size: 17, tint: MeadowPreviewPalette.gold)
    }

    private func go() {
        guard !wheel.spinning else { return }
        let w = library.current
        do {
            let receipt = try session.spinCustomWheel(actor: actor, wheel: w.forSpin)
            guard let slot = receipt.events.first(where: { $0.kind == "customWheel" })?.amount else { return }
            spin.isEnabled = false; members.isEnabled = false; wheelButton.isEnabled = false; edit.isEnabled = false
            card.hide(); result.text = nil; lastWin = nil; removeWon.isHidden = true
            if w.prizes.indices.contains(slot) { CustomWheelHistory.shared.add(player: session.engine.state.units[actor]?.shortName ?? actor, wheel: w.name, prize: w.prizes[slot].title) }
            refresh(); onChange?()
            let name = session.engine.state.units[actor]?.shortName ?? ""
            wheel.spin(to: slot) { [weak self] in
                guard let self else { return }
                self.spin.isEnabled = true; self.members.isEnabled = true; self.wheelButton.isEnabled = true; self.edit.isEnabled = true
                self.wheel.celebrate(slot)
                let slices = w.slices(catalog: self.session.engine.catalog)
                if slices.indices.contains(slot) { self.card.show(slices[slot]) }
                self.highlightLegend(slot)
                let prize = w.prizes[slot]
                self.result.text = "\(name) 抽中：\(prize.title)" + (prize.offGame ? "（课堂奖励，请老师兑现）" : "（已发到背包 / 金币积分）")
                self.lastWin = (w.name, slot); self.removeWon.isHidden = w.prizes.count <= 2
                self.refresh(); self.onChange?()
            }
        } catch { result.text = error.localizedDescription }
    }

    private func removeLastWin() {
        guard !wheel.spinning, let win = lastWin, win.wheel == library.current.name else { return }
        let title = library.current.prizes.indices.contains(win.slot) ? library.current.prizes[win.slot].title : ""
        do {
            try library.removePrize(win.slot)
            let keep = result.text
            loadWheel(); onChange?()
            result.text = (keep.map { $0 + "\n" } ?? "") + "已从「\(library.current.name)」移除：\(title)"
        } catch { result.text = error.localizedDescription }
    }

    private func restore(_ at: Int?) {
        guard !wheel.spinning else { return }
        let names = (library.current.removed ?? []).enumerated().filter { at == nil || $0.offset == at }.map(\.element.prize.title)
        do {
            try library.restorePrize(at)
            loadWheel(); onChange?()
            result.text = "已恢复到「\(library.current.name)」：" + names.joined(separator: "、")
        } catch { result.text = error.localizedDescription }
    }

    private func openHistory() {
        let name = session.engine.state.units[actor]?.shortName ?? actor
        let screen = UIHostingController(rootView: WheelHistoryView(player: name, entries: CustomWheelHistory.shared.of(name), onClose: { [weak self] in self?.dismiss(animated: true) }))
        screen.modalPresentationStyle = .formSheet; screen.preferredContentSize = CGSize(width: 640, height: 620)
        present(screen, animated: true)
    }

    private func openEditor(new: Bool) {
        guard !wheel.spinning else { return }
        let start = new ? CustomWheel(name: library.unusedName(), prizes: CustomWheelLibrary.sample.prizes) : library.current
        let items = session.engine.catalog.items.map { (id: $0.id, name: $0.name) }
        let editor = UIHostingController(rootView: CustomWheelEditor(wheel: start, oldName: new ? nil : start.name, items: items, canDelete: !new && library.wheels.count > 1,
                                                                    onDone: { [weak self] in self?.dismiss(animated: true) { self?.loadWheel() } }))
        editor.modalPresentationStyle = .formSheet; editor.preferredContentSize = CGSize(width: 820, height: 680)
        present(editor, animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let inset = view.safeAreaInsets, w = view.bounds.width, h = view.bounds.height
        header.frame = CGRect(x: inset.left + 14, y: inset.top + 10, width: w - inset.left - inset.right - 28, height: 60)
        let hw = header.bounds.width
        titleLabel.frame = CGRect(x: 16, y: 12, width: 96, height: 36)
        wheelButton.frame = CGRect(x: 114, y: 11, width: 214, height: 38)
        close.frame = CGRect(x: hw - 112, y: 8, width: 102, height: 44)
        edit.frame = CGRect(x: hw - 220, y: 8, width: 102, height: 44)
        history.frame = CGRect(x: hw - 328, y: 8, width: 102, height: 44)
        coinsLabel.frame = CGRect(x: hw - 498, y: 12, width: 162, height: 36)
        let mx = wheelButton.frame.maxX + 10
        members.frame = CGRect(x: mx, y: 12, width: max(120, coinsLabel.frame.minX - mx - 10), height: 36)

        let top = header.frame.maxY + 10
        stage.frame = CGRect(x: inset.left + 14, y: top, width: w - inset.left - inset.right - 28, height: h - top - inset.bottom - 12)
        let sw = stage.bounds.width, sh = stage.bounds.height
        let wide = sw >= 600

        if wide {
            let rightW = min(400, max(240, sw * 0.36))
            let leftW = sw - rightW - 14
            let size = max(200, min(leftW - 12, sh - 114))
            wheel.frame = CGRect(x: (leftW - size) / 2, y: 2, width: size, height: size)
            spin.frame = CGRect(x: leftW / 2 - 116, y: wheel.frame.maxY + 6, width: 232, height: 50)
            removeWon.frame = CGRect(x: spin.frame.maxX + 10, y: spin.frame.minY + 3, width: 142, height: 44)
            result.frame = CGRect(x: 8, y: spin.frame.maxY + 4, width: leftW - 16, height: 48)

            legendPanel.isHidden = false
            legendPanel.frame = CGRect(x: leftW + 14, y: 2, width: rightW, height: sh - 4)
            let lw = legendPanel.bounds.width
            legendTitle.frame = CGRect(x: 14, y: 12, width: lw - 28, height: 26)
            legendScroll.frame = CGRect(x: 10, y: 44, width: lw - 20, height: max(1, legendPanel.bounds.height - 54))
            let rw = legendScroll.bounds.width
            let rowH: CGFloat = 46, gap: CGFloat = 6, headH: CGFloat = 34
            var y: CGFloat = 0
            for item in legendRows {
                let row = item.view
                if item.slot == Int.min {
                    row.frame = CGRect(x: 0, y: y + 6, width: rw, height: headH)
                    row.viewWithTag(10)?.frame = CGRect(x: 4, y: 7, width: rw - 100, height: 20)
                    row.viewWithTag(11)?.frame = CGRect(x: rw - 92, y: 2, width: 88, height: 30)
                    y += headH + 6 + gap; continue
                }
                row.frame = CGRect(x: 0, y: y, width: rw, height: rowH)
                row.viewWithTag(1)?.frame = CGRect(x: 0, y: 0, width: 4.5, height: rowH)
                row.viewWithTag(5)?.frame = CGRect(x: rw - 56, y: 13, width: 48, height: 20)
                row.viewWithTag(4)?.frame = CGRect(x: rw - 98, y: 14, width: 38, height: 18)
                let tw = max(50, rw - 114)
                row.viewWithTag(2)?.frame = CGRect(x: 12, y: 6, width: tw, height: 19)
                row.viewWithTag(3)?.frame = CGRect(x: 12, y: 25, width: tw, height: 15)
                row.viewWithTag(6)?.frame = row.bounds
                y += rowH + gap
            }
            legendContent.frame = CGRect(x: 0, y: 0, width: rw, height: max(1, y))
            legendScroll.contentSize = legendContent.bounds.size

            let cw = min(310, leftW - 32)
            card.frame = CGRect(x: (leftW - cw) / 2, y: wheel.frame.midY - 122, width: cw, height: 248)
        } else {
            legendPanel.isHidden = true
            let size = max(180, min(sw - 16, sh - 116))
            wheel.frame = CGRect(x: (sw - size) / 2, y: 0, width: size, height: size)
            spin.frame = CGRect(x: sw / 2 - 116, y: wheel.frame.maxY + 4, width: 232, height: 52)
            removeWon.frame = CGRect(x: spin.frame.maxX + 10, y: spin.frame.minY + 4, width: 144, height: 44)
            result.frame = CGRect(x: 10, y: spin.frame.maxY + 4, width: sw - 20, height: 50)
            let cw = min(310, sw - 40)
            card.frame = CGRect(x: (sw - cw) / 2, y: wheel.frame.midY - 120, width: cw, height: 244)
        }
    }
}

// MARK: - Editor

/// One prize being edited: what it gives (an item, coins, score, or only words), its name and its weight.
struct WheelPrizeDraft: Identifiable {
    enum Kind: String, CaseIterable { case item = "物品", coins = "金币", score = "积分", text = "文字" }
    let id = UUID()
    var kind: Kind
    var title: String
    var item: String
    var amount: String
    var weight: String
    init(_ p: CustomWheelPrize) {
        kind = p.item != nil ? .item : p.coins > 0 ? .coins : p.score > 0 ? .score : .text
        title = p.title; item = p.item ?? "smallPotion"
        amount = String(p.item != nil ? max(1, p.count) : p.coins > 0 ? p.coins : p.score > 0 ? p.score : 1); weight = String(p.weight)
    }
    static func number(_ s: String) -> Int { Int(s.filter(\.isNumber).prefix(6)) ?? 0 }
    var prize: CustomWheelPrize {
        let n = Self.number(amount), w = Self.number(weight), t = title.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .item: return CustomWheelPrize(title: t, item: item, count: max(1, n), weight: w)
        case .coins: return CustomWheelPrize(title: t, coins: n, weight: w)
        case .score: return CustomWheelPrize(title: t, score: n, weight: w)
        case .text: return CustomWheelPrize(title: t, weight: w)
        }
    }
}

struct CustomWheelEditor: View {
    @State private var name: String
    @State private var cost: String
    @State private var rows: [WheelPrizeDraft]
    @State private var error: String?
    @State private var confirmDelete = false
    let oldName: String?
    let items: [(id: String, name: String)]
    let canDelete: Bool
    var onDone: () -> Void
    init(wheel: CustomWheel, oldName: String?, items: [(id: String, name: String)], canDelete: Bool, onDone: @escaping () -> Void) {
        _name = State(initialValue: wheel.name); _cost = State(initialValue: String(wheel.cost)); _rows = State(initialValue: wheel.prizes.map(WheelPrizeDraft.init))
        self.oldName = oldName; self.items = items; self.canDelete = canDelete; self.onDone = onDone
    }
    private var total: Int { rows.reduce(0) { $0 + WheelPrizeDraft.number($1.weight) } }
    private func itemName(_ id: String) -> String { items.first { $0.id == id }?.name ?? id }
    /// The name a prize gets from what it gives, while the teacher has not typed their own.
    private func autoTitle(_ r: WheelPrizeDraft) -> String {
        let n = WheelPrizeDraft.number(r.amount)
        switch r.kind {
        case .item: return itemName(r.item) + (n > 1 ? " ×\(n)" : "")
        case .coins: return "\(n) 金币"
        case .score: return "+\(n) 积分"
        case .text: return r.title
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label(oldName == nil ? "新建转盘" : "编辑转盘", systemImage: "chart.pie.fill").font(.title2.bold())
                Spacer()
                if canDelete { Button(role: .destructive) { confirmDelete = true } label: { Label("删除转盘", systemImage: "trash") }.buttonStyle(GlassIconButtonStyle()) }
                Button { onDone() } label: { Label("取消", systemImage: "xmark") }.buttonStyle(GlassIconButtonStyle())
                Button { save() } label: { Label("保存", systemImage: "checkmark") }.buttonStyle(GlassIconButtonStyle(prominent: true))
            }
            HStack(spacing: 12) {
                Text("名称").font(.callout.bold()); TextField("转盘名称", text: $name).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Text("每次花费").font(.callout.bold()); TextField("0", text: $cost).textFieldStyle(.roundedBorder).frame(width: 70)
                Text("金币（0 = 免费）").font(.caption).foregroundStyle(GameTheme.muted)
                Spacer()
                Text("概率 = 权重 ÷ 总权重 \(total)").font(.caption).foregroundStyle(GameTheme.muted)
            }
            if let error { Text(error).font(.callout.bold()).foregroundStyle(.red) }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach($rows) { $row in rowView($row) }
                }
            }
            HStack {
                Button { rows.append(WheelPrizeDraft(CustomWheelPrize(title: "", weight: 10))) } label: { Label("添加奖项", systemImage: "plus") }
                    .buttonStyle(GlassIconButtonStyle()).disabled(rows.count >= 24)
                Text("\(rows.count)/24 项 · 物品、金币、积分会直接发给转的人；“文字”是游戏外的奖励，由老师兑现。").font(.caption).foregroundStyle(GameTheme.muted)
            }
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(GlassBackdrop()).foregroundStyle(GameTheme.ink)
        .alert("删除转盘「\(oldName ?? "")」？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { if let oldName { CustomWheelLibrary.shared.remove(oldName) }; onDone() }
            Button("取消", role: .cancel) {}
        }
    }
    @ViewBuilder private func rowView(_ row: Binding<WheelPrizeDraft>) -> some View {
        let r = row.wrappedValue, w = WheelPrizeDraft.number(r.weight)
        HStack(spacing: 8) {
            Picker("", selection: Binding(get: { r.kind }, set: { k in
                let auto = r.title.isEmpty || r.title == autoTitle(r)
                row.wrappedValue.kind = k
                if auto { row.wrappedValue.title = k == .text ? "" : autoTitle(row.wrappedValue) }
            })) { ForEach(WheelPrizeDraft.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            .pickerStyle(.segmented).frame(width: 210)
            switch r.kind {
            case .item:
                Menu {
                    ForEach(items, id: \.id) { it in
                        Button(it.name) {
                            let auto = r.title.isEmpty || r.title == autoTitle(r)
                            row.wrappedValue.item = it.id
                            if auto { row.wrappedValue.title = autoTitle(row.wrappedValue) }
                        }
                    }
                } label: { Label(itemName(r.item), systemImage: "bag").lineLimit(1).frame(width: 140, alignment: .leading) }
                amountField(row, label: "件")
            case .coins: amountField(row, label: "金币")
            case .score: amountField(row, label: "积分")
            case .text: EmptyView()
            }
            TextField(r.kind == .text ? "奖励内容，如：免作业一次" : "显示名称", text: row.title).textFieldStyle(.roundedBorder)
            Text("权重").font(.caption.bold())
            TextField("10", text: row.weight).textFieldStyle(.roundedBorder).frame(width: 56)
            Text(total > 0 ? String(format: "%.1f%%", Double(w) / Double(total) * 100) : "—").font(.callout.monospacedDigit().bold()).foregroundStyle(GameTheme.primary).frame(width: 56, alignment: .trailing)
            Button { rows.removeAll { $0.id == r.id } } label: { Image(systemName: "minus.circle.fill").font(.title3) }.buttonStyle(.plain).foregroundStyle(.red.opacity(0.8)).disabled(rows.count <= 2)
        }
        .padding(8).background(GlassFill.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private func amountField(_ row: Binding<WheelPrizeDraft>, label: String) -> some View {
        HStack(spacing: 4) {
            TextField("1", text: Binding(get: { row.wrappedValue.amount }, set: { v in
                let auto = row.wrappedValue.title.isEmpty || row.wrappedValue.title == autoTitle(row.wrappedValue)
                row.wrappedValue.amount = v
                if auto { row.wrappedValue.title = autoTitle(row.wrappedValue) }
            })).textFieldStyle(.roundedBorder).frame(width: 60)
            Text(label).font(.caption)
        }
    }
    private func save() {
        let wheel = CustomWheel(name: name.trimmingCharacters(in: .whitespaces), cost: WheelPrizeDraft.number(cost), prizes: rows.map(\.prize))
        do { try CustomWheelLibrary.shared.put(wheel, replacing: oldName); onDone() }
        catch { self.error = error.localizedDescription }
    }
}

extension MeadowTeacherCoordinator {
    /// Top bar 转盘: the teacher's own wheel, shown on the public screen like the shop.
    func openCustomWheel() {
        guard let c = campaign, c.engine.state.battle == nil, let host = presentationHost else { message = "请打开行程、在战斗外使用转盘。"; revision += 1; return }
        let screen = CustomWheelViewController(session: c, actor: c.selectedPlayerID)
        screen.onChange = { [weak self] in self?.renderer?.classroomRefresh(); self?.revision += 1 }
        host.present(screen, animated: true)
    }
}
