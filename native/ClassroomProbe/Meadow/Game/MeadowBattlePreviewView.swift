import UIKit
import ClassroomGameCore
import MeadowBattleSupport
import CoreImage

enum MeadowPreviewPalette {
    static let panel = UIColor(red: 0.10, green: 0.17, blue: 0.13, alpha: 0.97)
    static let card = UIColor(red: 0.17, green: 0.25, blue: 0.19, alpha: 1)
    static let ink = UIColor(red: 0.98, green: 0.93, blue: 0.77, alpha: 1)
    static let muted = UIColor(red: 0.72, green: 0.79, blue: 0.66, alpha: 1)
    static let gold = UIColor(red: 0.92, green: 0.77, blue: 0.42, alpha: 1)
    static let border = UIColor(red: 0.60, green: 0.57, blue: 0.34, alpha: 0.65)
    /// Flat sans-serif (the earlier serif design read as broken strokes in Chinese at game sizes).
    static func font(_ size:CGFloat,_ weight:UIFont.Weight = .bold)->UIFont {
        let base=UIFont.systemFont(ofSize:size,weight:weight)
        return UIFont(descriptor:base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor,size:size)
    }
    static let glassTint = UIColor(red: 0.06, green: 0.12, blue: 0.09, alpha: 0.5)
    /// Frosted glass panel: live blur of whatever is behind, a light dark tint so text stays legible
    /// (the tint alone also carries the panel in the teacher mirror, which cannot capture blur), a hairline highlight.
    static func stylePanel(_ view: UIView) {
        view.backgroundColor = glassTint
        view.layer.cornerRadius = 18
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
        guard !view.subviews.contains(where:{$0.accessibilityIdentifier=="glass"}) else{return}
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blur.accessibilityIdentifier = "glass"; blur.isUserInteractionEnabled = false
        blur.layer.cornerRadius = 18; blur.layer.cornerCurve = .continuous; blur.clipsToBounds = true
        blur.frame = view.bounds; blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(blur, at: 0)
    }
    /// Icon-first glass button: an SF Symbol with an optional short caption.
    static func iconButton(_ symbol:String,_ title:String?=nil,prominent:Bool=false)->UIButton {
        var style = prominent ? UIButton.Configuration.filled():UIButton.Configuration.gray()
        style.image = UIImage(systemName:symbol,withConfiguration:UIImage.SymbolConfiguration(pointSize:18,weight:.semibold))
        style.title = title; style.imagePadding = 6; style.cornerStyle = .capsule
        style.titleTextAttributesTransformer=UIConfigurationTextAttributesTransformer { value in var v=value;v.font=font(16,.semibold);return v }
        style.baseBackgroundColor = prominent ? gold:UIColor.white.withAlphaComponent(0.16)
        style.baseForegroundColor = prominent ? panel:ink
        style.background.visualEffect = prominent ? nil:UIBlurEffect(style:.systemUltraThinMaterialDark)
        style.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 14)
        let button = UIButton(type: .system); button.configuration = style
        if let title {button.accessibilityLabel = title}
        return button
    }
    static func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .medium) -> UILabel {
        let label = UILabel(); label.text = text
        label.font = font(size,weight)
        label.textColor = ink; label.adjustsFontSizeToFitWidth = true; label.minimumScaleFactor = 1
        return label
    }
    static func button(_ title: String) -> UIButton {
        var style = UIButton.Configuration.filled(); style.title = title; style.cornerStyle = .capsule
        style.titleTextAttributesTransformer=UIConfigurationTextAttributesTransformer { value in var v=value;v.font=font(18,.semibold);return v }; style.baseBackgroundColor = gold.withAlphaComponent(0.92); style.baseForegroundColor = panel
        style.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        let button = UIButton(type: .system); button.configuration = style
        return button
    }
}

