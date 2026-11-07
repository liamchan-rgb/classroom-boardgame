import UIKit

/// Per-layer transform in registered 256 px artwork coordinates. Every part
/// uses the same canvas and pivots, so appearance assets can use this rig too.
struct MeadowBattleLayerPose {
    var offset: CGPoint = .zero
    var pivot: CGPoint = CGPoint(x: 128, y: 160)
    var rotation: CGFloat = 0
    var scale: CGFloat = 1
}

/// A sampled battle pose. `rootOffset` is deliberately separate from the
/// registered art: the battlefield owns lunge/knockback travel and can keep
/// the planted-foot shadow aligned. Contacts are in canvas pixels.
struct MeadowBattlePoseSample {
    var clip: String
    var progress: CGFloat
    var rootOffset: CGPoint
    var footAnchorPx: CGPoint
    var contacts: [CGPoint]
    var layers: [String: MeadowBattleLayerPose]
    var hitFlash: CGFloat
    var recoil: CGFloat
}

private struct MeadowBattleAnimationKey: Decodable {
    let t: CGFloat
    let root: [CGFloat]
    let lean: CGFloat
    let crouch: CGFloat
    let shoulder: CGFloat
    let elbow: CGFloat
    let wrist: CGFloat
    let nearHip: CGFloat
    let nearKnee: CGFloat
    let farHip: CGFloat
    let farKnee: CGFloat
    let flash: CGFloat
    let recoil: CGFloat
    var rootPoint: CGPoint { CGPoint(x: root[0], y: root[1]) }
}

private struct MeadowBattleAnimationClip: Decodable {
    let durationMs: Int
    let loop: Bool
    let keys: [MeadowBattleAnimationKey]
}

private struct MeadowBattleAnimationLibrary: Decodable {
    let schemaVersion: Int
    let frameDurationMs: Int
    let silhouetteBuckets: Int
    let clips: [String: MeadowBattleAnimationClip]
}

/// Runtime and review renderers share this JSON clip library.
enum MeadowBattleAnimation {
    private static let library: MeadowBattleAnimationLibrary = {
        guard let data = NSDataAsset(name: "MeadowBattleHeroAnimationV2")?.data,
              let decoded = try? JSONDecoder().decode(MeadowBattleAnimationLibrary.self, from: data) else {
            fatalError("Missing or invalid MeadowBattleHeroAnimationV2 asset")
        }
        return decoded
    }()
    static let clips = ["idle", "attack", "guard", "hit", "victory", "defeat"]
    static let frameDurationMs = library.frameDurationMs
    static let silhouetteBuckets = library.silhouetteBuckets
    static func durationMs(for clip: String) -> Int { library.clips[clip]?.durationMs ?? 2400 }
    static func loops(_ clip: String) -> Bool { library.clips[clip]?.loop ?? false }

    static func sample(clip: String, progress raw: CGFloat) -> MeadowBattlePoseSample {
        let name = library.clips[clip] == nil ? "idle" : clip
        let progress = min(1, max(0, raw))
        let sequence = library.clips[name]!.keys
        let upper = sequence.firstIndex(where: { $0.t >= progress }) ?? sequence.count - 1
        let a = sequence[max(0, upper - 1)], b = sequence[upper]
        let f = b.t == a.t ? 0 : (progress - a.t) / (b.t - a.t)
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * f }
        func mixPoint(_ x: CGPoint, _ y: CGPoint) -> CGPoint { CGPoint(x: mix(x.x, y.x), y: mix(x.y, y.y)) }
        let root = mixPoint(a.rootPoint, b.rootPoint)
        let lean = mix(a.lean, b.lean), crouch = mix(a.crouch, b.crouch)
        func bodyPoint(_ point: CGPoint) -> CGPoint {
            let dx = point.x - 132, dy = point.y - 167
            let c = cos(lean), s = sin(lean)
            return CGPoint(x: 132 + dx * c - dy * s,
                           y: 167 + dx * s + dy * c + crouch)
        }
        func rotate(_ point: CGPoint, around pivot: CGPoint, by angle: CGFloat) -> CGPoint {
            let x = point.x - pivot.x, y = point.y - pivot.y
            let c = cos(angle), s = sin(angle)
            return CGPoint(x: pivot.x + x * c - y * s, y: pivot.y + x * s + y * c)
        }
        func layerPose(pivot: CGPoint, movedPivot: CGPoint, rotation: CGFloat) -> MeadowBattleLayerPose {
            .init(offset: CGPoint(x: movedPivot.x - pivot.x, y: movedPivot.y - pivot.y),
                  pivot: pivot, rotation: rotation)
        }

        let shoulderPivot = CGPoint(x: 117, y: 141), elbowPivot = CGPoint(x: 128, y: 158)
        let gripPivot = CGPoint(x: 145.6, y: 163.7)
        let shoulderAngle = mix(a.shoulder, b.shoulder)
        let elbowAngle = mix(a.elbow, b.elbow)
        let wristAngle = mix(a.wrist, b.wrist)
        let movedShoulder = bodyPoint(shoulderPivot)
        let movedElbow = bodyPoint(rotate(elbowPivot, around: shoulderPivot, by: shoulderAngle))
        let movedGrip = bodyPoint(rotate(rotate(gripPivot, around: elbowPivot, by: elbowAngle),
                                         around: shoulderPivot, by: shoulderAngle))
        let torsoPose = MeadowBattleLayerPose(offset: CGPoint(x: 0, y: crouch),
                                              pivot: CGPoint(x: 132, y: 167), rotation: lean)

