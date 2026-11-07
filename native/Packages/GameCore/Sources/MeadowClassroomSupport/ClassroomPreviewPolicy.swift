import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Bound the teacher's auxiliary preview, independently of the 60 Hz game.
public enum ClassroomPreviewPolicy {
    public static let framesPerSecond=30.0
    public static let pixelScale=0.75
    public static func size(for source:CGSize)->CGSize {
        CGSize(width:max(1,(source.width*pixelScale).rounded(.down)),height:max(1,(source.height*pixelScale).rounded(.down)))
    }
    public static func refreshOverlay(now:Double,last:Double,dirty:Bool,battle:Bool)->Bool {
        (dirty || battle) && now-last >= 1/(battle ? framesPerSecond:10)
    }
    public static func enabled(external:Bool,visible:Bool,foreground:Bool,privateModal:Bool,surface:ClassroomPublicSurface)->Bool {
        external && visible && foreground && !privateModal && surface != .book && surface != .waiting
    }
}
public extension ClassroomPublicSurface {
    var acceptsMapInput:Bool {
        switch self {case .exploration,.encounter:return true;default:return false}
    }
}

/// Keep the sampling phase despite slightly early native vsync; drop backlog
/// after suspension instead of trying to replay missed frames.
public struct ClassroomPreviewClock {
    private var next:Double?
    public init(){}
    public mutating func take(at now:Double)->Bool {
        guard now.isFinite else{return false}
        let step=1/ClassroomPreviewPolicy.framesPerSecond
        if let next,now+0.0005<next{return false}
        let planned=(next ?? now)+step
        next=planned<now ? now+step:max(planned,now+step*0.5)
        return true
    }
}
