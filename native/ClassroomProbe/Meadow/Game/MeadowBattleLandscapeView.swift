import UIKit
import CoreImage
import MeadowBattleSupport

final class MeadowBattleLandscapeView: UIView {
    private let canvas = UIView()
    private let world = UIView()
    private let cameraBackdrop = UIImageView()
    private let canvasFeatherMask = CAGradientLayer()
    private var cameraBackdropRenderSize = CGSize.zero
    private let farForest = UIImageView(image: MeadowBattlePlateProcessor.image(named: "MeadowCampFarForest", role: .farForest))
    private let ground = UIImageView(image: MeadowBattlePlateProcessor.image(named: "MeadowCampGround", role: .ground))
    private let midground = UIImageView(image: MeadowBattlePlateProcessor.image(named: "MeadowCampMidground", role: .midground))
    private let foreground = UIImageView(image: UIImage(named: "MeadowCampForeground"))
    private let hero: MeadowBattleActorView
    private let enemy: MeadowBattleEnemyTargetView
    private let heroShadow: MeadowBattleGroundingView
    private let enemyShadow: MeadowBattleGroundingView
    private let backdropDim = UIView()
    private let backgroundDim = UIView()
    private let foregroundDim = UIImageView()
    private let enemyDim = UIImageView()
    private let deathWind = UIImageView()
    private let groundEffects = MeadowBattleEffectsView()
    private let heroFlash = UIImageView()
    private let enemyFlash = UIImageView()
    var onEnemySelected: (() -> Void)?
    private let diceView=MeadowBattleDiceView()
    private var diceVisibleAt=0.0,diceSettledAt:Double?,diceExitAt:Double?,diceCastAt:Double?
    private var diceAtEnemy=false
    private var diceCastFrom:CGFloat=0
    private let clock = MeadowBattleSceneClock()
    private let effects = MeadowBattleEffectsView()
    private let attachedSkills = MeadowBattleAttachedSkillsView(frame:.zero)
    private var recoveryStartedAt: Double?
    private let heroStatus = MeadowBattleVitalsView()
    private let enemyStatus = MeadowBattleVitalsView()
    private var baseHeroFrame = CGRect.zero
    private var baseEnemyFrame = CGRect.zero
    private var cue: MeadowBattleAnimationCue?
    private var cueElapsed: TimeInterval = 0
    private var cueDuration: TimeInterval = 1.2
    private var completion: (() -> Void)?
    private var impactHandler: (() -> MeadowBattleActionResult?)?
    private var impactClock = MeadowBattleImpactClock(duration: 1, impactTime: nil)
    private var sceneTime = 0.0
    private var focusedAction: MeadowBattleAction?
    private var focusStartedAt = 0.0
    private var previewExitDim: CGFloat = 0
    private var castInitialDim: CGFloat = 0
    private var castLightAt: Double?
    private var lastImpactAt: Double?
    private var lastImpactCue: MeadowBattleAnimationCue?
    private var deathStartedAt: Double?
    private var lastDeathFrame = -1
    private var savedImpact = CGPoint.zero
    private var attackContactPoint = CGPoint.zero
    private var usesStaff=false
    private let staffEffects=MeadowStaffEffectsView(frame:.zero)
    private var usesBow=false
    private var usesGreatSword=false
    private let greatSwordTrail=CAShapeLayer()
    private let bowArrow=CAShapeLayer()
    private var lightEmissions: [MeadowBattleLightEmission] = []
    private var shieldFormationBase=0.0
    private var shieldFormationAt: Double?
    private var shieldBirthAt: Double?
    private var shieldContactAt: Double?
    private var shieldBreakAt: Double?
    private var idleElapsed: TimeInterval = 0
    private var recoveryTier: HealingEffectTier?
    private var terminalClip: String?
    private var heroHP = 12
    private var heroMaxHP = 12
    private var enemyHP = 18
    private var shieldValue = 0
    private var shownHeroHP = 12
    private var shownEnemyHP = 18
    private var shownShieldValue = 0
    private var selected = false
    private var lastShadowPose = ""
    private var lastEnemyPose = -1
    private var hitWasBlocked = false
    private var enemyMeetsShield = false
    private var enemyMotionDuration: TimeInterval { Double(MeadowBattleEnemyFrames.attack.count) * 0.12 }

    private var sceneLayers: [UIImageView] { [farForest, ground, midground, foreground] }

    var sceneLayerOrder: [String] { sceneLayers.compactMap(\.accessibilityIdentifier) }
    var sceneLayerFrames: [CGRect] { sceneLayers.map(\.frame) }
    var sceneCanvasFrame: CGRect { canvas.frame }
    var cameraBackdropFrame: CGRect { cameraBackdrop.frame }
    var cameraBackdropContentMode: UIView.ContentMode { cameraBackdrop.contentMode }
    var cameraBackdropClipsToBounds: Bool { cameraBackdrop.clipsToBounds }
    var sceneCanvasSubviewOrder: [String] { (world.subviews + canvas.subviews.filter { $0 !== world }).compactMap(\.accessibilityIdentifier) }
    var heroViewFrame: CGRect { hero.frame }
    var heroLayerNames: [String] { hero.layerNames }
    var enemyViewFrame: CGRect { enemy.frame }
    var enemyIsMirrored: Bool { enemy.transform.a < 0 }

