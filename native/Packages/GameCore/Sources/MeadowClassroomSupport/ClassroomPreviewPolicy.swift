import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Bound the teacher's auxiliary preview, independently of the 60 Hz game.
public enum ClassroomPreviewPolicy {
    public static let framesPerSecond=15.0
    public static let pixelScale=0.5
    public static func size(for source:CGSize)->CGSize {
        CGSize(width:max(1,(source.width*pixelScale).rounded(.down)),height:max(1,(source.height*pixelScale).rounded(.down)))
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
