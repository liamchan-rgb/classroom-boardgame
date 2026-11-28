import SwiftUI
import UIKit
import ClassroomGameCore
import MeadowWorldSupport

// MARK: - Teacher's hero preset

/// The teacher's own hero, set up ahead of class on this device: name, class, look and gear. "出场" puts exactly this
/// hero on the field at once (map or battle) on the side the teacher picks; nothing reloads.
struct TeacherHeroPreset: Codable, Equatable {
    var name = "老师"
    var classID = "adventurer"
    var appearance = PlayerAppearance(body: "forester", hair: "hair_neat")
    var loadout = Equipment()

    private static let key = "classroom.teacherHero"
    static var current: TeacherHeroPreset {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(TeacherHeroPreset.self, from: $0) } ?? TeacherHeroPreset() }
        set { if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: key) }; newValue.prewarm() }
    }

    /// The gear that exists in `catalog` (an older trip may not know newer items), each in its own slot.
    func loadout(for catalog: GameCatalog) -> Equipment {
        var gear = Equipment()
        for slot in ItemSlot.allCases {
            if let id = loadout[slot], let item = try? catalog.item(id), item.kind == .equipment, item.slot == slot { gear[slot] = id }
        }
        return gear
    }
    func classID(for catalog: GameCatalog) -> String { catalog.classes.contains { $0.id == classID } ? classID : (catalog.classes.first?.id ?? "adventurer") }

    /// Bakes this hero's map and battle pictures in the background, so coming on shows the real look at once.
    func prewarm() {
        guard PixelHeroAtlas.enabled else { return }
        let index = HeroFrames.appearanceIDs.firstIndex(of: appearance.body) ?? 0
        let armor = appearance.armor(worn: loadout.armor), weapon = loadout.weapon ?? "trainingSword"
        let map = HeroFrames.pixelLook(heroIndex: 0, appearanceIndex: index, weaponID: weapon, armorID: armor,
                                       hair: appearance.hair, hairColor: appearance.hairColor, face: appearance.face)
        let battle = PixelHeroLook(body: appearance.body, armor: armor, weapon: weapon, hair: appearance.hair, hairColor: appearance.hairColor, face: appearance.face)
        PixelHeroAtlas.prepare(map: map.map { [$0] } ?? [], battle: [battle])
    }
}

// MARK: - Coordinator: people come and go without reloading anything

extension MeadowTeacherCoordinator {
    var teacherOnField: GameUnit? { campaign?.engine.state.players.first { $0.host } }
    /// Teams someone can come on with right now: in a duel only its two sides, in a monster fight the fighting teams,
    /// otherwise every team.
    var enterableTeams: [GameTeam] {
        guard let c = campaign else { return [] }
        let state = c.engine.state
        guard let battle = state.battle else { return state.teams }
        let fighting = Set(battle.queue.compactMap { state.units[$0] }.filter { $0.kind == .player }.compactMap(\.teamID))
        let list = state.teams.filter { fighting.contains($0.id) }
        return list.isEmpty && battle.duel != true ? state.teams : list
    }
    /// The teacher's preset hero comes on with `team` (map: next to that team; battle: into the fight, with the entrance).
    func teacherEnter(team: String) {
        guard let c = campaign else { message = "请先开始行程。"; revision += 1; return }
        guard !busy else { message = "请等当前动作播放完再出场。"; revision += 1; return }
        let preset = TeacherHeroPreset.current
        do {
            try c.enter(host: true, name: preset.name, classID: preset.classID(for: c.engine.catalog), team: team,
                        appearance: preset.appearance, loadout: preset.loadout(for: c.engine.catalog))
            rosterChanged()
            message = "\(preset.name) 出场（\(c.teamName(team))）" + (c.engine.state.battle != nil ? "，加入战斗。" : "。")
        } catch { message = error.localizedDescription }
        revision += 1
    }
    /// A student joins mid-trip (also mid-battle) in the first free seat. Returns false with the reason in `message`.
    @discardableResult func studentEnter(name: String, classID: String, team: String, appearance: PlayerAppearance?) -> Bool {
        guard let c = campaign else { message = "请先开始行程。"; revision += 1; return false }
        guard !busy else { message = "请等当前动作播放完再加入。"; revision += 1; return false }
        do {
            let seat = try c.enter(host: false, name: name, classID: classID, team: team, appearance: appearance)
            rosterChanged()
            message = "\(c.engine.state.units[seat]?.shortName ?? name) 加入了\(c.teamName(team))" + (c.engine.state.battle != nil ? "，直接参战。" : "。")
            revision += 1; return true
        } catch { message = error.localizedDescription; revision += 1; return false }
    }
    /// `id` leaves at any time (also mid-battle, not on their own turn). Undo in 存档 → 历史.
    func leaveGame(_ id: String) {
        guard let c = campaign else { return }
        guard !busy else { message = "请等当前动作播放完。"; revision += 1; return }
        let name = c.engine.state.units[id]?.shortName ?? id
        do { try c.leave(id); rosterChanged(); message = "\(name) 已退场（可在存档 → 历史里撤销）。" } catch { message = error.localizedDescription }
        revision += 1
    }
    /// The party changed in place: the map rebuilds only its traveller sprites, the battle places the newcomer with the
    /// entrance effect, and the HUDs follow. Nothing is reloaded.
    func rosterChanged() {
        guard let c = campaign else { return }
        let ids = Set(c.playerIDs)
        grantDraft.recipients = grantDraft.recipients.filter(ids.contains)
        if grantDraft.recipients.isEmpty { grantDraft.recipients = [c.selectedPlayerID] }
        if !ids.contains(selectedTarget) { selectedTarget = c.selectedPlayerID }
        renderer?.classroomRefresh()
    }
    func openTeacherHeroEditor() {
        guard !modalOpen, let presenter = presentationHost else { return }
        let screen = UIHostingController(rootView: TeacherHeroEditor(game: self, onClose: { [weak self] in self?.presentationHost?.dismiss(animated: true) }))
        screen.modalPresentationStyle = .formSheet; screen.preferredContentSize = CGSize(width: 760, height: 720)
        presenter.present(screen, animated: true)
    }
}

