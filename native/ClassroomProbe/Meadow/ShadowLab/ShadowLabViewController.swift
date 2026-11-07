import MetalKit
import UIKit

final class ShadowLabViewController: UIViewController {
    private var metalView: MTKView!
    private var renderer: ShadowLabRenderer?
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let pauseButton = UIButton(type: .system)
    private let sunButton = UIButton(type: .system)
    private let shadowButton = UIButton(type: .system)
    private let modelButton = UIButton(type: .system)
    private let layoutButton = UIButton(type: .system)
    private let sunSlider = UISlider()
    private let controls = UIStackView()
    private var pinchStart: Float = 1
    private var demoTimer: Timer?
    private var demoStep = 0

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.24, green: 0.31, blue: 0.16, alpha: 1)
        guard let device = MTLCreateSystemDefaultDevice() else { showFailure("此设备无法使用 Metal") ; return }
        do {
            let renderer = try ShadowLabRenderer(device: device)
            self.renderer = renderer
            metalView = MTKView(frame: view.bounds, device: device)
            metalView.colorPixelFormat = .bgra8Unorm
            metalView.preferredFramesPerSecond = 60
            metalView.delegate = renderer
            metalView.accessibilityIdentifier = "shadowLabSurface"
            metalView.accessibilityLabel = "光影试验场，树、塔和行走旅人"
            metalView.isAccessibilityElement = true
            view.addSubview(metalView)
            renderer.onStatus = { [weak self] status in
                guard let self else { return }
                self.statusLabel.text = status
                self.publishState()
            }
        } catch { showFailure(error.localizedDescription); return }
        titleLabel.text = "光影试验场 · 树、塔与旅人"
        titleLabel.textColor = UIColor(red: 1, green: 0.96, blue: 0.77, alpha: 1)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.layer.shadowColor = UIColor.black.cgColor
        titleLabel.layer.shadowOpacity = 0.8
        titleLabel.layer.shadowRadius = 3
        titleLabel.layer.shadowOffset = .zero
        view.addSubview(titleLabel)
        statusLabel.textColor = titleLabel.textColor
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusLabel.textAlignment = .right
        statusLabel.text = "正在建立三维实时投影…"
        statusLabel.layer.shadowColor = UIColor.black.cgColor
        statusLabel.layer.shadowOpacity = 0.9
        statusLabel.layer.shadowRadius = 3
        statusLabel.layer.shadowOffset = .zero
        view.addSubview(statusLabel)
        configure(closeButton, "返回地图", "shadowLabClose", #selector(close))
        configure(pauseButton, "暂停动态", "shadowLabPause", #selector(togglePause))
        configure(sunButton, "阳光自动", "shadowLabSun", #selector(toggleSun))
        configure(shadowButton, "投影开启", "shadowLabShadows", #selector(toggleShadows))
        configure(modelButton, "网格隐藏", "shadowLabModels", #selector(toggleModels))
        configure(layoutButton, "换一组布局", "shadowLabRelayout", #selector(relayout))
        controls.axis = .horizontal; controls.spacing = 8; controls.distribution = .fillEqually
        for button in [sunButton, shadowButton, modelButton, layoutButton] { controls.addArrangedSubview(button) }
        view.addSubview(controls)
        sunSlider.minimumValue = -1.5; sunSlider.maximumValue = 1.5; sunSlider.value = -0.65
        sunSlider.tintColor = UIColor(red: 1, green: 0.83, blue: 0.35, alpha: 1)
        sunSlider.accessibilityIdentifier = "shadowLabSunSlider"
        sunSlider.accessibilityLabel = "太阳方向"
        sunSlider.addTarget(self, action: #selector(changeSun), for: .valueChanged)
        view.addSubview(sunSlider)
        metalView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
        if ProcessInfo.processInfo.arguments.contains("-shadowReviewDemo") {
            demoTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.advanceDemo() }
        }
    }

    private func configure(_ button: UIButton, _ title: String, _ identifier: String, _ action: Selector) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = UIColor(red: 0.97, green: 0.91, blue: 0.70, alpha: 0.96)
        configuration.baseForegroundColor = UIColor(red: 0.25, green: 0.28, blue: 0.14, alpha: 1)
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
        button.configuration = configuration
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
        view.addSubview(button)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        metalView?.frame = view.bounds
        let safe = view.safeAreaInsets
        let left = max(safe.left, 12), right = view.bounds.width - max(safe.right, 12)
        let top = max(safe.top, 8), bottom = view.bounds.height - max(safe.bottom, 10)
        closeButton.frame = CGRect(x: left, y: top, width: 96, height: 36)
        pauseButton.frame = CGRect(x: right - 96, y: top, width: 96, height: 36)
        titleLabel.frame = CGRect(x: left + 100, y: top, width: max(0, right - left - 200), height: 36)
        let width = min(690, right - left)
        controls.frame = CGRect(x: view.bounds.midX - width / 2, y: bottom - 36, width: width, height: 36)
        sunSlider.frame = CGRect(x: left + 8, y: bottom - 77, width: min(260, (right - left) * 0.40), height: 32)
        statusLabel.frame = CGRect(x: right - min(390, (right - left) * 0.57), y: bottom - 73,
                                   width: min(390, (right - left) * 0.57), height: 26)
    }

    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); metalView?.isPaused = false }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); metalView?.isPaused = true; demoTimer?.invalidate() }

    private func showFailure(_ message: String) {
        titleLabel.text = "光影试验场启动失败：\(message)"
        titleLabel.textColor = .white; titleLabel.numberOfLines = 0
        titleLabel.frame = view.bounds.insetBy(dx: 40, dy: 40); titleLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(titleLabel)
    }

    private func title(_ button: UIButton, _ text: String) { var c = button.configuration; c?.title = text; button.configuration = c }
    @objc private func togglePause() { renderer?.paused.toggle(); title(pauseButton, renderer?.paused == true ? "继续动态" : "暂停动态"); publishState() }
    @objc private func toggleSun() {
        guard let renderer else { return }
        renderer.manualSun = renderer.currentSunAngle
        renderer.automaticSun.toggle()
        sunSlider.value = renderer.manualSun
        title(sunButton, renderer.automaticSun ? "阳光自动" : "阳光固定"); publishState()
    }
    @objc private func toggleShadows() { renderer?.shadowsEnabled.toggle(); title(shadowButton, renderer?.shadowsEnabled == true ? "投影开启" : "投影关闭"); publishState() }
    @objc private func toggleModels() { renderer?.modelsVisible.toggle(); title(modelButton, renderer?.modelsVisible == true ? "网格显示" : "网格隐藏"); publishState() }
    @objc private func relayout() { renderer?.seed += 7; publishState() }
    @objc private func changeSun() { renderer?.automaticSun = false; renderer?.manualSun = sunSlider.value; title(sunButton, "阳光固定"); publishState() }
    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        guard let renderer else { return }
        if gesture.state == .began { pinchStart = renderer.zoom }
        renderer.zoom = max(0.8, min(1.6, pinchStart * Float(gesture.scale)))
        publishState()
    }
    @objc private func close() {
        if presentingViewController != nil { dismiss(animated: true) }
        else { view.window?.rootViewController = GameViewController() }
    }

    private func publishState() {
        guard let renderer, let metalView else { return }
        let state: [String: Any] = ["ready": true, "renderer": "Metal depth shadow map", "objects": 3,
                                    "shadowSize": renderer.shadowSize, "shadows": renderer.shadowsEnabled,
                                    "models": renderer.modelsVisible, "paused": renderer.paused,
                                    "automaticSun": renderer.automaticSun, "seed": renderer.seed, "time": renderer.elapsed,
                                    "zoom": renderer.zoom]
        if let data = try? JSONSerialization.data(withJSONObject: state, options: .sortedKeys) {
            metalView.accessibilityValue = String(data: data, encoding: .utf8)
        }
    }

    private func advanceDemo() {
        guard let renderer else { return }
        demoStep += 1
        switch demoStep {
        case 1: toggleModels()
        case 2:
            toggleModels(); togglePause()
            renderer.automaticSun = false; renderer.manualSun = 0.85; title(sunButton, "阳光固定")
        case 3: toggleShadows()
        case 4: toggleShadows(); relayout(); togglePause()
        default: demoTimer?.invalidate()
        }
        publishState()
    }
}
