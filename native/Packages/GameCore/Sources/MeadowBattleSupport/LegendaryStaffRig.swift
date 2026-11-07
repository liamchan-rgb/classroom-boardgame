import Foundation

private struct LegendaryStaffKey: Decodable {
    let t: Double
    let root: [Double]
    let lean: Double
    let crouch: Double
    let shoulder: Double
    let elbow: Double
    let wrist: Double
    let nearHip: Double
    let nearKnee: Double
    let farHip: Double
    let farKnee: Double
    let flash: Double
    let recoil: Double
    var rootPoint: PartyPoint { PartyPoint(root[0],root[1]) }
}


private struct LegendaryStaffLibrary:Decodable { let schemaVersion:Int;let keys:[LegendaryStaffKey];let clips:[String:[LegendaryStaffKey]];let layerOrder:[String] }
/// Approved legendary-staff joint curves; equipment is still an independent layer.
public enum LegendaryStaffRig {
    private static let library:LegendaryStaffLibrary = {
        guard let url=Bundle.module.url(forResource:"legendary-staff-v1",withExtension:"json"),let data=try? Data(contentsOf:url),let value=try? JSONDecoder().decode(LegendaryStaffLibrary.self,from:data),value.schemaVersion==1,value.keys.count==241 else { fatalError("Missing legendary staff motion profile") }
        return value
    }()
    /// The held staff stays in front of the legs through idle, cast and recovery.
    public static var layerOrder:[String] { library.layerOrder }
    public static let impactAge=1.048
    public static let releaseAge=1.0*impactAge/1.25
    public static func artTime(age:Double)->Double {
        if age<=impactAge { return max(0,age)*1.25/impactAge }
        if age<=impactAge+0.1 { return 1.25 }
        return 1.25+0.52*min(1,max(0,(age-impactAge-0.1)/(1.7-impactAge-0.1)))
    }
    public static func progress(age:Double)->Double { min(1,max(0,(artTime(age:age)-0.12)/1.65)) }
    public static func point(_ point:PartyPoint,part:WeaponLayerPose,root:PartyPoint=PartyPoint(0,0))->PartyPoint {
        let x=point.x-part.pivot.x,y=point.y-part.pivot.y,c=cos(part.rotation),s=sin(part.rotation)
        return PartyPoint(part.pivot.x+part.offset.x+x*c-y*s+root.x,part.pivot.y+part.offset.y+x*s+y*c+root.y)
    }
    public static func gem(progress:Double)->PartyPoint {
        let q=pose(progress:progress)
        return point(PartyPoint(165,132),part:q.layers["MeadowBattleHeroWeapon"]!,root:q.rootOffset)
    }
    public static func pose(progress raw:Double,clip:String="attack") -> WeaponPoseSample {
        let name=clip
        let progress = min(1, max(0, raw))
        let sequence = clip=="attack" ? library.keys:library.clips[clip] ?? library.keys
        let upper = sequence.firstIndex(where: { $0.t >= progress }) ?? sequence.count - 1
        let a = sequence[max(0, upper - 1)], b = sequence[upper]
        let f = b.t == a.t ? 0 : (progress - a.t) / (b.t - a.t)
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * f }
        func mixPoint(_ x: PartyPoint, _ y: PartyPoint) -> PartyPoint { PartyPoint(mix(x.x, y.x),mix(x.y, y.y)) }
        let root = mixPoint(a.rootPoint, b.rootPoint)
        let lean = mix(a.lean, b.lean), crouch = mix(a.crouch, b.crouch)
        func bodyPoint(_ point: PartyPoint) -> PartyPoint {
            let dx = point.x - 132, dy = point.y - 167
            let c = cos(lean), s = sin(lean)
            return PartyPoint( 132 + dx * c - dy * s,
                            167 + dx * s + dy * c + crouch)
        }
        func rotate(_ point: PartyPoint, around pivot: PartyPoint, by angle: Double) -> PartyPoint {
            let x = point.x - pivot.x, y = point.y - pivot.y
            let c = cos(angle), s = sin(angle)
            return PartyPoint(pivot.x + x * c - y * s,pivot.y + x * s + y * c)
        }
        func layerPose(pivot: PartyPoint, movedPivot: PartyPoint, rotation: Double) -> WeaponLayerPose {
            .init(offset: PartyPoint(movedPivot.x - pivot.x,movedPivot.y - pivot.y),
                  pivot: pivot, rotation: rotation)
        }

