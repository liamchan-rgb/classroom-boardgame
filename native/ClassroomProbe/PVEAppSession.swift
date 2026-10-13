import Foundation
import SwiftUI
import ClassroomGameCore

@MainActor
final class PVEAppSession: ObservableObject {
    @Published private(set) var play: PVEPlaySession?
    @Published private(set) var revision = 0
    @Published private(set) var message = "正在准备课堂游戏。"
    @Published private(set) var aiRunning = false
    @Published private(set) var bookOpen = false
    @Published private(set) var publicCamera = MapCamera(zoom:1.35)
    @Published private(set) var cameraFocusID: String?
    @Published private(set) var cameraFollowsCurrent = true
    @Published private(set) var inventoryPage = 0
    private var detailActorID: String?
    private(set) var modalOpen = false
    private let display: PublicDisplayModel
    private var store: AtomicGameStore?
    private var active = false
    private var timer: Timer?
    private var aiTask: Task<Void,Never>?
    private var presentation = PresentationLedger()
    private var lastTick = ProcessInfo.processInfo.systemUptime

    init(display: PublicDisplayModel) {
        self.display = display
        do {
            let base = try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
            let store = AtomicGameStore(url:base.appendingPathComponent("ClassroomPVE/session.json"))
            self.store = store
            if FileManager.default.fileExists(atPath:store.url.path) {
                let archive = try store.load()
                play = PVEPlaySession(engine:try GameEngine(catalog:archive.catalog,state:archive.state,history:archive.history,persist:store.save))
                message = "已恢复本地PVE进度，计时和怪物保持暂停。"
            } else {
                let catalog = try GameCatalog.initial()
                var state = try PVEGameFactory.make(players:[PlayerSetup(id:"p1",name:"学生1",classID:"adventurer"),PlayerSetup(id:"p2",name:"学生2",classID:"spellblade")],seed:UInt64.random(in:1...UInt64.max),catalog:catalog)
                state.pauseReasons = [.manual]
                let engine = try GameEngine(catalog:catalog,state:state,persist:store.save)
                try store.save(engine.archive); play = PVEPlaySession(engine:engine)
                message = "森林地图已准备。点击相邻地点规划移动，或创建新局设置玩家。"
            }
        } catch { message = "读取游戏失败，原存档保留：\(error.localizedDescription)" }
        if let play { presentation.suppressHistory(play.engine.history) }
        timer = Timer.scheduledTimer(withTimeInterval:0.2,repeats:true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    #if DEBUG
    func installVisualFixture(_ fixture:PVEPlaySession) {
        active = false; cancelAI(); play = fixture; fixture.toggleReward("p2"); fixture.toggleReward("p3")
        message = "视觉验证：7角色、3怪物、独立奖励、倒地和下轮资格。"; publish()
    }
    #endif
    var state: GameState? { play?.engine.state }
    var catalog: GameCatalog? { play?.engine.catalog }
    var actor: GameUnit? { play?.actor }
    var paused: Bool { state?.pauseReasons.isEmpty == false }
    var scenario: PVEScenario? { state?.verificationScenario.flatMap(PVEScenario.init(rawValue:)) }
    func activate() { presentation.clearVisible(); active = true; lastTick = ProcessInfo.processInfo.systemUptime; publish(); scheduleAI() }
    func deactivate() { pause(.manual,enabled:true); active = false; cancelAI(); display.playFrame = nil; display.playBook = false }
    func pause(_ reason: GamePause, enabled: Bool) {
        guard let play else { return }
        if enabled { cancelAI() }
        do { try captureElapsed(); if enabled { presentation.clearVisible() }; try play.engine.setPause(reason,enabled:enabled) }
        catch {
            if enabled { try? play.engine.setPause(reason,enabled:true) }
            message = "计时状态保存失败：\(error.localizedDescription)"
        }
        lastTick = ProcessInfo.processInfo.systemUptime; play.synchronize(); publish(); scheduleAI()
    }
    func togglePause() { pause(.manual,enabled:state?.pauseReasons.contains(.manual) != true) }
    func setModal(_ open: Bool, reason: GamePause = .editor) { modalOpen = open; pause(reason,enabled:open) }
    func setBook(_ open: Bool) { bookOpen = open; pause(.book,enabled:open) }
    func selectPlayer(_ id: String) { play?.selectPlayer(id); publish() }
    func toggleReward(_ id: String) { play?.toggleReward(id); publish() }
    func toggleTravel(_ id: String) { play?.toggleTravel(id); publish() }
    func choose(_ action: PlayerAction) { play?.choose(action); publish() }
    func target(_ value: ActionTarget) { play?.selectTarget(value); publish() }
    func tapNode(_ id: Int) {
        do { try play?.tapNode(id); message = "路径和目标已选择，确认行动后结算。" }
        catch { message = error.localizedDescription }
        publish()
    }
    func clearPath() { play?.clearPath(); publish() }
    // Explicit view controls are independent of private action/reward selections.
    func focusPublicPlayer(_ id:String) {
        guard let player = state?.units[id], player.kind == .player,
              let node = state?.map.nodes.first(where: { $0.id == player.nodeID }) else { return }
        cameraFocusID = id; cameraFollowsCurrent = false
        publicCamera = MapCamera(x:node.x,y:node.y,zoom:max(1.8,publicCamera.zoom)); publish()
    }
    func followPublicActor() { cameraFocusID = nil; cameraFollowsCurrent = true; publish() }
    func overviewPublicMap() { cameraFocusID = nil; cameraFollowsCurrent = false; publicCamera = MapCamera(); publish() }
    func zoomPublicMap(_ factor:Double) { publicCamera = publicCamera.scaled(by:factor); publish() }
    func panPublicMap(x:Double,y:Double) {
        cameraFocusID = nil; cameraFollowsCurrent = false
        publicCamera = publicCamera.panned(x:x,y:y); publish()
    }
    func turnInventoryPage(_ amount:Int) {
        let count = (try? play?.publicFrame().currentDetails?.items.count) ?? 0
        inventoryPage = max(0,min(max(0,(count+3)/4-1),inventoryPage+amount)); publish()
    }
    func perform() {
        guard let play, !aiRunning, !bookOpen, !modalOpen else { return }
        run { try play.perform() }
    }
    func award(_ value: ResourceReward) { guard let play else { return }; run { try play.reward(value) } }
    func endTurn() {
        guard let actor, actor.kind == .player, state?.battle != nil, !modalOpen, !bookOpen else { return }
        apply(.endTurn(actor:actor.id,timedOut:false))
    }
    func apply(_ command: GameCommand) { guard let play else { return }; run { try play.apply(command) } }
    func startHere() {
        guard let play, let actor else { return }
        let enemies = play.engine.state.units.values.filter { $0.kind == .monster && $0.isAlive && $0.nodeID == actor.nodeID }.map(\.id).sorted()
        apply(.startBattle(kind:.pve,monsters:enemies))
    }
    func extendTime() {
        do { try captureElapsed(); try play?.engine.extendTime(by:15); message = "本次决策时间增加15秒。" }
        catch { message = error.localizedDescription }
        publish()
    }
    func undo() {
        guard let play else { return }
        cancelAI()
        do {
            try play.engine.setPause(.manual,enabled:true)
            let receipt = try play.engine.undo()
            try play.engine.setPause(.manual,enabled:true)
            presentation.suppressHistory(play.engine.history)
            play.synchronize(); message = "已撤销完整一步，保持暂停：" + OperationSummary.lines(receipt,catalog:play.engine.catalog,publicOnly:false).joined(separator:"；")
        } catch { message = error.localizedDescription }
        lastTick = ProcessInfo.processInfo.systemUptime; publish()
    }
    func save() {
        do { try captureElapsed(); if let play { try store?.save(play.engine.archive) }; message = "当前PVE进度已保存到本机。" }
        catch { message = "保存失败：\(error.localizedDescription)" }
        publish()
    }
    func restore() {
        guard let store else { return }
        cancelAI()
        do {
            let archive = try store.load()
            let engine = try GameEngine(catalog:archive.catalog,state:archive.state,history:archive.history,persist:store.save)
            if modalOpen { try engine.setPause(.editor,enabled:true) }
            if bookOpen { try engine.setPause(.book,enabled:true) }
            presentation.suppressHistory(engine.history)
            play = PVEPlaySession(engine:engine); message = "已恢复保存的PVE，保持暂停。"
        } catch { message = "恢复失败，当前进度保留：\(error.localizedDescription)" }
        lastTick = ProcessInfo.processInfo.systemUptime; publish()
    }
    @discardableResult
    func newGame(players:[PlayerSetup],scenario:PVEScenario) -> Bool {
        guard let store else { return false }
        cancelAI()
        do {
            let catalog = try GameCatalog.initial()
            var state = try PVEGameFactory.make(players:players,scenario:scenario,seed:UInt64.random(in:1...UInt64.max),catalog:catalog)
            if modalOpen { state.pauseReasons.insert(.editor) }
            if let previous = play { try AtomicGameStore(url:store.url.deletingLastPathComponent().appendingPathComponent("previous-session.json")).save(previous.engine.archive) }
            let engine = try GameEngine(catalog:catalog,state:state,persist:store.save)
            try store.save(engine.archive)
            presentation.suppressHistory([])
            play = PVEPlaySession(engine:engine); message = "新局已建立：\(scenario.title)。"; lastTick = ProcessInfo.processInfo.systemUptime
            publish(); scheduleAI(); return true
        } catch { message = "新局未建立，当前进度保留：\(error.localizedDescription)"; publish(); return false }
    }
    func handleKey(_ code:String,shift:Bool) -> Bool {
        guard !modalOpen else { return false }
        if let number = Int(code), let selected = play?.shortcutPlayer(number) {
            let id = selected.id
            if shift { play?.toggleReward(id) } else { play?.selectReward(id); if state?.battle == nil { play?.selectPlayer(id) } }
            publish(); return true
        }
        switch code {
        case "g": award(ResourceReward(coins:10))
        case "a": award(ResourceReward(ap:1))
        case "s": award(ResourceReward(score:2))
        case " ": togglePause()
        case "e": endTurn()
        default: return false
        }
        return true
    }
    private func run(_ operation: () throws -> OperationReceipt) {
        do {
            try captureElapsed()
            let receipt = try operation()
            if let play {
                try presentation.submit(receipt,catalog:play.engine.catalog,now:Date())
                message = OperationSummary.lines(receipt,catalog:play.engine.catalog,publicOnly:false).joined(separator:"；")
            }
        } catch { message = "操作未执行：\(error.localizedDescription)" }
        lastTick = ProcessInfo.processInfo.systemUptime; play?.synchronize(); publish(); scheduleAI()
    }
    private func captureElapsed() throws {
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastTick = now }
        guard active, let play else { return }
        let date = Date()
        let elapsed = presentation.elapsedDecisionTime(from:date.addingTimeInterval(-max(0,now-lastTick)),to:date)
        if let receipt = try play.engine.advanceClock(by:elapsed) {
            try presentation.submit(receipt,catalog:play.engine.catalog,now:date)
            message = OperationSummary.lines(receipt,catalog:play.engine.catalog).joined(separator:"；")
        }
        play.synchronize()
    }
    private func tick() {
        guard active, let play else { lastTick = ProcessInfo.processInfo.systemUptime; return }
        let previous = play.engine.state
        do { try captureElapsed() }
        catch {
            cancelAI(); try? play.engine.setPause(.manual,enabled:true)
            message = "自动结算保存失败，已暂停：\(error.localizedDescription)"
        }
        let expired = presentation.removeExpired(at:Date())
        if play.engine.state != previous || expired { publish(); scheduleAI() }
    }
    private func cancelAI() { aiTask?.cancel(); aiTask = nil; aiRunning = false }
    private func scheduleAI() {
        guard active, !modalOpen, !bookOpen, aiTask == nil, let play,
              play.engine.state.pauseReasons.isEmpty, play.actor?.kind == .monster, presentation.pending.isEmpty else { return }
        aiRunning = true
        aiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.active, let play = self.play,
                  !self.modalOpen, !self.bookOpen, play.engine.state.pauseReasons.isEmpty, play.actor?.kind == .monster, self.presentation.pending.isEmpty {
                do { try await Task.sleep(nanoseconds:300_000_000) } catch { return }
                guard !Task.isCancelled, play.engine.state.pauseReasons.isEmpty else { return }
                do {
                    let receipt = try play.apply(.monsterStep)
                    try self.presentation.submit(receipt,catalog:play.engine.catalog,now:Date())
                    self.message = OperationSummary.lines(receipt,catalog:play.engine.catalog,publicOnly:false).joined(separator:"；")
                } catch {
                    try? play.engine.setPause(.manual,enabled:true)
                    self.message = "怪物行动未提交，已暂停：\(error.localizedDescription)"
                }
                self.lastTick = ProcessInfo.processInfo.systemUptime; self.publish()
            }
            if !Task.isCancelled { self.aiTask = nil; self.aiRunning = false; self.publish() }
        }
    }
    private func publish() {
        revision &+= 1
        guard active, let play else { return }
        do {
            var frame = try play.publicFrame()
            frame.presentations = presentation.pending
            let focus = cameraFollowsCurrent ? frame.snapshot.units.first(where: { $0.current }) : frame.snapshot.units.first(where: { $0.id == cameraFocusID })
            if let focus, let node = frame.snapshot.nodes.first(where: { $0.id == focus.nodeID }) {
                publicCamera = MapCamera(x:node.x,y:node.y,zoom:publicCamera.zoom)
            }
            if detailActorID != frame.currentDetails?.unitID { inventoryPage = 0; detailActorID = frame.currentDetails?.unitID }
            inventoryPage = min(inventoryPage,max(0,((frame.currentDetails?.items.count ?? 0)+3)/4-1))
            frame.camera = publicCamera; frame.cameraFocusID = cameraFocusID
            frame.followsCurrent = cameraFollowsCurrent; frame.inventoryPage = inventoryPage
            display.playFrame = frame; display.playBook = bookOpen
        }
        catch { message = "公开画面未更新：\(error.localizedDescription)" }
    }
}