// MARK: - Toolbar: 出场 / 退场

struct TeacherEnterMenu: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    var prepare: () -> Void = {}
    var body: some View {
        let host = game.teacherOnField
        Menu {
            if let host {
                Section("\(host.shortName) 在场上") {
                    Button(role: .destructive) { prepare(); game.leaveGame(host.id) } label: { Label("老师退场", systemImage: "figure.walk.departure") }
                    if game.campaign?.engine.state.battle == nil, (game.campaign?.engine.state.teams.count ?? 0) > 1 {
                        ForEach(game.campaign?.engine.state.teams.filter { $0.id != host.teamID } ?? []) { team in
                            Button { prepare(); game.movePlayer(host.id, toTeam: team.id) } label: { Label("换到 \(team.name)", systemImage: "arrow.left.arrow.right") }
                        }
                    }
                }
            } else {
                Section(game.campaign?.engine.state.battle != nil ? "直接加入这场战斗" : "选边出场") {
                    ForEach(game.enterableTeams) { team in
                        Button { prepare(); game.teacherEnter(team: team.id) } label: { Label("出场 · \(team.name)", systemImage: "bolt.fill") }
                    }
                }
            }
            Divider()
            Button { prepare(); game.openTeamConsole() } label: { Label("学生中途加入 / 退场…", systemImage: "person.2.badge.plus") }
            Button { prepare(); game.openTeacherHeroEditor() } label: { Label("老师人物配置（名字 · 职业 · 装备）…", systemImage: "person.crop.circle.badge.gearshape") }
        } label: { Label(host == nil ? "老师出场" : "老师在场", systemImage: host == nil ? "bolt.circle" : "bolt.circle.fill") }
            .buttonStyle(ToolbarIconStyle(tint: host == nil ? GameTheme.primary : .orange))
            .disabled(game.campaign == nil || game.campaign?.isCompleted == true)
    }
}

// MARK: - Preset editor