    override init(frame: CGRect) {
        let actor = MeadowBattleActorView(frame: .zero)
        hero = actor
        let enemyImage = UIImage(named: "MeadowBattleForestWarden")
        enemy = MeadowBattleEnemyTargetView(image: enemyImage)
        heroShadow = MeadowBattleGroundingView(image: actor.silhouette, soleY: 214, contacts: [
            .init(point: CGPoint(x: 98, y: 214), radius: 12),
            .init(point: CGPoint(x: 146, y: 214), radius: 12)
        ])
        enemyShadow = MeadowBattleGroundingView(image: enemyImage, soleY: 241, contacts: [
            .init(point: CGPoint(x: 84, y: 240), radius: 16),
            .init(point: CGPoint(x: 172, y: 240), radius: 16),
            .init(point: CGPoint(x: 230, y: 239), radius: 16),
            .init(point: CGPoint(x: 314, y: 240), radius: 17)
        ])
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = 14
        layer.borderWidth = 1
        layer.borderColor = UIColor(red: 0.91, green: 0.81, blue: 0.58, alpha: 0.7).cgColor

        cameraBackdrop.contentMode = .scaleToFill
        cameraBackdrop.clipsToBounds = true
        cameraBackdrop.alpha = 0.82
        cameraBackdrop.accessibilityIdentifier = "meadowBattleCameraBackdrop"
        addSubview(cameraBackdrop)
        backdropDim.backgroundColor = .black; backdropDim.isUserInteractionEnabled = false
        addSubview(backdropDim)

        canvas.clipsToBounds = true
        canvasFeatherMask.startPoint = CGPoint(x: 0.5, y: 0)
        canvasFeatherMask.endPoint = CGPoint(x: 0.5, y: 1)
        canvasFeatherMask.colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.clear.cgColor]
        canvasFeatherMask.locations = [0, 0.88, 1]
        canvas.layer.mask = canvasFeatherMask
        canvas.accessibilityIdentifier = "meadowBattleSceneCanvas"
        addSubview(canvas)
        canvas.addSubview(world)
        for (index, imageView) in sceneLayers.enumerated() {
            imageView.accessibilityIdentifier = MeadowBattleCanvasGeometry.sceneLayerOrder[index]
            imageView.contentMode = .scaleToFill
            imageView.isAccessibilityElement = false
            imageView.layer.minificationFilter = .linear
            imageView.layer.magnificationFilter = .linear
            world.addSubview(imageView)
        }
        configureShadow(heroShadow, identifier: "meadowBattleHeroShadow")
        configureShadow(enemyShadow, identifier: "meadowBattleForestWardenShadow")
        world.addSubview(heroShadow)
        world.addSubview(enemyShadow)
        backgroundDim.backgroundColor = .black; backgroundDim.isUserInteractionEnabled = false
        world.addSubview(backgroundDim)
        groundEffects.groundOnly = true; world.addSubview(groundEffects)

        hero.accessibilityIdentifier = "meadowBattleHero"
        hero.isAccessibilityElement = true
        hero.accessibilityLabel = "Meadow Journey 冒险者，向右侧向备战，独立头发、五官、衣物与短剑"
        world.addSubview(hero)
        hero.addSubview(attachedSkills)
        world.addSubview(heroFlash)

        enemy.accessibilityIdentifier = "meadowBattleForestWarden"
        enemy.isAccessibilityElement = true
        enemy.accessibilityLabel = "林地鹿灵敌方单位示意，朝左站立警戒"
        enemy.contentMode = .scaleToFill
        enemy.layer.minificationFilter = .nearest
        enemy.layer.magnificationFilter = .nearest
        world.addSubview(enemy)
        world.addSubview(enemyFlash)
        enemyDim.isUserInteractionEnabled = false; enemyDim.contentMode = .scaleToFill
        world.addSubview(enemyDim)
        deathWind.isUserInteractionEnabled = false; deathWind.contentMode = .scaleToFill
        deathWind.layer.magnificationFilter = .nearest; world.addSubview(deathWind)
        for flash in [heroFlash, enemyFlash] {
            flash.isUserInteractionEnabled = false; flash.isAccessibilityElement = false
            flash.contentMode = .scaleToFill; flash.alpha = 0
            flash.layer.magnificationFilter = .nearest
        }

