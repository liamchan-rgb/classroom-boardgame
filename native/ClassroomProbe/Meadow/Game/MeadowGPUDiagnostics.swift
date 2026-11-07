import MetalKit
import SpriteKit
import Darwin

/// Small, atomic reports survive a watchdog termination. A pending stage is a
/// breadcrumb, not proof that its encoder caused a GPU fault.
final class MeadowGPUDiagnostics {
    static let shared = MeadowGPUDiagnostics()
    private let lock = NSLock()
    private let url: URL
    private var report: [String: Any] = [:]
    private var started: [String: TimeInterval] = [:]

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeadowGPUDiagnostic.json")
        if let data = try? Data(contentsOf: self.url),
           let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { report = saved }
    }

    func begin(device: MTLDevice?, size: CGSize, scale: CGFloat) {
        lock.lock(); defer { lock.unlock() }
        if !report.isEmpty, let previous = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? previous.write(to: url.deletingLastPathComponent().appendingPathComponent("MeadowGPUDiagnostic.previous.json"), options: .atomic)
        }
        var machine = utsname(); uname(&machine)
        let capacity = MemoryLayout.size(ofValue: machine.machine)
        let model = withUnsafePointer(to: &machine.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        report = ["format": 2, "status": "running", "startedAt": ISO8601DateFormatter().string(from: Date()),
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "hardware": model, "system": UIDevice.current.systemVersion,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "gpu": device?.name ?? "unavailable", "viewPoints": [Double(size.width), Double(size.height)], "displayScale": Double(scale),
            "startupPath": "b24 one MTKView, one queue; NW leg-region calibration and in-map eight-direction gait test",
            "notes": ["A stages: serial native Metal command buffers before SpriteKit preload/rendering.",
                      "B stages: serial offscreen SKRenderer submissions at the foreground pixel size.",
                      "C00: 60 repeated full-composite offscreen frames, reusing the production depth and backdrop resources.",
                      "C02: actual single MTKView composition, with native passes and SKRenderer in the same completed command buffer.",
                      "firstError means the first error observed in this diagnostic launch; SubmissionsIgnored alone does not reveal its earlier cause.",
                      "A pending stage after termination is a breadcrumb, not a confirmed GPU error."], "events": [[String: Any]]()]
        started = [:]
        saveLocked()
    }

    func beginStage(_ stage: String, kind: String, size: CGSize? = nil, recordEvent: Bool = true) {
        lock.lock(); defer { lock.unlock() }
        guard report["firstError"] == nil else { return }
        started[stage] = ProcessInfo.processInfo.systemUptime
        report["currentStage"] = stage
        var event: [String: Any] = ["stage": stage, "state": "submitted", "kind": kind]
        if let size { event["pixels"] = [Double(size.width), Double(size.height)] }
        if recordEvent { appendLocked(event) }
        saveLocked()
    }

    func passed(_ stage: String, command: MTLCommandBuffer, recordEvent: Bool = true, group: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        guard report["firstError"] == nil else { return }
        var event: [String: Any] = ["stage": stage, "state": "gpuCompleted", "command": command.label ?? ""]
        if let began = started[stage] { event["wallMilliseconds"] = (ProcessInfo.processInfo.systemUptime - began) * 1000 }
        if command.gpuEndTime > command.gpuStartTime, command.gpuStartTime > 0 {
            event["gpuMilliseconds"] = (command.gpuEndTime - command.gpuStartTime) * 1000
        }
        var count = 0
        if let group {
            var statistics = report["statistics"] as? [String: [String: Any]] ?? [:]
            var stats = statistics[group] ?? [:]
            count = (stats["completedFrames"] as? Int ?? 0) + 1
            stats["completedFrames"] = count
            if let milliseconds = event["gpuMilliseconds"] as? Double {
                let measured = (stats["measuredFrames"] as? Int ?? 0) + 1
                let total = (stats["totalGPUms"] as? Double ?? 0) + milliseconds
                stats["measuredFrames"] = measured; stats["totalGPUms"] = total
                stats["meanGPUms"] = total / Double(measured)
                stats["minGPUms"] = min(stats["minGPUms"] as? Double ?? milliseconds, milliseconds)
                stats["maxGPUms"] = max(stats["maxGPUms"] as? Double ?? milliseconds, milliseconds)
            }
            statistics[group] = stats; report["statistics"] = statistics
        }
        report["lastCompletedStage"] = stage
        if recordEvent { appendLocked(event) }
        // Keep live per-frame I/O out of the frame budget. Failure always saves
        // the current accumulated statistics; routine live updates save at 1Hz.
        if recordEvent || (group != nil && count % 60 == 0) { saveLocked() }
    }

    @discardableResult
    func failed(_ error: Error, stage: String? = nil, command: MTLCommandBuffer? = nil, context: [String: Any] = [:]) -> NSError {
        lock.lock(); defer { lock.unlock() }
        if report["firstError"] == nil {
            let original = error as NSError
            var detail: [String: Any] = ["stage": stage ?? report["currentStage"] as? String ?? "setup",
                "domain": original.domain, "code": original.code, "description": original.localizedDescription,
                "gpuCommand": command != nil, "command": command?.label ?? ""]
            detail["context"] = context
            if let reason = original.localizedFailureReason { detail["reason"] = reason }
            if let debug = original.userInfo[NSDebugDescriptionErrorKey] { detail["debug"] = String(describing: debug) }
            if let infos = original.userInfo[MTLCommandBufferEncoderInfoErrorKey] as? [MTLCommandBufferEncoderInfo] {
                detail["encoders"] = infos.map {
                    let raw = Int($0.errorState.rawValue)
                    return ["label": $0.label ?? "", "state": String(describing: $0.errorState),
                            "stateName": [0: "unknown", 1: "affected", 2: "completed", 3: "pending", 4: "faulted"][raw] ?? "unknown",
                            "signposts": $0.debugSignposts] as [String: Any]
                }
            }
            report["firstError"] = detail; report["status"] = "failed"
            appendLocked(["stage": detail["stage"]!, "state": "failed"])
            saveLocked()
        }
        let first = report["firstError"] as? [String: Any] ?? [:]
        let text = "首次失败：\(first["stage"] as? String ?? "unknown")\n\(first["description"] as? String ?? error.localizedDescription)"
        return NSError(domain: "MeadowGPU.Diagnostic", code: first["code"] as? Int ?? -1,
                       userInfo: [NSLocalizedDescriptionKey: text, NSUnderlyingErrorKey: error])
    }

    func mapReady() {
        lock.lock(); defer { lock.unlock() }
        guard report["firstError"] == nil else { return }
        report["status"] = "ready"
        appendLocked(["stage": "C02 实际单视图地图", "state": "firstCompositeGPUCompleted",
                      "proof": "The native depth/backdrop, Retina presentation and SpriteKit foreground shared the completed command buffer."])
        saveLocked()
    }

    var savedFailureOrInterruption: String? {
        lock.lock(); defer { lock.unlock() }
        if let first = report["firstError"] as? [String: Any] {
            return "上次首次失败：\(first["stage"] as? String ?? "unknown")\n\(first["description"] as? String ?? "")"
        }
        if report["status"] as? String == "running" {
            return "上次诊断中断于：\(report["currentStage"] as? String ?? "资源准备")\n中断本身不能证明该阶段有 GPU 错误。"
        }
        return nil
    }

    var recordedBuild: String? {
        lock.lock(); defer { lock.unlock() }
        return report["build"] as? String
    }

    var requiresColdLaunch: Bool {
        lock.lock(); defer { lock.unlock() }
        return (report["firstError"] as? [String: Any])?["gpuCommand"] as? Bool ?? false
    }

    var json: String {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func command(queue: MTLCommandQueue, label: String) throws -> MTLCommandBuffer {
        let descriptor = MTLCommandBufferDescriptor()
        descriptor.errorOptions = .encoderExecutionStatus
        guard let command = queue.makeCommandBuffer(descriptor: descriptor) else { throw ShadowLabError.setup("诊断命令缓冲区分配失败") }
        command.label = label
        return command
    }

    private func appendLocked(_ event: [String: Any]) {
        var events = report["events"] as? [[String: Any]] ?? []
        events.append(event); report["events"] = Array(events.suffix(128))
    }

    private func saveLocked() {
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch { report["persistenceError"] = error.localizedDescription }
    }
}

