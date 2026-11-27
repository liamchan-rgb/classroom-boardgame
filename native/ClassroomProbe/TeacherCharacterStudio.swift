import SwiftUI
import ClassroomGameCore
import MeadowWorldSupport

/// The character studio: a teacher-only screen to dress a character and keep the look. A large live preview walks the figure round
/// all eight directions; hairstyles, hair colors, eye colors and dedicated non-equipment costumes are organized into crisp visual grids;
/// the result is applied to a member of the running journey and/or saved to one of the 50 character slots. Looks only - class, numbers and gear stay.
struct TeacherCharacterStudio: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    var onClose: () -> Void

    enum Tab: Int, CaseIterable, Identifiable {
        case hair, hairColor, eye, costume
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .hair: "发型"
            case .hairColor: "发色"
            case .eye: "瞳色"
            case .costume: "时装"
            }
        }
        var icon: String {
            switch self {
            case .hair: "scissors"
            case .hairColor: "paintpalette.fill"
            case .eye: "eye.fill"
            case .costume: "tshirt.fill"
            }
        }
        var count: Int {
            switch self {
            case .hair: CharacterCustomizationCatalog.hairstyles.count
            case .hairColor: CharacterCustomizationCatalog.hairColors.count
            case .eye: CharacterCustomizationCatalog.eyes.count
            case .costume: CharacterCustomizationCatalog.costumes.count
            }
        }
    }

    @State private var player = "p1"
    @State private var name = "新角色"
    @State private var body_ = "forester"
    @State private var outfit = "follow"
    @State private var hair = "original"
    @State private var hairColor = "default"
    @State private var face = "original"
    @State private var tab: Tab = .hair
    @State private var slot = 1
    @State private var notice = "自由搭配 20 种发型、20 种发色、18 种瞳色与 16 套原创时装，左侧预览实时八向行走。"
    @State private var turning = true
    @State private var facingIndex = 0
    @State private var previewFrames: [String: UIImage] = [:]
    @State private var tileImages: [String: UIImage] = [:]
    @State private var confirm = false
    @State private var confirmation = ""
    @State private var pending: (() throws -> Void)?
    @State private var used: [Int: String] = [:]

    /// Turning order: down, down-left, left, up-left, up, up-right, right, down-right.
    private static let turn = [0, 5, 1, 6, 2, 7, 3, 4]
    private static let turnNames = ["正面", "左前", "左侧", "左后", "背面", "右后", "右侧", "右前"]
    private static let bodyCrop = CGRect(x: 52, y: 56, width: 152, height: 168)
    private static let headCrop = CGRect(x: 68, y: 54, width: 120, height: 112)

    private var players: [GameUnit] { game.campaign?.engine.state.players ?? [] }
    private var worn: String? { game.campaign?.engine.state.units[player]?.equipment.armor }
    private var weapon: String? { game.campaign?.engine.state.units[player]?.equipment.weapon ?? "trainingSword" }
    private var appearance: PlayerAppearance {
        PlayerAppearance(
            body: body_,
            outfit: outfit == "follow" ? nil : outfit,
            hair: hair == "original" ? nil : hair,
            hairColor: hairColor == "default" ? nil : hairColor,
            face: face == "original" ? nil : face
        )
    }
    private var store: MeadowSlotStore { MeadowTeacherCoordinator.slotStore }

    private var costumeOptionsList: [(id: String, name: String)] {
        var list: [(id: String, name: String)] = [("follow", "随护甲")] + CharacterCustomizationCatalog.costumes
        // If a loaded legacy save still uses an older outfit id, keep it selectable as a badge without adding other gear.
        if outfit != "follow", !list.contains(where: { $0.id == outfit }) {
            list.insert((outfit, CharacterCustomizationCatalog.costumeName(outfit)), at: 1)
        }
        return list
    }

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 18) {
                preview.frame(width: 330)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        identity
                        quickBar
                        tabContent
                        actions
                    }
                    .padding(.trailing, 6)
                }
            }
            .padding(18)
            .background(GlassBackdrop())
            .navigationTitle("人物自定义")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { onClose() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2)
                    }
                    .accessibilityLabel("关闭")
                }
            }
            .alert("确认操作", isPresented: $confirm) {
                Button("取消", role: .cancel) { pending = nil }
                Button("确认") { run() }
            } message: { Text(confirmation) }
            .onAppear {
                player = game.campaign?.selectedPlayerID ?? players.first?.id ?? "p1"
                readPlayer()
                scanSlots()
                prewarmPreview()
            }
            .onChange(of: player) { _, _ in readPlayer() }
            .onChange(of: appearance.visualKey) { _, _ in prewarmPreview() }
        }
    }

    // MARK: Left Live 8-Way Preview

    private var preview: some View {
        VStack(spacing: 10) {
            TimelineView(.periodic(from: .timelineAnchor, by: 0.11)) { context in
                let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.11)
                let facing = Self.turn[turning ? (tick / 16) % 8 : facingIndex]
                let column = 1 + tick % 8
                ZStack(alignment: .bottom) {
                    LinearGradient(
                        colors: [Color(red: 0.36, green: 0.55, blue: 0.38), Color(red: 0.20, green: 0.36, blue: 0.22)],
                        startPoint: .top, endPoint: .bottom
                    )
                    Ellipse().fill(.black.opacity(0.25)).frame(width: 120, height: 26).offset(y: -30)
                    if let image = previewCell(facing: facing, column: column) {
                        Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(width: 300, height: 330).padding(.bottom, 14)
                    } else {
                        ProgressView().tint(.white).padding(.bottom, 140)
                    }
                    Text(Self.turnNames[Self.turn.firstIndex(of: facing) ?? 0])
                        .font(.caption.bold()).foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.black.opacity(0.32), in: Capsule())
                        .padding(.bottom, 10)
                }
                .frame(height: 350)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.6), lineWidth: 1.5))
            }

            HStack(spacing: 10) {
                Button { turning = false; facingIndex = (facingIndex + 7) % 8 } label: { Image(systemName: "arrow.counterclockwise") }.accessibilityLabel("向左转")
                Button { if turning { facingIndex = 0 }; turning.toggle() } label: { Image(systemName: turning ? "pause.fill" : "play.fill") }.accessibilityLabel(turning ? "停在当前方向" : "自动转身")
                Button { turning = false; facingIndex = (facingIndex + 1) % 8 } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("向右转")
            }
            .buttonStyle(GlassIconButtonStyle())

            // All eight standing poses at once.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                ForEach(0..<8, id: \.self) { i in
                    Button { turning = false; facingIndex = i } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GlassFill.button)
                            if let image = previewCell(facing: Self.turn[i], column: 0) {
                                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                            }
                        }
                        .frame(height: 74)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(!turning && facingIndex == i ? GameTheme.accent : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Current look summary pill
            VStack(spacing: 4) {
                Text("\(CharacterCustomizationCatalog.hairstyleName(appearance.hair)) · \(CharacterCustomizationCatalog.hairColorName(appearance.hairColor)) · \(CharacterCustomizationCatalog.eyeName(appearance.face))")
                    .font(.caption.weight(.semibold)).foregroundStyle(GameTheme.ink).lineLimit(1).minimumScaleFactor(0.75)
                Text("时装：\(CharacterCustomizationCatalog.costumeName(appearance.outfit))  |  仅外观 · 数值不变")
                    .font(.caption2).foregroundStyle(GameTheme.muted).lineLimit(1)
            }
            .padding(.top, 2)
        }
        .glassPanel(radius: 22, padding: 12)
    }

    // MARK: Top Identity & Category Bar

    private var identity: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassHeader(icon: "person.crop.circle", title: "角色")
            if !players.isEmpty {
                Picker("角色", selection: $player) {
                    ForEach(players) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.segmented)
            } else {
                Label("无进行中行程 · 可先存到人物槽", systemImage: "tray").font(.caption).foregroundStyle(GameTheme.muted)
            }
            HStack(spacing: 8) {
                GlassField(icon: "character.cursor.ibeam", placeholder: "人物名", text: $name, limit: 40)
                Button { renameWithAlert() } label: { Image(systemName: "pencil") }
                    .buttonStyle(GlassIconButtonStyle()).accessibilityLabel("弹窗输入名字")
            }
        }
        .glassPanel()
    }

    private var quickBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                GlassHeader(icon: "wand.and.stars", title: "装扮搭配")

                Spacer(minLength: 4)

                Button { randomLook(includeCostume: false) } label: {
                    Label("随机五官发型", systemImage: "dice.fill")
                }
                .buttonStyle(GlassIconButtonStyle(tint: GameTheme.accent, prominent: true))

                Button { randomLook(includeCostume: true) } label: {
                    Label("全套随机", systemImage: "sparkles")
                }
                .buttonStyle(GlassIconButtonStyle())
            }

            // Category Tabs
            HStack(spacing: 8) {
                ForEach(Tab.allCases, id: \.self) { item in
                    let active = tab == item
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { tab = item }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon).font(.subheadline)
                            Text(item.title).font(.subheadline.weight(.bold))
                            Text("\(item.count)")
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(active ? Color.white.opacity(0.24) : Color.black.opacity(0.08), in: Capsule())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(active ? AnyShapeStyle(GameTheme.accent) : AnyShapeStyle(GlassFill.button), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(active ? Color.white : GameTheme.ink)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(active ? Color.white.opacity(0.5) : Color.white.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .glassPanel()
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .hair:
            pictureGrid(
                title: "发型（共 \(CharacterCustomizationCatalog.hairstyles.count) 款）",
                icon: "scissors",
                options: [("original", "原有")] + CharacterCustomizationCatalog.hairstyles,
                selection: $hair,
                crop: Self.headCrop
            ) { id in look(hair: id) }

        case .hairColor:
            hairColorGrid

        case .eye:
            eyeColorGrid

        case .costume:
            pictureGrid(
                title: "原创时装（共 \(CharacterCustomizationCatalog.costumes.count) 套 · 独立于装备护甲）",
                icon: "tshirt.fill",
                options: costumeOptionsList,
                selection: $outfit,
                crop: Self.bodyCrop
            ) { id in look(outfit: id) }
        }
    }

    // MARK: Async Pixel Tile Grid (Hairstyles & Costumes)

    private func pictureGrid(
        title: String,
        icon: String,
        options: [(id: String, name: String)],
        selection: Binding<String>,
        crop: CGRect,
        lookForOption: @escaping (String) -> PlayerAppearance
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassHeader(icon: icon, title: title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                ForEach(options, id: \.id) { option in
                    let selected = selection.wrappedValue == option.id
                    let candidate = lookForOption(option.id)
                    let pixel = pixelLook(for: candidate)
                    let cacheKey = "\(pixel.key)|\(Int(crop.origin.x))|\(Int(crop.width))"
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            selection.wrappedValue = option.id
                        }
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(LinearGradient(
                                        colors: [Color(red: 0.42, green: 0.62, blue: 0.45).opacity(0.55), Color(red: 0.20, green: 0.36, blue: 0.24).opacity(0.65)],
                                        startPoint: .top, endPoint: .bottom
                                    ))
                                if let img = tileImages[cacheKey] ?? PixelHeroAtlas.cachedCell(look: pixel, facing: 0, column: 0, crop: crop) {
                                    Image(uiImage: img).interpolation(.none).resizable().scaledToFit().padding(2)
                                } else {
                                    ProgressView().scaleEffect(0.75).tint(.white.opacity(0.75))
                                }
                            }
                            .frame(height: 92)
                            .task(id: cacheKey) {
                                if tileImages[cacheKey] != nil { return }
                                if let hit = PixelHeroAtlas.cachedCell(look: pixel, facing: 0, column: 0, crop: crop) {
                                    tileImages[cacheKey] = hit
                                    return
                                }
                                PixelHeroAtlas.prepareCell(look: pixel, facing: 0, column: 0, crop: crop) { img in
                                    if let img { tileImages[cacheKey] = img }
                                }
                            }
                            Text(option.name)
                                .font(.caption.weight(selected ? .bold : .regular))
                                .lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .padding(5)
                        .background(GlassFill.button, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? GameTheme.accent : .white.opacity(0.5), lineWidth: selected ? 3 : 1))
                        .overlay(alignment: .topTrailing) {
                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.white, GameTheme.accent)
                                    .font(.system(size: 17))
                                    .padding(5)
                            }
                        }
                        .scaleEffect(selected ? 1.03 : 1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(GameTheme.ink)
                }
            }
        }
        .glassPanel()
    }

    // MARK: Instant Glossy Hair Color Grid (20 Curated 5-Ramp Swatches)

    private var hairColorGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassHeader(icon: "paintpalette.fill", title: "发色（共 \(CharacterCustomizationCatalog.hairColors.count) 色 · 适配全部发型）")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                // Default option (follow body)
                hairColorTile(
                    id: "default", name: "默认",
                    dark: body_ == "wayfarer" ? 0x6a7088 : 0x4e1e16,
                    mid: body_ == "wayfarer" ? 0xa8b0c2 : 0x86362a,
                    light: body_ == "wayfarer" ? 0xffffff : 0xf0a070
                )
                ForEach(CharacterCustomizationCatalog.hairColors) { entry in
                    hairColorTile(id: entry.id, name: entry.name, dark: entry.darkHex, mid: entry.midHex, light: entry.lightHex)
                }
            }
        }
        .glassPanel()
    }

    private func hairColorTile(id: String, name: String, dark: UInt32, mid: UInt32, light: UInt32) -> some View {
        let selected = hairColor == id
        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.74)) { hairColor = id }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [colorFromHex(light), colorFromHex(mid), colorFromHex(dark)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 44, height: 44)
                        .overlay(
                            // Glossy anime hair ring highlight band
                            Capsule()
                                .fill(Color.white.opacity(0.45))
                                .frame(width: 24, height: 5)
                                .offset(y: -8)
                        )
                        .overlay(Circle().stroke(Color.black.opacity(0.32), lineWidth: 1.5))
                        .shadow(color: colorFromHex(mid).opacity(0.35), radius: 4, y: 2)
                }
                .frame(height: 52)
                Text(name)
                    .font(.caption.weight(selected ? .bold : .regular))
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8).padding(.horizontal, 4)
            .background(GlassFill.button, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? GameTheme.accent : .white.opacity(0.5), lineWidth: selected ? 3 : 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, GameTheme.accent)
                        .font(.system(size: 16))
                        .padding(5)
                }
            }
            .scaleEffect(selected ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(GameTheme.ink)
    }

    // MARK: Instant Pixel-Eye Swatch Grid (18 Jewel & Heterochromia Eyes)

    private var eyeColorGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassHeader(icon: "eye.fill", title: "瞳色（共 \(CharacterCustomizationCatalog.eyes.count) 色 · 含异色瞳）")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 10) {
                eyeColorTile(
                    id: "original",
                    entry: .init(
                        id: "original", name: "原有",
                        dark: body_ == "wayfarer" ? 0x5a3410 : 0x1c2e6a,
                        mid: body_ == "wayfarer" ? 0xc07a20 : 0x3a64c4,
                        light: body_ == "wayfarer" ? 0xf0c060 : 0x86b4f4
                    )
                )
                ForEach(CharacterCustomizationCatalog.eyes) { entry in
                    eyeColorTile(id: entry.id, entry: entry)
                }
            }
        }
        .glassPanel()
    }

    private func eyeColorTile(id: String, entry: CharacterCustomizationCatalog.EyeEntry) -> some View {
        let selected = face == id
        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.74)) { face = id }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(red: 0.96, green: 0.85, blue: 0.72))
                        .frame(height: 52)
                    HStack(spacing: 12) {
                        pixelEyeGlyph(dark: entry.leftDark, mid: entry.leftMid, light: entry.leftLight, mirrored: false)
                        pixelEyeGlyph(
                            dark: entry.rightDark ?? entry.leftDark,
                            mid: entry.rightMid ?? entry.leftMid,
                            light: entry.rightLight ?? entry.leftLight,
                            mirrored: true
                        )
                    }
                }
                Text(entry.name)
                    .font(.caption.weight(selected ? .bold : .regular))
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(GlassFill.button, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? GameTheme.accent : .white.opacity(0.5), lineWidth: selected ? 3 : 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, GameTheme.accent)
                        .font(.system(size: 16))
                        .padding(5)
                }
            }
            .scaleEffect(selected ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(GameTheme.ink)
    }

    /// Exact 3×4 pixel eye pattern from `face_round` (`["000","041","012",".23"]`) rendered crisp at 7pt per pixel!
    private func pixelEyeGlyph(dark: UInt32, mid: UInt32, light: UInt32, mirrored: Bool) -> some View {
        let pattern = ["000", "041", "012", ".23"]
        let px: CGFloat = 7
        return VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { row in
                let chars = Array(mirrored ? String(pattern[row].reversed()) : pattern[row])
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { col in
                        let ch = chars[col]
                        let fill: Color = switch ch {
                        case "0": Color(red: 0.09, green: 0.07, blue: 0.12)
                        case "1": colorFromHex(dark)
                        case "2": colorFromHex(mid)
                        case "3": colorFromHex(light)
                        case "4": .white
                        default: .clear
                        }
                        Rectangle().fill(fill).frame(width: px, height: px)
                    }
                }
            }
        }
    }

    private func colorFromHex(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }

    // MARK: Actions Panel

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassHeader(icon: "square.and.arrow.down.on.square", title: "保存")
            Text(notice).font(.footnote).foregroundStyle(GameTheme.muted).lineLimit(2)
            HStack(spacing: 10) {
                Button {
                    let profile = MeadowPlayerProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), appearance: appearance)
                    let id = player
                    ask("将姓名和装扮应用到该角色？职业、数值、装备和行程保持不变。") {
                        try game.applyProfile(profile, to: id)
                        notice = "已应用到 " + profile.name + "。"
                    }
                } label: { Label("应用", systemImage: "person.fill.checkmark") }
                .buttonStyle(GlassIconButtonStyle(prominent: true))
                .disabled(game.busy || game.campaign == nil || game.campaign?.isCompleted == true || players.isEmpty)

                Button { readPlayer() } label: { Label("还原", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(GlassIconButtonStyle())
                    .disabled(players.isEmpty)

                Divider().frame(height: 40)

                Picker("人物槽", selection: $slot) {
                    ForEach(1...MeadowSlotStore.profileCount, id: \.self) { s in
                        Text("\(s)" + (used[s].map { " · " + $0 } ?? " · 空")).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 6)
                .frame(minHeight: 48)
                .background(GlassFill.button, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    let profile = MeadowPlayerProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), appearance: appearance)
                    let target = slot
                    let save = {
                        try store.saveProfile(profile, slot: target, title: profile.name)
                        notice = "已保存到人物槽\(target)。"
                        scanSlots()
                    }
                    if used[target] != nil {
                        ask("覆盖人物槽\(target)（\(used[target] ?? "")）？", action: save)
                    } else {
                        do { try save() } catch { notice = "未保存：" + error.localizedDescription }
                    }
                } label: { Label("存入", systemImage: "tray.and.arrow.down.fill") }
                .buttonStyle(GlassIconButtonStyle(tint: GameTheme.accent, prominent: true))

                Button {
                    do {
                        guard let p = try store.profile(slot)?.value else { notice = "人物槽\(slot)是空的。"; return }
                        name = p.name
                        body_ = p.appearance.body
                        outfit = p.appearance.outfit ?? "follow"
                        hair = p.appearance.hair ?? "original"
                        hairColor = p.appearance.hairColor ?? "default"
                        face = p.appearance.face ?? "original"
                        notice = "已读取人物槽\(slot)到编辑区。"
                    } catch {
                        notice = "读取失败，原文件保留：" + error.localizedDescription
                    }
                } label: { Label("读取", systemImage: "tray.and.arrow.up") }
                .buttonStyle(GlassIconButtonStyle())
                .disabled(used[slot] == nil)
            }
            Label("\(MeadowSlotStore.profileCount) 个人物槽 · 新行程可读取", systemImage: "square.grid.3x3")
                .font(.caption).foregroundStyle(GameTheme.muted)
        }
        .glassPanel()
    }

    // MARK: Helpers & Background Prewarming

    private func renameWithAlert() {
        guard let host = game.privatePresenter else { return }
        var top = host; while let next = top.presentedViewController { top = next }
        let alert = UIAlertController(title: "人物名", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = name; $0.placeholder = "1-40字"; $0.clearButtonMode = .whileEditing }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            let value = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { name = String(value.prefix(40)) }
        })
        top.present(alert, animated: true)
    }

    private func look(body: String? = nil, outfit: String? = nil, hair: String? = nil, hairColor: String? = nil, face: String? = nil) -> PlayerAppearance {
        var a = appearance
        if let body { a.body = body }
        if let outfit { a.outfit = outfit == "follow" ? nil : outfit }
        if let hair { a.hair = hair == "original" ? nil : hair }
        if let hairColor { a.hairColor = hairColor == "default" ? nil : hairColor }
        if let face { a.face = face == "original" ? nil : face }
        return a
    }

    private func pixelLook(for a: PlayerAppearance) -> PixelHeroLook {
        PixelHeroLook(
            body: a.body,
            armor: a.armor(worn: worn),
            weapon: weapon,
            hair: a.hair,
            hairColor: a.hairColor,
            face: a.face
        )
    }

    private func previewCell(facing: Int, column: Int) -> UIImage? {
        let pixel = pixelLook(for: appearance)
        let key = "\(pixel.key)|\(facing)|\(column)"
        if let hit = previewFrames[key] { return hit }
        if let hit = PixelHeroAtlas.cachedCell(look: pixel, facing: facing, column: column, crop: Self.bodyCrop) {
            return hit
        }
        // Fallback to synchronous crop ONLY if map atlas is already in memory (instant), otherwise bake in background!
        if PixelHeroAtlas.isMapReady(pixel),
           let full = PixelHeroAtlas.cell(look: pixel, facing: facing, column: column),
           let cg = full.cgImage?.cropping(to: Self.bodyCrop) {
            return UIImage(cgImage: cg)
        }
        PixelHeroAtlas.prepareCell(look: pixel, facing: facing, column: column, crop: Self.bodyCrop) { img in
            if let img { previewFrames[key] = img }
        }
        return nil
    }

    private func prewarmPreview() {
        let pixel = pixelLook(for: appearance)
        // Bake full 8-direction walk atlas once in background so the live 8-way turntable runs at 0ms/frame!
        PixelHeroAtlas.prepare(map: [pixel]) {
            guard pixel == pixelLook(for: appearance) else { return }
            var next: [String: UIImage] = [:]
            for facing in 0..<8 {
                for col in 0...8 {
                    if let full = PixelHeroAtlas.cell(look: pixel, facing: facing, column: col),
                       let cg = full.cgImage?.cropping(to: Self.bodyCrop) {
                        next["\(pixel.key)|\(facing)|\(col)"] = UIImage(cgImage: cg)
                    }
                }
            }
            previewFrames = next
        }
    }

    private func randomLook(includeCostume: Bool) {
        let next = PlayerAppearance.random(excluding: [appearance])
        let nextOutfit = includeCostume ? (PlayerAppearance.costumeOptions.randomElement() ?? "follow") : "follow"
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            body_ = next.body
            hair = next.hair ?? "original"
            hairColor = next.hairColor ?? "default"
            face = next.face ?? "original"
            outfit = nextOutfit
        }
    }

    private func readPlayer() {
        guard let u = game.campaign?.engine.state.units[player] else { return }
        name = u.name
        let a = u.appearance ?? .init(body: game.campaign?.snapshot.appearanceID ?? "forester")
        body_ = a.body
        outfit = a.outfit ?? "follow"
        hair = a.hair ?? "original"
        hairColor = a.hairColor ?? "default"
        face = a.face ?? "original"
    }

    private func scanSlots() {
        var found = [Int: String]()
        for s in 1...MeadowSlotStore.profileCount {
            if let p = try? store.profile(s) { found[s] = p.value.name }
        }
        used = found
        if used[slot] != nil, let free = (1...MeadowSlotStore.profileCount).first(where: { used[$0] == nil }) {
            slot = free
        }
    }

    private func ask(_ message: String, action: @escaping () throws -> Void) {
        confirmation = message; pending = action; confirm = true
    }

    private func run() {
        defer { pending = nil }
        do { try pending?() } catch { notice = "未完成：" + error.localizedDescription }
    }
}
