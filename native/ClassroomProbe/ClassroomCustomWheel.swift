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
        if !wheels.contains(where: { $0.name == currentName }) { currentName = wheels[0].name }
    }
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

extension CustomWheel {
    /// The wheel's slices: items with their pictures, coins / score in amber, prizes outside the game as words;
    /// rarity from the item and from how unlikely the prize is.
    func slices(catalog: GameCatalog?) -> [WheelSlice] {
        prizes.indices.map { i in
            let p = prizes[i], chance = self.chance(i)
            if let id = p.item {
                let item = try? catalog?.item(id)
                return WheelSlice(title: p.title, icon: MeadowItemIcon.image(id, item: item, side: 96), badge: p.count > 1 ? "×\(p.count)" : nil,
                                  rarity: WheelSlice.rarity(chance: chance, item: MeadowItemRarity.of(id, item: item)), weight: Double(max(0, p.weight)))
            }
            if p.coins > 0 { return WheelSlice(title: p.title, icon: nil, badge: "\(p.coins)", rarity: WheelSlice.rarity(chance: chance), coins: true, weight: Double(max(0, p.weight))) }
            if p.score > 0 { return WheelSlice(title: p.title, icon: nil, badge: "+\(p.score)", rarity: WheelSlice.rarity(chance: chance), coins: true, weight: Double(max(0, p.weight))) }
            return WheelSlice(title: p.title, icon: nil, badge: nil, rarity: WheelSlice.rarity(chance: chance), weight: Double(max(0, p.weight)))
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
    private let wheel = MeadowPrizeWheelView()
    private let card = WheelPrizeCard()
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
        // No odds list: the slices' sizes show how likely each prize is.
        [header].forEach { MeadowPreviewPalette.stylePanel($0, liveBlur: true); view.addSubview($0) }
        view.addSubview(stage)
        [titleLabel, wheelButton, members, coinsLabel, edit, close].forEach(header.addSubview)
        [wheel, spin, result, card].forEach(stage.addSubview)
        titleLabel.attributedText = MeadowGlassText.iconLine("chart.pie.fill", "转盘", size: 26)
        wheelButton.titleLabel?.font = MeadowPreviewPalette.font(18, .heavy); wheelButton.tintColor = MeadowPreviewPalette.ink
        wheelButton.showsMenuAsPrimaryAction = true
        wheelButton.backgroundColor = UIColor.white.withAlphaComponent(0.55); wheelButton.layer.cornerRadius = 12
        for state in [UIControl.State.normal, .selected] { members.setTitleTextAttributes([.font: MeadowPreviewPalette.font(16), .foregroundColor: MeadowPreviewPalette.ink], for: state) }
        members.selectedSegmentTintColor = MeadowPreviewPalette.primary
        for (i, p) in people.enumerated() { members.insertSegment(withTitle: p.shortName, at: i, animated: false) }
        members.addAction(UIAction { [weak self] _ in guard let self else { return }; let list = self.people; if list.indices.contains(self.members.selectedSegmentIndex) { self.actor = list[self.members.selectedSegmentIndex].id }; self.refresh() }, for: .valueChanged)
        edit.addAction(UIAction { [weak self] _ in self?.openEditor(new: false) }, for: .touchUpInside)
        // The star in the middle spins too; the win and its prize card fade after a second (the line below the
        // wheel keeps what was won).
        wheel.onHubTap = { [weak self] in self?.go() }
        wheel.onWinFaded = { [weak self] in self?.card.hide() }
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        spin.addAction(UIAction { [weak self] _ in self?.go() }, for: .touchUpInside)
        result.font = MeadowPreviewPalette.font(20, .heavy); result.textColor = MeadowPreviewPalette.ink; result.textAlignment = .center; result.numberOfLines = 2
        loadWheel()
    }
    private func loadWheel() {
        let w = library.current
        wheel.slices = w.slices(catalog: session.engine.catalog); card.hide(); result.text = nil
        wheelButton.setTitle("  \(w.name)  ▾", for: .normal)
        wheelButton.menu = UIMenu(children: library.wheels.map { item in
            UIAction(title: item.name, state: item.name == w.name ? .on : .off) { [weak self] _ in self?.library.currentName = item.name; self?.loadWheel() }
        } + [UIMenu(options: .displayInline, children: [
            UIAction(title: "新建转盘…", image: UIImage(systemName: "plus")) { [weak self] _ in self?.openEditor(new: true) },
            UIAction(title: "编辑当前转盘…", image: UIImage(systemName: "slider.horizontal.3")) { [weak self] _ in self?.openEditor(new: false) },
        ])])
        refresh()
        view.setNeedsLayout()
    }
    private func refresh() {
        guard let unit = session.engine.state.units[actor] else { return }
        members.selectedSegmentIndex = people.firstIndex { $0.id == actor } ?? 0
        let cost = library.current.cost
        coinsLabel.attributedText = MeadowGlassText.iconLine("bitcoinsign.circle.fill", "\(unit.coins)" + (cost > 0 ? " · 每次 \(cost)" : " · 免费"), size: 18, tint: MeadowPreviewPalette.gold)
    }
    private func go() {
        guard !wheel.spinning else { return }
        let w = library.current
        do {
            let receipt = try session.spinCustomWheel(actor: actor, wheel: w)
            guard let slot = receipt.events.first(where: { $0.kind == "customWheel" })?.amount else { return }
            spin.isEnabled = false; members.isEnabled = false; wheelButton.isEnabled = false; edit.isEnabled = false
            card.hide(); result.text = nil
            refresh(); onChange?()
            let name = session.engine.state.units[actor]?.shortName ?? ""
            wheel.spin(to: slot) { [weak self] in
                guard let self else { return }
                self.spin.isEnabled = true; self.members.isEnabled = true; self.wheelButton.isEnabled = true; self.edit.isEnabled = true
                self.wheel.celebrate(slot)
                let slices = w.slices(catalog: self.session.engine.catalog)
                if slices.indices.contains(slot) { self.card.show(slices[slot]) }
                let prize = w.prizes[slot]
                self.result.text = "\(name) 抽中：\(prize.title)" + (prize.offGame ? "（课堂奖励，请老师兑现）" : "（已发到背包 / 金币积分）")
                self.refresh(); self.onChange?()
            }
        } catch { result.text = error.localizedDescription }
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
        header.frame = CGRect(x: inset.left + 16, y: inset.top + 12, width: w - inset.left - inset.right - 32, height: 64)
        let hw = header.bounds.width
        titleLabel.frame = CGRect(x: 18, y: 14, width: 110, height: 36)
        wheelButton.frame = CGRect(x: 128, y: 13, width: 230, height: 38)
        // Icon-and-word buttons: room for both.
        close.frame = CGRect(x: hw - 104, y: 10, width: 92, height: 44)
        edit.frame = CGRect(x: hw - 204, y: 10, width: 92, height: 44)
        coinsLabel.frame = CGRect(x: hw - 420, y: 14, width: 206, height: 36)
        let mx = wheelButton.frame.maxX + 14
        members.frame = CGRect(x: mx, y: 14, width: max(120, coinsLabel.frame.minX - mx - 12), height: 36)
        let top = header.frame.maxY + 12
        stage.frame = CGRect(x: inset.left + 16, y: top, width: w - inset.left - inset.right - 32, height: h - top - inset.bottom - 16)
        let sw = stage.bounds.width, sh = stage.bounds.height
        let size = max(160, min(sw - 20, sh - 120))
        wheel.frame = CGRect(x: (sw - size) / 2, y: 0, width: size, height: size)
        spin.frame = CGRect(x: sw / 2 - 120, y: wheel.frame.maxY + 4, width: 240, height: 56)
        result.frame = CGRect(x: 10, y: spin.frame.maxY + 4, width: sw - 20, height: 52)
        let cw = min(320, sw - 40)
        card.frame = CGRect(x: (sw - cw) / 2, y: wheel.frame.midY - 115, width: cw, height: 240)
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