/// SKRenderer exposes the command buffer that SKView hides. Probe each production
/// shader at full foreground pixel size, serially, without reading any image pixels.
final class MeadowGPUProbe {
    private let prepared: PreparedMeadow
    private let size: CGSize
    private let pixels: CGSize
    private let renderer: SKRenderer
    private let queue: MTLCommandQueue
    private let target: MTLTexture
    private let diagnostics: MeadowGPUDiagnostics
    private let progress: (Double, String) -> Void
    private var completion: ((Result<Void, Error>) -> Void)?
    private var stage = 0
    private var sample = 0
    private let labels = ["B01 普通贴图前景", "B02 全物件植被着色器", "B03 后层薄雾", "B04 阳光光束", "B05 前层薄雾", "B06 完整前景组合", "C00 单队列连续组合"]

    init(prepared: PreparedMeadow, size: CGSize, scale: CGFloat, diagnostics: MeadowGPUDiagnostics = .shared,
         progress: @escaping (Double, String) -> Void) throws {
        guard let device = prepared.renderer?.device, let queue = device.makeCommandQueue() else { throw ShadowLabError.setup("前景诊断队列分配失败") }
        self.prepared = prepared; self.size = size; self.progress = progress; self.diagnostics = diagnostics
        pixels = CGSize(width: max(1, (size.width * scale).rounded(.up)), height: max(1, (size.height * scale).rounded(.up)))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(pixels.width), height: Int(pixels.height), mipmapped: false)
        descriptor.storageMode = .private; descriptor.usage = .renderTarget
        guard let target = device.makeTexture(descriptor: descriptor) else { throw ShadowLabError.setup("前景诊断目标分配失败") }
        self.target = target; self.queue = queue; renderer = SKRenderer(device: device)
    }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
        submitNext()
    }

    private func submitNext() {
        guard stage < labels.count else {
            renderer.scene = nil
            let finished = completion; completion = nil; finished?(.success(())); return
        }
        let repeats = stage == 6 ? 60 : 2
        let record = sample < 2 || sample == repeats - 1
        let label = "\(labels[stage]) [\(sample + 1)/\(repeats)]"
        progress(Double(stage * 2 + sample) / 72, label)
        diagnostics.beginStage(label, kind: stage == 6 ? "production native + SKRenderer path; repeated offscreen resource reuse" : "offscreen SKRenderer", size: pixels, recordEvent: record)
        do {
            if sample == 0 { renderer.scene = makeScene(stage: stage) }
            let time: TimeInterval = stage == 6 ? Double(sample) / 60 : (sample == 0 ? 0 : 2)
            prepared.effects.update(time: time)
            let command = try MeadowGPUDiagnostics.command(queue: queue, label: label)
            let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.15, green: 0.2, blue: 0.08, alpha: 1)
            renderer.update(atTime: stage == 6 ? 12 + Double(sample + 1) / 60 : Double(stage * 2 + sample + 1))
            if stage == 6, let world = renderer.scene?.children.first as? LivingWorld, let scene = renderer.scene, let native = prepared.renderer {
                let heroes = (0..<3).map { MeadowHeroCaster(index: $0, foot: CGPoint(x: 300 + $0 * 100, y: 442), facing: 0, frame: 0) }
                let frame = MeadowFrameState(world: world, camera: MeadowViewport(world: world, scene: scene, viewSize: size), time: time, heroes: heroes)
                try native.encodeComposite(command: command, target: pass, frame: frame, foreground: renderer, forceBackground: true)
            } else {
                renderer.render(withViewport: CGRect(origin: .zero, size: pixels), commandBuffer: command, renderPassDescriptor: pass)
            }
            command.addCompletedHandler { [weak self] buffer in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let error = buffer.error {
                        let failure = self.diagnostics.failed(error, stage: label, command: buffer, context: ["sample": self.sample + 1, "environmentTime": time])
                        let finished = self.completion; self.completion = nil; finished?(.failure(failure)); return
                    }
                    guard buffer.status == .completed else { return }
                    self.diagnostics.passed(label, command: buffer, recordEvent: record, group: self.stage == 6 ? "offscreenComposite" : nil)
                    self.sample += 1
                    if self.sample == repeats { self.sample = 0; self.stage += 1 }
                    DispatchQueue.main.async { self.submitNext() }
                }
            }
            command.commit()
        } catch {
            let failure = diagnostics.failed(error, stage: label)
            let finished = completion; completion = nil; finished?(.failure(failure))
        }
    }

    private func makeScene(stage: Int) -> SKScene {
        let scene = SKScene(size: size); scene.scaleMode = .resizeFill; scene.backgroundColor = .clear
        if stage == 3 {
            scene.addChild(prepared.effects.makeSunlightOverlay(size: size))
            return scene
        }
        let root: SKNode
        if stage == 0 || stage == 1 || stage >= 5 {
            root = LivingWorld(definition: prepared.definition, roadMask: prepared.roadMask, props: prepared.props,
                textures: prepared.textures, effects: prepared.effects, renderTerrain: false,
                vegetationEnabled: stage != 0, atmosphereEnabled: stage >= 5)
            for index in 0..<3 {
                let actor = SKSpriteNode(texture: prepared.heroes[index][0][0], size: CGSize(width: 64, height: 64))
                actor.anchorPoint = CGPoint(x: 0.5, y: 0.125)
                actor.position = LivingWorld.position(CGPoint(x: 300 + index * 100, y: 442))
                actor.zPosition = 10442; root.addChild(actor)
            }
        } else {
            root = SKNode()
            let sprite = SKSpriteNode(color: .white, size: LivingWorld.bounds.size)
            sprite.position = LivingWorld.position(CGPoint(x: LivingWorld.bounds.midX, y: LivingWorld.bounds.midY))
            sprite.shader = stage == 2 ? prepared.effects.backMist : prepared.effects.frontMist
            root.addChild(sprite)
        }
        let scale = min(size.width / 1280, size.height / 720)
        root.setScale(scale)
        root.position = CGPoint(x: size.width / 2 - 640 * scale, y: size.height / 2 + 360 * scale)
        scene.addChild(root)
        (root as? LivingWorld)?.attachSunlight(to: scene)
        return scene
    }
}