/// A compact, playable P1 versus one Forest Warden encounter layered over the map.
final class MeadowBattlePreviewView: UIView {
    var classroomModelFactory:(()throws->PartyEncounter)? {didSet{party.classroomModelFactory=classroomModelFactory}}
    func classroomEnemyStep(){party.classroomEnemyStep()}
    func classroomToggleMap(){party.classroomToggleMap()}
    func classroomHit(at point:CGPoint)->MeadowPartyBattleView.ClassroomHit? {party.classroomHit(at:convert(point,to:party))}
    var classroomMode=false {didSet {
        party.classroomMode=classroomMode
        if classroomMode {
            // The formal party preview is the sole public battle UI. Remove
            // the parent single-player training UI rather than overlaying it.
            let obsolete:[UIView]=[header,landscape,track,details,mapBorder,mapTitle,partyButton,stageTitle]
            obsolete.forEach{$0.removeFromSuperview()}
        }
    }}
    func classroomPause(_ value:Bool){party.classroomSetPaused(value)}
    func classroomRefresh(){party.classroomRefresh()}
    func classroomResume(){if !isActive{setActive(true)};party.classroomSetPaused(false)}
    var classroomBusy:Bool {party.classroomBusy}
    var classroomActions:[PartyAction] {party.classroomActions}
    func classroomAction(_ action:PartyAction,target:String){party.classroomAction(action,target:target)}
    func classroomFocus(_ action:PartyAction?,target:String){party.classroomFocus(action,target:target)}
    private var equipmentWeaponID:String?="trainingSword"
    func configureEquipment(_ units:[String:GameUnit]) {
        party.loadoutUnits=units;equipmentWeaponID=units["p1"]?.equipment.weapon
        if encounter.phase == .exploration,let unit=units["p1"],let catalog=try? GameCatalog.initial(),let stats=try? GameRules.attributes(unit,catalog:catalog) { encounter=MeadowBattleEncounter(maximumHealth:stats.maximumHealth,baseAP:min(stats.baseAP,stats.maximumAP),damageBonus:stats.damage) }
        if let unit=units["p1"],let catalog=try? GameCatalog.initial() {
            details.accessoryReadout=try? AccessoryReadout.make(unit,catalog:catalog)
        }
        details.accessoryHost=self
        details.hasWeapon=equipmentWeaponID != nil
        landscape.configureWeapon(HeroFrames.weaponVisual(equipmentWeaponID)?.battleAsset)
        landscape.configureArmor(units["p1"]?.equipment.armor)
    }
    var onClose: (() -> Void)?
    var onPartyActiveChanged: ((Bool)->Void)?
    private var campaignMode=false
    private var partyMode=false
    private let party=MeadowPartyBattleView(frame:.zero)
    private let partyButton=MeadowPreviewPalette.button("小队支援")
    var onLayoutChanged: (() -> Void)?
    private var encounter = MeadowBattleEncounter()
    private var isActive = false
    private var isAnimating = false
    private var generation: UInt = 0
    private var pendingEnemyAction: DispatchWorkItem?
    private var lastPrimaryActionTime = 0.0
    private var mode: MeadowBattlePreviewMode { encounter.phase == .exploration ? .exploration : .playerTurn }
    var mapFrame: CGRect { MeadowBattleLayout(size: bounds.size, safeArea: safeAreaInsets, mode: partyMode ? .playerTurn:mode).map }