        let nearHip = CGPoint(x: 134, y: 175), nearKnee = CGPoint(x: 141, y: 187)
        let farHip = CGPoint(x: 115, y: 176), farKnee = CGPoint(x: 104, y: 192)
        let nearHipAngle = mix(a.nearHip, b.nearHip), nearKneeAngle = mix(a.nearKnee, b.nearKnee)
        let farHipAngle = mix(a.farHip, b.farHip), farKneeAngle = mix(a.farKnee, b.farKnee)
        let movedNearHip = bodyPoint(nearHip)
        let movedNearKnee = bodyPoint(rotate(nearKnee, around: nearHip, by: nearHipAngle))
        let movedFarHip = bodyPoint(farHip)
        let movedFarKnee = bodyPoint(rotate(farKnee, around: farHip, by: farHipAngle))
        func legPoint(_ point: CGPoint, hip: CGPoint, knee: CGPoint, hipAngle: CGFloat, kneeAngle: CGFloat) -> CGPoint {
            bodyPoint(rotate(rotate(point, around: knee, by: kneeAngle), around: hip, by: hipAngle))
        }
        // Sample several points along each boot's registered sole. Screen y
        // grows downward, so the lowest transformed point is the support plane.
        let farSoles = [90, 98, 105].map {
            legPoint(CGPoint(x: CGFloat($0), y: 214), hip: farHip, knee: farKnee,
                     hipAngle: farHipAngle, kneeAngle: farKneeAngle)
        }
        let nearSoles = [145, 150, 156].map {
            legPoint(CGPoint(x: CGFloat($0), y: 214), hip: nearHip, knee: nearKnee,
                     hipAngle: nearHipAngle, kneeAngle: nearKneeAngle)
        }
        let upperArm = layerPose(pivot: shoulderPivot, movedPivot: movedShoulder,
                                 rotation: lean + shoulderAngle)
        let forearm = layerPose(pivot: elbowPivot, movedPivot: movedElbow,
                                rotation: lean + shoulderAngle + elbowAngle)
        let nearThigh = layerPose(pivot: nearHip, movedPivot: movedNearHip,
                                  rotation: lean + nearHipAngle)
        let nearShin = layerPose(pivot: nearKnee, movedPivot: movedNearKnee,
                                 rotation: lean + nearHipAngle + nearKneeAngle)
        let farThigh = layerPose(pivot: farHip, movedPivot: movedFarHip,
                                 rotation: lean + farHipAngle)
        let farShin = layerPose(pivot: farKnee, movedPivot: movedFarKnee,
                                rotation: lean + farHipAngle + farKneeAngle)
        let handPose = layerPose(pivot: gripPivot, movedPivot: movedGrip,
                                 rotation: lean + shoulderAngle + elbowAngle + wristAngle)
        let swordPose = layerPose(pivot: gripPivot, movedPivot: movedGrip,
                                  rotation: lean + shoulderAngle + elbowAngle + wristAngle)
        let layers: [String: MeadowBattleLayerPose] = [
            "MeadowBattleHeroBodyCore": torsoPose,
            "MeadowBattleHeroWardrobeCore": torsoPose,
            "MeadowBattleHeroJointUnderlay": torsoPose,
            "MeadowBattleHeroHair": torsoPose,
            "MeadowBattleHeroFace": torsoPose,
            "MeadowBattleHeroLegNearThighBody": nearThigh,
            "MeadowBattleHeroLegNearThighWardrobe": nearThigh,
            "MeadowBattleHeroLegNearShinBody": nearShin,
            "MeadowBattleHeroLegNearShinWardrobe": nearShin,
            "MeadowBattleHeroLegFarThighBody": farThigh,
            "MeadowBattleHeroLegFarThighWardrobe": farThigh,
            "MeadowBattleHeroLegFarShinBody": farShin,
            "MeadowBattleHeroLegFarShinWardrobe": farShin,
            "MeadowBattleHeroArmNearUpperBody": upperArm,
            "MeadowBattleHeroArmNearUpperWardrobe": upperArm,
            "MeadowBattleHeroArmNearForearmBody": forearm,
            "MeadowBattleHeroArmNearForearmWardrobe": forearm,
            "MeadowBattleHeroNearHand": handPose,
            "MeadowBattleHeroFarHand": torsoPose,
            "MeadowBattleHeroWeapon": swordPose
        ]
        // Keep the support sole at the registered 214 px ground line. Contacts
        // include planted soles only; a lifted boot must not cast a full-strength
        // contact shadow. These local points are transformed with the actor.
        let allSoles = farSoles + nearSoles
        let groundY = allSoles.map(\.y).max() ?? 214
        let rootOffset = CGPoint(x: root.x, y: root.y + 214 - groundY)
        func plantedBootContact(_ soles: [CGPoint]) -> CGPoint? {
            let planted = soles.filter { groundY - $0.y <= 1 }
            guard !planted.isEmpty else { return nil }
            return CGPoint(x: planted.map(\.x).reduce(0, +) / CGFloat(planted.count),
                           y: planted.map(\.y).reduce(0, +) / CGFloat(planted.count))
        }
        let contacts = [plantedBootContact(farSoles), plantedBootContact(nearSoles)].compactMap { $0 }
        let anchorX = contacts.isEmpty ? 123 : contacts.map(\.x).reduce(0, +) / CGFloat(contacts.count)
        return MeadowBattlePoseSample(clip: name, progress: progress, rootOffset: rootOffset,
                                      footAnchorPx: CGPoint(x: anchorX, y: groundY),
                                      contacts: contacts, layers: layers,
                                      hitFlash: mix(a.flash, b.flash), recoil: mix(a.recoil, b.recoil))
    }
}

