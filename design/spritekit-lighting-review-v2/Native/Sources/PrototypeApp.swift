import SwiftUI
import SpriteKit
import Combine

enum ReviewAspect: String, CaseIterable {
    case wide, standard
    var title: String { self == .wide ? "16:9" : "4:3" }
    var ratio: CGFloat { self == .wide ? 16.0/9.0 : 4.0/3.0 }
}

@MainActor final class PrototypeController: ObservableObject {
    let scene = GrassScene(size: CGSize(width: 1600, height: 900))
    @Published var mode: LightingMode
    @Published var strength: Double = 0.75
    @Published var aspect: ReviewAspect
    @Published var isReady = false
    @Published var error: String?
    @Published var follows = false
    @Published var arrivalState = "node-1"
    private var replayTask: Task<Void, Never>?
    private var replayEvents: [[String: Any]] = []
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        mode = arguments.contains("--lighting=flat") || arguments.contains("--review-replay") ? .flat : .sunlight
        aspect = ProcessInfo.processInfo.environment["PROTOTYPE_RATIO"] == "4x3" ? .standard : .wide
        scene.onReady = { [weak self] in DispatchQueue.main.async {
            self?.isReady = true; self?.startReviewReplayIfRequested()
        } }
        scene.onError = { [weak self] error in DispatchQueue.main.async { self?.error = error } }
        scene.onArrival = { [weak self] in DispatchQueue.main.async { self?.arrivalState = "node-2" } }
        scene.setLighting(mode, strength: CGFloat(strength))
    }
    func setMode(_ value: LightingMode) { mode = value; scene.setLighting(value, strength: CGFloat(strength)) }
    func setStrength(_ value: Double) { strength = value; scene.setLighting(mode, strength: CGFloat(value)) }
    func follow(_ value: Bool) { follows = value; scene.followHero(value) }
    func play() { arrivalState = "moving"; scene.playFixture() }
    private func trace(_ phase: String) {
        var event = scene.reviewState
        event["phase"] = phase; event["timestamp"] = Date().timeIntervalSince1970
        event["ratio"] = aspect.title
        event["sourceCommit"] = ProcessInfo.processInfo.environment["PROTOTYPE_SOURCE_COMMIT"] ?? "local"
        replayEvents.append(event)
        do {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("review-replay.json")
            try JSONSerialization.data(withJSONObject: replayEvents, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        } catch { print("Review trace failed: \(error)") }
    }
    private func startReviewReplayIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--review-replay"), replayTask == nil else { return }
        // An opt-in deterministic display fixture for CI video, with no game commands.
        replayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.setMode(.flat); self.trace("original")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.setMode(.sunlight); self.trace("sunlight")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.play(); self.trace("movement-start")
            try? await Task.sleep(nanoseconds: 900_000_000)
            self.trace("movement-middle")
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self.trace("arrival")
            self.follow(true); self.scene.setZoom(1.45); self.play(); self.trace("follow-start")
            try? await Task.sleep(nanoseconds: 2_100_000_000)
            self.trace("follow-arrival"); self.follow(false); self.scene.overview(); self.setMode(.normal)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.trace("local-light")
            self.setMode(.sunlight)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.trace("complete")
        }
    }
}

struct PrototypeGlass: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        #else
        content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        #endif
    }
}

@MainActor struct PrototypeView: View {
    @StateObject private var model = PrototypeController()
    @State private var settings = false
    @State private var previousDrag = CGSize.zero
    @State private var previousMagnification: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var forcedReduceMotion: Bool { ProcessInfo.processInfo.arguments.contains("--reduce-motion") }
    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, geometry.size.height * model.aspect.ratio)
            let height = width / model.aspect.ratio
            ZStack(alignment: .top) {
                SpriteView(scene: model.scene, preferredFramesPerSecond: 30)
                    .gesture(DragGesture(minimumDistance: 8).onChanged { value in
                        model.follows = false
                        model.scene.pan(dx: value.translation.width - previousDrag.width, dy: value.translation.height - previousDrag.height)
                        previousDrag = value.translation
                    }.onEnded { _ in previousDrag = .zero })
                    .simultaneousGesture(MagnificationGesture().onChanged { value in
                        model.scene.magnify(by: value / previousMagnification); previousMagnification = value
                    }.onEnded { _ in previousMagnification = 1 })
                HStack {
                    Text("安然").font(.system(size: 23, weight: .semibold)).padding(.horizontal, 18).padding(.vertical, 12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    Spacer()
                    glassButton("play.fill", label: "播放移动样例", id: "play-demo") { model.play() }.disabled(!model.isReady)
                        .accessibilityValue(model.arrivalState)
                    glassButton(model.mode == .flat ? "sun.max" : "sun.max.fill", label: "切换光照模式", id: "lighting-mode") { model.setMode(model.mode.next) }
                        .accessibilityValue(model.mode.title)
                    glassButton("scope", label: "地图总览", id: "overview") { model.follows = false; model.scene.overview() }
                    glassButton("slider.horizontal.3", label: "查看设置", id: "review-settings") { settings = true }
                }.padding(20)
                if let error = model.error {
                    Text(error).foregroundStyle(.red).padding().background(.regularMaterial).padding(.top, 95)
                }
            }.frame(width: width, height: height)
                .position(x: geometry.size.width/2, y: geometry.size.height/2)
        }.background(Color(red: 0.04, green: 0.10, blue: 0.13)).ignoresSafeArea()
            .onAppear { model.scene.setReducedMotion(reduceMotion || forcedReduceMotion) }
            .onChange(of: reduceMotion) { _, value in model.scene.setReducedMotion(value || forcedReduceMotion) }
            .sheet(isPresented: $settings) {
                NavigationStack {
                    Form {
                        Picker("光照", selection: Binding(get: { model.mode }, set: model.setMode)) {
                            ForEach(LightingMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
                        }
                        VStack(alignment: .leading) {
                            Text("光影强度")
                            Slider(value: Binding(get: { model.strength }, set: model.setStrength), in: 0...1)
                        }
                        Picker("画面比例", selection: $model.aspect) {
                            ForEach(ReviewAspect.allCases, id: \.self) { aspect in Text(aspect.title).tag(aspect) }
                        }.pickerStyle(.segmented)
                        Toggle("跟随人物", isOn: Binding(get: { model.follows }, set: model.follow))
                        Text("原始素材保留图内已有光照；太阳光影增加投影与遮阴；局部光照用于比较灯光效果。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.navigationTitle("小样查看设置")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { settings = false } } }
                }
            }
    }
    private func glassButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 20, weight: .medium)).frame(width: 48, height: 48) }
            .buttonStyle(.plain).modifier(PrototypeGlass()).accessibilityLabel(label).accessibilityIdentifier(id)
    }
}

@main struct GrassLightingPrototypeApp: App {
    var body: some Scene { WindowGroup { PrototypeView() } }
}
