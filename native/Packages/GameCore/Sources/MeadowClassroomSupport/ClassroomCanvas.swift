import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Screen-independent game coordinates. Hosts letterbox; they never resize the
/// simulation canvas or derive another camera from a television's pixel scale.
public enum ClassroomCanvas {
    public static let size=CGSize(width:1280,height:720)
    public static func fitted(in host:CGSize)->CGRect {
        guard host.width>0,host.height>0 else{return .zero}
        let scale=min(host.width/size.width,host.height/size.height)
        let width=size.width*scale,height=size.height*scale
        return CGRect(x:(host.width-width)/2,y:(host.height-height)/2,width:width,height:height)
    }
    public static func point(_ point:CGPoint,in host:CGSize)->CGPoint? {
        let rect=fitted(in:host)
        guard rect.width>0,rect.height>0,rect.contains(point) else{return nil}
        return CGPoint(x:(point.x-rect.minX)*size.width/rect.width,y:(point.y-rect.minY)*size.height/rect.height)
    }
    /// Invert the actual renderer projection, including camera pan and zoom.
    public static func unproject(_ point:CGPoint,origin:CGPoint,xAxis:CGPoint,yAxis:CGPoint)->CGPoint? {
        let determinant=xAxis.x*yAxis.y-xAxis.y*yAxis.x
        guard determinant.isFinite,abs(determinant)>0.000001 else{return nil}
        let x=point.x-origin.x,y=point.y-origin.y
        return CGPoint(x:(x*yAxis.y-y*yAxis.x)/determinant,y:(y*xAxis.x-x*xAxis.y)/determinant)
    }
}