/// A single registered pose assembled from data. Appearance layers never alter
/// the pose, source canvas or foot anchor, and add no appearance-ID branches.
struct MeadowBattleActorConfiguration: Decodable {
    let canvasPx: [CGFloat]
    let footAnchorPx: [CGFloat]
    let referenceHeightPx: CGFloat
    let layers: [String]

    static func load() -> MeadowBattleActorConfiguration? {
        guard let data = NSDataAsset(name: "MeadowBattleHeroConfigurationV2")?.data else { return nil }
        guard let configuration = try? JSONDecoder().decode(Self.self, from: data),
              configuration.canvasPx.count == 2, configuration.footAnchorPx.count == 2,
              configuration.canvasPx.allSatisfy({ $0 > 0 }),
              configuration.referenceHeightPx > 0, !configuration.layers.isEmpty else { return nil }
        return configuration
    }

    var canvasSize: CGSize { CGSize(width: canvasPx[0], height: canvasPx[1]) }
    var footAnchor: CGPoint { CGPoint(x: footAnchorPx[0], y: footAnchorPx[1]) }
}

import MeadowBattleSupport

final class MeadowBattleActorView: UIView {
    let configuration: MeadowBattleActorConfiguration?
    private var images: [UIImageView]
    private let bowGeometry=MeadowBowGeometryView()
    private var bowSurfaces:[String:MeadowBowSurfaceView]=[:]
    private var bowNativeGroups:[String] {
        ["torso","head","farArm","farHand","nearUpperArm","nearSleeveConnected","nearHand"] + layerNames.filter { $0 == "MeadowBattleHeroBodyCore" || $0 == "MeadowBattleHeroHair" || $0 == "MeadowBattleHeroFace" || $0.contains("Leg") }
    }
    private var isStaff:Bool { weaponAsset=="MeadowBattleLegendaryStaff" }
    private var isGreatSword:Bool { weaponAsset=="MeadowBattleGreatSword" }
    private var isBow:Bool { weaponAsset=="MeadowBattleHuntingBow" }
    private var weaponAsset:String?="MeadowBattleHeroWeapon"
    private var armorID:String?
    private var armor:HeroFrames.ArmorVisualBinding? { HeroFrames.armorVisual(armorID) }
    private static let pauldron="MeadowBattleHeroPauldronNearWardrobe"
    private static let armorExtras=[pauldron,"MeadowBattleHeroHemFarWardrobe","MeadowBattleHeroHemNearWardrobe"]
    var layerNames: [String] { (configuration?.layers ?? [])+Self.armorExtras }
    let silhouette: UIImage?
    private(set) var currentPose = MeadowBattleAnimation.sample(clip: "idle", progress: 0)
    private let silhouetteCache = NSCache<NSString, UIImage>()
    var poseRootOffset: CGPoint { currentPose.rootOffset }
    var poseFootAnchorPx: CGPoint { currentPose.footAnchorPx }
    var poseContacts: [CGPoint] { currentPose.contacts }
    var poseSilhouette: UIImage { silhouette(for: currentPose) }

    override init(frame: CGRect) {
        let configuration = MeadowBattleActorConfiguration.load()
        self.configuration = configuration
        images = ((configuration?.layers ?? [])+Self.armorExtras).map { name in
            let view = UIImageView(image: UIImage(named: name))
            view.accessibilityIdentifier = name
            view.layer.minificationFilter = .nearest
            view.layer.magnificationFilter = .nearest
            view.contentMode = .scaleToFill
            return view
        }
        if let configuration {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            silhouette = UIGraphicsImageRenderer(size: configuration.canvasSize, format: format).image { _ in
                for name in configuration.layers {
                    if name == "MeadowBattleHeroJointUnderlay" { continue }
                    UIImage(named: name)?.draw(in: CGRect(origin: .zero, size: configuration.canvasSize))
                }
            }
        } else {
            silhouette = nil
        }
        super.init(frame: frame)
        silhouetteCache.countLimit = 96
        silhouetteCache.totalCostLimit = 24*1024*1024
        images.forEach(addSubview)
        for group in bowNativeGroups {
            let view=MeadowBowSurfaceView(frame:.zero);view.group=group;bowSurfaces[group]=view;addSubview(view);view.isHidden=true
        }
        addSubview(bowGeometry);bowGeometry.isHidden=true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        (images+Array(bowSurfaces.values)).forEach {
            $0.layer.anchorPoint = .zero
            $0.bounds = CGRect(origin: .zero, size: bounds.size)
            $0.layer.position = bounds.origin
        }
        bowGeometry.frame=bounds
        applyPose(currentPose)
    }