    private let header = UIView()
    private let actor = MeadowPreviewPalette.label("", size: 26, weight: .heavy)
    private let subtitle = MeadowPreviewPalette.label("", size: 16, weight: .semibold)
    private let primaryButton = MeadowPreviewPalette.button("开始遭遇")
    private let closeButton = MeadowPreviewPalette.button("返回地图")
    private let landscape = MeadowBattleLandscapeView()
    private let mapBorder = UIView()
    private let mapTitle = MeadowPreviewPalette.label("Meadow Journey", size: 18, weight: .bold)
    private let stageTitle = MeadowPreviewPalette.label("Meadow Journey · 林地", size: 19, weight: .bold)
    private let track = MeadowTurnTrackView()
    private let details = MeadowPlayerDetailsView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        accessibilityIdentifier = "meadowBattlePreview"
        MeadowPreviewPalette.stylePanel(header)
        header.accessibilityIdentifier = "battlePreviewHeader"
        addSubview(header)
        actor.accessibilityIdentifier = "previewCurrentActor"
        header.addSubview(actor); header.addSubview(subtitle)
        subtitle.textColor = MeadowPreviewPalette.muted
        primaryButton.accessibilityIdentifier = "battlePreviewPrimaryAction"
        primaryButton.addAction(UIAction { [weak self] _ in self?.performPrimaryAction() }, for: .touchUpInside)
        header.addSubview(primaryButton)
        closeButton.accessibilityIdentifier = "closeBattlePreview"
        closeButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.setActive(false)
            self.onClose?()
        }, for: .touchUpInside)
        header.addSubview(closeButton)
        mapBorder.layer.cornerRadius = 14; mapBorder.layer.borderWidth = 1
        mapBorder.layer.borderColor = MeadowPreviewPalette.border.cgColor
        mapBorder.isUserInteractionEnabled = false; addSubview(mapBorder)
        mapTitle.backgroundColor = MeadowPreviewPalette.panel
        mapTitle.textAlignment = .center; mapTitle.layer.cornerRadius = 8; mapTitle.clipsToBounds = true
        mapTitle.isUserInteractionEnabled = false; addSubview(mapTitle)
        landscape.accessibilityIdentifier = "battleLandscape"
        landscape.isAccessibilityElement = false
        landscape.accessibilityLabel = "Meadow Journey 林地战场，P1 冒险者与一只林地鹿灵。"
        addSubview(landscape)
        stageTitle.text = "Meadow Journey · 林地遭遇"
        stageTitle.textAlignment = .center
        stageTitle.backgroundColor = MeadowPreviewPalette.panel.withAlphaComponent(0.88)
        stageTitle.layer.cornerRadius = 8; stageTitle.clipsToBounds = true
        stageTitle.isUserInteractionEnabled = false; landscape.addSubview(stageTitle)
        track.accessibilityIdentifier = "previewTurnTrack"; addSubview(track)
        details.accessibilityIdentifier = "previewPlayerDetails"; addSubview(details)
        details.onAction = { [weak self] action in self?.perform(action) }
        details.onPreview = { [weak self] action in self?.landscape.preview(action) }
        landscape.onEnemySelected = { [weak self] in self?.selectEnemy() }
        partyButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.setActive(false);self.partyMode=true;self.party.isHidden=false
            self.party.setActive(true);self.onPartyActiveChanged?(true);self.setNeedsLayout()
        },for:.touchUpInside)
        addSubview(partyButton)
        party.isHidden=true
        party.onClose={ [weak self] in
            guard let self else { return }
            if self.campaignMode {self.onClose?();return}
            self.partyMode=false;self.party.isHidden=true
            self.setActive(true);self.onPartyActiveChanged?(false)
        }
        addSubview(party)
        updatePresentation()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Called by the owner when the overlay appears or disappears.
    func configureCampaign(engine:GameEngine,onCommit:@escaping(OperationReceipt)->Void) {
        campaignMode=true;party.campaignEngine=engine;party.onCommit=onCommit
    }
    func setActive(_ active: Bool) {
        if campaignMode {
            isActive=active;partyMode=active;party.isHidden = !active;party.setActive(active)
            partyButton.isHidden=true;onPartyActiveChanged?(active);setNeedsLayout();return
        }

        if active {
            isActive = true
            updatePresentation()
            return
        }
        if partyMode { party.setActive(false);party.isHidden=true;partyMode=false;onPartyActiveChanged?(false) }
        isActive = false
        details.dismissAccessory()
        generation &+= 1
        pendingEnemyAction?.cancel()
        pendingEnemyAction = nil
        isAnimating = false
        landscape.cancelAnimations()
        encounter.returnToMap()
        updatePresentation()
    }

    private func performPrimaryAction() {
        guard isActive, !isAnimating else { return }
        let inputTime = ProcessInfo.processInfo.systemUptime
        guard inputTime - lastPrimaryActionTime > 0.18 else { return }
        lastPrimaryActionTime = inputTime
        switch encounter.phase {
        case .exploration:
            generation &+= 1
            encounter.begin()
            updatePresentation()
        case .playerTurn:
            endPlayerTurn()
        case .victory, .defeat:
            generation &+= 1
            encounter.retry()
            updatePresentation()
        case .enemyPreparing, .enemyTurn:
            break
        }
    }

    private func perform(_ action: MeadowBattleAction) {
        if action == .strike && equipmentWeaponID == nil { return }
        guard isActive, !isAnimating, let cue = encounter.beginAction(action) else { return }
        isAnimating = true
        let token = generation
        updatePresentation()
        landscape.play(cue, onImpact: { [weak self] in
            guard let self, self.isActive, self.generation == token else { return nil }
            let result = self.encounter.resolveActionImpact()
            self.updatePresentation()
            return result
        }) { [weak self] in
            guard let self, self.isActive, self.generation == token else { return }
            if self.encounter.phase == .victory {
                self.play(.victory, generation: token) { [weak self] in self?.finishAnimation() }
            } else {
                self.finishAnimation()
            }
        }
    }

    private func selectEnemy() {
        guard isActive, !isAnimating else { return }
        encounter.selectEnemy()
        updatePresentation()
    }

    private func endPlayerTurn() {
        guard encounter.phase == .playerTurn else { return }
        encounter.endPlayerTurn()
        isAnimating = true
        generation &+= 1
        let token = generation
        updatePresentation()
        // A clear wind-up window lets the player see the Forest Warden prepare.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isActive, self.generation == token,
                  self.encounter.beginEnemyAction() else { return }
            self.pendingEnemyAction = nil
            self.updatePresentation()
            self.landscape.play(.enemyStrike, onImpact: { [weak self] in
                guard let self, self.isActive, self.generation == token else { return nil }
                let result = self.encounter.resolveEnemyImpact()
                self.updatePresentation()
                return result
            }) { [weak self] in
                guard let self, self.isActive, self.generation == token else { return }
                if self.encounter.phase == .defeat {
                    self.play(.defeat, generation: token) { [weak self] in self?.finishAnimation() }
                } else {
                    self.encounter.completeEnemyTurn()
                    self.updatePresentation()
                    self.finishAnimation()
                }
            }
        }
        pendingEnemyAction = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func play(_ cue: MeadowBattleAnimationCue, generation token: UInt, completion: @escaping () -> Void) {
        landscape.play(cue) { [weak self] in
            guard let self, self.isActive, self.generation == token else { return }
            completion()
        }
    }

    private func finishAnimation() {
        isAnimating = false
        updatePresentation()
    }

    private func updatePresentation() {
        let phase = encounter.phase
        let activeBattle = encounter.isEncounterActive
        let status: String
        switch phase {
        case .exploration: status = "探索 · 林地"
        case .playerTurn: status = "第\(encounter.round)轮 · P1 行动"
        case .enemyPreparing: status = "第\(encounter.round)轮 · 鹿灵蓄势"
        case .enemyTurn: status = "第\(encounter.round)轮 · 鹿灵行动"
        case .victory: status = "遭遇胜利 · 鹿灵退去"
        case .defeat: status = "遭遇失败 · P1 力竭"
        }
        actor.text = status
        switch phase {
        case .exploration: subtitle.text = "在林地地图开始一场局部遭遇"
        case .playerTurn:
            subtitle.text = isAnimating ? "动作进行中…" : encounter.actionPoints == 0
                ? "行动点用尽 · 点击结束回合" : encounter.enemySelected
                ? "鹿灵已选中 · 点击下方技能行动" : "点选右侧鹿灵作为目标 · 或使用防护"
        case .enemyPreparing: subtitle.text = "鹿灵蓄势 · 即将冲撞"
        case .enemyTurn: subtitle.text = "鹿灵冲撞 · 护盾优先抵挡伤害"
        case .victory: subtitle.text = "可以重试遭遇，或返回地图"
        case .defeat: subtitle.text = "可以重试 · 试试防护和喘息"
        }
        primaryButton.isHidden = phase == .enemyPreparing || phase == .enemyTurn
        switch phase {
        case .exploration: primaryButton.configuration?.title = "开始遭遇"
        case .playerTurn: primaryButton.configuration?.title = "结束回合 · 鹿灵行动"
        case .victory, .defeat: primaryButton.configuration?.title = "重试遭遇"
        default: break
        }
        primaryButton.isEnabled = isActive && !isAnimating && phase != .enemyPreparing && phase != .enemyTurn
        closeButton.configuration?.title = "返回地图"
        landscape.isHidden = !activeBattle
        track.isHidden = !activeBattle
        details.isHidden = !activeBattle
        track.show(phase: phase, round: encounter.round)
        details.show(encounter: encounter, enabled: isActive && !isAnimating)
        landscape.setEncounter(heroHP: encounter.playerHP, enemyHP: encounter.enemyHP,
                               shield: encounter.shield, selected: encounter.enemySelected,maximumHP:encounter.playerMaxHP)
        stageTitle.text = phase == .exploration ? "Meadow Journey · 林地地图" : "Meadow Journey · 鹿灵遭遇"
        setNeedsLayout()
        onLayoutChanged?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        party.frame=bounds
        partyButton.isHidden=partyMode
        let layout = MeadowBattleLayout(size: bounds.size, safeArea: safeAreaInsets, mode: mode)
        header.frame = layout.header
        mapBorder.frame = mapFrame
        partyButton.frame=CGRect(x:mapFrame.maxX-150,y:mapFrame.minY+12,width:136,height:34)
        mapTitle.frame = CGRect(x: mapFrame.minX + 12, y: mapFrame.minY + 12, width: 180, height: 32)
        landscape.frame = layout.battlefield; track.frame = layout.track; details.frame = layout.details
        stageTitle.frame = CGRect(x: 16, y: 12, width: min(300, max(1, landscape.bounds.width - 32)), height: 32)
        let buttonWidth: CGFloat = 178
        let closeWidth: CGFloat = 112
        closeButton.frame = CGRect(x: header.bounds.width - closeWidth - 12, y: (header.bounds.height - 44) / 2,
                                   width: closeWidth, height: 44)
        primaryButton.frame = CGRect(x: closeButton.frame.minX - buttonWidth - 8, y: closeButton.frame.minY,
                                     width: buttonWidth, height: 44)
        let textWidth = max(1, primaryButton.frame.minX - 28)
        actor.frame = CGRect(x: 16, y: 8, width: textWidth, height: 32)
        subtitle.frame = CGRect(x: 16, y: 43, width: textWidth, height: 23)
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // The party battle's pull tab sits on the map's edge, and with the map drawer closed the battlefield covers the map: those touches stay here.
        if partyMode,let hit=super.hitTest(point,with:event),party.mapHidden || hit.accessibilityIdentifier=="battleMapDrawer" { return hit }
        if mapFrame.contains(point),(partyMode || !partyButton.frame.contains(point)) { return nil }
        return super.hitTest(point, with: event)
    }
}

