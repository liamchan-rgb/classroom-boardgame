import UIKit
import SpriteKit

final class GameViewController: UIViewController, UIGestureRecognizerDelegate {
    private let gameView = SKView()
    private let scene = GameScene()
    private let titleButton = ParchmentButton(symbol: .title)
    private let playButton = ParchmentButton(symbol: .play)
    private let resetButton = ParchmentButton(symbol: .reset)
    private let zoomButton = ParchmentButton(symbol: .zoom)
    private var gestureZoom: CGFloat = 1
    private let metricsLabel = UILabel()
    private let discoveryLabel = UILabel()
    private let reviewMode = ProcessInfo.processInfo.arguments.contains("-visualReview")

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    override func loadView() { view = UIView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        gameView.frame = view.bounds
        view.addSubview(gameView)
        gameView.ignoresSiblingOrder = true
        gameView.preferredFramesPerSecond = 60
        gameView.isMultipleTouchEnabled = true
        gameView.accessibilityIdentifier = "meadowMap"
        gameView.isAccessibilityElement = true
        gameView.accessibilityLabel = "林间地图，已选择 P1"
        gameView.accessibilityTraits = .allowsDirectInteraction
        scene.scaleMode = .resizeFill
        scene.size = view.bounds.size
        for button in [titleButton, playButton, resetButton, zoomButton] { view.addSubview(button) }
        for label in [metricsLabel, discoveryLabel] {
            label.textColor = UIColor(red: 1, green: 0.94, blue: 0.75, alpha: 1)
            label.backgroundColor = UIColor(red: 0.17, green: 0.22, blue: 0.17, alpha: 0.82)
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            label.textAlignment = .center
            label.layer.cornerRadius = 6
            label.clipsToBounds = true
            label.isUserInteractionEnabled = false
            view.addSubview(label)
        }
        metricsLabel.numberOfLines = 2
        metricsLabel.isHidden = true
        discoveryLabel.alpha = 0
        titleButton.accessibilityIdentifier = "helpButton"
        titleButton.accessibilityLabel = "安然，查看操作说明"
        titleButton.addTarget(self, action: #selector(showHelp), for: .touchUpInside)
        playButton.accessibilityIdentifier = "playButton"
        playButton.accessibilityLabel = "开始行旅"
        playButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
        resetButton.accessibilityIdentifier = "resetButton"
        resetButton.accessibilityLabel = "复位地图和人物"
        resetButton.addTarget(self, action: #selector(reset), for: .touchUpInside)
        zoomButton.accessibilityIdentifier = "zoomButton"
        zoomButton.accessibilityLabel = "放大地图"
        zoomButton.accessibilityValue = "100%"
        zoomButton.addTarget(self, action: #selector(zoom), for: .touchUpInside)
        scene.onPlaybackChanged = { [weak self] playing in
            self?.playButton.isPlaying = playing
            self?.playButton.accessibilityLabel = playing ? "暂停行旅" : "开始行旅"
        }
        scene.onSelectionChanged = { [weak self] name in
            self?.gameView.accessibilityLabel = "林间地图，已选择 \(name)"
        }
        scene.onDiagnostics = { [weak self] text in
            guard let self else { return }
            self.gameView.accessibilityValue = self.reviewMode ? text : (self.scene.isRunning ? "旅人移动中" : "旅人暂停")
            self.zoomButton.accessibilityValue = "\(Int(round(self.scene.zoom * 100)))%"
        }
        scene.onMetrics = { [weak self] text in self?.metricsLabel.text = text }
        scene.onDiscovery = { [weak self] text in
            guard let self else { return }
            self.discoveryLabel.text = text
            self.discoveryLabel.layer.removeAllAnimations()
            self.discoveryLabel.alpha = 1
            UIView.animate(withDuration: 0.6, delay: 2.2, options: [.beginFromCurrentState]) {
                self.discoveryLabel.alpha = 0
            }
        }
        gameView.presentScene(scene)
        titleButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(toggleMetrics(_:))))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinchMap(_:)))
        pinch.delegate = self
        gameView.addGestureRecognizer(pinch)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panMap(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        gameView.addGestureRecognizer(pan)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gameView.frame = view.bounds
        let inset = view.safeAreaInsets
        let top = max(inset.top, 6)
        let isPad = traitCollection.userInterfaceIdiom == .pad
        let button: CGFloat = isPad ? 44 : 34
        let spacing = button + 2
        titleButton.frame = CGRect(x: max(inset.left, 10) + 4, y: top, width: isPad ? 88 : 70, height: isPad ? 44 : 38)
        let right = view.bounds.width - max(inset.right, 10) - 4
        zoomButton.frame = CGRect(x: right - button, y: top + 2, width: button, height: button)
        resetButton.frame = zoomButton.frame.offsetBy(dx: -spacing, dy: 0)
        playButton.frame = resetButton.frame.offsetBy(dx: -spacing, dy: 0)
        metricsLabel.frame = CGRect(x: right - 225, y: view.bounds.height - max(inset.bottom, 10) - 50, width: 225, height: 48)
        discoveryLabel.frame = CGRect(x: view.bounds.midX - 110, y: view.bounds.height - max(inset.bottom, 10) - 44, width: 220, height: 34)
    }

    @objc private func togglePlayback() { scene.togglePlayback() }

    @objc private func reset() {
        scene.reset()
        zoomButton.accessibilityValue = "100%"
    }

    @objc private func zoom() {
        scene.setZoom(scene.zoom >= 1.79 ? 1 : scene.zoom + 0.25)
        zoomButton.accessibilityValue = "\(Int(scene.zoom * 100))%"
    }

    @objc private func pinchMap(_ recognizer: UIPinchGestureRecognizer) {
        if recognizer.state == .began { gestureZoom = scene.zoom }
        scene.setZoom(gestureZoom * recognizer.scale, anchorInView: recognizer.location(in: gameView))
        zoomButton.accessibilityValue = "\(Int(scene.zoom * 100))%"
    }

    @objc private func panMap(_ recognizer: UIPanGestureRecognizer) {
        scene.panBy(recognizer.translation(in: gameView))
        recognizer.setTranslation(.zero, in: gameView)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    @objc private func toggleMetrics(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began { metricsLabel.isHidden.toggle() }
    }

    @objc private func showHelp() {
        let help = UIAlertController(title: "安然 · 林间行旅",
                                     message: "▶ 三位旅人沿土路往返；Ⅱ 暂停后保留目的地\n点选 P1 / P2 / P3，再点道路指定目的地\n点问号，让旅人抵达并探索\n↻ 恢复初始位置；＋ 放大\n双指缩放、拖动；长按安然显示运行指标", preferredStyle: .alert)
        help.addAction(UIAlertAction(title: "出发", style: .default))
        present(help, animated: true)
    }
}