    /// Apply one deterministic pose sample without starting a timer. The scene
    /// can use the same sample to move the actor and shadow on its own clock.
    func setPose(clip: String, progress: CGFloat) {
        let pose = bodyPose(clip:clip,progress:progress)
        currentPose = pose
        applyPose(pose)
    }
    private func bodyPose(clip:String,progress:CGFloat)->MeadowBattlePoseSample {
        if isGreatSword || isStaff {
            let q=isStaff ? LegendaryStaffRig.pose(progress:Double(progress),clip:clip):GreatSwordRig.pose(progress:Double(progress),clip:clip)
            return MeadowBattlePoseSample(clip:clip,progress:progress,rootOffset:CGPoint(x:q.rootOffset.x,y:q.rootOffset.y),footAnchorPx:CGPoint(x:q.footAnchorPx.x,y:q.footAnchorPx.y),contacts:q.contacts.map { CGPoint(x:$0.x,y:$0.y) },layers:q.layers.mapValues { .init(offset:CGPoint(x:$0.offset.x,y:$0.offset.y),pivot:CGPoint(x:$0.pivot.x,y:$0.pivot.y),rotation:CGFloat($0.rotation)) },hitFlash:CGFloat(q.hitFlash),recoil:CGFloat(q.recoil))
        }
        if isBow && ["attack","idle"].contains(clip) { var p=MeadowBattleAnimation.sample(clip:"idle",progress:0);p.clip=clip;p.progress=progress;return p }
        var pose=MeadowBattleAnimation.sample(clip:clip,progress:progress)
        if isBow {
            let rig=BowRig.sample(clip:clip,progress:Double(progress))
            if rig.canvasBaked == true {
                pose.layers=pose.layers.mapValues { _ in MeadowBattleLayerPose() }
                if let root=rig.rootOffset { pose.rootOffset=CGPoint(x:root.x,y:root.y) }
                pose.contacts=(rig.contacts ?? []).map { CGPoint(x:$0.x,y:$0.y) }
                let ground=CGFloat(rig.groundY ?? 214)
                let x=pose.contacts.isEmpty ? 123:pose.contacts.map(\.x).reduce(0,+)/CGFloat(pose.contacts.count)
                pose.footAnchorPx=CGPoint(x:x,y:ground)
            }
        }
        return pose
    }
    func setWeaponAsset(_ asset:String?) {
        guard asset != weaponAsset else { return };weaponAsset=asset;silhouetteCache.removeAllObjects()
        if let i=layerNames.firstIndex(of:"MeadowBattleHeroWeapon") { images[i].image=asset.flatMap { UIImage(named:$0) };images[i].isHidden=asset==nil };currentPose=bodyPose(clip:currentPose.clip,progress:currentPose.progress);applyPose(currentPose)
    }
    func setArmor(_ id:String?) {
        guard id != armorID else { return };armorID=id;silhouetteCache.removeAllObjects()
        for (index,name) in layerNames.enumerated() { images[index].image=sourceAsset(name).flatMap { UIImage(named:$0) } }
        applyPose(currentPose)
    }
    func trailImage(progress:CGFloat)->UIImage {
        silhouette(for:MeadowBattleAnimation.sample(clip:"attack",progress:progress))
    }