        world.addSubview(foreground)
        foregroundDim.image = foreground.image?.withTintColor(.black, renderingMode: .alwaysOriginal)
        foregroundDim.contentMode = .scaleToFill; foregroundDim.isUserInteractionEnabled = false
        world.addSubview(foregroundDim)
        effects.accessibilityIdentifier = "battleCombatEffects"
        world.addSubview(effects)
        for label in [heroStatus, enemyStatus] { canvas.addSubview(label) }
        canvas.addSubview(diceView)
        MeadowBattleVFXAssets.prewarm()
        heroStatus.accessibilityIdentifier = "battleHeroHealth"
        enemyStatus.accessibilityIdentifier = "battleEnemyHealth"
        enemy.isUserInteractionEnabled = true
        enemy.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectEnemy)))
        enemy.onActivate = { [weak self] in self?.onEnemySelected?() }
        enemy.accessibilityTraits = .button
        clock.onTick = { [weak self] delta in self?.advanceAnimation(delta) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static let blurredCameraPlate: CIImage? = {
        let size = MeadowBattleCanvasGeometry.sourceCanvas
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let plate = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            for name in MeadowBattleCanvasGeometry.sceneLayerOrder {
                UIImage(named: name)?.draw(in: rect)
            }
        }
        guard let cgImage = plate.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        let blur = CIFilter(name: "CIGaussianBlur")
        blur?.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        blur?.setValue(18, forKey: kCIInputRadiusKey)
        let blurred = blur?.outputImage?.cropped(to: input.extent)
        let controls = CIFilter(name: "CIColorControls")
        controls?.setValue(blurred, forKey: kCIInputImageKey)
        controls?.setValue(0.75, forKey: kCIInputSaturationKey)
        controls?.setValue(0.92, forKey: kCIInputContrastKey)
        return (controls?.outputImage?.cropped(to: input.extent) ?? blurred ?? input).clampedToExtent()
    }()

    private static let cameraBackdropContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Render the soft plate with the exact horizontal scale and top anchor of
    /// the sharp canvas. Clamping its blurred lower edge fills any extra height
    /// without stretching the scene or creating a second camera transform.
    private static func makeCameraBackdrop(for viewport: CGSize) -> UIImage? {
        guard viewport.width > 0, viewport.height > 0,
              let plate = blurredCameraPlate else { return nil }
        let outputRect = CGRect(x: 0, y: 0,
                                width: viewport.width.rounded(.up), height: viewport.height.rounded(.up))
        let transform = MeadowBattleCanvasGeometry.backdropTransform(for: outputRect.size)
        let aligned = plate.transformed(by: transform)
        guard let image = cameraBackdropContext.createCGImage(aligned, from: outputRect) else { return nil }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    private func configureShadow(_ shadow: UIView, identifier: String) {
        shadow.accessibilityIdentifier = identifier
        shadow.isUserInteractionEnabled = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if cameraBackdropRenderSize != bounds.size || cameraBackdrop.image == nil {
            cameraBackdrop.image = Self.makeCameraBackdrop(for: bounds.size)
            cameraBackdropRenderSize = bounds.size
        }
        let fitted = MeadowBattleCanvasGeometry.fittedCanvas(in: bounds)
        cameraBackdrop.frame = bounds; backdropDim.frame = bounds
        canvas.frame = fitted
        canvasFeatherMask.frame = canvas.bounds
        let canvasBounds = canvas.bounds
        world.transform = .identity; world.frame = canvasBounds
        sceneLayers.forEach { $0.frame = canvasBounds }

        if let configuration = hero.configuration {
            baseHeroFrame = MeadowBattleCanvasGeometry.actorFrame(configuration: configuration, canvas: canvasBounds)
        }
        let enemyFrame = MeadowBattleCanvasGeometry.registeredSpriteFrame(
            imageSize: MeadowBattleCanvasGeometry.enemyImageSize,
            alphaBounds: MeadowBattleCanvasGeometry.enemyAlphaBounds,
            foot: MeadowBattleCanvasGeometry.enemyFoot, visibleHeight: MeadowBattleCanvasGeometry.enemyVisibleHeight,
            canvas: canvasBounds)
        baseEnemyFrame = enemyFrame

        heroShadow.frame = canvasBounds
        heroShadow.spriteFrame = baseHeroFrame
        enemyShadow.frame = canvasBounds
        enemyShadow.spriteFrame = enemyFrame
        effects.frame = canvasBounds; groundEffects.frame = canvasBounds
        backgroundDim.frame = canvasBounds; foregroundDim.frame = canvasBounds
        renderAnimation()
    }

    func configureArmor(_ id:String?) { hero.setArmor(id);lastShadowPose="";renderAnimation() }
    func configureWeapon(_ asset:String?) { usesStaff=asset=="MeadowBattleLegendaryStaff";usesGreatSword=asset=="MeadowBattleGreatSword";usesBow=asset=="MeadowBattleHuntingBow";if bowArrow.superlayer==nil { world.layer.addSublayer(bowArrow);bowArrow.zPosition=1000;bowArrow.strokeColor=MeadowPreviewPalette.ink.cgColor;bowArrow.lineWidth=2;bowArrow.shadowColor=MeadowPreviewPalette.gold.cgColor;bowArrow.shadowOpacity=0.7;bowArrow.shadowRadius=5 };if greatSwordTrail.superlayer==nil { world.layer.addSublayer(greatSwordTrail);greatSwordTrail.zPosition=999;greatSwordTrail.fillColor=UIColor.clear.cgColor;greatSwordTrail.strokeColor=MeadowPreviewPalette.ink.cgColor;greatSwordTrail.lineWidth=2.5;greatSwordTrail.lineCap = .round;greatSwordTrail.shadowColor=MeadowPreviewPalette.gold.cgColor;greatSwordTrail.shadowRadius=6;greatSwordTrail.shadowOpacity=0.8 };if staffEffects.superview==nil { world.addSubview(staffEffects);staffEffects.layer.zPosition=1000 };hero.setWeaponAsset(asset);lastShadowPose="";renderAnimation() }
    @objc private func selectEnemy() { onEnemySelected?() }

    func setEncounter(heroHP: Int, enemyHP: Int, shield: Int, selected: Bool,maximumHP:Int=12) {
        let reset = enemyHP > self.enemyHP || (self.heroHP == 0 && heroHP > 0)
        self.heroHP = heroHP;self.heroMaxHP=maximumHP; self.enemyHP = enemyHP; shieldValue = shield
        self.selected = selected && enemyHP > 0
        if reset {
            terminalClip = nil; deathStartedAt = nil; lastDeathFrame = -1
            castLightAt = nil; lastImpactAt = nil; lastEnemyPose = -1
            shieldFormationAt=nil; shieldBirthAt=nil; shieldContactAt=nil; shieldBreakAt=nil; recoveryStartedAt=nil; lightEmissions.removeAll()
            enemy.alpha = 1; enemyShadow.alpha = 1; hero.alpha = 1
        }
        refreshHealth()
        enemy.isUserInteractionEnabled = enemyHP > 0
        enemy.accessibilityValue = "生命 \(enemyHP)/18，\(selected ? "已选中" : "点击选择目标")"
        if !isHidden, window != nil { clock.start() }
    }

    private func smooth(_ x: Double) -> CGFloat { let t = min(1,max(0,x)); return CGFloat(t*t*(3-2*t)) }
    private func darkness() -> CGFloat {
        let recoverDim=recoveryStartedAt.map { CGFloat(MeadowBattleRecoveryField.pulse(sceneTime-$0))*0.30 } ?? 0
        let handoff=diceCastAt.map { diceCastFrom*(1-smooth((sceneTime-$0)/1.0)) } ?? 0
        let supportDim=max(recoverDim,handoff)
        if let at = castLightAt, sceneTime-at < 3.36 {
            let t=sceneTime-at
            let envelope=(castInitialDim+(0.64-castInitialDim)*smooth(t/0.44))*(1-smooth((t-2)/1.36))
            let peak=lastImpactAt.map { at -> CGFloat in
                guard lastImpactCue == .strike else { return 0 }
                let age=sceneTime-at
                return age<0.035 ? smooth(age/0.035) : 1-smooth((age-0.035)/0.19)
            } ?? 0
            return max(supportDim,max(envelope,0.82*peak))
        }
        let target: CGFloat = focusedAction == .strike ? 0.45 : focusedAction == .breathe ? 0.24 : focusedAction == .protection ? 0.25:0
        let fade=smooth((sceneTime-focusStartedAt)/0.28)
        return max(supportDim,previewExitDim+(target-previewExitDim)*fade)
    }

    func preview(_ action: MeadowBattleAction?) {
        guard cue == nil, focusedAction != action else { return }
        previewExitDim = darkness(); focusStartedAt = sceneTime; focusedAction = action
        if let action {
            diceVisibleAt=sceneTime;diceSettledAt=nil;diceExitAt=nil;diceAtEnemy=false
            let color=action == .strike ? "red":action == .breathe ? "green":"blue"
            diceView.dice=[BattleDie(color,value:action == .strike ? 5:4,label:action == .strike ? "固定伤害":"固定值")]
        } else { diceExitAt=sceneTime }
        if !isHidden, window != nil { clock.start() }
        renderAnimation()
    }

    func play(_ value: MeadowBattleAnimationCue, onImpact: (() -> MeadowBattleActionResult?)? = nil, completion: @escaping () -> Void) {
        let initial=darkness()
        if [.strike,.enemyStrike,.guardPose,.heal].contains(value) {
            if diceView.dice.isEmpty || diceAtEnemy != (value == .enemyStrike) { diceVisibleAt=sceneTime }
            diceAtEnemy=value == .enemyStrike;diceSettledAt=nil;diceExitAt=nil;diceCastAt=sceneTime;diceCastFrom=initial
            diceView.dice=[BattleDie(value == .heal ? "green":value == .guardPose ? "blue":"red",value:value == .strike ? 5:4,label:"固定值")]
        } else { diceExitAt=sceneTime }
        self.completion = nil; cue = value; cueElapsed = 0
        self.completion = completion; impactHandler = onImpact; terminalClip = nil
        shieldFormationBase = 0
        focusedAction = nil; previewExitDim = 0
        var contact: Double?
        switch value {
        case .strike:
            cueDuration = MeadowBattleImpactClock.strikeDuration
            contact = MeadowBattleImpactClock.strikeContact
            castInitialDim = initial; castLightAt = sceneTime
        case .enemyStrike:
            enemyMeetsShield = shieldValue > 0
            hitWasBlocked = shieldValue >= 4
            cueDuration = ceil(max(enemyMotionDuration,enemyMotionDuration*0.46+(hitWasBlocked ? 0.96 : 0.84))/0.04)*0.04
            contact = enemyMotionDuration*0.46
        case .guardPose: cueDuration = 0.96; contact = 0.46; shieldFormationAt=sceneTime
        case .heal: cueDuration = 1.20; contact = MeadowBattleRecoveryField.impactTime; recoveryStartedAt=nil; recoveryTier=nil
        case .victory: cueDuration = 1.08
        case .defeat: cueDuration = 1.08
        }
        impactClock = MeadowBattleImpactClock(duration: cueDuration, impactTime: contact)
        renderAnimation(); clock.start()
    }

    func cancelAnimations() {
        diceView.dice=[];diceCastAt=nil;diceSettledAt=nil;diceExitAt=nil
        clock.stop(); cue = nil; completion = nil; impactHandler = nil; terminalClip = nil
        deathStartedAt = nil; castLightAt = nil; lastImpactAt = nil; focusedAction = nil
        previewExitDim = 0; castInitialDim = 0; sceneTime = 0; focusStartedAt = 0
        shieldFormationAt=nil; shieldBirthAt=nil; shieldContactAt=nil; shieldBreakAt=nil; recoveryStartedAt=nil; recoveryTier=nil; lightEmissions.removeAll(); world.transform = .identity
        cueElapsed = 0; idleElapsed = 0; effects.cue = nil; effects.message = ""
        hero.setPose(clip: "idle", progress: 0); hero.alpha = 1; enemy.alpha = 1
        enemy.image = MeadowBattleEnemyFrames.image(progress: 0)
        lastEnemyPose = -1; lastShadowPose = ""; lastDeathFrame = -1
        refreshHealth(); renderAnimation()
    }

    private func refreshHealth() {
        shownHeroHP = heroHP; shownEnemyHP = enemyHP; shownShieldValue = shieldValue
        heroStatus.show(name:"P1",hp:shownHeroHP,maximum:heroMaxHP,shield:shownShieldValue)
        enemyStatus.show(name:"鹿灵",hp:shownEnemyHP,maximum:18,shield:0)
        enemyStatus.isHidden=shownEnemyHP<=0
    }

    private func applyImpact(_ result: MeadowBattleActionResult) {
        lastImpactAt = sceneTime; lastImpactCue = result.cue
        let value=result.cue == .heal ? result.healed:result.cue == .guardPose ? result.shieldGained:result.damage+result.shieldAbsorbed
        diceView.dice=[BattleDie(result.cue == .heal ? "green":result.cue == .guardPose ? "blue":"red",value:value,label:"定值")]
        diceSettledAt=sceneTime
        let unit = baseHeroFrame.width / 256
        let foot = CGPoint(x:hero.frame.minX+hero.poseFootAnchorPx.x*unit,y:hero.frame.minY+hero.poseFootAnchorPx.y*unit)
        func emit(_ kind: MeadowBattleLightKind,_ origin: CGPoint,_ floor: CGFloat) {
            let scale=canvas.bounds.width/760
            guard scale>0 else { return }
            lightEmissions.append(.init(kind:kind,startedAt:sceneTime,x:Double(origin.x/scale),y:Double(origin.y/scale),groundY:Double(floor/scale)))
        }
        switch result.cue {
        case .strike:
            effects.message = "−\(result.damage)"; effects.messageColor = .white
            let floor=baseEnemyFrame.minY+240/256*baseEnemyFrame.height
            emit(.strike,attackContactPoint,floor)
            if enemyHP == 0 { emit(.death,attackContactPoint,floor) }
            if enemyHP == 0, deathStartedAt == nil { deathStartedAt = sceneTime; lastDeathFrame = -1; selected = false }
        case .enemyStrike:
            hitWasBlocked = result.damage == 0
            if result.shieldAbsorbed > 0 {
                shieldContactAt=sceneTime
                emit(.shieldContact,CGPoint(x:hero.frame.minX+CGFloat(MeadowBattleShieldGeometry.contactX)*unit,y:hero.frame.minY+CGFloat(MeadowBattleShieldGeometry.contactY)*unit),foot.y)
                if shieldValue == 0 {
                    shieldBreakAt=sceneTime
                    emit(.shieldBreak,CGPoint(x:hero.frame.minX+CGFloat(MeadowBattleShieldGeometry.centerX)*unit,y:hero.frame.minY+CGFloat(MeadowBattleShieldGeometry.centerY)*unit),foot.y)
                }
            }
            effects.message = hitWasBlocked ? "格挡" : "−\(result.damage)"
            effects.messageColor = hitWasBlocked ? .systemCyan : .systemOrange
        case .heal:
            effects.message = "+\(result.healed)"; effects.messageColor = .systemGreen
            recoveryTier=HealingEffectTier.classify(actualHPGained:result.healed)
            recoveryStartedAt=recoveryTier == nil ? nil:sceneTime
        case .guardPose:
            shieldBirthAt=sceneTime; shieldBreakAt=nil
            effects.message = "护盾 +\(result.shieldGained)"; effects.messageColor = .systemCyan
        default: break
        }
        refreshHealth()
    }

    private func advanceAnimation(_ delta: TimeInterval) {
        guard !isHidden, window != nil else { clock.stop(); return }
        sceneTime += delta; idleElapsed += delta
        lightEmissions.removeAll { sceneTime-$0.startedAt >= 3 }
        if cue != nil {
            let fired = impactClock.advance(delta); cueElapsed = impactClock.elapsed
            if fired { let handler=impactHandler; impactHandler=nil; if let result=handler?() { applyImpact(result) } }
        }
        renderAnimation()
        if let value=cue, cueElapsed >= cueDuration {
            if value == .victory { terminalClip = "victory" }
            if value == .defeat { terminalClip = "defeat" }
            cue=nil; impactHandler=nil
            MeadowBattleFrameTiming.flush()
            let finished=completion; completion=nil; finished?()
        }
    }

    private func renderAnimation() {
        guard baseHeroFrame.width > 0, baseEnemyFrame.width > 0 else { return }
        CATransaction.begin();CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let visualDuration = cue == .enemyStrike ? enemyMotionDuration : cueDuration
        let p = cue == .strike ? CGFloat(min(1,MeadowBattleImpactClock.strikePoseTime(cueElapsed)/1.2)) : CGFloat(min(1,cueElapsed/max(0.01,visualDuration)))
        var clip = terminalClip ?? "idle"
        var poseProgress = terminalClip == nil ? CGFloat(idleElapsed.truncatingRemainder(dividingBy: 2.4) / 2.4) : 1
        var heroTravel: CGFloat = 0, heroLift:CGFloat=0, enemyTravel: CGFloat = 0
        var monsterProgress: CGFloat = 0
        var enemyRecoil: CGFloat = 0
        func transformPoint(_ point: CGPoint, part: MeadowBattleLayerPose) -> CGPoint {
            let dx = point.x - part.pivot.x, dy = point.y - part.pivot.y
            let c = cos(part.rotation) * part.scale, s = sin(part.rotation) * part.scale
            return CGPoint(x: part.pivot.x + part.offset.x + dx * c - dy * s,
                           y: part.pivot.y + part.offset.y + dx * s + dy * c)
        }
        func approach() -> CGFloat {
            if p < 0.12 || p >= 1 { return 0 }
            if p >= 0.40, p <= 0.66 { return 1 }
            let t = p < 0.40 ? (p - 0.12) / 0.28 : (1 - p) / 0.34
            return t * t * (3 - 2 * t)
        }
        func pulse(_ start: CGFloat, _ peak: CGFloat, _ end: CGFloat) -> CGFloat {
            if p < start || p > end { return 0 }
            let t = p < peak ? (p - start) / (peak - start) : (end - p) / (end - peak)
            return t * t * (3 - 2 * t)
        }
        if let cue {
            switch cue {
            case .strike:
                clip = "attack"; poseProgress = usesBow ? CGFloat(BowRig.progress(age:cueElapsed)):usesGreatSword ? CGFloat(GreatSwordRig.progress(age:cueElapsed)):usesStaff ? CGFloat(LegendaryStaffRig.progress(age:cueElapsed)):p
                let contact = MeadowBattleAnimation.sample(clip: "attack", progress: 0.54)
                let tip = transformPoint(CGPoint(x: 191, y: 142), part: contact.layers["MeadowBattleHeroWeapon"] ?? .init())
                let heroReach = baseHeroFrame.minX + (tip.x + contact.rootOffset.x) / 256 * baseHeroFrame.width
                let enemyFront = baseEnemyFrame.minX + 125 / 384 * baseEnemyFrame.width
                heroTravel = usesBow || usesStaff ? 0:min(canvas.bounds.width * 0.22, max(0, enemyFront - heroReach)) * approach()
                if usesGreatSword {
                    let s=Double(baseHeroFrame.width/256)
                    let from=PartyPoint(Double(baseHeroFrame.minX+123*baseHeroFrame.width/256),Double(baseHeroFrame.minY+214*baseHeroFrame.height/256))
                    let to=PartyPoint(Double(baseEnemyFrame.minX+94*baseEnemyFrame.width/384),Double(baseEnemyFrame.minY+152*baseEnemyFrame.height/256))
                    let travel=GreatSwordRig.travel(age:cueElapsed,from:from,to:to,scale:s);heroTravel=CGFloat(travel.x);heroLift=CGFloat(travel.y)
                }
                let age=cueElapsed-MeadowBattleImpactClock.strikeContact
                let recoil=age <= 0.14 ? smooth((age+0.02)/0.16) : 1-smooth((age-0.14)/0.38)
                enemyRecoil = canvas.bounds.width * 0.025 * recoil
            case .enemyStrike:
                monsterProgress = p
                let enemyFront = baseEnemyFrame.minX + 42 / 384 * baseEnemyFrame.width
                let heroCenter = baseHeroFrame.minX + CGFloat(enemyMeetsShield ? MeadowBattleShieldGeometry.contactX : 128) / 256 * baseHeroFrame.width
                enemyTravel = -max(0, enemyFront - heroCenter - (enemyMeetsShield ? 0 : canvas.bounds.width * 0.015)) * pulse(0.08, 0.48, 0.98)
                if p >= 0.46 {
                    clip = hitWasBlocked ? "guard" : "hit"
                    let duration = Double(MeadowBattleAnimation.durationMs(for: clip)) / 1000
                    poseProgress = CGFloat(min(1, (cueElapsed - enemyMotionDuration * 0.46) / duration))
                }
            case .guardPose: clip = "guard"; poseProgress = p
            case .heal: clip = "idle"; poseProgress = p
            case .victory: clip = "victory"; poseProgress = p
            case .defeat: clip = "defeat"; poseProgress = p; hero.alpha = 1 - p * 0.35
            }
        }
        staffEffects.frame=world.bounds
        staffEffects.sample=nil
        if usesStaff,cue == .strike {
            let s=Double(baseHeroFrame.width/256)
            let from=PartyPoint(Double(baseHeroFrame.minX+123*baseHeroFrame.width/256),Double(baseHeroFrame.minY+214*baseHeroFrame.height/256))
            let to=PartyPoint(Double(baseEnemyFrame.minX+94*baseEnemyFrame.width/384),Double(baseEnemyFrame.minY+152*baseEnemyFrame.height/256))
            staffEffects.sample=LegendaryStaffRig.effect(age:cueElapsed,foot:from,target:to,groundY:Double(baseEnemyFrame.minY+240*baseEnemyFrame.height/256),scale:s)
        }
        staffEffects.setNeedsDisplay()
        greatSwordTrail.path=nil
        if usesGreatSword,cue == .strike {
            let s=Double(baseHeroFrame.width/256)
            let from=PartyPoint(Double(baseHeroFrame.minX+123*baseHeroFrame.width/256),Double(baseHeroFrame.minY+214*baseHeroFrame.height/256))
            let to=PartyPoint(Double(baseEnemyFrame.minX+94*baseEnemyFrame.width/384),Double(baseEnemyFrame.minY+152*baseEnemyFrame.height/256))
            let points=GreatSwordRig.trail(age:cueElapsed,from:from,to:to,scale:s)
            if points.count>1 {
                let path=UIBezierPath();path.move(to:CGPoint(x:points[0].x,y:points[0].y));for p in points.dropFirst() { path.addLine(to:CGPoint(x:p.x,y:p.y)) }
                greatSwordTrail.path=path.cgPath;greatSwordTrail.opacity=Float(PartyVisual.pulse(GreatSwordRig.artTime(age:cueElapsed),0.86,1.0275,1.20))
            }
        }
        bowArrow.path=nil
        if usesBow,cue == .strike {
            let unit=baseHeroFrame.width/256
            let tip=BowRig.releaseArrowTip
            let from=PartyPoint(Double(baseHeroFrame.minX+CGFloat(tip.x)*unit),Double(baseHeroFrame.minY+CGFloat(tip.y)*unit))
            let to=PartyPoint(Double(attackContactPoint.x),Double(attackContactPoint.y))
            if let arrow=BowRig.projectile(age:cueElapsed,from:from,to:to,impact:MeadowBattleImpactClock.strikeContact,scale:Double(unit)) {
                let path=UIBezierPath();path.move(to:CGPoint(x:arrow.tail.x,y:arrow.tail.y));path.addLine(to:CGPoint(x:arrow.tip.x,y:arrow.tip.y));bowArrow.path=path.cgPath
            }
        }
        hero.setPose(clip: clip, progress: poseProgress)
        let unit = baseHeroFrame.width / 256
        let offset = hero.poseRootOffset
        hero.transform = .identity
        hero.frame = baseHeroFrame.offsetBy(dx: heroTravel + offset.x * unit, dy: heroLift + offset.y * unit)
        enemy.transform = .identity
        let monster=PartyVisual.monster(time:sceneTime,attackAge:cue == .enemyStrike ? cueElapsed:nil,hurtAge:lastImpactCue == .strike ? lastImpactAt.map { sceneTime-$0 }:nil)
        enemy.frame = baseEnemyFrame.offsetBy(dx: enemyTravel + enemyRecoil, dy: 0)
        if deathStartedAt == nil {
            let old=enemy.frame;let h=old.height*monster.scaleY
            enemy.frame=CGRect(x:old.minX,y:old.minY+(old.height-h)*240/256,width:old.width,height:h)
        }
        let enemyPose = min(7, max(0, Int(monsterProgress * 8)))
        if deathStartedAt == nil, enemyPose != lastEnemyPose {
            enemy.image = MeadowBattleEnemyFrames.image(progress: monsterProgress)
            enemyDim.image = enemy.image?.withTintColor(.black, renderingMode: .alwaysOriginal)
            let contacts = MeadowBattleEnemyFrames.feet(progress: monsterProgress)
            enemyShadow.update(image: enemy.image, soleY: 240,
                contacts: contacts.map { .init(point: $0, radius: 14) })
            lastEnemyPose = enemyPose
        }
        let shadowKey = "\(clip)-\(Int((poseProgress * CGFloat(MeadowBattleAnimation.silhouetteBuckets)).rounded()))"
        if shadowKey != lastShadowPose {
            heroFlash.image = hero.poseSilhouette.withTintColor(.white, renderingMode: .alwaysOriginal)
            heroShadow.update(image: hero.poseSilhouette, soleY: hero.poseFootAnchorPx.y,
                contacts: hero.poseContacts.map { .init(point: $0, radius: 12) })
            lastShadowPose = shadowKey
        }
        attachedSkills.frame=hero.bounds
        attachedSkills.update(shield:shownShieldValue,preview:0,time:sceneTime,
            formation:shownShieldValue>0 ? nil : shieldFormationAt.flatMap { sceneTime-$0<0.96 ? sceneTime-$0 : nil },formationBase:shieldFormationBase,birth:shieldBirthAt.map { sceneTime-$0 },contact:shieldContactAt.map { sceneTime-$0 },
            broken:shieldBreakAt.map { sceneTime-$0 },recovery:recoveryStartedAt.map { sceneTime-$0 },recoveryTier:recoveryTier)
        heroShadow.spriteFrame = hero.frame; enemyShadow.spriteFrame = enemy.frame
        heroFlash.frame = hero.frame; enemyFlash.frame = enemy.frame
        heroFlash.alpha = cue == .enemyStrike && !hitWasBlocked ? 0.25 * pulse(0.46, 0.51, 0.66) : 0
        enemyFlash.image = UIImage(named: "BattleVFXHeavyHitMask")
        enemyFlash.alpha = 0
        if deathStartedAt == nil, lastImpactCue == .strike, let at = lastImpactAt {
            let age=sceneTime-at
            if age < 0.22 {
                enemyFlash.alpha = 0.85 * (age < 0.04 ? smooth((age+0.04)/0.08) : 1-smooth((age-0.04)/0.18))
            }
        }
        if let at = deathStartedAt {
            let index = MeadowBattleVisualMotion.windFrame(sceneTime-at)
            if index != lastDeathFrame {
                enemy.image = MeadowBattleVFXAssets.body[MeadowBattleVisualMotion.bodyFrame(sceneTime-at)]
                enemyDim.image = enemy.image?.withTintColor(.black, renderingMode: .alwaysOriginal)
                enemyShadow.update(image: enemy.image, soleY: 240, contacts: [])
                deathWind.image = MeadowBattleVFXAssets.wind[index]; lastDeathFrame = index
            }
            let scale=baseEnemyFrame.width/384
            deathWind.frame = CGRect(x:baseEnemyFrame.minX,y:baseEnemyFrame.minY-32*scale,width:448*scale,height:320*scale)
            deathWind.isHidden = sceneTime-at >= MeadowBattleVisualMotion.deathDuration
        } else { deathWind.isHidden = true }
        enemyDim.frame=enemy.frame
        let dim=darkness(); backgroundDim.alpha=dim; foregroundDim.alpha=dim; backdropDim.alpha=dim
        enemyDim.alpha=dim*0.55
        let heroFoot = CGPoint(x: hero.frame.minX + hero.poseFootAnchorPx.x * unit,
                               y: hero.frame.minY + hero.poseFootAnchorPx.y * unit)
        let enemyFoot = CGPoint(x: enemy.frame.minX + 178.5 / 384 * enemy.frame.width,
                               y: enemy.frame.minY + 240 / 256 * enemy.frame.height)
        let dieUnit=canvas.bounds.width/760
        let dieFoot=diceAtEnemy ? enemyFoot:heroFoot
        diceView.bounds=CGRect(x:0,y:0,width:220,height:100)
        diceView.center=CGPoint(x:dieFoot.x-(cue == .strike ? 18*approach()*dieUnit:0),y:dieFoot.y-(diceAtEnemy ? 307:237)*dieUnit)
        diceView.transform=CGAffineTransform(scaleX:dieUnit,y:dieUnit)
        diceView.time=sceneTime;diceView.visibleAge=sceneTime-diceVisibleAt;diceView.resolvedAge=diceSettledAt.map { sceneTime-$0 };diceView.exitAge=diceExitAt.map { sceneTime-$0 };diceView.setNeedsDisplay()
        let contact = MeadowBattleAnimation.sample(clip: "attack", progress: 0.54)
        let blade=transformPoint(CGPoint(x:191,y:142),part:contact.layers["MeadowBattleHeroWeapon"] ?? .init())
        let reach=baseHeroFrame.minX+(blade.x+contact.rootOffset.x)*unit
        let fullTravel=min(canvas.bounds.width*0.22,max(0,baseEnemyFrame.minX+125/384*baseEnemyFrame.width-reach))
        let contactPoint=usesGreatSword || usesStaff ? CGPoint(x:baseEnemyFrame.minX+94*baseEnemyFrame.width/384,y:baseEnemyFrame.minY+152*baseEnemyFrame.height/256):CGPoint(x:reach+fullTravel,y:baseHeroFrame.minY+(blade.y+contact.rootOffset.y)*unit)
        attackContactPoint = contactPoint
        let wardPoint=CGPoint(x:hero.frame.minX+CGFloat(MeadowBattleShieldGeometry.contactX)*unit,y:hero.frame.minY+CGFloat(MeadowBattleShieldGeometry.contactY)*unit)
        savedImpact = lastImpactCue == .enemyStrike ? shieldContactAt == lastImpactAt ? wardPoint : CGPoint(x:heroFoot.x+8*unit,y:heroFoot.y-65*unit) : contactPoint
        let focusEnvelope=focusedAction == nil ? CGFloat(0) : smooth((sceneTime-focusStartedAt)/0.28)
        let power: CGFloat = focusedAction == nil ? 0 : focusedAction == .strike ? 0.9 : 0.28
        let ring: CGFloat = cue == .strike ? 0.65*(1-smooth((cueElapsed-0.24)/0.16)) : cue == nil && focusedAction != .protection ? power*0.7*focusEnvelope : 0
        let particles=lightEmissions.flatMap { e in MeadowBattleLightField.sample(e.kind,age:sceneTime-e.startedAt,originX:e.x,originY:e.y,groundY:e.groundY) }
        for renderer in [effects,groundEffects] {
            renderer.rangedImpact=usesBow || usesStaff
            renderer.heroFoot=heroFoot; renderer.enemyFoot=enemyFoot; renderer.impact=savedImpact
            renderer.cue=cue; renderer.progress=p; renderer.selected=selected; renderer.shield=shownShieldValue
            renderer.previewPower=0; renderer.previewEnvelope=0; renderer.ringAlpha=0
            renderer.impactAge=lastImpactCue == .strike ? lastImpactAt.map { sceneTime-$0 } : nil
            renderer.messageAge=lastImpactAt.map { sceneTime-$0 }; renderer.time=sceneTime
            renderer.messageAtHero = lastImpactCue == .enemyStrike || lastImpactCue == .heal || lastImpactCue == .guardPose
            renderer.shieldPreview=focusedAction == .protection
            renderer.shieldBirthAge=shieldBirthAt.map { sceneTime-$0 }
            renderer.shieldContactAge=shieldContactAt.map { sceneTime-$0 }
            renderer.shieldBreakAge=shieldBreakAt.map { sceneTime-$0 }
            renderer.deathAge=deathStartedAt.map { sceneTime-$0 }
            renderer.particles=particles
            renderer.recoveryAge=recoveryStartedAt.map { sceneTime-$0 }
            renderer.recoveryTier=recoveryTier
            renderer.setNeedsDisplay()
        }
        // Move only the world; HUD, health labels and skill cards remain stable.
        let hitAge=lastImpactAt.map { sceneTime-$0 } ?? 10
        let wardAge=shieldContactAt.map { sceneTime-$0 } ?? 10
        var shake: CGFloat = 0, zoom: CGFloat = 0
        if lastImpactCue == .strike, hitAge<0.5 {
            shake=4*(1-smooth(hitAge/0.28)); zoom=0.045*(1-smooth(hitAge/0.5))
        } else if wardAge<0.22 { shake=1.5*(1-smooth(wardAge/0.22)) }
        if UIAccessibility.isReduceMotionEnabled { shake=0; zoom=0 }
        world.transform=CGAffineTransform(translationX:sin(CGFloat(hitAge)*83)*shake*canvas.bounds.width/760,
            y:cos(CGFloat(hitAge)*64)*shake*0.55*canvas.bounds.width/760).scaledBy(x:1+zoom,y:1+zoom)
        let labelWidth = max(108, canvas.bounds.width * 0.20)
        heroStatus.frame = CGRect(x: heroFoot.x - labelWidth / 2,
            y: max(48, heroFoot.y - canvas.bounds.height * MeadowBattleCanvasGeometry.heroVisibleHeight - 49),
            width: labelWidth, height: 44)
        enemyStatus.frame = CGRect(x: enemyFoot.x - labelWidth / 2,
            y: max(48, enemyFoot.y - canvas.bounds.height * MeadowBattleCanvasGeometry.enemyVisibleHeight - 49),
            width: labelWidth, height: 44)
    }

}