        let shoulderPivot = PartyPoint(117,141), elbowPivot = PartyPoint(128,158)
        let gripPivot = PartyPoint(145.6,163.7)
        let shoulderAngle = mix(a.shoulder, b.shoulder)
        let elbowAngle = mix(a.elbow, b.elbow)
        let wristAngle = mix(a.wrist, b.wrist)
        let movedShoulder = bodyPoint(shoulderPivot)
        let movedElbow = bodyPoint(rotate(elbowPivot, around: shoulderPivot, by: shoulderAngle))
        let movedGrip = bodyPoint(rotate(rotate(gripPivot, around: elbowPivot, by: elbowAngle),
                                         around: shoulderPivot, by: shoulderAngle))
        let torsoPose = WeaponLayerPose(offset: PartyPoint(0,crouch),
                                              pivot: PartyPoint(132,167), rotation: lean)

        let nearHip = PartyPoint(134,175), nearKnee = PartyPoint(141,187)
        let farHip = PartyPoint(115,176), farKnee = PartyPoint(104,192)
        let nearHipAngle = mix(a.nearHip, b.nearHip), nearKneeAngle = mix(a.nearKnee, b.nearKnee)
        let farHipAngle = mix(a.farHip, b.farHip), farKneeAngle = mix(a.farKnee, b.farKnee)
        let movedNearHip = bodyPoint(nearHip)
        let movedNearKnee = bodyPoint(rotate(nearKnee, around: nearHip, by: nearHipAngle))
        let movedFarHip = bodyPoint(farHip)
        let movedFarKnee = bodyPoint(rotate(farKnee, around: farHip, by: farHipAngle))
        func legPoint(_ point: PartyPoint, hip: PartyPoint, knee: PartyPoint, hipAngle: Double, kneeAngle: Double) -> PartyPoint {
            bodyPoint(rotate(rotate(point, around: knee, by: kneeAngle), around: hip, by: hipAngle))
        }
        // Sample several points along each boot's registered sole. Screen y
        // grows downward, so the lowest transformed point is the support plane.
        let farSoles = [90, 98, 105].map {
            legPoint(PartyPoint(Double($0),214), hip: farHip, knee: farKnee,
                     hipAngle: farHipAngle, kneeAngle: farKneeAngle)
        }
        let nearSoles = [145, 150, 156].map {
            legPoint(PartyPoint(Double($0),214), hip: nearHip, knee: nearKnee,
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
        let layers: [String: WeaponLayerPose] = [
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
        let rootOffset = PartyPoint(root.x,root.y + 214 - groundY)
        func plantedBootContact(_ soles: [PartyPoint]) -> PartyPoint? {
            let planted = soles.filter { groundY - $0.y <= 1 }
            guard !planted.isEmpty else { return nil }
            return PartyPoint( planted.map(\.x).reduce(0, +) / Double(planted.count),
                            planted.map(\.y).reduce(0, +) / Double(planted.count))
        }
        let contacts = [plantedBootContact(farSoles), plantedBootContact(nearSoles)].compactMap { $0 }
        let anchorX = contacts.isEmpty ? 123 : contacts.map(\.x).reduce(0, +) / Double(contacts.count)
        return WeaponPoseSample(clip: name, progress: progress, rootOffset: rootOffset,
                                      footAnchorPx: PartyPoint(anchorX,groundY),
                                      contacts: contacts, layers: layers,
                                      hitFlash: mix(a.flash, b.flash), recoil: mix(a.recoil, b.recoil))
    }
}