    /// Keep the original lower body here; the original head is painted once
    /// above the raised sleeve. Exclude the detached sword-shoulder pixel.
    private static let bowBodyCore:UIImage? = {
        let f=UIGraphicsImageRendererFormat();f.scale=1
        return UIGraphicsImageRenderer(size:CGSize(width:256,height:256),format:f).image { renderer in
            let c=renderer.cgContext;c.setAllowsAntialiasing(false);c.interpolationQuality = .none
            c.addRect(CGRect(x:100,y:174,width:53,height:17));c.clip()
            UIImage(named:"MeadowBattleBowReviewedBodyCore")?.draw(in:CGRect(x:0,y:0,width:256,height:256))
        }
    }()
    private func bowSample(_ pose:MeadowBattlePoseSample)->BowRigSample {
        let torso=pose.layers["MeadowBattleHeroBodyCore"] ?? .init()
        return BowRig.sample(clip:pose.clip,progress:Double(pose.progress),lean:Double(torso.rotation),crouch:Double(torso.offset.y))
    }
    private func resolvedPose(_ pose:MeadowBattlePoseSample)->MeadowBattlePoseSample {
        var value=pose
        if !isBow,armor != nil {
            let arm=pose.layers["MeadowBattleHeroArmNearUpperWardrobe"] ?? .init()
            let body=pose.layers["MeadowBattleHeroWardrobeCore"] ?? .init()
            let delta=atan2(sin(arm.rotation-body.rotation),cos(arm.rotation-body.rotation))
            value.layers[Self.pauldron] = .init(offset:arm.offset,pivot:arm.pivot,rotation:body.rotation+min(.pi/15,max(-.pi/15,delta*0.38)))
            // The skirt overlaps the belt, follows each hip by a restrained
            // fraction, and stays above trousers instead of being baked in.
            for side in ["Far","Near"] {
                if let thigh=pose.layers["MeadowBattleHeroLeg\(side)ThighWardrobe"] {
                    let angle=atan2(sin(thigh.rotation-body.rotation),cos(thigh.rotation-body.rotation))
                    value.layers["MeadowBattleHeroHem\(side)Wardrobe"] = .init(offset:thigh.offset,pivot:thigh.pivot,rotation:body.rotation+min(.pi/22.5,max(-.pi/22.5,angle*0.35)))
                }
            }
        }
        guard isBow else { return value }
        let sample=bowSample(pose)
        if let q=sample.parts["bow"] { value.layers["MeadowBattleHeroWeapon"] = .init(offset:CGPoint(x:q.offset.x,y:q.offset.y),pivot:CGPoint(x:q.pivot.x,y:q.pivot.y),rotation:CGFloat(q.rotation)) }

        return value
    }
    private func sourceAsset(_ name:String)->String? {
        if name=="MeadowBattleHeroWeapon" { return weaponAsset }
        if isBow && name=="MeadowBattleHeroBodyCore" { return "MeadowBattleBowReviewedBodyCore" }
        if isBow && ["MeadowBattleHeroWardrobeCore","MeadowBattleHeroNearHand","MeadowBattleHeroJointUnderlay","MeadowBattleHeroArmNearUpperBody","MeadowBattleHeroArmNearForearmBody","MeadowBattleHeroArmNearUpperWardrobe","MeadowBattleHeroArmNearForearmWardrobe"].contains(name) { return nil }
        if isBow && name=="MeadowBattleHeroLegFarThighWardrobe" { return "MeadowBattleBowReviewedLegFarThighWardrobe" }
        if isBow && name=="MeadowBattleHeroLegNearThighWardrobe" { return "MeadowBattleBowReviewedLegNearThighWardrobe" }
        if isBow && name=="MeadowBattleHeroFarHand" { return nil }
        if isBow && Self.armorExtras.contains(name) { return nil }
        if let replacement=armor?.battleLayers[name] { return replacement }
        if Self.armorExtras.contains(name) { return nil }
        return name
    }
    private func applyPose(_ rawPose: MeadowBattlePoseSample) {
        let pose=resolvedPose(rawPose)
        let rig=isBow ? bowSample(rawPose):nil
        let surfaceDepth=Dictionary(uniqueKeysWithValues:orderedLayerNames(for:pose.clip).enumerated().map { ($0.element,CGFloat($0.offset)) })
        for (group,view) in bowSurfaces { view.isHidden = !isBow;view.layer.zPosition=surfaceDepth[group] ?? 0;view.update(rig,atlas:armor?.bowAtlas,torso:armor?.bowTorso) }

        bowGeometry.isHidden = !isBow;bowGeometry.sample=rig;bowGeometry.layer.zPosition=CGFloat(orderedLayerNames(for:pose.clip).firstIndex(of:"MeadowBattleHeroWeapon") ?? 28)+0.5
        guard !images.isEmpty else { return }
        let orderedNames = orderedLayerNames(for: pose.clip)
        let depth = Dictionary(uniqueKeysWithValues: orderedNames.enumerated().map { ($0.element, CGFloat($0.offset)) })
        UIView.performWithoutAnimation {
            let orderedImages=images.enumerated().map { (layerNames[$0.offset],$0.element) }
            for (name,image) in orderedImages {
                image.image=(isBow && name=="MeadowBattleHeroBodyCore") ? Self.bowBodyCore:sourceAsset(name).flatMap { UIImage(named:$0) };image.isHidden=sourceAsset(name)==nil || rig?.nativeTiles?[name] != nil
                image.layer.zPosition = depth[name] ?? 0
                image.alpha = (name == "MeadowBattleHeroJointUnderlay" && pose.clip == "idle" && !isStaff) ? 0 : name.hasPrefix("BowFar") ? 0.86:1
                guard let part = pose.layers[name] else { image.transform = .identity; continue }
                let sx = bounds.width / (configuration?.canvasSize.width ?? 256)
                let sy = bounds.height / (configuration?.canvasSize.height ?? 256)
                let px = part.pivot.x * sx, py = part.pivot.y * sy
                let ox = part.offset.x * sx, oy = part.offset.y * sy
                let c = cos(part.rotation) * part.scale, s = sin(part.rotation) * part.scale
                let transform = CGAffineTransform(a: c, b: s, c: -s, d: c,
                                                  tx: px + ox - c * px + s * py,
                                                  ty: py + oy - s * px - c * py)
                image.layer.setAffineTransform(transform)
            }
        }
    }

