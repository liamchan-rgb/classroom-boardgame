import Combine
import SwiftUI
import UIKit

/// 像素人物测试界面（教师端）。
/// 用游戏内 Swift 烘焙器现场合成人物：切换套装、上衣 / 围巾配色、发型、发色、五官、瞳色、肤色和武器，
/// 右侧实时预览八个方向的待机与行走动画，下方显示整张 5 方向 × 8 帧的 sprite sheet。
/// 发型、五官数据来自 Resources/CharacterParts（与网页制作工具共用）。
struct PixelCharacterLab: View {
    var onClose: () -> Void

    @State private var outfit = "traveler"
    @State private var topVariant = ""
    @State private var scarfVariant = ""
    @State private var hair = "hair_messy"
    @State private var hairVariant = ""
    @State private var face = "face_round"
    @State private var faceVariant = ""
    @State private var skin = "fair"
    @State private var weapon = ""
    @State private var sheet: CGImage?
    @State private var frames: [[CGImage]] = []
    @State private var bakeMs = 0.0
    @State private var message = ""
    @State private var walking = true
    @State private var turning = true
    @State private var dir8 = 0
    @State private var tick = 0

    private let catalog = CharacterCatalog.shared
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    /// 八个方向 → (原生 sheet 的行, 是否水平镜像, 名称)
    private static let dirs: [(row: Int, flip: Bool, name: String)] = [
        (0, false, "正面"), (1, false, "右前"), (2, false, "右侧"), (3, false, "右后"),
        (4, false, "背面"), (3, true, "左后"), (2, true, "左侧"), (1, true, "左前"),
    ]
    private static let skins: [(String, String)] = [("fair", "白皙"), ("light", "浅"), ("tan", "小麦"), ("deep", "深")]

    private var outfitDef: OutfitDef? { CharacterCatalog.outfits.first { $0.id == outfit } }

    private func variants(of slot: Slot) -> [ItemVariant] {
        guard let entry = outfitDef?.slots[slot], let id = entry, let item = catalog.item(id) else { return [] }
        return item.variants
    }

    private func variants(ofItem id: String) -> [ItemVariant] { catalog.item(id)?.variants ?? [] }