struct TeacherHeroEditor: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    var onClose: () -> Void
    @State private var preset = TeacherHeroPreset.current
    @State private var profiles: [(slot: Int, profile: MeadowPlayerProfile)] = []
    @State private var preview: UIImage?
    @State private var notice = "保存后，下次“出场”就是这位老师。"
    private var catalog: GameCatalog? { game.campaign?.engine.catalog ?? (try? GameCatalog.initial()) }
    var body: some View {
        NavigationStack {
            Form {
                Section("名字与职业") {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.35))
                            if let preview { Image(uiImage: preview).interpolation(.none).resizable().scaledToFit().padding(6) }
                            else { ProgressView() }
                        }.frame(width: 110, height: 140)
                        VStack(alignment: .leading, spacing: 10) {
                            ClassroomTextField(placeholder: "老师人物名", text: $preset.name)
                            Picker("职业", selection: $preset.classID) {
                                ForEach(MeadowPartyConfiguration.classIDs, id: \.self) { id in Text((try? catalog?.playerClass(id).name) ?? id).tag(id) }
                            }
                        }
                    }
                }.glassRow()
                Section("装备（出场时直接穿上，不占背包）") {
                    gearPicker("武器", .weapon)
                    gearPicker("护甲", .armor)
                    gearPicker("饰品", .accessory)
                }.glassRow()
                Section("外观") {
                    Menu {
                        ForEach(profiles, id: \.slot) { row in
                            Button("人物槽\(row.slot) · \(row.profile.name)") { preset.appearance = row.profile.appearance }
                        }
                        if profiles.isEmpty { Text("还没有保存的人物槽（在“人物形象”里保存）") }
                    } label: { Label("用人物槽里的装扮", systemImage: "person.crop.square") }
                    Button { preset.appearance = PlayerAppearance.random() } label: { Label("随机外观", systemImage: "dice") }
                }.glassRow()
                if let host = game.teacherOnField {
                    Section("场上的老师") {
                        Text("\(host.shortName) 已在场上。新配置在下次出场时生效；名字和外观也可以现在就套用。").font(.callout)
                        Button("名字和外观现在就套用到场上的老师") { applyToField(host.id) }
                    }.glassRow()
                }
                Section { Text(notice).font(.callout).foregroundStyle(.secondary) }.glassRow()
            }.glassSheet().navigationTitle("老师人物配置")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { onClose() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
                }
                .onAppear { loadProfiles(); refreshPreview() }
                .onChange(of: preset) { _, _ in refreshPreview() }
        }
    }
    private func gearPicker(_ title: String, _ slot: ItemSlot) -> some View {
        let items = (catalog?.items ?? []).filter { $0.kind == .equipment && $0.slot == slot }
            .sorted { (MeadowItemRarity.of($0.id, item: $0), $0.name) < (MeadowItemRarity.of($1.id, item: $1), $1.name) }
        return Picker(title, selection: Binding(get: { preset.loadout[slot] ?? "" }, set: { preset.loadout[slot] = $0.isEmpty ? nil : $0 })) {
            Text(slot == .weapon ? "职业初始武器" : "不穿").tag("")
            ForEach(items) { item in Text("\(MeadowItemRarity.of(item.id, item: item).stars) \(item.name)").tag(item.id) }
        }
    }
    private func loadProfiles() {
        let store = MeadowTeacherCoordinator.slotStore
        profiles = (1...MeadowSlotStore.profileCount).compactMap { slot in (try? store.profile(slot)).flatMap { $0 }.map { (slot, $0.value) } }
    }
    private func refreshPreview() {
        guard PixelHeroAtlas.enabled else { return }
        let a = preset.appearance
        let look = PixelHeroLook(body: a.body, armor: a.armor(worn: preset.loadout.armor), weapon: preset.loadout.weapon ?? "trainingSword", hair: a.hair, hairColor: a.hairColor, face: a.face)
        if let image = PixelHeroAtlas.fullBody(look, ready: { refreshPreview() }) { preview = image } else { preview = nil }
    }
    private func save() {
        let clean = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 40 else { notice = "名字需为1至40个字符。"; return }
        preset.name = clean; TeacherHeroPreset.current = preset
        notice = "已保存。点工具栏“老师出场”选一边就能直接上场。"
    }
    private func applyToField(_ id: String) {
        let clean = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        do { try game.applyProfile(MeadowPlayerProfile(name: clean, appearance: preset.appearance), to: id); notice = game.message }
        catch { notice = error.localizedDescription }
    }
}

// MARK: - A student joins mid-trip

/// In the 队伍 window: name, class, team and look of a late student; joins at once (also into a running battle).
struct StudentJoinForm: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    @State private var name = ""
    @State private var classID = "adventurer"
    @State private var team = "party"
    @State private var appearance = PlayerAppearance.random()
    @State private var notice = ""
    var body: some View {
        let seat = game.campaign?.freeStudentSeat
        let teams = game.enterableTeams
        Section(game.campaign?.engine.state.battle != nil ? "中途加入学生 · 直接参战" : "中途加入学生") {
            ClassroomTextField(placeholder: "学生名字", text: $name)
            Picker("职业", selection: $classID) {
                ForEach(MeadowPartyConfiguration.classIDs, id: \.self) { id in Text((try? game.campaign?.engine.catalog.playerClass(id).name) ?? id).tag(id) }
            }
            Picker("加入队伍", selection: $team) { ForEach(teams) { Text($0.name).tag($0.id) } }
            HStack {
                Button { appearance = PlayerAppearance.random(excluding: game.campaign?.engine.state.players.compactMap(\.appearance) ?? []) } label: { Label("换个随机外观", systemImage: "dice") }
                Spacer()
                Button {
                    KeyHostingController<EmptyView>.endEditing()
                    if game.studentEnter(name: name, classID: classID, team: team, appearance: appearance) {
                        name = ""; appearance = PlayerAppearance.random(excluding: game.campaign?.engine.state.players.compactMap(\.appearance) ?? [])
                    }
                    notice = game.message
                } label: { Label(seat.map { "加入（\($0.uppercased())）" } ?? "已满6名学生", systemImage: "person.badge.plus") }
                    .buttonStyle(.borderedProminent)
                    .disabled(seat == nil || name.trimmingCharacters(in: .whitespaces).isEmpty || game.busy || !teams.contains { $0.id == team })
            }
            if !notice.isEmpty { Text(notice).font(.caption).foregroundStyle(.secondary) }
        }
        .glassRow()
        .onAppear { if !teams.contains(where: { $0.id == team }), let first = teams.first { team = first.id } }
    }
}
