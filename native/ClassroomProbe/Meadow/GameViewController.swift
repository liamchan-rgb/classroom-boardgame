import UIKit
import SpriteKit
import MetalKit
import MeadowBattleSupport
import ClassroomGameCore
import MeadowWorldSupport
import MeadowClassroomSupport

final class GameViewController: UIViewController, UIGestureRecognizerDelegate {
    private let classroomMode:Bool
    private var classroomSuspended=false
    var classroomMirrorEnabled=false {didSet{
        // In battle the teacher frame is one GPU snapshot of the whole screen (map drawer included): no separate map readback.
        groundRenderer?.classroomMirrorEnabled=classroomMirrorEnabled && !battlePreviewActive
        if classroomMirrorEnabled && !oldValue {classroomOverlayDirty=true;classroomDeliveredMap = -1;classroomDeliveryClock=ClassroomPreviewClock()}
    }}
    private var classroomMapFrame:CGImage?
    private var classroomMapSerial=0, classroomOverlaySerial=0
    private var classroomDeliveredMap = -1, classroomDeliveredOverlay = -1
    private var classroomOverlay:UIImage?
    private var classroomOverlayDirty=true
    private var classroomOverlayAt:TimeInterval = -.infinity
    private var classroomDeliveryClock=ClassroomPreviewClock()
    var classroomFrameAvailable:(()->Void)?
    /// Map pixels are never rerasterized on the main thread. UIKit captures
    /// only the transparent game overlay, cached between actual HUD changes.
    func classroomCaptureFrame()->MeadowTeacherPreviewFrame? {
        guard classroomMode,classroomMirrorEnabled,isViewLoaded,view.window != nil else{return nil}
        let now=ProcessInfo.processInfo.systemUptime
        let needsOverlay=ClassroomPreviewPolicy.refreshOverlay(now:now,last:classroomOverlayAt,dirty:classroomOverlayDirty || !ready,battle:battlePreviewActive)
        guard classroomDeliveredMap != classroomMapSerial || needsOverlay else{return nil}
        guard classroomDeliveryClock.take(at:now) else{return nil}
        if needsOverlay,battlePreviewActive {
            // Battle: re-rasterizing the whole battle layer tree on the CPU 30 times a second stole the main thread from the
            // 60 Hz battle on the TV, and could not show content drawn by the GPU. Take the render server's finished picture
            // instead (what the TV actually shows), at a lower size and rate.
            let format=UIGraphicsImageRendererFormat();format.scale=ClassroomPreviewPolicy.battleScale;format.opaque=true;format.preferredRange = .standard
            let bounds=CGRect(origin:.zero,size:ClassroomCanvas.size)
            classroomOverlay=UIGraphicsImageRenderer(size:ClassroomCanvas.size,format:format).image{context in
                if !view.drawHierarchy(in:bounds,afterScreenUpdates:false) {
                    for subview in view.subviews where !subview.isHidden && subview.alpha>0 {
                        context.cgContext.saveGState();context.cgContext.translateBy(x:subview.frame.minX,y:subview.frame.minY)
                        subview.layer.render(in:context.cgContext);context.cgContext.restoreGState()
                    }
                }
            }
            classroomOverlayAt=now;classroomOverlayDirty=false;classroomOverlaySerial += 1
            classroomDeliveredOverlay=classroomOverlaySerial
            return MeadowTeacherPreviewFrame(map:nil,mapRect:.zero,overlay:classroomOverlay,background:.black)
        }
        if needsOverlay {
            let format=UIGraphicsImageRendererFormat();format.scale=ClassroomPreviewPolicy.pixelScale;format.opaque=false;format.preferredRange = .standard
            classroomOverlay=UIGraphicsImageRenderer(size:ClassroomCanvas.size,format:format).image{context in
                for subview in view.subviews where subview !== groundView && !subview.isHidden && subview.alpha>0 {
                    context.cgContext.saveGState();context.cgContext.translateBy(x:subview.frame.minX,y:subview.frame.minY)
                    (subview.layer.presentation() ?? subview.layer).render(in:context.cgContext)
                    context.cgContext.restoreGState()
                }
            }
            classroomOverlayAt=now;classroomOverlayDirty=false;classroomOverlaySerial += 1
        }
        guard classroomDeliveredMap != classroomMapSerial || classroomDeliveredOverlay != classroomOverlaySerial else{return nil}
        classroomDeliveredMap=classroomMapSerial;classroomDeliveredOverlay=classroomOverlaySerial
        var map:CGImage?
        if let ground=groundView,let image=classroomMapFrame {
            let wanted=ClassroomPreviewPolicy.size(for:ground.drawableSize)
            if image.width==Int(wanted.width) && image.height==Int(wanted.height){map=image}
        }
        return MeadowTeacherPreviewFrame(map:map,mapRect:groundView?.frame ?? .zero,overlay:classroomOverlay,background:view.backgroundColor ?? .black)
    }
    func classroomZoom(by scale:CGFloat,anchor:CGPoint,role:ClassroomRole)throws {
        try ClassroomGameBackend.requireTeacher(role)
        guard ready,!classroomBusy,!battlePreviewActive,scale.isFinite,scale>0,gameView.frame.contains(anchor) else{return}
        scene.setZoom(scene.zoom*scale,anchorInView:CGPoint(x:anchor.x-gameView.frame.minX,y:anchor.y-gameView.frame.minY))
    }
    func classroomWorldPoint(at point:CGPoint,role:ClassroomRole)throws->CGPoint? {
        try ClassroomGameBackend.requireTeacher(role)
        guard ready,!battlePreviewActive,gameView.frame.contains(point) else{return nil}
        guard encounterPreview.isHidden || !encounterPreview.frame.contains(point) else{return nil}
        return scene.classroomWorldPoint(CGPoint(x:point.x-gameView.frame.minX,y:point.y-gameView.frame.minY))
    }
    func classroomNode(atWorldPoint point:CGPoint,role:ClassroomRole)throws->Int? {
        try ClassroomGameBackend.requireTeacher(role)
        guard ready,!battlePreviewActive else{return nil}
        return scene.classroomNode(atWorldPoint:point)
    }
    weak var classroomPrivatePresenter:UIViewController?
    var classroomAdvanceTravel:((Double)throws->[OperationReceipt])?
    var classroomBattleModel:(()throws->PartyEncounter)?
    func classroomEnemyStep(){battlePreviewView?.classroomEnemyStep()}
    var classroomStatus:((String)->Void)?
    var classroomInventoryChanged:((String?)->Void)?
    var classroomReload:(()->Void)?
    var classroomReady:Bool {ready}
    var classroomBusy:Bool {battlePreviewView?.classroomBusy ?? false}
    var classroomActions:[PartyAction] {battlePreviewView?.classroomActions ?? []}
    func classroomBattleHit(at point:CGPoint,role:ClassroomRole)throws->MeadowPartyBattleView.ClassroomHit? {
        try ClassroomGameBackend.requireTeacher(role)
        guard classroomMode,ready,battlePreviewActive,!classroomBusy,let battle=battlePreviewView else{return nil}
        return battle.classroomHit(at:view.convert(point,to:battle))
    }
    /// The "you received" card on the public display, put away from the teacher window.
    var classroomHasGainPopup:Bool {view.subviews.contains{$0 is MeadowGainPopup}}
    func classroomGainPopupTap(at point:CGPoint,role:ClassroomRole)throws->Bool {
        try ClassroomGameBackend.requireTeacher(role)
        guard let popup=view.subviews.compactMap({$0 as? MeadowGainPopup}).last else{return false}
        popup.relayTap(view.convert(point,to:popup));classroomOverlayDirty=true;return true
    }
    func classroomToggleBattleMap(role:ClassroomRole)throws {
        try ClassroomGameBackend.requireTeacher(role);battlePreviewView?.classroomToggleMap()
    }
    func classroomFinishBattleIfReady(){
        if classroomMode,battlePreviewActive,!classroomBusy,campaign?.engine.state.battle==nil {setBattlePreviewActive(false)}
    }
    private let campaign:MeadowCampaignSession?
    private let campaignRefill=MeadowPreviewPalette.button("补充移动")
    private let campaignItems=MeadowPreviewPalette.button("行囊与装备")
    private let campaignBattle=MeadowPreviewPalette.button("继续战斗")
    private let campaignEdit=MeadowPreviewPalette.button("编辑地点")
    private let campaignEnd=MeadowPreviewPalette.button("路线与目标")
    private let campaignTeam=MeadowPreviewPalette.button("队伍与成员")
    private let campaignHUD=UIView()
    private let campaignRoutePanel=UIView()
    private let campaignRouteTitle=MeadowPreviewPalette.label("点击道路即时移动",size:17)
    private let campaignRouteDetail=MeadowPreviewPalette.label("",size:14)
    private let campaignMovement=MeadowBattleResourceBar()
    private let campaignHealth=(0..<7).map{_ in MeadowBattleResourceBar()}
    private let campaignAP=(0..<7).map{_ in MeadowBattleActionPointsView()}
    private let encounterPreview=MeadowEncounterPreviewView()
    private var previewEncounterNode:Int?
    private let previewMap: GeneratedMeadowMap?
    private let randomMapButton = UIButton(type: .system)
    private let randomMapSummary = UILabel()