    /// Keep the approved idle stack exactly as imported (weapon behind the
    /// character). During authored clips, bring the independently moving blade
    /// in front of the torso and sleeves while retaining head/hand foreground.
    private func orderedLayerNames(for clip: String) -> [String] {
        let names = layerNames
        if isBow {
            let skip=["MeadowBattleHeroWeapon","MeadowBattleHeroFarHand","MeadowBattleHeroNearHand","MeadowBattleHeroJointUnderlay","MeadowBattleHeroWardrobeCore","MeadowBattleHeroArmNearUpperBody","MeadowBattleHeroArmNearForearmBody","MeadowBattleHeroArmNearUpperWardrobe","MeadowBattleHeroArmNearForearmWardrobe"]
            let base=names.filter { !skip.contains($0) && !Self.armorExtras.contains($0) }
            let insertion=base.firstIndex(of:"MeadowBattleHeroHair") ?? base.endIndex
            return Array(base[..<insertion])+["farArm","nearUpperArm","torso","nearSleeveConnected","head"]+Array(base[insertion...])+["MeadowBattleHeroWeapon","farHand","nearHand"]

        }
        if let order=armor?.battleLayerOrder { return order.filter { names.contains($0) } }
        if isStaff {
            var order=LegendaryStaffRig.layerOrder.filter { names.contains($0) }
            if armor != nil,let i=order.firstIndex(of:"MeadowBattleHeroArmNearUpperWardrobe") { order.insert(Self.pauldron,at:i+1) }
            return order
        }
        guard clip != "idle" else {
            var order=names.filter { !Self.armorExtras.contains($0) }
            if armor != nil,let i=order.firstIndex(of:"MeadowBattleHeroArmNearUpperWardrobe") { order.insert(Self.pauldron,at:i+1) }
            return order
        }
        let animated = [
            "MeadowBattleHeroJointUnderlay", "MeadowBattleHeroBodyCore",
            "MeadowBattleHeroLegFarThighBody", "MeadowBattleHeroLegFarShinBody",
            "MeadowBattleHeroLegNearThighBody", "MeadowBattleHeroLegNearShinBody",
            "MeadowBattleHeroArmNearUpperBody", "MeadowBattleHeroArmNearForearmBody",
            "MeadowBattleHeroWardrobeCore", "MeadowBattleHeroLegFarThighWardrobe",
            "MeadowBattleHeroLegFarShinWardrobe", "MeadowBattleHeroLegNearThighWardrobe",
            "MeadowBattleHeroLegNearShinWardrobe", "MeadowBattleHeroArmNearUpperWardrobe",
            "MeadowBattleHeroPauldronNearWardrobe", "MeadowBattleHeroArmNearForearmWardrobe", "MeadowBattleHeroWeapon",
            "MeadowBattleHeroHair", "MeadowBattleHeroFace", "MeadowBattleHeroNearHand",
            "MeadowBattleHeroFarHand"
        ]
        return animated.filter { names.contains($0) }
    }

    private func silhouette(for pose: MeadowBattlePoseSample) -> UIImage {
        let bowPose=bodyPose(clip:pose.clip,progress:pose.progress)
        let bucket = isBow ? (bowSample(bowPose).nativeFrame ?? 0):Int((pose.progress * CGFloat(MeadowBattleAnimation.silhouetteBuckets)).rounded())
        let body=bowPose.layers["MeadowBattleHeroBodyCore"] ?? .init()
        let bodyKey=isBow ? "-\(Int(body.rotation*1000))-\(Int(body.offset.y*100))":""
        let key = "\(pose.clip)-\(bucket)-\(weaponAsset ?? "none")-\(armorID ?? "none")\(bodyKey)" as NSString
        if let cached = silhouetteCache.object(forKey: key) { return cached }
        let poseForBowSilhouette=isBow ? bowPose:bodyPose(clip:pose.clip,progress:CGFloat(bucket)/CGFloat(MeadowBattleAnimation.silhouetteBuckets))
        let renderPose = resolvedPose(poseForBowSilhouette)
        let size = configuration?.canvasSize ?? CGSize(width: 256, height: 256)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            for name in orderedLayerNames(for: pose.clip) {
                if isBow && name == "farHand" { MeadowBowGeometryView.paint(renderer.cgContext,sample:bowSample(poseForBowSilhouette)) }
                if isBow && bowNativeGroups.contains(name) && (bowSample(poseForBowSilhouette).nativeTiles?[name] != nil || ["torso","head","farArm","farHand","nearUpperArm","nearSleeveConnected","nearHand"].contains(name)) {
                    MeadowBowSurfaceView.render(sample:bowSample(poseForBowSilhouette),group:name,atlas:armor?.bowAtlas,torso:armor?.bowTorso).draw(at:.zero);continue
                }
                if name == "MeadowBattleHeroJointUnderlay" && pose.clip == "idle" && !isStaff { continue }
                guard let asset=sourceAsset(name),let image = (isBow && name=="MeadowBattleHeroBodyCore") ? Self.bowBodyCore:UIImage(named: asset) else { continue }
                let part = renderPose.layers[name] ?? MeadowBattleLayerPose()
                let sx = size.width / 256, sy = size.height / 256
                let px = part.pivot.x * sx, py = part.pivot.y * sy
                let ox = part.offset.x * sx, oy = part.offset.y * sy
                let c = cos(part.rotation) * part.scale, s = sin(part.rotation) * part.scale
                let transform = CGAffineTransform(a: c, b: s, c: -s, d: c,
                                                  tx: px + ox - c * px + s * py,
                                                  ty: py + oy - s * px - c * py)
                renderer.cgContext.saveGState()
                renderer.cgContext.concatenate(transform)
                image.draw(in: CGRect(origin: .zero, size: size))
                renderer.cgContext.restoreGState()
            }
        }
        silhouetteCache.setObject(rendered, forKey: key,cost:256*256*4)
        return rendered
    }
}

