import UIKit
import SwiftUI

enum MeadowBridgeAssets {
    private static let images = NSCache<NSString, UIImage>()
    static func data(_ name:String) -> Data? {
        Bundle.main.url(forResource:name,withExtension:"json",subdirectory:"MeadowArt").flatMap { try? Data(contentsOf:$0) }
    }
    static func image(_ name:String) -> UIImage? {
        if let cached = images.object(forKey:name as NSString) { return cached }
        guard let url=Bundle.main.url(forResource:name,withExtension:"png",subdirectory:"MeadowArt"), let image=UIImage(contentsOfFile:url.path) else { return nil }
        images.setObject(image,forKey:name as NSString); return image
    }
    private static let cells = NSCache<NSString, UIImage>()
    static let mapGround:UIImage? = {
        guard let image=image("MeadowCampGround")?.cgImage,
              let crop=image.cropping(to:CGRect(x:0,y:image.height*2/3,width:image.width,height:image.height/3)) else { return nil }
        return UIImage(cgImage:crop)
    }()
    static func cell(_ name:String, column:Int,row:Int,columns:Int,rows:Int) -> UIImage? {
        cells.countLimit=240
        let key="\(name):\(column):\(row)" as NSString
        if let cached=cells.object(forKey:key) { return cached }
        guard let atlas=image(name)?.cgImage, column>=0,column<columns,row>=0,row<rows,
              let crop=atlas.cropping(to:CGRect(x:column*atlas.width/columns,y:row*atlas.height/rows,width:atlas.width/columns,height:atlas.height/rows)) else { return nil }
        let value=UIImage(cgImage:crop);cells.setObject(value,forKey:key);return value
    }
}

/// Uses the accepted registered melee rig without changing joints or artwork.
struct MeadowBridgeHero: UIViewRepresentable {
    let clip:String
    let progress:Double
    func makeUIView(context:Context) -> MeadowBridgeHeroView { MeadowBridgeHeroView() }
    func updateUIView(_ view:MeadowBridgeHeroView,context:Context) { view.pose=MeadowBattleAnimation.sample(clip:clip,progress:CGFloat(progress));view.setNeedsLayout() }
}
final class MeadowBridgeHeroView: UIView {
    private let names=MeadowBattleActorConfiguration.load()?.layers ?? []
    private var parts:[String:UIImageView]=[:]
    var pose=MeadowBattleAnimation.sample(clip:"idle",progress:0)
    init() {
        super.init(frame:.zero);isUserInteractionEnabled=false
        for name in names {
            let image=UIImageView(image:MeadowBridgeAssets.image(name));image.layer.magnificationFilter = .nearest;image.layer.minificationFilter = .nearest
            addSubview(image);parts[name]=image
        }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) unsupported") }
    override func layoutSubviews() {
        super.layoutSubviews()
        var order=names
        if pose.clip != "idle" {
            order=["MeadowBattleHeroJointUnderlay","MeadowBattleHeroBodyCore",
                "MeadowBattleHeroLegFarThighBody","MeadowBattleHeroLegFarShinBody","MeadowBattleHeroLegNearThighBody","MeadowBattleHeroLegNearShinBody",
                "MeadowBattleHeroArmNearUpperBody","MeadowBattleHeroArmNearForearmBody","MeadowBattleHeroWardrobeCore",
                "MeadowBattleHeroLegFarThighWardrobe","MeadowBattleHeroLegFarShinWardrobe","MeadowBattleHeroLegNearThighWardrobe","MeadowBattleHeroLegNearShinWardrobe",
                "MeadowBattleHeroArmNearUpperWardrobe","MeadowBattleHeroArmNearForearmWardrobe","MeadowBattleHeroWeapon",
                "MeadowBattleHeroHair","MeadowBattleHeroFace","MeadowBattleHeroNearHand","MeadowBattleHeroFarHand"].filter { names.contains($0) }
        }
        UIView.performWithoutAnimation {
            layer.sublayerTransform=CATransform3DMakeTranslation(pose.rootOffset.x*bounds.width/256,pose.rootOffset.y*bounds.height/256,0)
            for (index,name) in order.enumerated() {
                guard let image=parts[name] else { continue }
                image.layer.setAffineTransform(.identity);image.frame=bounds;image.layer.zPosition=CGFloat(index)
                image.alpha=name == "MeadowBattleHeroJointUnderlay" && pose.clip == "idle" ? 0:1
                guard let p=pose.layers[name] else { continue }
                let sx=bounds.width/256,sy=bounds.height/256,c=cos(p.rotation)*p.scale,s=sin(p.rotation)*p.scale
                let x=p.pivot.x*sx,y=p.pivot.y*sy
                image.layer.setAffineTransform(CGAffineTransform(a:c,b:s,c:-s,d:c,tx:x+p.offset.x*sx-c*x+s*y,ty:y+p.offset.y*sy-s*x-c*y))
            }
        }
    }
}

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
        guard let data = MeadowBridgeAssets.data("animation"),
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
        guard let data = MeadowBridgeAssets.data("configuration") else { return nil }
        guard let configuration = try? JSONDecoder().decode(Self.self, from: data),
              configuration.canvasPx.count == 2, configuration.footAnchorPx.count == 2,
              configuration.canvasPx.allSatisfy({ $0 > 0 }),
              configuration.referenceHeightPx > 0, !configuration.layers.isEmpty else { return nil }
        return configuration
    }

    var canvasSize: CGSize { CGSize(width: canvasPx[0], height: canvasPx[1]) }
    var footAnchor: CGPoint { CGPoint(x: footAnchorPx[0], y: footAnchorPx[1]) }
}