    init(previewMap: GeneratedMeadowMap? = nil,campaign:MeadowCampaignSession? = nil,classroomMode:Bool=false) {
        self.classroomMode=classroomMode
        self.campaign=campaign
        self.previewMap = campaign?.snapshot.layout ?? previewMap
        super.init(nibName:nil,bundle:nil)
    }
    required init?(coder: NSCoder) { classroomMode=false;campaign=nil;previewMap=nil;super.init(coder:coder) }
    deinit {NotificationCenter.default.removeObserver(self)}
    private let gameView = UIView()
    private var gaitView: SKView?
    private let scene = GameScene()
    private let loadingView = MeadowLoadingView()
    private var loadStarted = false
    private var ready = false
    private var groundBecameReady = false
    private var foregroundBecameReady = false
    private var loadingTimer: Timer?
    private var loadingBegan: TimeInterval = 0
    private var lastHeartbeat: TimeInterval = 0
    private var longestHeartbeatGap: TimeInterval = 0
    private var loadingHeartbeats = 0
    private var loadingStage = "准备进入林地"
    private var loadingProgress: Float = 0
    private var firstFrameWaitSeconds: TimeInterval?
    private var loadingFailed = false
    private var setupTimings: [String: Double] = [:]
    private var mapPresentationBegan: TimeInterval = 0
    private var groundView: MTKView?
    private var groundRenderer: MeadowShadowRenderer?
    private var gpuProbe: MeadowGPUProbe?
    private var checkedSavedReport = false
    private var mapPresented = false
    private let groundDrawableScale: CGFloat = 1
    private let gpuFallbackCount = 0
    private let titleButton = ParchmentButton(symbol: .title)
    private let playButton = ParchmentButton(symbol: .play)
    private let resetButton = ParchmentButton(symbol: .reset)
    private let zoomButton = ParchmentButton(symbol: .zoom)
    private let shadowLabButton = UIButton(type: .system)
    private var battleGainBase:GameState?
    private let gaitTestButton = UIButton(type: .system)
    private let battlePreviewButton = UIButton(type: .system)
    private var battlePreviewView: MeadowBattlePreviewView?
    private var battlePreviewActive = false
    private var metricsHiddenBeforeBattlePreview = true
    private let gaitPanel = UIStackView()
    private let gaitStatusLabel = UILabel()
    private let gaitPauseButton = UIButton(type: .system)
    private let gaitSlowButton = UIButton(type: .system)
    private let gaitStepButton = UIButton(type: .system)
    private let gaitLayeredPreviewButton = UIButton(type: .system)
    private let p1AppearanceButton = UIButton(type: .system)
    private var campSession:CampInventorySession?
    private var equipmentModel:TrainingLoadout? { campSession?.loadout }
    private var inventoryStartupIssue:String?
    private var gaitDirectionButtons: [UIButton] = []
    private var gaitCaptureTimer: Timer?
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
        view.backgroundColor = UIColor(red: 0.055, green: 0.09, blue: 0.065, alpha: 1)
        gameView.frame = view.bounds
        // This transparent UIView owns gestures/accessibility, not a renderer.
        // Normal map graphics are presented by the single MTKView below it.
        gameView.isOpaque = false
        gameView.backgroundColor = .clear
        view.addSubview(gameView)
        scene.onForegroundReady = { [weak self] in
            guard let self else { return }
            self.setupTimings["mapFirstForegroundDelay"] = ProcessInfo.processInfo.systemUptime - self.mapPresentationBegan
            self.foregroundBecameReady = true; self.finishLoading()
        }
        if !ProcessInfo.processInfo.arguments.contains("-gaitReview"), let device = MTLCreateSystemDefaultDevice() {
            let ground = MTKView(frame: view.bounds, device: device)
            ground.preferredFramesPerSecond = 60
            ground.autoResizeDrawable = !classroomMode
            ground.framebufferOnly = !classroomMode
            if classroomMode {ground.contentScaleFactor=1;ground.drawableSize=ClassroomCanvas.size}
            ground.colorPixelFormat = .bgra8Unorm
            ground.isOpaque = true
            ground.clearColor = MTLClearColor(red: 0.15, green: 0.20, blue: 0.08, alpha: 1)
            ground.isPaused = true
            ground.isUserInteractionEnabled = false
            ground.accessibilityElementsHidden = true
            view.insertSubview(ground, belowSubview: gameView)
            groundView = ground
            scene.onWorldReady = { [weak self] world in
                guard let self else { return }
                if self.groundRenderer != nil {
                    world.terrain.removeFromParent()
                    self.scene.backgroundColor = .clear
                }
            }
        }
        view.isUserInteractionEnabled = !classroomMode
        gameView.isMultipleTouchEnabled = true
        gameView.accessibilityIdentifier = "meadowMap"
        gameView.isAccessibilityElement = true
        gameView.accessibilityLabel = "林间地图，已选择 P1"
        gameView.accessibilityTraits = .allowsDirectInteraction
        scene.classroomAdvanceTravel=classroomAdvanceTravel
        scene.scaleMode = classroomMode ? .aspectFit:.resizeFill
        scene.size = view.bounds.size
        if !classroomMode { for button in [titleButton, playButton, resetButton, zoomButton] { view.addSubview(button) } }
        var labStyle = UIButton.Configuration.filled()
        labStyle.title = "光影试验"
        labStyle.baseBackgroundColor = UIColor(red: 0.97, green: 0.91, blue: 0.70, alpha: 0.96)
        labStyle.baseForegroundColor = UIColor(red: 0.25, green: 0.28, blue: 0.14, alpha: 1)
        shadowLabButton.configuration = labStyle
        shadowLabButton.accessibilityIdentifier = "openShadowLab"
        shadowLabButton.addTarget(self, action: #selector(openShadowLab), for: .touchUpInside)
        if !classroomMode {view.addSubview(shadowLabButton)}
        if previewMap == nil { configureCampSave() }
        configureGaitControls()
        configureBattlePreview()
        if let campaign {
            scene.campaign=campaign
            scene.onCampaignChanged={ [weak self] in DispatchQueue.main.async {self?.refreshCampaignStatus()} }
            scene.onCampaignError={ [weak self] text in DispatchQueue.main.async {self?.showCampaignMessage(text)} }
            scene.onCampaignNodeSelected={ [weak self] id in
                guard let self,let node=self.campaign?.engine.state.map.nodes.first(where:{$0.id==id}) else{return}
                guard node.kind == .combat || node.kind == .boss || node.kind == .reward else {
                    self.showCampaignMessage("请选择战斗、首领或补给建筑；再次点编辑按钮可取消。");return
                }
                self.cancelNodeSelection()
                self.editNodeContents(id)
            }
            scene.onCampaignEncounterSelected={ [weak self] id in self?.selectEncounterPreview(id) }
            scene.onCampaignInteractionRequested={ [weak self] id in
                guard let self else{return}
                if let campaign=self.campaign,(try? campaign.encounterPreview(node:id)) != nil{self.selectEncounterPreview(id)}
                else{self.showCampaignInteraction()}
            }
            configureCampaignControls()
        }
        var mapStyle=labStyle
        mapStyle.title=campaign != nil ? "保存并返回":previewMap == nil ? "随机地图" : "返回地图设置"
        randomMapButton.configuration=mapStyle
        randomMapButton.accessibilityIdentifier="openRandomMap"
        randomMapButton.addTarget(self,action:#selector(openMapSettings),for:.touchUpInside)
        randomMapButton.isEnabled=false
        if !classroomMode {view.addSubview(randomMapButton)}
        randomMapSummary.isHidden=previewMap == nil
        randomMapSummary.text=previewMap.map { "地点预览 · \($0.map.nodes.count)节点 · 战斗与奖励暂不结算" }
        randomMapSummary.textColor=UIColor(red:1,green:0.94,blue:0.75,alpha:1)
        randomMapSummary.backgroundColor=UIColor(red:0.09,green:0.16,blue:0.11,alpha:0.9)
        randomMapSummary.font = .boldSystemFont(ofSize:14)
        randomMapSummary.textAlignment = .center;randomMapSummary.numberOfLines=2
        if !classroomMode {view.addSubview(randomMapSummary)}
        if previewMap != nil {
            for control in [shadowLabButton,gaitTestButton,battlePreviewButton,p1AppearanceButton] { control.isHidden=true }
        }
        for label in [metricsLabel, discoveryLabel] {
            label.textColor = UIColor(red: 1, green: 0.94, blue: 0.75, alpha: 1)
            label.backgroundColor = UIColor(red: 0.17, green: 0.22, blue: 0.17, alpha: 0.82)
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            label.textAlignment = .center
            label.layer.cornerRadius = 6
            label.clipsToBounds = true
            label.isUserInteractionEnabled = false
            if !classroomMode {view.addSubview(label)}
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
            DispatchQueue.main.async {
                self?.playButton.isPlaying = playing
                self?.playButton.accessibilityLabel = playing ? "暂停行旅" : "开始行旅"
            }
        }
        scene.onSelectionChanged = { [weak self] name in
            DispatchQueue.main.async { self?.gameView.accessibilityLabel = "林间地图，已选择 \(name)";self?.refreshCampaignStatus() }
        }
        scene.onDiagnostics = { [weak self] text in
            guard let self else { return }
            let playing = self.scene.isRunning, zoom = self.scene.zoom
            DispatchQueue.main.async {
                guard !self.loadingFailed else { return }
                self.gameView.accessibilityValue = self.reviewMode ? text : (playing ? "旅人移动中" : "旅人暂停")
                self.zoomButton.accessibilityValue = "\(Int(round(zoom * 100)))%"
            }
        }
        scene.onMetrics = { [weak self] text in DispatchQueue.main.async { self?.metricsLabel.text = text } }
        scene.onDiscovery = { [weak self] text in
            DispatchQueue.main.async {
            guard let self else { return }
            self.discoveryLabel.text = text
            self.discoveryLabel.layer.removeAllAnimations()
            self.discoveryLabel.alpha = 1
            UIView.animate(withDuration: 0.6, delay: 2.2, options: [.beginFromCurrentState]) {
                self.discoveryLabel.alpha = 0
            }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-gaitReview") {
            let review = GaitReviewScene(size: view.bounds.size)
            review.onReviewAccessibilityValue = { [weak self] value in
                DispatchQueue.main.async { self?.gameView.accessibilityValue = value }
            }
            review.scaleMode = .resizeFill
            let reviewView = SKView(frame: gameView.bounds)
            reviewView.preferredFramesPerSecond = 60
            reviewView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            gameView.addSubview(reviewView); gaitView = reviewView
            reviewView.presentScene(review)
            mapPresented = true
            for button in [titleButton, playButton, resetButton, zoomButton] { button.isHidden = true }
            shadowLabButton.isHidden = true
            gaitTestButton.isHidden = true
        } else {
            loadingView.frame = view.bounds
            view.addSubview(loadingView)
            loadingView.onRetry = { [weak self] in
                guard let self else { return }
                if self.classroomMode {self.classroomReload?();return}
                if self.previewMap != nil { self.dismiss(animated:true);return }
                if !self.loadStarted { self.beginLoading() }
                else if !MeadowGPUDiagnostics.shared.requiresColdLaunch { self.view.window?.rootViewController = GameViewController() }
            }
            loadingView.onCopy = { UIPasteboard.general.string = MeadowGPUDiagnostics.shared.json }
            setMapEnabled(false)
        }
        titleButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(toggleMetrics(_:))))
        gameView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapMap(_:))))
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
        classroomOverlayDirty=true
        let mapFrame: CGRect
        if battlePreviewActive, let preview = battlePreviewView {
            preview.frame = view.bounds
            mapFrame = classroomMode ? preview.mapFrame.integral:preview.mapFrame
        } else {
            battlePreviewView?.frame = .zero
            mapFrame = view.bounds
        }
        let mapWidth = mapFrame.width
        gameView.frame = mapFrame
        groundView?.frame = mapFrame
        if classroomMode,let ground=groundView {
            ground.contentScaleFactor=1
            let pixels=CGSize(width:max(1,mapFrame.width.rounded(.up)),height:max(1,mapFrame.height.rounded(.up)))
            if ground.drawableSize != pixels {classroomMapFrame=nil;ground.drawableSize=pixels}
        }
        groundView?.layer.cornerRadius = battlePreviewActive ? 14 : 0
        groundView?.clipsToBounds = battlePreviewActive
        scene.resizeMapViewport(to: mapFrame.size, referenceSize: view.bounds.size)
        loadingView.frame = view.bounds
        let inset:UIEdgeInsets = classroomMode ? .zero:view.safeAreaInsets
        let top = max(inset.top, 6)
        let isPad = traitCollection.userInterfaceIdiom == .pad
        let button: CGFloat = isPad ? 44 : 34
        let spacing = button + 2
        titleButton.frame = CGRect(x: max(inset.left, 10) + 4, y: top, width: isPad ? 88 : 70, height: isPad ? 44 : 38)
        shadowLabButton.frame = CGRect(x: titleButton.frame.maxX + 8, y: top + 2, width: 96, height: button)
        gaitTestButton.frame = CGRect(x: (scene.gaitTest == nil ? shadowLabButton.frame.maxX : titleButton.frame.maxX) + 8,
                                      y: top + 2, width: 100, height: button)
        let battleX = battlePreviewActive ? titleButton.frame.maxX + 8 : gaitTestButton.frame.maxX + 8
        battlePreviewButton.frame = CGRect(x: battleX, y: top + 2, width: 104, height: button)
        p1AppearanceButton.frame = CGRect(x: battlePreviewButton.frame.maxX + 8, y: top + 2, width: 112, height: button)
        campaignTeam.frame=CGRect(x:titleButton.frame.maxX+8,y:top+2,width:128,height:button)
        campaignEnd.frame=CGRect(x:campaignTeam.frame.maxX+8,y:top+2,width:120,height:button)
        let panelWidth = min(960, max(1, mapWidth - 32))
        gaitPanel.frame = CGRect(x: (view.bounds.width - panelWidth) / 2,
                                 y: view.bounds.height - max(inset.bottom, 12) - 194, width: panelWidth, height: 194)
        let right = mapWidth - max(inset.right, 10) - 4
        zoomButton.frame = CGRect(x: right - button, y: top + 2, width: button, height: button)
        resetButton.frame = zoomButton.frame.offsetBy(dx: -spacing, dy: 0)
        playButton.frame = resetButton.frame.offsetBy(dx: -spacing, dy: 0)
        if scene.gaitTest == nil && p1AppearanceButton.frame.maxX > playButton.frame.minX - 8 {
            p1AppearanceButton.frame.origin = CGPoint(x: titleButton.frame.minX, y: top + button + 10)
        }
        metricsLabel.frame = CGRect(x: right - 225, y: view.bounds.height - max(inset.bottom, 10) - 50, width: 225, height: 48)
        discoveryLabel.frame = CGRect(x: view.bounds.midX - 110, y: view.bounds.height - max(inset.bottom, 10) - 44, width: 220, height: 34)
        randomMapButton.frame=CGRect(x:max(inset.left,10)+4,y:view.bounds.height-max(inset.bottom,10)-44,width:140,height:38)
        randomMapButton.isHidden=battlePreviewActive || scene.gaitTest != nil
        if campaign != nil {
            let footer=view.bounds.height-max(inset.bottom,10)-44
            let controlsX=max(inset.left,10)+4,controlsRight=view.bounds.width-max(inset.right,10)-8,gap:CGFloat=6
            let hudWidth=min(334,(controlsRight-controlsX)*0.42)
            campaignHUD.frame=CGRect(x:controlsRight-hudWidth,y:footer-52-CGFloat(56+40*(campaign?.playerIDs.count ?? 2)),width:hudWidth,height:CGFloat(56+40*(campaign?.playerIDs.count ?? 2)))
            campaignMovement.frame=CGRect(x:8,y:5,width:hudWidth-16,height:42)
            for i in 0..<7 {campaignHealth[i].isHidden=i >= (campaign?.playerIDs.count ?? 2);campaignHealth[i].frame=CGRect(x:8,y:CGFloat(i)*40+53,width:hudWidth-16,height:36);campaignAP[i].isHidden=true}
            let buttonWidth=max(1,(controlsRight-controlsX-gap*3)/4),buttonY=footer-46
            campaignRefill.frame=CGRect(x:controlsX,y:buttonY,width:buttonWidth,height:38)
            campaignItems.frame=CGRect(x:controlsX+buttonWidth+gap,y:buttonY,width:buttonWidth,height:38)
            campaignBattle.frame=CGRect(x:controlsX+(buttonWidth+gap)*2,y:buttonY,width:buttonWidth,height:38)
            campaignEdit.frame=CGRect(x:controlsX+(buttonWidth+gap)*3,y:buttonY,width:buttonWidth,height:38)
            let compact=view.bounds.height<430
            let routeTop=top+button+10,routeHeight:CGFloat=compact ? 78:56
            let leftWidth=min(430,max(180,campaignHUD.frame.minX-controlsX-8))
            campaignRoutePanel.frame=CGRect(x:controlsX,y:routeTop,width:compact ? leftWidth:controlsRight-controlsX,height:routeHeight)
            campaignRouteTitle.frame=CGRect(x:12,y:3,width:campaignRoutePanel.bounds.width-24,height:24)
            campaignRouteDetail.frame=CGRect(x:12,y:26,width:campaignRoutePanel.bounds.width-24,height:routeHeight-28)
            campaignRouteDetail.numberOfLines=compact ? 3:1
            campaignRoutePanel.isHidden=battlePreviewActive || (compact && !encounterPreview.isHidden)
            let previewTop=compact ? routeTop:campaignRoutePanel.frame.maxY+6
            encounterPreview.frame=CGRect(x:controlsX,y:previewTop,width:leftWidth,height:max(120,min(encounterPreview.preferredHeight,buttonY-previewTop-8)))
        }
        let summaryMaxX=campaign == nil ? view.bounds.width-max(inset.right,10)-8:campaignEdit.frame.minX-8
        randomMapSummary.frame=CGRect(x:randomMapButton.frame.maxX+8,y:randomMapButton.frame.minY,
            width:max(1,summaryMaxX-randomMapButton.frame.maxX-8),height:38)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !ProcessInfo.processInfo.arguments.contains("-gaitReview") { beginLoading() }
    }

    private func beginLoading() {
        guard !loadStarted else { return }
        if !checkedSavedReport {
            checkedSavedReport = true
            if MeadowGPUDiagnostics.shared.recordedBuild == Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
               let saved = MeadowGPUDiagnostics.shared.savedFailureOrInterruption {
                loadingView.showSavedReport(saved)
                return
            }
        }
        loadStarted = true
        guard groundView?.device != nil else { showLoadingFailure(ShadowLabError.setup("无法取得 Metal 设备")); return }
        MeadowGPUDiagnostics.shared.begin(device: groundView?.device, size: gameView.bounds.size, scale: gameView.contentScaleFactor)
        MeadowGPUDiagnostics.shared.beginStage("资源准备", kind: "CPU setup; not GPU fault attribution")
        loadingBegan = ProcessInfo.processInfo.systemUptime
        lastHeartbeat = loadingBegan
        longestHeartbeatGap = 0; loadingHeartbeats = 0
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.longestHeartbeatGap = max(self.longestHeartbeatGap, now - self.lastHeartbeat)
            if let waited = self.firstFrameWaitSeconds, UIApplication.shared.applicationState == .active {
                // Count active heartbeat time; app suspension must not consume
                // the first-frame timeout when the user returns to loading.
                let elapsed = waited + min(now - self.lastHeartbeat, 1)
                self.firstFrameWaitSeconds = elapsed
                if elapsed >= 20 {
                    self.failRendering(ShadowLabError.setup("首帧渲染等待超时，请重新加载"))
                }
            }
            self.lastHeartbeat = now; self.loadingHeartbeats += 1
        }
        MeadowLoader.load(device: groundView?.device, definition: previewMap.map { SceneDefinition.generated($0) }, diagnosticSize: gameView.bounds.size, progress: { [weak self] value, text in
            self?.reportLoadingProgress(value, text: text)
        }) { [weak self] result in
            guard let self, !self.loadingFailed else { return }
            switch result {
            case .success(let prepared):
                self.groundRenderer = prepared.renderer
                if self.classroomMode {
                    self.groundRenderer?.classroomMirrorEnabled=self.classroomMirrorEnabled
                    self.groundRenderer?.onClassroomMapFrame={ [weak self] image in self?.classroomMapFrame=image;self?.classroomMapSerial += 1;self?.classroomFrameAvailable?() }
                }
                self.scene.shadowMapSize = prepared.renderer?.shadowSize ?? 0
                self.groundRenderer?.alignmentReview = ProcessInfo.processInfo.arguments.contains("-alignmentReview")
                self.groundRenderer?.onFirstFrameCompleted = { [weak self] in
                    self?.groundBecameReady = true
                    self?.foregroundBecameReady = true // Same completed command includes the foreground.
                    self?.finishLoading()
                }
                self.groundRenderer?.onFrameFailed = { [weak self] error in self?.failRendering(error) }
                do {
                    MeadowGPUDiagnostics.shared.beginStage("B00 前景诊断目标准备", kind: "CPU SKRenderer setup; not GPU completion")
                    let probe = try MeadowGPUProbe(prepared: prepared, size: self.gameView.bounds.size,
                        scale: self.gameView.contentScaleFactor, progress: { [weak self] value, label in
                            self?.reportLoadingProgress(Float(0.84 + value * 0.12), text: label)
                        })
                    self.gpuProbe = probe
                    probe.start { [weak self] result in
                        guard let self else { return }
                        self.gpuProbe = nil
                        switch result {
                        case .success: self.prepareWorld(prepared)
                        case .failure(let error): self.showLoadingFailure(error)
                        }
                    }
                } catch {
                    self.showLoadingFailure(error)
                }
            case .failure(let error): self.showLoadingFailure(error)
            }
        }
    }

    private func prepareWorld(_ prepared: PreparedMeadow) {
        reportLoadingProgress(0.96, text: "布置场景")
        scene.size = gameView.bounds.size
        scene.prepare(prepared, progress: { [weak self] value in
            self?.reportLoadingProgress(Float(0.96 + value * 0.03), text: "布置场景")
        }) { [weak self] in
            guard let self, !self.loadingFailed else { return }
            self.reportLoadingProgress(0.99, text: "显示林地")
            // Only the actual map's first frame gets a timeout. Shader warmup
            // and world population may take longer on slower physical iPads.
            self.firstFrameWaitSeconds = 0
            self.mapPresentationBegan = ProcessInfo.processInfo.systemUptime
            guard let surface = self.groundView, let renderer = self.groundRenderer else {
                self.showLoadingFailure(ShadowLabError.setup("单视图地图渲染器缺失")); return
            }
            MeadowGPUDiagnostics.shared.beginStage("C02 实际单视图地图", kind: "one MTKView; native backdrop + SKRenderer in one submitted command buffer")
            do {
                if let session=self.campSession,let unit=session.loadout.units["p1"] {
                    try self.prepareCampVisuals(unit,appearance:session.appearanceID,retaining:false)
                    self.applyCampVisuals()
                }
                if let campaign=self.campaign,let unit=campaign.engine.state.units["p1"],let index=HeroFrames.appearanceIDs.firstIndex(of:campaign.snapshot.appearanceID) {
                    try self.groundRenderer?.prepareP1Equipment(appearance:index,weapon:unit.equipment.weapon,armor:unit.equipment.armor,retainingCurrent:false)
                    self.scene.selectP1Loadout(appearance:index,weapon:unit.equipment.weapon,armor:unit.equipment.armor)
                }
            } catch { self.showLoadingFailure(error);return }
            do{try self.prepareProfileVisuals()}catch{self.showLoadingFailure(error);return}
            self.scene.activateForMetalRenderer()
            self.mapPresented = true
            renderer.start(in: surface, scene: self.scene)
            self.setupTimings["presentMap"] = ProcessInfo.processInfo.systemUptime - self.mapPresentationBegan
        }
    }

    private func reportLoadingProgress(_ value: Float, text: String) {
        guard !ready, !loadingFailed else { return }
        loadingProgress = max(loadingProgress, min(1, value))
        loadingStage = text
        loadingView.update(value, text: text)
        if reviewMode { gameView.accessibilityValue = "{\"loadingProgress\":\(loadingProgress),\"phase\":\"\(text)\"}" }
    }

    private func finishLoading() {
        guard !ready, !loadingFailed, foregroundBecameReady, groundRenderer == nil || groundBecameReady else { return }
        ready = true
        classroomOverlayDirty=true
        firstFrameWaitSeconds = nil
        let now = ProcessInfo.processInfo.systemUptime
        loadingTimer?.invalidate(); loadingTimer = nil
        scene.startupMetrics = ["seconds": now - loadingBegan,
            "mainThreadLongestGap": max(longestHeartbeatGap, now - lastHeartbeat), "heartbeats": Double(loadingHeartbeats)]
            .merging(setupTimings, uniquingKeysWith: { _, new in new })
            .merging(scene.setupTimings, uniquingKeysWith: { _, new in new })
        scene.shadowReady = groundRenderer?.shadowsEnabled ?? false
        scene.shadowMapSize = groundRenderer?.shadowSize ?? 0
        scene.gpuFallbackCount = gpuFallbackCount
        scene.groundDrawableScale = Double(groundDrawableScale)
        scene.refreshDiagnostics()
        MeadowGPUDiagnostics.shared.mapReady()
        loadingView.update(1, text: "准备就绪")
        loadingView.isHidden = true
        setMapEnabled(true)
        if let campaign {
            refreshCampaignStatus()
            if campaign.isCompleted{showCampaignResults()}
        }
        if ProcessInfo.processInfo.arguments.contains("-gaitCapture") { startGaitCapture() }
    }

    /// CI records the real single-MTKView renderer, at normal and quarter speed.
    /// This deliberately uses the same scene and controls as manual inspection.
    private func startGaitCapture() {
        scene.toggleGaitTest()
        let slow = ProcessInfo.processInfo.arguments.contains("-slowGaitCapture")
        if slow { scene.toggleGaitSlow() }
        let order = GaitTest.menuOrder
        scene.setGaitDirection(order[0]); refreshGaitControls()
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? Data("ready".utf8).write(to: directory.appendingPathComponent("GaitCaptureReady.txt"), options: .atomic)
        var index = 0
        gaitCaptureTimer = Timer.scheduledTimer(withTimeInterval: slow ? 6 : 4, repeats: true) { [weak self] _ in
            index = (index + 1) % order.count
            self?.scene.setGaitDirection(order[index]); self?.refreshGaitControls()
        }
    }

    private func setMapEnabled(_ enabled: Bool) {
        gameView.isUserInteractionEnabled = enabled
        for button in [titleButton, playButton, resetButton, zoomButton] { button.isEnabled = enabled }
        shadowLabButton.isEnabled = enabled
        gaitTestButton.isEnabled = enabled
        battlePreviewButton.isEnabled = enabled
        p1AppearanceButton.isEnabled = enabled
        randomMapButton.isEnabled = enabled
        gaitPanel.isUserInteractionEnabled = enabled
    }

    private func failRendering(_ error: Error) { showLoadingFailure(error) }

    private func showLoadingFailure(_ error: Error) {
        guard !loadingFailed else { return }
        let diagnostic = MeadowGPUDiagnostics.shared.failed(error)
        if classroomMode {classroomStatus?(diagnostic.localizedDescription)}
        let first=classroomMode ? NSError(domain:"ClassroomRenderer",code:diagnostic.code,userInfo:[NSLocalizedDescriptionKey:"林地载入暂停，请教师在后台重试。"]):diagnostic
        loadingFailed = true; firstFrameWaitSeconds = nil
        loadingTimer?.invalidate(); loadingTimer = nil
        setRenderingPaused(true)
        setMapEnabled(false)
        loadingView.isHidden = false
        classroomOverlayDirty=true
        loadingView.failed(first, restartRequired: MeadowGPUDiagnostics.shared.requiresColdLaunch)
        if reviewMode, let data = try? JSONSerialization.data(withJSONObject: [
            "loadingError": error.localizedDescription, "loadingProgress": loadingProgress,
            "loadingStage": loadingStage,
            "foregroundReady": foregroundBecameReady, "groundReady": groundBecameReady,
            "shadowFrames": groundRenderer?.submittedFrames ?? 0,
            "gpuFallbackCount": gpuFallbackCount,
            "shadowMapSize": groundRenderer?.shadowSize ?? 0,
            "shadowsEnabled": groundRenderer?.shadowsEnabled ?? false,
            "groundDrawableScale": groundDrawableScale
        ]), let text = String(data: data, encoding: .utf8) { gameView.accessibilityValue = text }
    }

    @objc private func togglePlayback() {
        guard let campaign else{scene.togglePlayback();return}
        do {try campaign.setPaused(campaign.isMoving);refreshCampaignStatus()}
        catch {showCampaignMessage(error.localizedDescription)}
    }

    private func configureGaitControls() {
        var style = UIButton.Configuration.filled()
        style.baseBackgroundColor = UIColor(red: 0.97, green: 0.91, blue: 0.70, alpha: 0.96)
        style.baseForegroundColor = UIColor(red: 0.25, green: 0.28, blue: 0.14, alpha: 1)
        style.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4)
        gaitTestButton.configuration = style
        gaitTestButton.configuration?.title = "步态测试"
        gaitTestButton.accessibilityIdentifier = "openGaitTest"
        gaitTestButton.addAction(UIAction { [weak self] _ in
            self?.scene.toggleGaitTest(); self?.refreshGaitControls()
        }, for: .touchUpInside)
        if !classroomMode {view.addSubview(gaitTestButton)}
        p1AppearanceButton.configuration = style
        p1AppearanceButton.configuration?.title = "P1 衣装"
        p1AppearanceButton.accessibilityIdentifier = "p1Appearance"
        p1AppearanceButton.accessibilityValue = HeroFrames.appearanceTitles.first
        p1AppearanceButton.addAction(UIAction { [weak self] _ in self?.openInventory() },for:.touchUpInside)
        refreshEquipmentMenu()
        p1AppearanceButton.isHidden = HeroFrames.appearanceTitles.isEmpty
        if !classroomMode {view.addSubview(p1AppearanceButton)}
        gaitPanel.axis = .vertical; gaitPanel.spacing = 6
        gaitPanel.isLayoutMarginsRelativeArrangement = true
        gaitPanel.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        gaitPanel.backgroundColor = UIColor(red: 0.13, green: 0.18, blue: 0.14, alpha: 0.94)
        gaitPanel.layer.cornerRadius = 10
        gaitPanel.isHidden = true
        gaitStatusLabel.textColor = .white
        gaitStatusLabel.textAlignment = .center
        gaitStatusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        gaitPanel.addArrangedSubview(gaitStatusLabel)
        let directions = UIStackView(); directions.distribution = .fillEqually; directions.spacing = 4
        for facing in GaitTest.menuOrder {
            let button = UIButton(type: .system); button.configuration = style
            button.configuration?.title = GaitTest.names[facing]
            button.tag = facing
            button.accessibilityIdentifier = "gaitDirection\(facing)"
            button.addAction(UIAction { [weak self] _ in
                self?.scene.setGaitDirection(facing); self?.refreshGaitControls()
            }, for: .touchUpInside)
            directions.addArrangedSubview(button); gaitDirectionButtons.append(button)
        }
        directions.heightAnchor.constraint(equalToConstant: 44).isActive = true
        gaitPanel.addArrangedSubview(directions)
        let controls = UIStackView(); controls.distribution = .fillEqually; controls.spacing = 6
        let restart = UIButton(type: .system)
        for button in [gaitPauseButton, gaitSlowButton, gaitStepButton, restart] {
            button.configuration = style; controls.addArrangedSubview(button)
        }
        gaitStepButton.configuration?.title = "单步"
        gaitStepButton.accessibilityIdentifier = "gaitStep"
        gaitPauseButton.accessibilityIdentifier = "gaitPause"
        gaitSlowButton.accessibilityIdentifier = "gaitSlow"
        restart.configuration?.title = "重新走"
        gaitPauseButton.addAction(UIAction { [weak self] _ in self?.scene.toggleGaitPause(); self?.refreshGaitControls() }, for: .touchUpInside)
        gaitSlowButton.addAction(UIAction { [weak self] _ in self?.scene.toggleGaitSlow(); self?.refreshGaitControls() }, for: .touchUpInside)
        gaitStepButton.addAction(UIAction { [weak self] _ in self?.scene.stepGait(); self?.refreshGaitControls() }, for: .touchUpInside)
        restart.addAction(UIAction { [weak self] _ in self?.scene.reset(); self?.refreshGaitControls() }, for: .touchUpInside)
        controls.heightAnchor.constraint(equalToConstant: 42).isActive = true
        gaitPanel.addArrangedSubview(controls)
        gaitLayeredPreviewButton.configuration = style
        gaitLayeredPreviewButton.configuration?.title = "原图 / 分层蓝靴对照"
        gaitLayeredPreviewButton.accessibilityIdentifier = "gaitLayeredPreview"
        gaitLayeredPreviewButton.heightAnchor.constraint(equalToConstant: 38).isActive = true
        gaitLayeredPreviewButton.addAction(UIAction { [weak self] _ in
            self?.scene.toggleLayeredPreview(); self?.refreshGaitControls()
        }, for: .touchUpInside)
        if HeroFrames.layeredPrototypeAvailable {
            gaitPanel.addArrangedSubview(gaitLayeredPreviewButton)
        }
        if !classroomMode {view.addSubview(gaitPanel)}
    }

    private func configureCampSave() {
        let directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        let store=CampSaveStore(url:directory.appendingPathComponent("MeadowCamp/camp-v1.json"))
        do { campSession=try CampInventorySession(store:store,appearances:HeroFrames.appearanceIDs) }
        catch {
            inventoryStartupIssue="暂时无法保存营地配置，可导出当前配置留存。"
            campSession=try? CampInventorySession(store:nil,appearances:HeroFrames.appearanceIDs)
        }
    }
    private func refreshEquipmentMenu() {
        guard let unit=equipmentModel?.units["p1"],let catalog=equipmentModel?.engine.catalog else{return}
        p1AppearanceButton.configuration?.title="行囊装备"
        p1AppearanceButton.accessibilityLabel="打开P1行囊与装备"
        p1AppearanceButton.accessibilityValue=unit.equipment.itemIDs.compactMap { try? catalog.item($0).name }.joined(separator:"、")
    }
    private var profileVisualSignature=""
    private func prepareProfileVisuals()throws {
        guard let campaign else{return}
        // 像素人物：每位旅人的武器、护甲都画在身上，所以所有人的装备变化都要刷新
        let units=campaign.engine.state.players.filter{$0.id=="p1" || $0.appearance != nil || PixelHeroAtlas.enabled}
        let signature=units.map{u in "\(u.id)-\((u.appearance?.body ?? campaign.snapshot.appearanceID))-\(u.appearance?.outfit ?? "follow")-\(u.appearance?.hair ?? "original")-\(u.appearance?.face ?? "original")-\(u.equipment.weapon ?? "none")-\(u.equipment.armor ?? "none")"}.joined(separator:"|")
        guard signature != profileVisualSignature else{return}
        if PixelHeroAtlas.enabled {
            // 像素人物：新外观先在后台烘好（地图图集 + 战斗帧），这期间画面保持原样，烘好再回来刷新，不卡主线程
            var mapLooks:[PixelHeroLook]=[],battleLooks:[PixelHeroLook]=[]
            for u in campaign.engine.state.players {
                let slot=campaign.playerIDs.firstIndex(of:u.id) ?? 0
                battleLooks.append(PixelHeroLook.battle(unit:u,slot:slot))
                if u.id != "p1",u.appearance == nil {
                    if let look=HeroFrames.pixelLook(heroIndex:slot%3,weaponID:u.equipment.weapon,armorID:u.equipment.armor){mapLooks.append(look)}
                } else {
                    let a=u.appearance ?? PlayerAppearance(body:campaign.snapshot.appearanceID),index=HeroFrames.appearanceIDs.firstIndex(of:a.body) ?? 0
                    if let look=HeroFrames.pixelLook(heroIndex:0,appearanceIndex:index,weaponID:u.equipment.weapon,armorID:a.armor(worn:u.equipment.armor),hair:a.hair,face:a.face){mapLooks.append(look)}
                }
            }
            // 战斗帧只在后台备好，不用等
            PixelHeroAtlas.prepare(battle:battleLooks)
            if !mapLooks.allSatisfy(PixelHeroAtlas.isMapReady) {
                PixelHeroAtlas.prepare(map:mapLooks){[weak self] in
                    do{try self?.prepareProfileVisuals()}catch{self?.showCampaignMessage(error.localizedDescription)}
                }
                return
            }
        }
        var names=Set<String>()
        for u in units {
            if PixelHeroAtlas.enabled,u.id != "p1",u.appearance == nil {
                let slot=(campaign.playerIDs.firstIndex(of:u.id) ?? 0)%3
                for diagonal in [false,true]{names.insert(HeroFrames.atlasName(heroIndex:slot,diagonal:diagonal,weaponID:u.equipment.weapon,armorID:u.equipment.armor))}
                continue
            }
            let a=u.appearance ?? PlayerAppearance(body:campaign.snapshot.appearanceID),index=HeroFrames.appearanceIDs.firstIndex(of:a.body) ?? 0,armor=a.armor(worn:u.equipment.armor)
            try groundRenderer?.prepareP1Equipment(appearance:index,weapon:u.equipment.weapon,armor:armor,retainingCurrent:true,hair:a.hair,face:a.face)
            for diagonal in [false,true]{names.insert(HeroFrames.atlasName(heroIndex:0,diagonal:diagonal,appearanceIndex:index,weaponID:u.equipment.weapon,armorID:armor,hair:a.hair,face:a.face))}
            if u.id=="p1"{scene.selectP1Loadout(appearance:index,weapon:u.equipment.weapon,armor:armor)}
        }
        groundRenderer?.retainCampaignArmorAtlases(names)
        scene.refreshProfileFrames();profileVisualSignature=signature
    }
    private func prepareCampVisuals(_ unit:GameUnit,appearance:String,retaining:Bool) throws {
        guard let index=HeroFrames.appearanceIDs.firstIndex(of:appearance) else { throw GameError("衣装不受支持。") }
        try groundRenderer?.prepareP1Equipment(appearance:index,weapon:unit.equipment.weapon,armor:unit.equipment.armor,retainingCurrent:retaining)
    }
    private func applyCampVisuals() {
        guard let session=campSession,let unit=session.loadout.units["p1"],let index=HeroFrames.appearanceIDs.firstIndex(of:session.appearanceID) else{return}
        scene.selectP1Loadout(appearance:index,weapon:unit.equipment.weapon,armor:unit.equipment.armor)
        refreshEquipmentMenu()
    }
    private func openInventory() {
        guard ready,!battlePreviewActive,scene.gaitTest==nil,presentedViewController==nil,let session=campSession else{return}
        let wasRunning=scene.isRunning;if wasRunning { scene.togglePlayback() };groundView?.isPaused=true
        let screen=MeadowInventoryViewController(session:session);screen.startupIssue=inventoryStartupIssue
        screen.performEquip={ [weak self] slot,item in
            guard let self else{return}
            let candidate=try session.candidateEquipment(slot:slot,item:item)
            try self.prepareCampVisuals(candidate,appearance:session.appearanceID,retaining:true)
            do { try session.equip(slot:slot,item:item) }
            catch { if let old=session.loadout.units["p1"] { try? self.prepareCampVisuals(old,appearance:session.appearanceID,retaining:false) };throw error }
            self.applyCampVisuals();try? self.prepareCampVisuals(candidate,appearance:session.appearanceID,retaining:false)
        }
        screen.performAppearance={ [weak self] id in
            guard let self,let unit=session.loadout.units["p1"] else{return}
            try self.prepareCampVisuals(unit,appearance:id,retaining:true)
            do { try session.setAppearance(id) }
            catch { try? self.prepareCampVisuals(unit,appearance:session.appearanceID,retaining:false);throw error }
            self.applyCampVisuals();try? self.prepareCampVisuals(unit,appearance:id,retaining:false)
        }
        screen.performImport={ [weak self] data in
            guard let self else{return}
            let save=try session.inspectImport(data),candidate=save.archive.state.units["p1"]!
            try self.prepareCampVisuals(candidate,appearance:save.appearanceID,retaining:true)
            do { try session.importData(data) }
            catch { if let old=session.loadout.units["p1"] { try? self.prepareCampVisuals(old,appearance:session.appearanceID,retaining:false) };throw error }
            self.applyCampVisuals();try? self.prepareCampVisuals(candidate,appearance:session.appearanceID,retaining:false)
        }
        screen.onChange={ [weak self] in self?.refreshEquipmentMenu() }
        screen.onClose={ [weak self] in
            guard let self else{return};self.groundView?.isPaused = !self.mapPresented || self.loadingFailed
            if wasRunning && !self.scene.isRunning { self.scene.togglePlayback() }
        }
        present(screen,animated:true)
    }
    private func configureBattlePreview() {
        var style = UIButton.Configuration.filled()
        style.title = "林地战斗"
        style.baseBackgroundColor = UIColor(red: 0.97, green: 0.91, blue: 0.70, alpha: 0.96)
        style.baseForegroundColor = UIColor(red: 0.25, green: 0.28, blue: 0.14, alpha: 1)
        style.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        battlePreviewButton.configuration = style
        battlePreviewButton.accessibilityIdentifier = "openBattlePreview"
        battlePreviewButton.accessibilityLabel = "打开 Meadow Journey 可交互林地战斗"
        battlePreviewButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.setBattlePreviewActive(!self.battlePreviewActive)
        }, for: .touchUpInside)
        if !classroomMode {view.addSubview(battlePreviewButton)}

        let preview = MeadowBattlePreviewView(frame: .zero)
        preview.classroomMode=classroomMode
        preview.classroomModelFactory=classroomBattleModel
        preview.isHidden = true
        preview.onPartyActiveChanged={ [weak self] active in
            guard let self else { return };self.groundView?.isPaused = !self.mapPresented || self.loadingFailed
            self.view.setNeedsLayout()
        }
        preview.onClose = { [weak self] in self?.setBattlePreviewActive(false) }
        preview.onLayoutChanged = { [weak self] in
            guard let self else { return }
            self.view.setNeedsLayout(); self.view.layoutIfNeeded()
        }
        view.addSubview(preview)
        battlePreviewView = preview
    }

    private func setBattlePreviewActive(_ active: Bool) {
        classroomOverlayDirty=true
        guard active != battlePreviewActive else { return }
        guard scene.gaitTest == nil else { return }
        p1AppearanceButton.isHidden = active || HeroFrames.appearanceTitles.isEmpty
        if active { metricsHiddenBeforeBattlePreview = metricsLabel.isHidden }
        if active { scene.beginBattlePreviewCamera() }
        battlePreviewActive = active
        battlePreviewView?.isHidden = !active
        // The map is only a small drawer during battle: half its frame rate and no separate mirror readback there.
        groundView?.preferredFramesPerSecond = active && classroomMode ? 30:60
        groundRenderer?.classroomMirrorEnabled = classroomMirrorEnabled && !active
        if !active {classroomDeliveredMap = -1}
        if let campaign {
            guard !active || campaign.engine.state.battle != nil else{return}
            battlePreviewView?.configureCampaign(engine:campaign.engine,onCommit:{ [weak self] receipt in self?.scene.refreshCampaign();self?.trackBattleGains(receipt) })
        } else if active,let units=equipmentModel?.units { battlePreviewView?.configureEquipment(units) }
        battlePreviewView?.setActive(active)
        battlePreviewButton.isHidden = active
        shadowLabButton.isHidden = active
        gaitTestButton.isHidden = active
        for control in [titleButton, playButton, resetButton, zoomButton] { control.isHidden = active }
        metricsLabel.isHidden = active ? true : metricsHiddenBeforeBattlePreview
        discoveryLabel.isHidden = active
        if active { gameView.accessibilityLabel = "Meadow Journey 林间地图，显示在左侧；右侧为可交互林地战斗" }
        else { gameView.accessibilityLabel = "林间地图，已选择 P1" }
        if campaign != nil {refreshCampaignStatus(allowBattleOpen:false)}
        view.setNeedsLayout()
        view.layoutIfNeeded()
        if !active {
            scene.endBattlePreviewCamera()
            zoomButton.accessibilityValue = "\(Int(round(scene.zoom * 100)))%"
        }
    }

    private func refreshGaitControls() {
        let active = scene.gaitTest != nil
        gaitPanel.isHidden = !active
        gaitTestButton.configuration?.title = active ? "返回地图" : "步态测试"
        battlePreviewButton.isHidden = active || battlePreviewActive
        let mapControls: [UIView] = [shadowLabButton, playButton, resetButton, zoomButton]
        for control in mapControls { control.isHidden = active }
        if let test = scene.gaitTest {
            gaitStatusLabel.text = scene.layeredPreview
                ? "P1 原图 / 分层蓝靴 · 同步向下循环 · " + (test.slow ? "四分之一速度" : "正常速度")
                : "P1 / P2 / P3 · " + GaitTest.names[test.facing] + " · 直线循环（走完回起点） · " + (test.slow ? "四分之一速度" : "正常速度")
            gaitPauseButton.configuration?.title = test.paused ? "继续" : "暂停"
            gaitSlowButton.configuration?.title = test.slow ? "切回正常" : "切换慢速"
            for button in gaitDirectionButtons {
                button.configuration?.baseBackgroundColor = button.tag == test.facing
                    ? UIColor(red: 0.98, green: 0.72, blue: 0.24, alpha: 1)
                    : UIColor(red: 0.97, green: 0.91, blue: 0.70, alpha: 0.96)
            }
        }
        gaitLayeredPreviewButton.configuration?.title = scene.layeredPreview ? "退出分层对照" : "原图 / 分层蓝靴对照"
        for button in gaitDirectionButtons { button.isEnabled = !scene.layeredPreview }
        view.setNeedsLayout()
    }

    @objc private func openShadowLab() {
        let lab = ShadowLabViewController()
        lab.modalPresentationStyle = .fullScreen
        present(lab, animated: true)
    }

    @objc private func openMapSettings() {
        if campaign != nil {
            do {try saveCampaign();dismiss(animated:true)} catch {refreshCampaignStatus(allowBattleOpen:false);showCampaignMessage("保存失败，请稍后重试："+error.localizedDescription)}
            return
        }
        if previewMap != nil { dismiss(animated:true);return }
        let settings=MeadowMapSettingsViewController()
        settings.modalPresentationStyle = .fullScreen
        present(settings,animated:true)
    }

    private func configureCampaignControls() {
        MeadowPreviewPalette.stylePanel(campaignHUD);view.addSubview(campaignHUD)
        MeadowPreviewPalette.stylePanel(campaignRoutePanel);view.addSubview(campaignRoutePanel)
        campaignRoutePanel.isUserInteractionEnabled=false
        campaignRoutePanel.addSubview(campaignRouteTitle);campaignRoutePanel.addSubview(campaignRouteDetail)
        campaignRouteTitle.accessibilityIdentifier="campaignRouteDestination"
        campaignRouteDetail.accessibilityIdentifier="campaignRouteResources"
        for label in [campaignRouteTitle,campaignRouteDetail]{label.adjustsFontSizeToFitWidth=true;label.minimumScaleFactor=0.8}
        campaignHUD.addSubview(campaignMovement)
        for i in 0..<7 {campaignHUD.addSubview(campaignHealth[i]);campaignHUD.addSubview(campaignAP[i])}
        if !classroomMode {for b in [campaignRefill,campaignItems,campaignBattle,campaignEdit,campaignTeam,campaignEnd] {view.addSubview(b)}}
        view.addSubview(encounterPreview);encounterPreview.isHidden=true
        encounterPreview.onClose={ [weak self] in self?.selectEncounterPreview(nil) }
        encounterPreview.onInteract={ [weak self] in
            guard let self,let campaign=self.campaign,let id=self.previewEncounterNode,
                  let value=try? campaign.encounterPreview(node:id,actor:self.scene.selectedCampaignPlayerID),value.canInteract else{return}
            do{try campaign.interactCurrentNode(actor:self.scene.selectedCampaignPlayerID);self.scene.refreshCampaign();self.refreshCampaignStatus()}
            catch{self.showCampaignMessage(error.localizedDescription)}
        }
        campaignEnd.addAction(UIAction{[weak self] _ in self?.showCampaignEnd()},for:.touchUpInside)
        campaignTeam.addAction(UIAction{[weak self] _ in self?.showCampaignTeam()},for:.touchUpInside)
        campaignEdit.accessibilityIdentifier="campaignNodeEditor"
        campaignEdit.accessibilityLabel="编辑行程节点的遭遇怪物或补给奖励"
        campaignRefill.addAction(UIAction{[weak self] _ in self?.refillCampaign()},for:.touchUpInside)
        campaignBattle.addAction(UIAction{[weak self] _ in self?.showCampaignInteraction()},for:.touchUpInside)
        campaignEdit.addAction(UIAction{[weak self] _ in self?.showEditableNodes()},for:.touchUpInside)
        campaignItems.accessibilityIdentifier="openCampaignInventory"
        campaignItems.addAction(UIAction{[weak self] _ in self?.openCampaignInventory()},for:.touchUpInside)
        NotificationCenter.default.addObserver(self,selector:#selector(backgroundCampaign),name:UIApplication.willResignActiveNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(foregroundCampaign),name:UIApplication.didBecomeActiveNotification,object:nil)
    }
    /// The "you received" card for whatever the heroes gained since `before` (nothing gained: no card).
    private func showGains(title:String,subtitle:String?,since before:GameState,emptyText:String?=nil) {
        guard let campaign else{return}
        MeadowGainPopup.present(in:view,title:title,subtitle:subtitle,gains:MeadowGain.between(before,campaign.engine.state),catalog:campaign.engine.catalog,emptyText:emptyText){[weak self] in self?.classroomOverlayDirty=true}
    }
    /// Remembers the state a battle started from; when the battle ends, everything won in it is shown on one card.
    private func trackBattleGains(_ receipt:OperationReceipt) {
        if battleGainBase==nil,receipt.before.battle != nil{battleGainBase=receipt.before}
        guard receipt.after.battle==nil,let base=battleGainBase ?? (receipt.before.battle != nil ? receipt.before:nil) else{return}
        battleGainBase=nil
        let won=receipt.after.players.contains(where:\.isAlive)
        // After the last blow and its death effect have played.
        DispatchQueue.main.asyncAfter(deadline:.now()+1.6){[weak self] in
            self?.showGains(title:won ? "战斗胜利":"小队倒地",subtitle:won ? "战利品已放入各自行囊":nil,since:base,emptyText:won ? "这场战斗没有掉落物品。":"全员倒地，行程结束。")
        }
    }
    private func showCampaignMessage(_ text:String) {
        if classroomMode {classroomStatus?(text);return}
        discoveryLabel.text=text;discoveryLabel.alpha=1
        discoveryLabel.layer.removeAllAnimations()
        UIView.animate(withDuration:0.5,delay:4,options:[.beginFromCurrentState]){[weak self] in self?.discoveryLabel.alpha=0}
    }
    private func saveCampaign()throws {
        guard let campaign else{return}
        try campaign.suspendAndCheckpoint(camera:scene.campaignCamera)
        cancelNodeSelection()
        selectEncounterPreview(nil)
        battlePreviewView?.setActive(false)
    }
    @objc private func backgroundCampaign() {guard ready,campaign != nil else{return};do{try saveCampaign()}catch{campaign?.pauseAfterFailure();showCampaignMessage("保存失败："+error.localizedDescription)}}
    @objc private func foregroundCampaign() {guard ready,campaign != nil,!classroomSuspended else{return};if battlePreviewActive{battlePreviewView?.setActive(true)};refreshCampaignStatus(allowBattleOpen:false)}
    private func refillCampaign() {
        guard let campaign,!campaign.isMoving,campaign.engine.state.battle==nil else{return}
        let cost=campaign.movementRefillCost,affordable=campaign.movementPurchaseCoins
        let menu=UIAlertController(title:"补充移动条",message:"剩余 \(Int(campaign.movementRemaining))/\(Int(campaign.movementCapacity)) 距离\n每50距离1金币，补满需要 \(cost) 金币。\n全队持有 \(campaign.partyCoins) 金币，可购买 \(Int(ceil(campaign.movementPurchaseDistance))) 距离。",preferredStyle:.actionSheet)
        func fill(_ coins:Bool) {
            do{try campaign.refillMovement(usingCoins:coins);refreshCampaignStatus();showCampaignMessage(campaign.hasPendingTravel ? "移动已补充，点击播放继续行走":"移动已补充，请点击新的道路目的地")}
            catch{showCampaignMessage(error.localizedDescription)}
        }
        let buyTitle=affordable>0 ? "花费 \(affordable) 金币"+(affordable==cost ? "补满":"补充部分移动"):"金币不足，暂不能购买"
        let buy=UIAlertAction(title:buyTitle,style:.default){_ in fill(true)};buy.isEnabled=affordable>0
        menu.addAction(buy);menu.addAction(UIAlertAction(title:"手动补满",style:.default){_ in fill(false)})
        menu.addAction(UIAlertAction(title:"取消",style:.cancel));menu.popoverPresentationController?.sourceView=campaignRefill;menu.popoverPresentationController?.sourceRect=campaignRefill.bounds
        present(menu,animated:true)
    }
    private func showCampaignInteraction() {
        guard let campaign else{return}
        if campaign.engine.state.battle != nil{setBattlePreviewActive(true);return}
        let actor=scene.selectedCampaignPlayerID
        guard campaign.travel==nil,let unit=campaign.engine.state.units[actor],let node=campaign.engine.state.map.nodes.first(where:{$0.id==unit.nodeID}) else{showCampaignMessage("请先抵达地点。");return}
        if campaign.siteAvailable(actor:actor){showCampaignSite(actor:actor,node:node);return}
        let combat=node.kind == .combat || node.kind == .boss
        guard (node.kind == .reward && !node.rewardCompleted) || (combat && campaign.engine.state.units.values.contains{$0.kind == .monster && $0.nodeID==node.id && $0.isAlive}) else{showCampaignMessage("此地点没有待处理事件，可继续前进。");return}
        let supplies=(try? campaign.rewardSummary(node:node.id)) ?? "领取此处补给。"
        let message=combat ? "主动进入此处战斗。人物各自按基础行动值开场；移动条独立保留。":supplies+"\n领取后不会重复发放。"
        let alert=UIAlertController(title:node.name,message:message,preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"暂不交互",style:.cancel))
        alert.addAction(UIAlertAction(title:combat ? "开始战斗":"领取补给",style:.default){[weak self] _ in
            do{let before=campaign.engine.state;try campaign.interactCurrentNode(actor:actor);self?.scene.refreshCampaign();self?.refreshCampaignStatus()
                if !combat{self?.showGains(title:"获得补给",subtitle:node.name,since:before)}}
            catch{self?.showCampaignMessage(error.localizedDescription)}
        })
        present(alert,animated:true)
    }
    private func presentSiteScreen(_ screen:UIAlertController) {
        if let old=presentedViewController as? UIAlertController {
            old.dismiss(animated:true){[weak self] in self?.present(screen,animated:true)}
        }else if presentedViewController==nil {present(screen,animated:true)}
    }
    private func showCampaignSite(actor:String,node:MapNode) {
        guard let campaign,let kind=campaign.siteKind(node:node.id),let unit=campaign.engine.state.units[actor] else{return}
        if kind == .shop {
            // The shop screen: item cards with pictures and prices, buyer switch, buy / sell one at a time.
            let shop=MeadowShopViewController(session:campaign,node:node.id,actor:actor)
            shop.onTrade={[weak self] _ in self?.scene.refreshCampaign();self?.refreshCampaignStatus()}
            if let old=presentedViewController as? UIAlertController {old.dismiss(animated:true){[weak self] in self?.present(shop,animated:true)}}
            else {present(shop,animated:true)}
        }else {
            let title=kind == .satchel ? "路边失物":"林间清泉"
            let config=CampaignSiteRules.configuration(node:node,seed:campaign.engine.state.map.seed)!
            let message=kind == .satchel ? "\(unit.name) 拾取\(config.gold)金币。":"\(unit.name) 恢复最多\(config.healing)生命，不超过个人上限；满血时可换成员再来。"
            let alert=UIAlertController(title:title,message:message+"\n此地点全队仅处理一次。暂不处理可稍后回来；明确离开则结束事件。",preferredStyle:.alert)
            alert.addAction(UIAlertAction(title:"暂不处理",style:.cancel))
            for player in campaign.engine.state.players where player.isAlive && player.nodeID==node.id && player.id != actor {
                alert.addAction(UIAlertAction(title:"改由 "+player.name+" 处理",style:.default){[weak self] _ in self?.showCampaignSite(actor:player.id,node:node)})
            }
            for (label,accept) in [("接受",true),("明确离开（结束事件）",false)] {
                let id=UUID().uuidString
                let action=UIAlertAction(title:label,style:accept ? .default:.destructive){[weak self] _ in
                    do{let before=campaign.engine.state;try campaign.resolveSite(actor:actor,accept:accept,id:id);self?.scene.refreshCampaign();self?.refreshCampaignStatus();self?.showCampaignMessage("事件已保存。")
                        self?.showGains(title:title,subtitle:nil,since:before)}
                    catch{self?.showCampaignMessage("事件未保存，可重试："+error.localizedDescription)}
                }
                let maximum=(try? GameRules.attributes(unit,catalog:campaign.engine.catalog).maximumHealth) ?? unit.baseAttributes.maximumHealth
                action.isEnabled = !accept || kind != .spring || unit.health<maximum
                alert.addAction(action)
            }
            presentSiteScreen(alert)
        }
    }
    private func confirmSiteTrade(actor:String,item:ItemDefinition,buy:Bool) {
        guard let campaign else{return}
        guard let u=campaign.engine.state.units[actor],let node=campaign.engine.state.map.nodes.first(where:{$0.id==u.nodeID}),let price=try? CampaignSiteRules.price(item:item,buy:buy,node:node,seed:campaign.engine.state.map.seed) else{return}
        let id=UUID().uuidString
        let alert=UIAlertController(title:(buy ? "购买":"出售")+item.name,message:"\(campaign.engine.state.units[actor]?.name ?? actor) · \(buy ? "支付":"获得") \(price) 个人金币 · 1件\n只变更此成员的金币和行囊，取消不交易。",preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"取消",style:.cancel))
        alert.addAction(UIAlertAction(title:"确认交易",style:.default){[weak self] _ in
            do{let before=campaign.engine.state;try campaign.tradeAtSite(actor:actor,item:item.id,buy:buy,id:id);self?.scene.refreshCampaign();self?.refreshCampaignStatus();self?.showCampaignMessage("交易已保存。")
                self?.showGains(title:buy ? "已放入行囊":"出售所得",subtitle:buy ? "花费 \(price) 金币":item.name,since:before)}
            catch{self?.showCampaignMessage("交易未保存，可重试："+error.localizedDescription)}
        });presentSiteScreen(alert)
    }
    private func cancelNodeSelection() {
        scene.selectingCampaignNode=false
        campaignEdit.configuration?.title="编辑地点"
        refreshCampaignStatus(allowBattleOpen:false)
    }
    private func showEditableNodes() {
        guard let campaign else{return}
        if scene.selectingCampaignNode {cancelNodeSelection();showCampaignMessage("已取消编辑选点");return}
        guard campaign.travel==nil,campaign.engine.state.battle==nil else{showCampaignMessage("请先完成移动并结束战斗。");return}
        selectEncounterPreview(nil)
        scene.selectingCampaignNode=true
        campaignEdit.configuration?.title="取消选点"
        refreshCampaignStatus(allowBattleOpen:false)
        showCampaignMessage("点击地图上的建筑，编辑遭遇、补给或商店/事件参数")
    }
    private func editNodeContents(_ id:Int) {
        guard let campaign,let node=campaign.engine.state.map.nodes.first(where:{$0.id==id}) else{return}
        switch node.kind {
        case .combat,.boss:chooseEncounter(node:id)
        case .reward:chooseRewardAction(node:node)
        case .start,.empty:chooseSiteConfiguration(node:node)
        }
    }
    private func chooseSiteConfiguration(node:MapNode) {
        guard let campaign else{return}
        guard node.siteResolved != true else {
            let c=CampaignSiteRules.configuration(node:node,seed:campaign.engine.state.map.seed)!
            let alert=UIAlertController(title:"已处理事件 · 只读",message:"买价\(c.buyPercent)% · 卖价\(c.sellPercent)%\n失物\(c.gold)金币 · 清泉回复\(c.healing)\n不能重置或再次发奖。",preferredStyle:.alert)
            alert.addAction(UIAlertAction(title:"关闭",style:.cancel));presentSiteScreen(alert);return
        }
        let menu=UIAlertController(title:"编辑地点服务 · #\(node.id)",message:"只改本地点；不移动建筑，不改变金币、生命或库存。已处理事件不能编辑。营地保留商店。",preferredStyle:.actionSheet)
        for (kind,name) in [(CampaignSiteKind.shop,"商店"),(.satchel,"失物"),(.spring,"清泉")] where node.kind != .start || kind == .shop {
            menu.addAction(UIAlertAction(title:name,style:.default){[weak self] _ in
                var c=CampaignSiteRules.configuration(node:node,seed:campaign.engine.state.map.seed) ?? .init(kind:kind);c.kind=kind
                self?.editSiteConfiguration(node:node.id,draft:c)
            })
        }
        menu.addAction(UIAlertAction(title:"取消",style:.cancel));menu.popoverPresentationController?.sourceView=campaignEdit;menu.popoverPresentationController?.sourceRect=campaignEdit.bounds;presentSiteScreen(menu)
    }
    private func editSiteConfiguration(node:Int,draft:CampaignSiteConfiguration) {
        let title:[CampaignSiteKind:String]=[.shop:"商店",.satchel:"失物",.spring:"清泉"]
        let alert=UIAlertController(title:"\(title[draft.kind]!)参数 · #\(node)",message:"依次为买价%、卖价%、失物金币、清泉恢复。100%=原目录价格。比例10—500%，金币1—1000、恢复1—100。未启用类型的参数暂存；卖价不得高于买价。保存不重置事件、不发奖。",preferredStyle:.alert)
        for (name,value) in zip(["买价比例 %","卖价比例 %","失物金币","清泉恢复"],[draft.buyPercent,draft.sellPercent,draft.gold,draft.healing]) {
            alert.addTextField{f in f.placeholder=name;f.accessibilityLabel=name;f.text=String(value);f.keyboardType = .numberPad;f.borderStyle = .roundedRect
                let label=UILabel(frame:CGRect(x:0,y:0,width:108,height:30));label.text=" "+name;label.font = .boldSystemFont(ofSize:16);label.textColor = .label
                f.leftView=label;f.leftViewMode = .always}
        }
        alert.addAction(UIAlertAction(title:"取消",style:.cancel))
        alert.addAction(UIAlertAction(title:"保存本地点",style:.default){[weak self,weak alert] _ in
            guard let fields=alert?.textFields else{return}
            let values=fields.map{Int($0.text ?? "") ?? -1}
            guard values.count==4 else{return}
            let c=CampaignSiteConfiguration(kind:draft.kind,buyPercent:values[0],sellPercent:values[1],gold:values[2],healing:values[3])
            self?.saveSiteConfiguration(node:node,draft:c)
        });presentSiteScreen(alert)
    }
    private func saveSiteConfiguration(node:Int,draft:CampaignSiteConfiguration) {
        guard let campaign else{return}
        do {
            try campaign.configureSite(node:node,configuration:draft)
            scene.refreshCampaign();refreshCampaignStatus(allowBattleOpen:false);showCampaignMessage("地点参数已保存；原资源和处理状态保留。")
        }catch {
            let alert=UIAlertController(title:"参数未保存",message:error.localizedDescription,preferredStyle:.alert)
            alert.addAction(UIAlertAction(title:"返回编辑",style:.default){[weak self] _ in self?.editSiteConfiguration(node:node,draft:draft)})
            alert.addAction(UIAlertAction(title:"重试保存",style:.default){[weak self] _ in self?.saveSiteConfiguration(node:node,draft:draft)})
            alert.addAction(UIAlertAction(title:"取消",style:.cancel));presentSiteScreen(alert)
        }
    }
    private func chooseRewardAction(node:MapNode) {
        let menu=UIAlertController(title:node.name,message:node.rewardCompleted ? "已领取的地点不会因修改内容再次发奖。":"修改奖励内容，或明确重置一次性领取状态。",preferredStyle:.actionSheet)
        menu.addAction(UIAlertAction(title:"编辑金币、积分与药水",style:.default){[weak self] _ in self?.editReward(node:node)})
        if node.rewardCompleted {
            menu.addAction(UIAlertAction(title:"重置已领取状态",style:.destructive){[weak self] _ in
                let confirm=UIAlertController(title:"重新开放补给？",message:"明确重置后，小队再次抵达此处时可领取当前奖励一次。",preferredStyle:.alert)
                confirm.addAction(UIAlertAction(title:"取消",style:.cancel))
                confirm.addAction(UIAlertAction(title:"重置状态",style:.destructive){_ in
                    guard let campaign=self?.campaign else{return}
                    do{_=try campaign.resetReward(node:node.id);self?.scene.refreshCampaign();self?.refreshCampaignStatus();self?.showCampaignMessage("已记录重置；再次抵达时可领取一次。")}
                    catch{self?.showCampaignMessage(error.localizedDescription)}
                })
                self?.present(confirm,animated:true)
            })
        }
        menu.addAction(UIAlertAction(title:"取消",style:.cancel))
        menu.popoverPresentationController?.sourceView=campaignEdit
        menu.popoverPresentationController?.sourceRect=campaignEdit.bounds
        present(menu,animated:true)
    }
    private func chooseEncounter(node:Int) {
        guard let campaign else{return}
        do {
            guard let mapNode=campaign.engine.state.map.nodes.first(where:{$0.id==node}) else{return}
            let templates=campaign.engine.state.units.values.filter{$0.kind == .monster && $0.nodeID==node}.sorted{$0.id<$1.id}.map(\.templateID)
            let draft=try MeadowEncounterEditDraft(node:mapNode,templates:templates,catalog:campaign.engine.catalog)
            let editor=MeadowEncounterEditorViewController(draft:draft,title:mapNode.name)
            editor.onSave={ [weak self] templates in
                _=try campaign.configureEncounter(node:node,templates:templates)
                self?.scene.refreshCampaign();self?.refreshCampaignStatus();self?.showCampaignMessage("地点 \(node) 的遭遇已更新并保存。")
            }
            present(editor,animated:true)
        }catch{showCampaignMessage(error.localizedDescription)}
    }
    private func editReward(node:MapNode) {
        guard let campaign else{return}
        let reward=node.reward ?? NodeReward()
        let alert=UIAlertController(title:"编辑补给内容",message:node.rewardCompleted ? "此地点已领取。修改内容会保留已领取状态，不会再次发奖。":"设置每位领取者获得的金币、积分和物品数量。",preferredStyle:.alert)
        let values=[String(reward.coins),String(reward.score),String(reward.items["smallPotion"] ?? 0),String(reward.items["largePotion"] ?? 0),String(reward.items["shieldPotion"] ?? 0),String(reward.items["revivalStone"] ?? 0)]
        let labels=["每人金币","每人积分","小型药水","大型药水","护盾药水","复活石"]
        for (i,label) in labels.enumerated() {
            alert.addTextField { field in
                field.placeholder=label;field.text=values[i];field.keyboardType = .numberPad;field.accessibilityLabel=label
                let name=UILabel(frame:CGRect(x:0,y:0,width:84,height:30));name.text="  "+label;name.font = .boldSystemFont(ofSize:14);name.textColor = .label
                field.leftView=name;field.leftViewMode = .always;field.textAlignment = .right
            }
        }
        alert.addAction(UIAlertAction(title:"取消",style:.cancel))
        alert.addAction(UIAlertAction(title:"保存内容",style:.default){[weak self,weak alert] _ in
            guard let fields=alert?.textFields,fields.count==6 else{return}
            let parsed=fields.compactMap{Int($0.text ?? "")}
            guard parsed.count==6,parsed.allSatisfy({$0>=0}),parsed[0]<=100_000,parsed[1]<=100_000,parsed.dropFirst(2).allSatisfy({$0<=1000}) else {
                self?.showCampaignMessage("请输入非负整数；物品最多1000，金币和积分最多100000。");return
            }
            let v=parsed;var items=reward.items
            for (key,count) in [("smallPotion",v[2]),("largePotion",v[3]),("shieldPotion",v[4]),("revivalStone",v[5])] {
                if count>0{items[key]=count}else{items.removeValue(forKey:key)}
            }
            do {
                _=try campaign.configureReward(node:node.id,reward:NodeReward(coins:v[0],score:v[1],items:items))
                self?.scene.refreshCampaign();self?.refreshCampaignStatus();self?.showCampaignMessage(node.rewardCompleted ? "补给内容已更新；已领取状态保留。":"补给内容已更新并保存。")
            } catch {self?.showCampaignMessage(error.localizedDescription)}
        })
        present(alert,animated:true)
    }

    private func selectEncounterPreview(_ id:Int?) {
        classroomOverlayDirty=true
        previewEncounterNode=id;refreshEncounterPreview();view.setNeedsLayout()
    }
    private func refreshEncounterPreview(){
        let wasHidden=encounterPreview.isHidden
        defer{
            campaignRoutePanel.isHidden=battlePreviewActive || (view.bounds.height<430 && !encounterPreview.isHidden)
            if wasHidden != encounterPreview.isHidden{view.setNeedsLayout()}
        }
        guard let campaign,let id=previewEncounterNode,!battlePreviewActive,campaign.engine.state.battle==nil,!scene.selectingCampaignNode,
              let value=try? campaign.encounterPreview(node:id,actor:scene.selectedCampaignPlayerID) else{encounterPreview.isHidden=true;return}
        encounterPreview.show(value,completed:campaign.isCompleted);encounterPreview.classroomReadOnly=classroomMode;encounterPreview.isHidden=false
    }