/// Low-opacity source-silhouette projection plus small, soft planted-foot
/// contacts. The cast goes down-right, matching the scene's upper-left light.
final class MeadowBattleGroundingView: UIView {
    struct Contact {
        let point: CGPoint
        let radius: CGFloat
    }
    var spriteFrame: CGRect = .zero { didSet { if oldValue != spriteFrame { setNeedsDisplay() } } }
    private final class CachedTile: NSObject { let source:UIImage;let image:UIImage;init(source:UIImage,image:UIImage) { self.source=source;self.image=image } }
    private static let cache: NSCache<NSString,CachedTile> = { let c=NSCache<NSString,CachedTile>();c.totalCostLimit=8*1024*1024;return c }()
    private var tile:UIImage?
    private var sourceSize=CGSize(width:256,height:256)
    private var tileOrigin=CGPoint.zero
    private static let contactMask:UIImage = {
        let f=UIGraphicsImageRendererFormat();f.scale=1
        return UIGraphicsImageRenderer(size:CGSize(width:64,height:64),format:f).image { ctx in
            let colors=[UIColor(red:0.025,green:0.035,blue:0.018,alpha:0.68).cgColor,UIColor.clear.cgColor] as CFArray
            let g=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,1])!
            ctx.cgContext.drawRadialGradient(g,startCenter:CGPoint(x:32,y:32),startRadius:0,endCenter:CGPoint(x:32,y:32),endRadius:32,options:[])
        }
    }()
    private var soleY: CGFloat
    private var contacts: [Contact]

    init(image: UIImage?, soleY: CGFloat, contacts: [Contact]) {
        // The original 0.16 tint disappeared against the bright, detailed
        // ground in actual iPad captures. Keep the cast restrained, but dark
        // enough to read at the 1x battle-scene scale.
        self.soleY = soleY
        self.contacts = contacts
        super.init(frame: .zero)
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
        update(image:image,soleY:soleY,contacts:contacts)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Update the projected registered pose. The actor caches silhouettes by
    /// clip and quantized progress, avoiding a render on every display tick.
    func update(image: UIImage?, soleY: CGFloat, contacts: [Contact]) {
        if let image {
            sourceSize=image.size;tileOrigin=CGPoint(x:-8,y:soleY-8)
            let key="\(ObjectIdentifier(image))-\(Int(soleY*10))" as NSString
            if let found=Self.cache.object(forKey:key) { tile=found.image } else {
                let tint=image.withTintColor(UIColor(red:0.035,green:0.045,blue:0.025,alpha:0.34),renderingMode:.alwaysOriginal)
                let size=CGSize(width:image.size.width+ceil(image.size.height*0.38)+16,height:ceil(image.size.height*0.15)+16)
                let format=UIGraphicsImageRendererFormat();format.scale=1
                let rendered=UIGraphicsImageRenderer(size:size,format:format).image { ctx in
                    let c=ctx.cgContext;c.translateBy(x:8,y:8-soleY)
                    c.concatenate(CGAffineTransform(a:1,b:0,c:-0.38,d:-0.15,tx:soleY*0.38,ty:soleY*1.15))
                    c.setShadow(offset:.zero,blur:3.5,color:UIColor.black.withAlphaComponent(0.18).cgColor)
                    tint.draw(at:.zero)
                }
                tile=rendered;Self.cache.setObject(CachedTile(source:image,image:rendered),forKey:key,cost:Int(size.width*size.height)*4)
            }
        } else { tile=nil }
        self.soleY = soleY
        self.contacts = contacts
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let tile, let context=UIGraphicsGetCurrentContext(),spriteFrame.width>0 else { return }
        context.saveGState()
        context.translateBy(x:spriteFrame.minX,y:spriteFrame.minY)
        context.scaleBy(x:spriteFrame.width/sourceSize.width,y:spriteFrame.height/sourceSize.height)
        tile.draw(at:tileOrigin)
        for contact in contacts {
            let r=contact.radius
            Self.contactMask.draw(in:CGRect(x:contact.point.x-r,y:contact.point.y-r*0.38,width:r*2,height:r*0.76))
        }
        context.restoreGState()
    }
}