    /// 所有会影响外观的选项拼成一个签名：任何一项变了就重新烘焙
    private var signature: String {
        [outfit, topVariant, scarfVariant, hair, hairVariant, face, faceVariant, skin, weapon].joined(separator: "|")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("像素人物测试").font(.title2.bold())
                Text("游戏内现场烘焙 · 每帧 \(SpriteRig.sprW)×\(SpriteRig.sprH)").foregroundStyle(.secondary)
                Spacer()
                Button("关闭", action: onClose).buttonStyle(.borderedProminent)
            }
            .padding(16)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                controls.frame(width: 340)
                Divider()
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(white: 0.11))
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onAppear { apply(CharacterCatalog.characters[0]) }
        .onChange(of: signature) { _, _ in rebake() }
        .onReceive(timer) { _ in
            tick += 1
            if turning && tick % 20 == 0 { dir8 = (dir8 + 1) % 8 }
        }
    }

    // MARK: 左侧选项

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("角色预设") {
                    HStack {
                        ForEach(CharacterCatalog.characters, id: \.id) { p in
                            Button(p.name) { apply(p) }.buttonStyle(.bordered)
                        }
                    }
                }
                section("衣服") {
                    picker("套装", Binding(get: { outfit }, set: { outfit = $0; topVariant = ""; scarfVariant = "" }),
                           CharacterCatalog.outfits.map { ($0.id, $0.name) })
                    picker("上衣配色", $topVariant, [("", "套装默认")] + variants(of: .top).map { ($0.id, $0.name) })
                    if !variants(of: .scarf).isEmpty {
                        picker("围巾配色", $scarfVariant, [("", "套装默认")] + variants(of: .scarf).map { ($0.id, $0.name) })
                    }
                }
                section("发型") {
                    picker("发型", Binding(get: { hair }, set: { hair = $0; hairVariant = "" }),
                           catalog.items(for: .hair).map { ($0.id, $0.name) })
                    picker("发色", $hairVariant, [("", "默认")] + variants(ofItem: hair).map { ($0.id, $0.name) })
                }
                section("五官与肤色") {
                    picker("五官", Binding(get: { face }, set: { face = $0; faceVariant = "" }),
                           catalog.items(for: .face).map { ($0.id, $0.name) })
                    picker("瞳色", $faceVariant, [("", "默认")] + variants(ofItem: face).map { ($0.id, $0.name) })
                    picker("肤色", $skin, Self.skins)
                }
                section("武器") {
                    picker("主手", $weapon, [("", "空手")] + catalog.items(for: .weaponMain).map { ($0.id, $0.name) })
                }
                section("预览") {
                    Toggle("行走（关闭为待机呼吸）", isOn: $walking)
                    Toggle("自动转向", isOn: $turning)
                    HStack {
                        ForEach(0..<8, id: \.self) { i in
                            Button(Self.dirs[i].name) { turning = false; dir8 = i }
                                .buttonStyle(.bordered).font(.caption2)
                                .tint(i == dir8 ? .accentColor : .gray)
                        }
                    }
                }
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func picker(_ title: String, _ value: Binding<String>, _ options: [(String, String)]) -> some View {
        HStack {
            Text(title).frame(width: 72, alignment: .leading).foregroundStyle(.secondary)
            Picker(title, selection: value) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.menu)
            Spacer(minLength: 0)
        }
    }

    // MARK: 右侧预览

    private var preview: some View {
        VStack(spacing: 16) {
            let d = Self.dirs[dir8]
            let col = walking ? 2 + tick % 6 : (tick / 6) % 2
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.36, green: 0.55, blue: 0.31))
                if frames.count == 5, let image = frames[d.row].indices.contains(col) ? frames[d.row][col] : nil {
                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(x: d.flip ? -1 : 1, y: 1)
                        .padding(24)
                } else {
                    ProgressView()
                }
            }
            .frame(height: 400)
            Text("\(d.name) · \(walking ? "行走" : "待机") 第 \(col) 列 · 烘焙 \(String(format: "%.0f", bakeMs)) ms")
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            if let sheet {
                VStack(alignment: .leading, spacing: 6) {
                    Text("原生 sheet：5 行（正面 / 右前 / 右侧 / 右后 / 背面）× 8 列（待机 0–1，行走 2–7）")
                        .font(.caption).foregroundStyle(.secondary)
                    Image(decorative: sheet, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .background(Color(red: 0.36, green: 0.55, blue: 0.31))
                        .frame(maxHeight: 220)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    // MARK: 烘焙

    private func apply(_ p: CharacterPreset) {
        let outfitVariants = CharacterCatalog.outfits.first { $0.id == p.outfit }?.variants ?? [:]
        outfit = p.outfit
        hair = p.hair
        face = p.face
        skin = p.skin ?? "fair"
        weapon = p.weapon ?? ""
        topVariant = p.variants[.top] ?? outfitVariants[.top] ?? ""
        scarfVariant = p.variants[.scarf] ?? outfitVariants[.scarf] ?? ""
        hairVariant = p.variants[.hair] ?? ""
        faceVariant = p.variants[.face] ?? ""
        message = "已载入预设：\(p.name)"
        rebake()
    }

    private func rebake() {
        var p = CharacterPreset(id: "lab", name: "测试", outfit: outfit, hair: hair, face: face)
        p.skin = skin
        p.weapon = weapon.isEmpty ? nil : weapon
        if !topVariant.isEmpty { p.variants[.top] = topVariant }
        if !scarfVariant.isEmpty { p.variants[.scarf] = scarfVariant }
        if !hairVariant.isEmpty { p.variants[.hair] = hairVariant }
        if !faceVariant.isEmpty { p.variants[.face] = faceVariant }
        do {
            let start = Date()
            let eq = try catalog.equipment(for: p)
            guard let image = SpriteBaker.sheet(eq) else {
                message = "烘焙失败：无法生成图像"
                return
            }
            bakeMs = Date().timeIntervalSince(start) * 1000
            sheet = image
            frames = Self.cut(image)
        } catch {
            message = "\(error)"
        }
    }

    /// 原生 sheet → [行][列] 单帧
    private static func cut(_ sheet: CGImage) -> [[CGImage]] {
        let w = SpriteRig.sprW, h = SpriteRig.sprH
        return (0..<5).map { r in
            (0..<SpriteRig.framesPerDir).compactMap { c in
                sheet.cropping(to: CGRect(x: c * w, y: r * h, width: w, height: h))
            }
        }
    }
}
