import Foundation

public struct BowPartPose:Codable {
    public let pivot:PartyPoint,offset:PartyPoint
    public let rotation:Double
    public init(_ pivot:PartyPoint,_ moved:PartyPoint,_ rotation:Double) { self.pivot=pivot;offset=PartyPoint(moved.x-pivot.x,moved.y-pivot.y);self.rotation=rotation }
}
public struct BowSurface:Codable { public let group:String,color:UInt32,points:[PartyPoint] }
/// Independent native layers, hand registrations and weapon/string anchors.
public struct BowRigSample:Codable {
    public let surfaces:[BowSurface]
    public let parts:[String:BowPartPose]
    public let upperTip:PartyPoint,lowerTip:PartyPoint,stringHand:PartyPoint
    public let arrowTail:PartyPoint,arrowTip:PartyPoint
    public let arrowVisible:Bool
    public let arrowAlpha:Double
    public var nativeFrame:Int? = nil
    public var sleeveTile:Int? = nil
    public var nativeTiles:[String:Int]? = nil
    public var drawingHandVariant:String? = nil
    /// Native state tiles already contain their own authored canvas transforms.
    public var canvasBaked:Bool? = nil
    public var rootOffset:PartyPoint? = nil
    public var groundY:Double? = nil
    public var contacts:[PartyPoint]? = nil
}
public struct BowNativeTile:Codable { public let x:Int,y:Int,width:Int,height:Int,canvasX:Int,canvasY:Int }
private struct ReviewedBowLibrary:Decodable {
    let schemaVersion:Int,frameDurationMs:Int
    let releaseArtTime:Double,recoveredArtTime:Double,restArtTime:Double
    let tiles:[BowNativeTile],frames:[BowRigSample]
    let clips:[String:[Int]]
}
public struct BowProjectile:Codable { public let tail:PartyPoint,tip:PartyPoint,alpha:Double }
public enum BowRig {
    public static let releaseAge=0.86
    public static let releaseProgress=(releaseAge-0.4)/1.2
    private static let library:ReviewedBowLibrary = {
        guard let url=Bundle.module.url(forResource:"reviewed-bow-r7",withExtension:"json"),
              let data=try? Data(contentsOf:url),let sheet=try? JSONDecoder().decode(ReviewedBowLibrary.self,from:data),
              sheet.schemaVersion==1,sheet.frames.count==345,Set(sheet.clips.keys)==Set(["guard","hit","victory","defeat"]) else { fatalError("Missing reviewed modular bow r7 library") }
        return sheet
    }()
    public static func nativeTile(_ sample:BowRigSample,group:String="nearSleeveConnected")->BowNativeTile { library.tiles[sample.nativeTiles![group]!] }
    /// Let the reviewed preparation start when the skill is confirmed. Keeping
    /// the old 0.4 s sword windup would squeeze all bow setup into 0.46 s.
    /// Recovery still observes the existing 0.1 s impact hold.
    public static func progress(age:Double)->Double {
        if age<=releaseAge { return max(0,age)/releaseAge*releaseProgress }
        let impactHold=min(0.1,max(0,age-1.048))
        return min(1,max(0,(age-0.4-impactHold)/1.2))
    }
    /// Keep the release/contact clock. Omit offline holds and preserve recovery.
    public static func artTime(progress:Double)->Double {
        let p=min(1,max(0,progress)),recovered=releaseProgress+0.34/1.2
        if p<=releaseProgress { return library.releaseArtTime*p/releaseProgress }
        if p<=recovered { return library.releaseArtTime+(p-releaseProgress)*1.2 }
        return library.recoveredArtTime+(library.restArtTime-library.recoveredArtTime)*(p-recovered)/(1-recovered)
    }
    public static func sample(clip:String,progress:Double,lean:Double=0,crouch:Double=0)->BowRigSample {
        let p=min(1,max(0,progress))
        let index:Int
        if let clipFrames=library.clips[clip] {
            index=clipFrames[min(clipFrames.count-1,Int((p*Double(clipFrames.count-1)+1e-7).rounded(.down)))]
        } else if clip=="attack" {
            index=min(142,Int((artTime(progress:p)*1000/Double(library.frameDurationMs)+1e-7).rounded(.down)))
        } else { index=142 }
        let source=library.frames[index]
        guard source.canvasBaked != true,lean != 0 || crouch != 0 else { return source }
        func body(_ q:PartyPoint)->PartyPoint {
            let x=q.x-132,y=q.y-167,c=cos(lean),s=sin(lean)
            return PartyPoint(132+x*c-y*s,167+x*s+y*c+crouch)
        }
        let surfaces=source.surfaces.map { s in BowSurface(group:s.group,color:s.color,points:s.points.map { q in let v=body(q);return PartyPoint(v.x.rounded(),v.y.rounded()) }) }
        let parts=source.parts.mapValues { q in BowPartPose(q.pivot,body(PartyPoint(q.pivot.x+q.offset.x,q.pivot.y+q.offset.y)),q.rotation+lean) }
        return BowRigSample(surfaces:surfaces,parts:parts,upperTip:body(source.upperTip),lowerTip:body(source.lowerTip),stringHand:body(source.stringHand),arrowTail:body(source.arrowTail),arrowTip:body(source.arrowTip),arrowVisible:source.arrowVisible,arrowAlpha:source.arrowAlpha,nativeFrame:source.nativeFrame,sleeveTile:source.sleeveTile,nativeTiles:source.nativeTiles,drawingHandVariant:source.drawingHandVariant)
    }
    public static var releaseArrowTip:PartyPoint { sample(clip:"attack",progress:releaseProgress).arrowTip }
    public static var releaseArrowLength:Double {
        let q=sample(clip:"attack",progress:releaseProgress)
        return hypot(q.arrowTip.x-q.arrowTail.x,q.arrowTip.y-q.arrowTail.y)
    }
    /// World-space projectile; use actor scale to preserve its native length.
    public static func projectile(age:Double,from:PartyPoint,to:PartyPoint,impact:Double,scale:Double=1)->BowProjectile? {
        guard age>=releaseAge,age<impact,impact>releaseAge else { return nil }
        let t=(age-releaseAge)/(impact-releaseAge),tip=PartyPoint(from.x+(to.x-from.x)*t,from.y+(to.y-from.y)*t)
        let dx=to.x-from.x,dy=to.y-from.y,length=max(1,hypot(dx,dy)),span=releaseArrowLength*scale
        return BowProjectile(tail:PartyPoint(tip.x-dx/length*span,tip.y-dy/length*span),tip:tip,alpha:1)
    }
}