/// The string is a continuous path between the actual limb tips and drawing hand.
private final class MeadowBowGeometryView:UIView {
    var sample:BowRigSample? { didSet { setNeedsDisplay() } }
    override init(frame:CGRect) { super.init(frame:frame);isOpaque=false;isUserInteractionEnabled=false }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ rect:CGRect) { guard let sample,let c=UIGraphicsGetCurrentContext() else { return };c.scaleBy(x:bounds.width/256,y:bounds.height/256);Self.paint(c,sample:sample) }
    static func paint(_ c:CGContext,sample:BowRigSample) {
        c.saveGState();c.setAllowsAntialiasing(false);c.setLineWidth(1);c.setStrokeColor(UIColor(red:0.88,green:0.78,blue:0.55,alpha:1).cgColor)
        c.move(to:CGPoint(x:sample.upperTip.x,y:sample.upperTip.y));c.addLine(to:CGPoint(x:sample.stringHand.x,y:sample.stringHand.y));c.addLine(to:CGPoint(x:sample.lowerTip.x,y:sample.lowerTip.y));c.strokePath()
        if sample.arrowVisible {
            c.saveGState();c.setAlpha(sample.arrowAlpha)
            let a=sample.arrowTail,b=sample.arrowTip;c.setLineWidth(1);c.setStrokeColor(UIColor(red:0.83,green:0.67,blue:0.40,alpha:1).cgColor);c.move(to:CGPoint(x:a.x,y:a.y));c.addLine(to:CGPoint(x:b.x,y:b.y));c.strokePath()
            c.setFillColor(UIColor(red:0.84,green:0.88,blue:0.85,alpha:1).cgColor);c.move(to:CGPoint(x:b.x+2,y:b.y));c.addLine(to:CGPoint(x:b.x-3,y:b.y-2));c.addLine(to:CGPoint(x:b.x-3,y:b.y+2));c.closePath();c.fillPath();c.restoreGState()
        };c.restoreGState()
    }
}

/// Each limb/hand remains a separate native layer. The compact atlas preserves
/// approved pixel outlines and avoids rerasterizing sleeve seams on each tick.
private final class MeadowBowSurfaceView:UIImageView {
    var group="nearSleeveConnected"
    override init(frame:CGRect) { super.init(frame:frame);isUserInteractionEnabled=false;layer.minificationFilter = .nearest;layer.magnificationFilter = .nearest }
    required init?(coder:NSCoder) { fatalError() }
    private var lastSignature:Int?
    func update(_ sample:BowRigSample?,atlas:String?,torso:String?) {
        guard let sample else { image=nil;lastSignature=nil;return }
        var h=Hasher();h.combine(group);h.combine(atlas);h.combine(torso);h.combine(sample.nativeTiles?[group]);h.combine(sample.canvasBaked)
        if let pose=sample.parts["torso"] { h.combine(pose.offset.x);h.combine(pose.offset.y);h.combine(pose.rotation) }
        let signature=h.finalize();guard signature != lastSignature else { return }
        lastSignature=signature;image=Self.render(sample:sample,group:group,atlas:atlas,torso:torso)
    }
    static func render(sample:BowRigSample,group:String,atlas:String?=nil,torso:String?=nil)->UIImage {
        let format=UIGraphicsImageRendererFormat();format.scale=1
        return UIGraphicsImageRenderer(size:CGSize(width:256,height:256),format:format).image { renderer in
            let c=renderer.cgContext;c.setAllowsAntialiasing(false);c.interpolationQuality = .none
            if sample.canvasBaked != true, let pose=sample.parts["torso"] {
                let px=pose.pivot.x,py=pose.pivot.y,co=cos(pose.rotation),si=sin(pose.rotation)
                c.concatenate(CGAffineTransform(a:co,b:si,c:-si,d:co,tx:px+pose.offset.x-co*px+si*py,ty:py+pose.offset.y-si*px-co*py))
            }
            if sample.nativeTiles?[group] != nil {
                let tile=BowRig.nativeTile(sample,group:group)
                Self.nativeImage(tile,atlas:atlas).draw(in:CGRect(x:CGFloat(tile.canvasX),y:CGFloat(tile.canvasY),width:CGFloat(tile.width),height:CGFloat(tile.height)))
            } else if group=="head" {
                c.addRect(CGRect(x:100,y:75,width:57,height:58))
                c.move(to:CGPoint(x:121,y:126));c.addLine(to:CGPoint(x:135,y:130));c.addLine(to:CGPoint(x:134,y:138));c.addLine(to:CGPoint(x:125,y:138));c.addLine(to:CGPoint(x:119,y:134));c.closePath();c.clip()
                UIImage(named:"MeadowBattleBowReviewedBodyCore")?.draw(in:CGRect(x:0,y:0,width:256,height:256))
            } else if group=="torso" {
                UIImage(named:torso ?? "MeadowBattleBowReviewedTorso")?.draw(in:CGRect(x:0,y:0,width:256,height:256))
            }
        }
    }
    private static var atlases:[String:CGImage]=[:]
    private static var nativeImages:[String:UIImage]=[:]
    private static func nativeImage(_ tile:BowNativeTile,atlas:String?)->UIImage {
        let name=atlas ?? "MeadowBattleBowReviewedSleeves"
        let key="\(name)-\(tile.x)-\(tile.y)"
        if atlases[name]==nil { atlases[name]=UIImage(named:name)!.cgImage! }
        let nativeAtlas=atlases[name]!
        if let image=nativeImages[key] { return image }
        let rectangle=CGRect(x:CGFloat(tile.x),y:CGFloat(tile.y),width:CGFloat(tile.width),height:CGFloat(tile.height))
        let image=UIImage(cgImage:nativeAtlas.cropping(to:rectangle)!,scale:1,orientation:.up)
        nativeImages[key]=image;return image
    }
}
