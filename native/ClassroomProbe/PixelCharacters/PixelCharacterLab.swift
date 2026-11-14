import Combine
import SwiftUI
import UIKit

/// 像素人物测试界面（教师端）。
/// 用游戏里同一个烘焙器（Resources/pixel-baker.js）现场合成人物：体型预设、发型、发色、五官、瞳色、上衣 / 护甲、肤色、武器，
/// 右侧放大预览选中的动画（行走、战斗待机、四种攻击、格挡、受击、胜利、倒下），可以按方向看或自动转圈，下方是整张 sheet。
struct PixelCharacterLab: View {
    var onClose: () -> Void

    @State private var hair = "hair_messy"
    @State private var hairColor = "chestnut"
    @State private var face = "face_round"
    @State private var eyes = "blue"
    @State private var top = "top_traveler"
    @State private var topVariant = "blue"
    @State private var skin = "fair"
    @State private var weapon = "weapon_training_sword"
    @State private var animation = "ready"
    @State private var dir8 = 2
    @State private var turning = false
    @State private var tick = 0
    @State private var sheet: CGImage?
    @State private var bakeMs = 0.0
    @State private var baking = false
    @State private var bakedSignature = ""

    private var info: PixelBaker.Info { PixelBaker.shared.info }
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    /// 8 个方向 → (sheet 的行, 是否镜像, 名称)。行顺序：S SE E NE N
    private static let dirs: [(row: Int, flip: Bool, name: String)] = [
        (0, false, "正面"), (1, false, "右前"), (2, false, "右侧"), (3, false, "右后"),
        (4, false, "背面"), (3, true, "左后"), (2, true, "左侧"), (1, true, "左前"),
    ]
    private static let animations: [(String, String)] = [
        ("idle", "普通待机"), ("walk", "行走"), ("ready", "战斗待机"), ("slash", "挥砍"), ("heavy", "重劈"),
        ("shoot", "射箭"), ("cast", "施法"), ("guard", "格挡"), ("hurt", "受击"), ("victory", "胜利"), ("defeat", "倒下"),
    ]
    private static let skins: [(String, String)] = [("fair", "白皙"), ("light", "浅"), ("tan", "小麦"), ("deep", "深")]
    /// 游戏里的体型和预设旅人
    private static let presets: [(String, PixelHeroLook)] = [
        ("林地旅人", PixelHeroLook(body: "forester", weapon: "trainingSword")),
        ("远行者", PixelHeroLook(body: "wayfarer", weapon: "legendaryStaff")),
        ("红衣旅人", PixelHeroLook(body: "crimson", weapon: "greatSword")),
        ("林间行者", PixelHeroLook(body: "grove", weapon: "huntingBow")),
    ]

    private func items(_ slot: String) -> [PixelBaker.Info.Item] { info.items[slot] ?? [] }
    private func variants(_ slot: String, _ id: String) -> [(String, String)] {
        (items(slot).first { $0.id == id }?.variants ?? []).map { ($0.id, $0.name) }
    }

