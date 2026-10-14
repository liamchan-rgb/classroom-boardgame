import SwiftUI
import SpriteKit
import Combine

enum ReviewAspect: String, CaseIterable {
    case wide, standard
    var title: String { self == .wide ? "16:9" : "4:3" }
    var ratio: CGFloat { self == .wide ? 16.0/9.0 : 4.0/3.0 }
}

@MainActor final class PrototypeController: ObservableObject {
    let scene = GrassScene(size: CGSize(width: 1600, height: 1200))
    @Published var mode: LightingMode
    @Published var strength: Double = 0.85
    @Published var effects = HD2DSettings()
    @Published var aspect: ReviewAspect
    @Published var isReady = false
    @Published var error: String?
    @Published var follows = false
    @Published var arrivalState = "node-1"
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        mode = arguments.contains("--lighting=flat") ? .flat : .sunlight
        aspect = ProcessInfo.processInfo.environment["PROTOTYPE_RATIO"] == "16x9" ? .wide : .standard
        scene.onReady = { [weak self] in DispatchQueue.main.async {
            self?.isReady = true
        } }
        scene.onError = { [weak self] error in DispatchQueue.main.async { self?.error = error } }
        scene.onArrival = { [weak self] in DispatchQueue.main.async { self?.arrivalState = "node-2" } }
        scene.setLighting(mode, strength: CGFloat(strength))
    }
    func setMode(_ value: LightingMode) { mode = value; scene.setLighting(value, strength: CGFloat(strength)) }
    func setStrength(_ value: Double) { strength = value; scene.setLighting(mode, strength: CGFloat(value)) }
    func follow(_ value: Bool) { follows = value; scene.followHero(value) }
    func play() { arrivalState = "moving"; scene.playFixture() }
    func updateEffects(_ value: HD2DSettings) { effects = value.bounded(); scene.setEffects(effects) }

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
        }.background(Color(red: 0.04, green: 0.10, blue: 0.13)).ignoresSafeArea().statusBarHidden(true)
            .onAppear { model.scene.setReducedMotion(reduceMotion || forcedReduceMotion) }
            .onChange(of: reduceMotion) { _, value in model.scene.setReducedMotion(value || forcedReduceMotion) }
            .sheet(isPresented: $settings) {
                NavigationStack {
                    Form {
                        Picker("光照", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                            ForEach(LightingMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
                        }
                        VStack(alignment: .leading) {
                            Text("光影强度")
                            Slider(value: Binding(get: { model.strength }, set: { model.setStrength($0) }), in: 0...1)
                        }
                        Picker("画面比例", selection: $model.aspect) {
                            ForEach(ReviewAspect.allCases, id: \.self) { aspect in Text(aspect.title).tag(aspect) }
                        }.pickerStyle(.segmented)
                        Toggle("跟随人物", isOn: Binding(get: { model.follows }, set: { model.follow($0) }))
                        Section("光照与材质") {
                            effectToggle("缓坡与岩壁", \.terrain)
                            effectToggle("左上暖阳", \.directionalLight)
                            effectToggle("自然色彩", \.colorGrade)
                            effectToggle("接触阴影", \.contactShadows)
                            effectSlider("投影强度", \.shadowStrength)
                            effectToggle("自然草地群落", \.vegetation)
                            effectSlider("草地细节", \.vegetationContrast)
                            effectToggle("地形明暗层次", \.relief)
                        }
                        Section("环境氛围") {
                            effectToggle("局部柔光", \.bloom)
                            effectSlider("柔光强度", \.bloomStrength)
                            effectToggle("远景空气透视", \.atmosphere)
                            effectSlider("空气透视", \.atmosphereStrength)
                            effectToggle("角落前景树", \.foregroundTrees)
                            effectToggle("边缘景深", \.edgeDepth)
                            effectSlider("景深半径", \.depthRadius, range: 0...2.2)
                            effectToggle("环境微动", \.environmentalMotion)
                            effectSlider("微动幅度", \.motionStrength)
                        }
                        Button("恢复推荐效果") { model.updateEffects(HD2DSettings()); model.setStrength(0.85); model.setMode(.sunlight) }
                    }.navigationTitle("小样查看设置")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { settings = false } } }
                }
            }
    }
    private func effectToggle(_ name: String, _ key: WritableKeyPath<HD2DSettings, Bool>) -> some View {
        Toggle(name, isOn: Binding(get: { model.effects[keyPath: key] }, set: { value in
            var settings = model.effects; settings[keyPath: key] = value; model.updateEffects(settings)
        }))
    }
    private func effectSlider(_ name: String, _ key: WritableKeyPath<HD2DSettings, Double>, range: ClosedRange<Double> = 0...1) -> some View {
        VStack(alignment: .leading) {
            Text(name)
            Slider(value: Binding(get: { model.effects[keyPath: key] }, set: { value in
                var settings = model.effects; settings[keyPath: key] = value; model.updateEffects(settings)
            }), in: range)
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