final class MeadowTurnTrackView: UIView {
    private let line = CAShapeLayer()
    private let completed = CAShapeLayer()
    private var ids = ["P1", "敌1"]
    private var tokens: [MeadowTurnTokenView] = []
    private var current = 0
    override init(frame: CGRect) {
        super.init(frame: frame); MeadowPreviewPalette.stylePanel(self)
        line.strokeColor = MeadowPreviewPalette.muted.withAlphaComponent(0.35).cgColor; line.lineWidth = 5
        completed.strokeColor = MeadowPreviewPalette.gold.cgColor; completed.lineWidth = 5
        layer.addSublayer(line); layer.addSublayer(completed)
        for id in ids { let token = MeadowTurnTokenView(id: id); tokens.append(token); addSubview(token) }
        show(phase: .playerTurn, round: 1)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show(phase: MeadowBattlePhase, round: Int) {
        let player = phase == .playerTurn || phase == .victory || phase == .defeat
        current = player ? 0 : 1
        let donePlayer = phase == .enemyPreparing || phase == .enemyTurn
        for (index, token) in tokens.enumerated() {
            token.show(current: index == current, done: index == 0 && donePlayer,
                       badge: index == 1 && phase == .victory ? "✓" : index == 1 && phase == .defeat ? "!" : "")
            token.accessibilityLabel = index == 0 ? "P1，第\(round)轮" : "鹿灵，第\(round)轮"
        }
        setNeedsLayout()
    }
    func show(ids:[String],names:[String:String],current:String?,done:Set<String>,down:Set<String>) {
        if self.ids != ids {
            tokens.forEach { $0.removeFromSuperview() };self.ids=ids
            tokens=ids.map { MeadowTurnTokenView(id:$0) };tokens.forEach(addSubview)
        }
        self.current=ids.firstIndex(of:current ?? "") ?? 0
        for (i,id) in ids.enumerated() {
            tokens[i].setName(names[id] ?? id)
            tokens[i].show(current:id==current,done:done.contains(id),badge:down.contains(id) ? "!":"")
        }
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let step = bounds.width / CGFloat(tokens.count)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let y = min(34, bounds.height * 0.46)
        let path = UIBezierPath(); path.move(to: CGPoint(x: step / 2, y: y)); path.addLine(to: CGPoint(x: bounds.width - step / 2, y: y)); line.path = path.cgPath
        let done = UIBezierPath(); done.move(to: CGPoint(x: step / 2, y: y)); done.addLine(to: CGPoint(x: step * (CGFloat(current) + 0.5), y: y)); completed.path = done.cgPath
        for (index, token) in tokens.enumerated() { token.frame = CGRect(x: CGFloat(index) * step, y: 0, width: step, height: bounds.height) }
    }
}

private final class MeadowTurnTokenView: UIView {
    private let circle = UIView()
    private let portrait = UIImageView()
    private let name: UILabel
    private let marker = MeadowPreviewPalette.label("▼", size: 11, weight: .bold)
    private let badge = MeadowPreviewPalette.label("", size: 17, weight: .bold)
    private let id: String
    private static let portraits: [UIImage?] = (1...3).map { index in
        guard let atlas = UIImage(named: "Hero\(index)Directions")?.cgImage else { return nil }
        let cell = atlas.height / HeroFrames.atlasRows
        return atlas.cropping(to: CGRect(x: 0, y: 0, width: cell, height: cell)).map { UIImage(cgImage: $0) }
    }
    init(id: String) {
        self.id = id; name = MeadowPreviewPalette.label(id == "敌1" ? "鹿灵" : id, size: 15, weight: .bold)
        super.init(frame: .zero); isAccessibilityElement = true
        accessibilityIdentifier = "previewQueue\(id)"
        accessibilityLabel = id
        circle.backgroundColor = MeadowPreviewPalette.card; circle.layer.borderWidth = 1.5
        addSubview(circle); addSubview(portrait); addSubview(name); addSubview(marker); addSubview(badge)
        name.textAlignment = .center; marker.textAlignment = .center; badge.textAlignment = .center
        marker.textColor = MeadowPreviewPalette.gold
        portrait.contentMode = .scaleAspectFit; portrait.layer.magnificationFilter = .nearest
        if id.lowercased().hasPrefix("p"), let number = Int(id.dropFirst()) { portrait.image = Self.portraits[(number - 1) % Self.portraits.count] }
        else { portrait.image = UIImage(systemName: "pawprint.fill"); portrait.tintColor = MeadowPreviewPalette.gold }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setName(_ value:String) { name.text=value }
    func show(current: Bool, done: Bool, badge value: String) {
        marker.isHidden = !current
        circle.layer.borderColor = (current || done ? MeadowPreviewPalette.gold : MeadowPreviewPalette.muted).cgColor
        circle.layer.borderWidth = current ? 3 : 1.5
        badge.text = value.isEmpty && done ? "✓" : value
        badge.textColor = value == "!" ? .systemRed : MeadowPreviewPalette.gold
        portrait.alpha = value == "!" ? 0.38 : 1
        accessibilityValue = current ? "当前行动" : done ? "已行动" : "待行动"
    }
    override func layoutSubviews() {
        super.layoutSubviews(); let side = min(44, bounds.height - 25)
        guard bounds.width > 0, bounds.height > 25 else { return }
        circle.frame = CGRect(x: (bounds.width - side) / 2, y: 12, width: side, height: side)
        circle.layer.cornerRadius = side / 2; portrait.frame = circle.frame.insetBy(dx: 5, dy: 4)
        marker.frame = CGRect(x: circle.frame.midX - 8, y: 0, width: 16, height: 13)
        badge.frame = CGRect(x: circle.frame.maxX - 10, y: 8, width: 20, height: 20)
        name.frame = CGRect(x: 0, y: circle.frame.maxY + 2, width: bounds.width, height: 16)
    }
}

private final class MeadowPlayerDetailsView: UIView {
    var hasWeapon=true
    var onAction: ((MeadowBattleAction) -> Void)?
    var onPreview: ((MeadowBattleAction?) -> Void)?
    private var focusedAction: MeadowBattleAction?
    private let health=MeadowBattleResourceBar()
    private let ward=MeadowBattleResourceBar()
    private let actions=MeadowBattleActionPointsView()
    private let buff=MeadowBattleBuffTile(type:.system)
    private let accessory=MeadowAccessoryBadge(type:.system)
    func dismissAccessory() { accessory.dismiss() }
    var accessoryReadout:AccessoryReadout?
    weak var accessoryHost:UIView?
    private var cards: [MeadowPreviewCard] = []
    override init(frame: CGRect) {
        super.init(frame: frame); MeadowPreviewPalette.stylePanel(self)
        health.accessibilityIdentifier="previewHealthBar";ward.accessibilityIdentifier="previewShieldBar";actions.accessibilityIdentifier="previewActionBar"
        [health,ward,actions,buff,accessory].forEach(addSubview)
        buff.layer.zPosition=200
        let definitions: [(String, MeadowBattleAction)] = [("强击", .strike), ("喘息", .breathe), ("简易防护", .protection)]
        for (title, action) in definitions {
            let card = MeadowPreviewCard(title: title, text: "")
            card.previewStrength = action == .strike ? 0.9 : 0.28
            card.previewColor = action == .protection ? .systemCyan : action == .breathe ? .systemGreen : MeadowPreviewPalette.gold
            card.button.addAction(UIAction { [weak self] _ in self?.onAction?(action) }, for: .touchUpInside)
            card.onFocus = { [weak self] active in
                guard let self else { return }
                if active { self.focusedAction = action; self.onPreview?(action) }
                else if self.focusedAction == action { self.focusedAction = nil; self.onPreview?(nil) }
            }
            card.button.accessibilityIdentifier = "battleAction\(title)"
            addSubview(card); cards.append(card)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show(encounter: MeadowBattleEncounter, enabled: Bool) {
        health.show("生命",value:encounter.playerHP,maximum:encounter.playerMaxHP,color:.systemGreen)
        ward.show("护盾",value:encounter.shield,maximum:8,color:.systemCyan)
        actions.show(value:encounter.actionPoints,maximum:encounter.playerTurnAP)
        accessory.show(accessoryReadout,host:accessoryHost)
        buff.show(shield:encounter.shield)
        let canAct = enabled && encounter.isPlayerActionEnabled
        if !canAct { focusedAction = nil; onPreview?(nil) }
        cards[0].update(title: "强击 · 1 AP", detail: "选中鹿灵造成\(encounter.strikeDamage)点伤害", enabled: canAct && hasWeapon && encounter.enemySelected && encounter.enemyHP > 0)
        cards[1].update(title: "喘息 · 1 AP", detail: "恢复4生命 · 余\(encounter.breathUses)次", enabled: canAct && encounter.breathUses > 0 && encounter.playerHP < encounter.playerMaxHP)
        cards[2].update(title: "简易防护 · 1 AP", detail: "获得4护盾 · 余\(encounter.guardUses)次", enabled: canAct && encounter.guardUses > 0)
    }
    override func layoutSubviews() {
        super.layoutSubviews(); guard bounds.width > 0, bounds.height > 0 else { return }
        let gap:CGFloat=10
        let barWidth=max(1,(bounds.width-28-100-gap*3)/3)
        for (i,bar) in [health,ward,actions].enumerated() { bar.frame=CGRect(x:14+CGFloat(i)*(barWidth+gap),y:9,width:barWidth,height:43) }
        buff.frame=CGRect(x:bounds.width-58,y:8,width:44,height:44)
        accessory.frame=CGRect(x:bounds.width-100,y:10,width:38,height:38)
        let width=max(1,(bounds.width-28-gap*2)/3)
        for (index,card) in cards.enumerated() {
            card.frame=CGRect(x:14+CGFloat(index)*(width+gap),y:62,width:width,height:max(1,bounds.height-72))
        }
    }
}

final class MeadowSkillButton: UIButton {
    var onFocus: ((Bool) -> Void)?
    private var hovering = false
    override var isHighlighted: Bool { didSet { updatePreview() } }
    override var isEnabled: Bool { didSet { if !isEnabled { hovering = false }; updatePreview() } }
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator); updatePreview()
    }
    func installHover() {
        isPointerInteractionEnabled = true
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
    }
    @objc private func hover(_ recognizer: UIHoverGestureRecognizer) {
        hovering = recognizer.state == .began || recognizer.state == .changed
        updatePreview()
    }
    private func updatePreview() { onFocus?(isEnabled && (hovering || isHighlighted || isFocused)) }
}

final class MeadowPreviewCard: UIView {
    private let title = MeadowPreviewPalette.label("", size: 20, weight: .heavy)
    private let detail = MeadowPreviewPalette.label("", size: 17, weight: .semibold)
    let button = MeadowSkillButton(type: .system)
    var onFocus: ((Bool) -> Void)?
    var previewStrength: Float = 0.9
    var previewColor = MeadowPreviewPalette.gold
    init(title titleText: String, text: String) {
        super.init(frame: .zero); backgroundColor = MeadowPreviewPalette.card
        layer.cornerRadius = 9; detail.numberOfLines = 2
        button.installHover()
        button.onFocus = { [weak self] active in
            guard let self else { return }
            self.layer.shadowColor = self.previewColor.cgColor
            self.layer.shadowRadius = 12; self.layer.shadowOpacity = active ? self.previewStrength * 0.85 : 0
            self.layer.shadowOffset = .zero
            self.onFocus?(active)
        }
        title.text = titleText; detail.text = text
        addSubview(title); addSubview(detail); addSubview(button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(title titleText: String, detail detailText: String, enabled: Bool) {
        title.text = titleText; detail.text = detailText
        button.isEnabled = enabled
        alpha = enabled || button.isHidden ? 1 : 0.46
        layer.borderWidth = enabled ? 1 : 0
        layer.borderColor = MeadowPreviewPalette.gold.withAlphaComponent(0.65).cgColor
        button.accessibilityLabel = "\(titleText). \(detailText)"
        button.accessibilityValue = enabled ? "可用" : "不可用"
        button.backgroundColor = enabled ? UIColor.white.withAlphaComponent(0.03) : .clear
        button.isUserInteractionEnabled = enabled
    }
    override func layoutSubviews() {
        super.layoutSubviews(); guard bounds.width > 0, bounds.height > 0 else { return }
        title.frame = CGRect(x: 10, y: 6, width: max(1, bounds.width - 20), height: 27)
        detail.frame = CGRect(x: 10, y: 35, width: max(1, bounds.width - 20), height: max(1, bounds.height - 40))
        button.frame = bounds
    }
}

struct MeadowBattleCanvasGeometry {
    static let sourceCanvas = CGSize(width: 1309, height: 1201)
    static let sceneLayerOrder = ["MeadowCampFarForest", "MeadowCampGround", "MeadowCampMidground", "MeadowCampForeground"]
    static let enemyImageSize = CGSize(width: 384, height: 256)
    static let enemyAlphaBounds = CGRect(x: 13, y: 9, width: 331, height: 232)
    static let enemyFoot = CGPoint(x: 0.65, y: 0.685)
    static let heroFoot = CGPoint(x: 0.29, y: 0.69)
    static let heroVisibleHeight: CGFloat = 0.17
    static let enemyVisibleHeight: CGFloat = 0.33

    static func fittedCanvas(in bounds: CGRect) -> CGRect {
        // The battle card gets taller on monster turns. Fit the world to its
        // stable width so actor scale and camera zoom do not jump with height.
        let scale = bounds.width / sourceCanvas.width
        let size = CGSize(width: sourceCanvas.width * scale, height: sourceCanvas.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.minY,
                      width: size.width, height: size.height)
    }

    static func backdropTransform(for outputSize: CGSize) -> CGAffineTransform {
        let scale = outputSize.width / sourceCanvas.width
        // Core Image's Y axis starts at the bottom. Align the source's top with
        // the output top so any clamped extension appears below the scene.
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: 0,
                                 ty: outputSize.height - sourceCanvas.height * scale)
    }

    static func registeredSpriteFrame(imageSize: CGSize, alphaBounds: CGRect, foot: CGPoint,
                                      visibleHeight: CGFloat, canvas: CGRect) -> CGRect {
        let scale = canvas.height * visibleHeight / alphaBounds.height
        let footPoint = CGPoint(x: canvas.minX + canvas.width * foot.x,
                                y: canvas.minY + canvas.height * foot.y)
        return CGRect(x: footPoint.x - (alphaBounds.midX * scale),
                      y: footPoint.y - (alphaBounds.maxY * scale),
                      width: imageSize.width * scale, height: imageSize.height * scale)
    }

    static func actorFrame(configuration: MeadowBattleActorConfiguration, canvas: CGRect) -> CGRect {
        let scale = canvas.height * heroVisibleHeight / configuration.referenceHeightPx
        return CGRect(x: canvas.minX + canvas.width * heroFoot.x - configuration.footAnchor.x * scale,
                      y: canvas.minY + canvas.height * heroFoot.y - configuration.footAnchor.y * scale,
                      width: configuration.canvasSize.width * scale, height: configuration.canvasSize.height * scale)
    }
}

/// A square status token: details are disclosed on pointer hover, focus or tap.
final class MeadowBattleBuffTile: UIButton {
    private let tip=UILabel()
    private var amount=0
    private var pinned=false
    private var hovering=false
    override init(frame:CGRect) {
        super.init(frame:frame)
        backgroundColor=MeadowPreviewPalette.card;layer.cornerRadius=6;layer.borderWidth=2;layer.borderColor=UIColor.systemCyan.cgColor
        setImage(UIImage(systemName:"shield.fill"),for:.normal);tintColor = .systemCyan
        setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize:24,weight:.bold),forImageIn:.normal)
        accessibilityLabel="防护状态";accessibilityHint="点按显示或隐藏详情"
        isPointerInteractionEnabled=true
        addGestureRecognizer(UIHoverGestureRecognizer(target:self,action:#selector(hover(_:))))
        addAction(UIAction { [weak self] _ in guard let self else { return }; self.pinned.toggle();self.refreshTip() },for:.touchUpInside)
        tip.numberOfLines=0;tip.font=MeadowPreviewPalette.font(18);tip.textColor=MeadowPreviewPalette.ink
        tip.backgroundColor=MeadowPreviewPalette.panel;tip.layer.cornerRadius=8;tip.layer.borderWidth=1;tip.layer.borderColor=MeadowPreviewPalette.gold.cgColor;tip.clipsToBounds=true
        tip.isUserInteractionEnabled=false;tip.isHidden=true;addSubview(tip)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show(shield:Int) {
        amount=shield;isHidden=shield<=0
        if isHidden { pinned=false;hovering=false }
        accessibilityValue="剩余\(shield)点，优先抵挡伤害，耗尽时破碎"
        tip.text="  防护 · 剩余 \(shield) 点\n  优先抵挡伤害\n  持续至耗尽，破碎后移除"
        refreshTip()
    }
    @objc private func hover(_ r:UIHoverGestureRecognizer) { hovering=r.state == .began || r.state == .changed;refreshTip() }
    private func refreshTip() { tip.isHidden=amount<=0 || !(hovering || pinned || isFocused) }
    override func didUpdateFocus(in context:UIFocusUpdateContext,with coordinator:UIFocusAnimationCoordinator) { super.didUpdateFocus(in:context,with:coordinator);refreshTip() }
    override func layoutSubviews() { super.layoutSubviews();tip.frame=CGRect(x:bounds.width-288,y:-100,width:288,height:90) }
    override func didMoveToWindow() { super.didMoveToWindow();if window==nil { pinned=false;hovering=false;refreshTip() } }
}