    private var spec: [String: Any] {
        var slots = ["hair": hair, "face": face, "top": top, "bottom": "bottom_trousers", "shoes": "shoes_boots"]
        if !weapon.isEmpty { slots["weapon_main"] = weapon }
        return ["slots": slots, "variants": ["hair": hairColor, "face": eyes, "top": topVariant, "bottom": "dark", "shoes": "brown"], "skin": skin]
    }
    private var signature: String { [hair, hairColor, face, eyes, top, topVariant, skin, weapon].joined(separator: "|") }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("像素人物测试").font(.title2.bold())
                Text("游戏内烘焙 · 每帧 \(info.sprW)×\(info.sprH) · 每方向 \(info.framesPerDir) 帧").foregroundStyle(.secondary)
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
        .onAppear { rebake() }
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
                section("游戏里的旅人") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                        ForEach(Self.presets, id: \.0) { p in Button(p.0) { apply(p.1) }.buttonStyle(.bordered) }
                    }
                }
                section("发型与五官") {
                    picker("发型", $hair, items("hair").map { ($0.id, $0.name) })
                    picker("发色", $hairColor, variants("hair", hair))
                    picker("五官", $face, items("face").map { ($0.id, $0.name) })
                    picker("瞳色", $eyes, [("", "默认")] + variants("face", face))
                    picker("肤色", $skin, Self.skins)
                }
                section("衣服与武器") {
                    picker("上衣", Binding(get: { top }, set: { top = $0; topVariant = "" }), items("top").map { ($0.id, $0.name) })
                    if !variants("top", top).isEmpty { picker("配色", $topVariant, [("", "默认")] + variants("top", top)) }
                    picker("武器", $weapon, [("", "空手")] + items("weapon_main").map { ($0.id, $0.name) })
                }
                section("预览") {
                    picker("动画", $animation, Self.animations)
                    Toggle("自动转向", isOn: $turning)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                        ForEach(0..<8, id: \.self) { i in
                            Button(Self.dirs[i].name) { turning = false; dir8 = i }
                                .buttonStyle(.bordered).font(.caption2)
                                .tint(i == dir8 ? .accentColor : .gray)
                        }
                    }
                }
                Text(baking ? "烘焙中…" : "烘焙 \(String(format: "%.0f", bakeMs)) ms（第二次起读缓存）")
                    .font(.footnote).foregroundStyle(.secondary)
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
            Text(title).frame(width: 56, alignment: .leading).foregroundStyle(.secondary)
            Picker(title, selection: value) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.menu)
            Spacer(minLength: 0)
        }
    }

    // MARK: 右侧预览

    private var currentColumn: Int {
        let frames = info.frames[animation] ?? [0]
        // 战斗动作 4 帧一轮，待机 / 呼吸慢一点
        let slow = ["idle", "ready", "guard", "hurt", "victory", "defeat"].contains(animation)
        return frames[(slow ? tick / 5 : tick / 2) % frames.count]
    }

    private var preview: some View {
        VStack(spacing: 16) {
            let d = Self.dirs[dir8]
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.36, green: 0.55, blue: 0.31))
                if let sheet, let image = sheet.cropping(to: CGRect(x: currentColumn * info.sprW, y: d.row * info.sprH, width: info.sprW, height: info.sprH)) {
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
            Text("\(d.name) · \(Self.animations.first { $0.0 == animation }?.1 ?? animation) · 第 \(currentColumn) 列")
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            if let sheet {
                VStack(alignment: .leading, spacing: 6) {
                    Text("sheet：5 行（正面 / 右前 / 右侧 / 右后 / 背面）× \(info.framesPerDir) 列").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        Image(decorative: sheet, scale: 1)
                            .interpolation(.none)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 200)
                            .background(Color(red: 0.36, green: 0.55, blue: 0.31))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    // MARK: 烘焙

    private func apply(_ look: PixelHeroLook) {
        let spec = look.spec
        let slots = spec["slots"] as? [String: String] ?? [:]
        let variants = spec["variants"] as? [String: String] ?? [:]
        hair = slots["hair"] ?? hair
        hairColor = variants["hair"] ?? ""
        face = slots["face"] ?? face
        eyes = variants["face"] ?? ""
        top = slots["top"] ?? top
        topVariant = variants["top"] ?? ""
        skin = spec["skin"] as? String ?? "fair"
        weapon = slots["weapon_main"] ?? ""
        animation = "ready"
    }

    private func rebake() {
        let spec = spec, signature = signature
        let w = info.sprW, h = info.sprH, columns = info.framesPerDir
        baking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let start = Date()
            let bytes = PixelBaker.shared.bake(spec: spec, dirs: PixelBaker.shared.info.dirs, frames: Array(0..<columns))
            let image = bytes.flatMap { PixelHeroAtlas.makeImage([UInt8]($0), width: w * columns, height: h * 5)?.cgImage }
            let ms = Date().timeIntervalSince(start) * 1000
            DispatchQueue.main.async {
                guard signature == self.signature else { return }
                sheet = image
                bakeMs = ms
                baking = false
                bakedSignature = signature
            }
        }
    }
}