private func refreshCampaignStatus(allowBattleOpen:Bool=true) {
        classroomOverlayDirty=true
        guard let campaign else{return}
        do{try prepareProfileVisuals()}catch{showCampaignMessage(error.localizedDescription)}
        for control in [shadowLabButton,gaitTestButton,battlePreviewButton,p1AppearanceButton] {control.isHidden=true}
        let state=campaign.engine.state,players=state.players
        randomMapSummary.text="已探索 \(state.map.revealed.count)/\(state.map.nodes.count) · 金币 \(players.reduce(0){$0+$1.coins}) · 积分 \(players.reduce(0){$0+$1.score})"+(campaign.cleared ? " · 敌人已清理":"")
        if scene.selectingCampaignNode {randomMapSummary.text="编辑选点中 · 点击建筑 · 再次点按钮取消"}
        let busy=campaign.travel != nil || state.battle != nil || campaign.isCompleted
        campaignRefill.isEnabled = !campaign.isCompleted && !campaign.isMoving && state.battle==nil && campaign.movementRefillCost>0
        campaignItems.isEnabled = !busy;campaignEdit.isEnabled = !busy
        let actor=scene.selectedCampaignPlayerID,node=state.map.nodes.first{$0.id==state.units[actor]?.nodeID}
        let eventAvailable=campaign.siteAvailable(actor:actor) || (node.map{n in n.kind == .reward ? !n.rewardCompleted:((n.kind == .combat || n.kind == .boss) && state.units.values.contains{$0.kind == .monster && $0.nodeID==n.id && $0.isAlive})} ?? false)
        campaignBattle.configuration?.title=state.battle != nil ? "继续战斗":(eventAvailable ? (campaign.siteAvailable(actor:actor) ? (campaign.siteKind(node:node!.id) == .shop ? "进入商店":"处理事件"):"交互地点"):"暂无事件")
        campaignBattle.isHidden=battlePreviewActive;campaignBattle.isEnabled = !campaign.isCompleted && (state.battle != nil || (!busy && eventAvailable))
        campaignMovement.show("地图移动",value:Int(ceil(campaign.movementRemaining)),maximum:max(1,Int(ceil(campaign.movementCapacity))),color:.systemYellow)
        for view in [campaignHUD,campaignRoutePanel,campaignRefill,campaignItems,campaignEdit,campaignTeam,campaignEnd,randomMapSummary] {view.isHidden=battlePreviewActive}
        if let route=campaign.routeReadout {
            campaignRouteTitle.text=route.title;campaignRouteDetail.text=route.detail
            campaignRouteDetail.textColor=route.additionalCoins>0 ? MeadowPreviewPalette.gold:MeadowPreviewPalette.ink
        }else{
            campaignRouteTitle.text=campaign.isCompleted ? "行程已结算":campaign.completionProgress
            let supplies=state.map.nodes.filter{$0.kind == .reward && !$0.rewardCompleted}.count
            campaignRouteDetail.text=campaign.isCompleted ? "可查看结算，或返回设置开始新行程":"剩余补给 \(supplies)处 · 全队金币 \(campaign.partyCoins) · 抵达后由教师选择交互"
            campaignRouteDetail.textColor=MeadowPreviewPalette.ink
        }
        playButton.isHidden=battlePreviewActive || !campaign.hasPendingTravel;resetButton.isHidden=true
        playButton.isPlaying=campaign.isMoving
        for i in players.indices {
            let u=players[i],stats=(try? GameRules.attributes(u,catalog:campaign.engine.catalog)) ?? u.baseAttributes
            campaignHealth[i].show((u.host && u.shortName==u.id.uppercased() ? "师":u.shortName)+" · "+(state.teams.first{$0.id==u.teamID}?.name ?? "未分队")+" · 上限 \(stats.maximumAP)",value:u.health,maximum:stats.maximumHealth,color:.systemGreen)
            campaignAP[i].show(value:u.ap,maximum:max(u.ap,stats.baseAP))
        }
        campaignEnd.configuration?.title=campaign.isCompleted ? "查看结算":"路线与目标"
        if campaign.isCompleted{randomMapSummary.text="行程已结算 · 可查看结果或返回设置"}
        refreshEncounterPreview()
        if ready,allowBattleOpen,state.battle != nil,players.contains(where: \.isAlive),!battlePreviewActive {setBattlePreviewActive(true)}
    }
    private func showCampaignEnd(){
        guard let campaign else{return}
        if campaign.isCompleted{showCampaignResults();return}
        let menu=UIAlertController(title:"路线与目标",message:campaign.closingReadout+"\n\n"+campaign.resourceGuidance+"\n\n路线按当前真实位置计算，不预支途中补给。地点事件由你主动触发。",preferredStyle:.actionSheet)
        for option in campaign.routeOptions(actor:scene.selectedCampaignPlayerID) {
            let prefix=option.kind=="supply" ? "最近补给 · ":option.kind=="encounter" ? "最近待战 · ":"返回"
            menu.addAction(UIAlertAction(title:prefix+option.title,style:.default){[weak self] _ in
                guard let self else{return}
                if campaign.movementRemaining<=0.000001{self.refillCampaign();return}
                self.cancelNodeSelection()
                self.scene.travelCampaign(to:option.nodeID)
            })
        }
        if campaign.movementRefillCost>0 && !campaign.isMoving && campaign.engine.state.battle==nil {
            menu.addAction(UIAlertAction(title:"购买移动 / 手动补满",style:.default){[weak self] _ in self?.refillCampaign()})
        }
        if campaign.canComplete || campaign.canCompleteDefeat {
            menu.addAction(UIAlertAction(title:"结束并结算",style:.default){[weak self] _ in self?.confirmCampaignEnd()})
        }
        menu.addAction(UIAlertAction(title:"关闭",style:.cancel))
        menu.popoverPresentationController?.sourceView=campaignEnd;menu.popoverPresentationController?.sourceRect=campaignEnd.bounds
        present(menu,animated:true)
    }
    private func confirmCampaignEnd(){
        guard let campaign else{return}
        guard campaign.canComplete || campaign.canCompleteDefeat else{
            let alert=UIAlertController(title:"行程目标",message:campaign.closingReadout,preferredStyle:.alert);alert.addAction(UIAlertAction(title:"继续行程",style:.default));present(alert,animated:true);return
        }
        let alert=UIAlertController(title:campaign.canCompleteDefeat ? "结束本次行程？":"完成行程并结算？",message:campaign.closingReadout,preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"取消",style:.cancel));alert.addAction(UIAlertAction(title:"结束并保存",style:.default){[weak self] _ in
            guard let self else{return}
            do{try campaign.completeCampaign(camera:self.scene.campaignCamera);self.cancelNodeSelection();self.refreshCampaignStatus(allowBattleOpen:false);self.showCampaignResults()}
            catch{self.showCampaignMessage("结算未保存："+error.localizedDescription)}
        });present(alert,animated:true)
    }
    private func showCampaignResults(){
        guard let campaign,let result=campaign.completion else{return}
        if let alert=presentedViewController as? UIAlertController{alert.dismiss(animated:true){[weak self] in self?.showCampaignResults()};return}
        guard presentedViewController==nil else{return}
        let screen=MeadowCampaignResultsViewController(result:result,catalog:campaign.engine.catalog,seed:campaign.snapshot.layout.configuration.seed)
        screen.onReturnSettings={ [weak self] in
            guard let self else{return};do{try self.saveCampaign();self.dismiss(animated:true)}catch{self.showCampaignMessage("保存失败："+error.localizedDescription)}
        }
        present(screen,animated:true)
    }
    private func showCampaignTeam(){
        guard let campaign else{return}
        let rows=campaign.engine.state.players.map{u in let a=(try? GameRules.attributes(u,catalog:campaign.engine.catalog)) ?? u.baseAttributes;return "\(u.name)：基础行动\(a.baseAP)，行动上限\(a.maximumAP)"}
        let menu=UIAlertController(title:"队伍与操作成员",message:rows.joined(separator:"\n")+"\n移动上限＝成员行动上限平均值×50。\n两位成员职业可在新行程设置中分别选择；当前行程沿用存档职业。",preferredStyle:.actionSheet)
        for id in campaign.playerIDs{menu.addAction(UIAlertAction(title:"切换操作成员 · \(id.uppercased())"+(id==campaign.selectedPlayerID ? " ✓":""),style:.default){[weak self] _ in do{try self?.scene.selectCampaignPlayer(id);self?.refreshCampaignStatus()}catch{self?.showCampaignMessage(error.localizedDescription)}})}
        menu.addAction(UIAlertAction(title:"关闭",style:.cancel));menu.popoverPresentationController?.sourceView=campaignTeam;menu.popoverPresentationController?.sourceRect=campaignTeam.bounds;present(menu,animated:true)
    }
    /// The shop opens anywhere during exploration: a moving party is paused first; prices follow the buyer's place.
    private func openTravellingShop() {
        guard ready,let campaign else{showCampaignMessage("画面准备中，请稍候。");return}
        if battlePreviewActive {classroomPreviewEncounter(nil)}
        if campaign.isMoving {try? campaign.setPaused(true);scene.refreshCampaign();refreshCampaignStatus()}
        let actor=scene.selectedCampaignPlayerID
        guard campaign.canManageInventory,let unit=campaign.engine.state.units[actor],unit.isAlive else{showCampaignMessage(campaign.engine.state.battle != nil ? "战斗中不能交易。":"请选择存活的成员。");return}
        cancelNodeSelection()
        let shop=MeadowShopViewController(session:campaign,node:unit.nodeID,actor:actor)
        shop.onTrade={[weak self] _ in self?.scene.refreshCampaign();self?.refreshCampaignStatus()}
        present(shop,animated:true)
    }
    private func openCampaignInventory() {
        guard ready,let campaign else{showCampaignMessage("画面准备中，请稍候。");return}
        guard classroomMode || presentedViewController==nil else{return}
        if battlePreviewActive {classroomPreviewEncounter(nil)}
        if campaign.isMoving {try? campaign.setPaused(true);scene.refreshCampaign();refreshCampaignStatus()}
        guard campaign.canManageInventory else{showCampaignMessage("请先结束战斗再打开行囊。");return}
        cancelNodeSelection()
        let screen=MeadowCampaignInventoryViewController(session:campaign,actor:scene.selectedCampaignPlayerID)
        if classroomMode {classroomInventoryChanged?(scene.selectedCampaignPlayerID)}
        screen.onActorChanged={ [weak self] id in self?.classroomInventoryChanged?(id) }
        screen.performEquip={ [weak self] actor,slot,item in
            guard let self else{return}
            let candidate=try campaign.candidateEquipment(actor:actor,slot:slot,item:item)
            if actor=="p1" || candidate.appearance != nil {
                let look=candidate.appearance ?? PlayerAppearance(body:campaign.snapshot.appearanceID)
                let index=HeroFrames.appearanceIDs.firstIndex(of:look.body) ?? 0
                try self.groundRenderer?.prepareP1Equipment(appearance:index,weapon:candidate.equipment.weapon,armor:look.armor(worn:candidate.equipment.armor),retainingCurrent:true,hair:look.hair,face:look.face)
            }
            try campaign.equipInventory(actor:actor,slot:slot,item:item)
            self.profileVisualSignature=""
            try self.prepareProfileVisuals()
        }
        screen.onChange={ [weak self] in self?.scene.refreshCampaign();self?.refreshCampaignStatus(allowBattleOpen:false) }
        screen.onClose={ [weak self] in self?.classroomInventoryChanged?(nil);self?.refreshCampaignStatus() }
        present(screen,animated:true)
    }
    enum TeacherOperation {case inventory,shop,interact,refill,team,route,editNode(Int),pauseOrResume,save,zoom(Int),pan(CGPoint)}
    func classroomPerform(_ operation:TeacherOperation,role:ClassroomRole)throws {
        try ClassroomGameBackend.requireTeacher(role)
        guard classroomMode,ready,!classroomBusy else{throw GameError("画面准备中或动作尚未结束。")}
        switch operation {
        case .inventory:openCampaignInventory()
        case .shop:openTravellingShop()
        case .interact:showCampaignInteraction()
        case .refill:refillCampaign()
        case .team:showCampaignTeam()
        case .route:showCampaignEnd()
        case .editNode(let id):
            guard let campaign,!campaign.isMoving,campaign.engine.state.battle==nil,!campaign.isCompleted else{throw GameError("请先停止移动并结束战斗。")}
            editNodeContents(id)
        case .pauseOrResume:togglePlayback()
        case .save:try campaign?.checkpoint(camera:scene.campaignCamera)
        case .zoom(let direction):scene.setZoom(scene.zoom+CGFloat(direction)*0.2)
        case .pan(let amount):scene.panBy(amount)
        }
    }
    func classroomRefresh(){scene.refreshCampaign();refreshCampaignStatus();battlePreviewView?.classroomRefresh()}
    func classroomPreviewEncounter(_ node:Int?){selectEncounterPreview(node)}
    func classroomAction(_ action:PartyAction,target:String,role:ClassroomRole)throws {
        try ClassroomGameBackend.requireTeacher(role)
        guard !classroomBusy,let campaign,campaign.engine.state.pauseReasons.isEmpty,let actor=campaign.engine.state.battle?.current,campaign.engine.state.units[actor]?.kind == .player else{throw GameError("请等待当前动作结束并继续玩家回合。")}
        battlePreviewView?.classroomAction(action,target:target)
    }
    func classroomFocus(_ action:PartyAction?,target:String,role:ClassroomRole)throws {
        try ClassroomGameBackend.requireTeacher(role);battlePreviewView?.classroomFocus(action,target:target)
    }
    func classroomSuspend()throws {
        classroomOverlayDirty=true
        guard !classroomBusy else{throw GameError("请等动作播放结束后切换绘本。")}
        if let campaign {try campaign.suspendAndCheckpoint(camera:scene.campaignCamera)}
        classroomSuspended=true
        if battlePreviewActive {battlePreviewView?.classroomPause(true)}
        setRenderingPaused(true)
    }
    func classroomResumeRenderer(){
        // Re-send a whole mirror frame (map and overlay): the teacher preview must not keep the book-time picture.
        classroomOverlayDirty=true;classroomDeliveredMap = -1;classroomDeliveryClock=ClassroomPreviewClock()
        classroomSuspended=false
        if battlePreviewActive {battlePreviewView?.classroomResume()}
        setRenderingPaused(!mapPresented || loadingFailed)
    }
    override func present(_ controller:UIViewController,animated:Bool,completion:(()->Void)?=nil) {
        guard classroomMode else{super.present(controller,animated:animated,completion:completion);return}
        guard let teacher=classroomPrivatePresenter,teacher.view.window != nil else{classroomStatus?("请在教师后台打开操作面板。");return}
        let show={
            if let popover=controller.popoverPresentationController {popover.sourceView=teacher.view;popover.sourceRect=CGRect(x:teacher.view.bounds.midX,y:teacher.view.bounds.midY,width:1,height:1)}
            var top=teacher
            while let next=top.presentedViewController {top=next}
            top.present(controller,animated:animated,completion:completion)
        }
        if let alert=teacher.presentedViewController as? UIAlertController {alert.dismiss(animated:false,completion:show)}else{show()}
    }
    private func setRenderingPaused(_ paused: Bool) { groundView?.isPaused = paused; gaitView?.isPaused = paused }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); setRenderingPaused(classroomSuspended || !mapPresented || loadingFailed) }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); setRenderingPaused(true) }

    @objc private func tapMap(_ recognizer: UITapGestureRecognizer) { scene.handleTap(inView: recognizer.location(in: gameView)) }

    @objc private func reset() {
        if campaign != nil {refillCampaign();return}
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
                                     message: "▶ 三位旅人沿土路往返；Ⅱ 暂停后保留目的地\n点选 P1 / P2 / P3，再点道路指定目的地\n点问号，让旅人抵达并探索\n↻ 恢复初始位置；＋ 放大\n双指缩放、拖动；长按安然显示运行指标\n战斗预览：地图留在左侧，右侧检查 Meadow Journey 林地横版场景\n步态测试：选择八个方向直线行走，可慢速、暂停和单步；走完一段会回到起点继续", preferredStyle: .alert)
        help.addAction(UIAlertAction(title: "出发", style: .default))
        help.addAction(UIAlertAction(title: "复制 GPU 诊断", style: .default) { _ in
            UIPasteboard.general.string = MeadowGPUDiagnostics.shared.json
        })
        present(help, animated: true)
    }
}
