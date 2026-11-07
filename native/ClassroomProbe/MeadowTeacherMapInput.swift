import SwiftUI
import UIKit
import MeadowClassroomSupport

struct MeadowTeacherMapInput:UIViewRepresentable {
    let canBegin:(CGPoint)->Bool
    let tap:(CGPoint)->Void
    let pan:(CGPoint)->Void
    let zoom:(CGFloat,CGPoint)->Void
    func makeUIView(context:Context)->MeadowMapInputView {MeadowMapInputView()}
    func updateUIView(_ view:MeadowMapInputView,context:Context){view.canBegin=canBegin;view.onTap=tap;view.onPan=pan;view.onZoom=zoom}
}
final class MeadowMapInputView:UIView,UIGestureRecognizerDelegate {
    var canBegin:((CGPoint)->Bool)?
    var onTap:((CGPoint)->Void)?
    var onPan:((CGPoint)->Void)?
    var onZoom:((CGFloat,CGPoint)->Void)?
    private var gestureStarts=[ObjectIdentifier:CGPoint]()
    private let tap=UITapGestureRecognizer(),pan=UIPanGestureRecognizer(),pinch=UIPinchGestureRecognizer()
    override init(frame:CGRect){
        super.init(frame:frame);isOpaque=false;backgroundColor = .clear;isMultipleTouchEnabled=true
        tap.addTarget(self,action:#selector(tapped));pan.addTarget(self,action:#selector(panned));pinch.addTarget(self,action:#selector(pinched))
        pan.minimumNumberOfTouches=1;pan.maximumNumberOfTouches=2
        for gesture in [tap,pan,pinch] as [UIGestureRecognizer] {gesture.delegate=self;addGestureRecognizer(gesture)}
        tap.require(toFail:pan);tap.require(toFail:pinch)
        accessibilityLabel="地图：拖动平移，双指缩放，点击道路移动"
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    private func point(_ gesture:UIGestureRecognizer)->CGPoint? {ClassroomCanvas.point(gesture.location(in:self),in:bounds.size)}
    override func gestureRecognizerShouldBegin(_ gestureRecognizer:UIGestureRecognizer)->Bool {
        guard let p=gestureStarts[ObjectIdentifier(gestureRecognizer)] ?? point(gestureRecognizer) else{return false};return canBegin?(p) ?? false
    }
    func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldReceive touch:UITouch)->Bool {
        guard let p=ClassroomCanvas.point(touch.location(in:self),in:bounds.size),canBegin?(p)==true else{return false}
        gestureStarts[ObjectIdentifier(gestureRecognizer)]=p;return true
    }
    func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldRecognizeSimultaneouslyWith otherGestureRecognizer:UIGestureRecognizer)->Bool {
        (gestureRecognizer === pan && otherGestureRecognizer === pinch) || (gestureRecognizer === pinch && otherGestureRecognizer === pan)
    }
    func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldBeRequiredToFailBy otherGestureRecognizer:UIGestureRecognizer)->Bool {
        // The containing settings page must wait for an in-map pan to fail.
        otherGestureRecognizer.view is UIScrollView
    }
    @objc private func tapped(){guard let p=point(tap) else{return};onTap?(p)}
    @objc private func panned(){
        if pan.state == .began || pan.state == .changed || pan.state == .ended {
            if let delta=ClassroomCanvas.translation(pan.translation(in:self),in:bounds.size){onPan?(delta)}
            pan.setTranslation(.zero,in:self)
        }
    }
    @objc private func pinched(){
        if pinch.state == .began || pinch.state == .changed || pinch.state == .ended,let p=point(pinch){onZoom?(pinch.scale,p);pinch.scale=1}
    }
}
