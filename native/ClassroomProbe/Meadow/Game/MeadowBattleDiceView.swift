import UIKit
import MeadowBattleSupport

/// Perspective projection of actual numbered polyhedra. Face labels are attached
/// to face planes; only the core receipt chooses the final landing orientation.
final class MeadowBattleDiceView:UIView {
    var dice:[BattleDie]=[]
    var time=0.0,visibleAge=0.0
    var resolvedAge:Double?,exitAge:Double?,confirmationAge:Double?
    var locked=false
    private static var glyphs:[String:UIImage]=[:]
    override init(frame:CGRect) { super.init(frame:frame);backgroundColor = .clear;isOpaque=false;isUserInteractionEnabled=false;accessibilityIdentifier="battleHeadDice" }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    private static func glyph(_ value:Int)->UIImage {
        let text=String(value)
        if let cached=glyphs[text] { return cached }
        let format=UIGraphicsImageRendererFormat();format.scale=1
        let im=UIGraphicsImageRenderer(size:CGSize(width:128,height:128),format:format).image { _ in
            let attrs:[NSAttributedString.Key:Any]=[.font:MeadowPreviewPalette.font(value>9 ? 86:98,.heavy),.foregroundColor:MeadowPreviewPalette.ink,.strokeColor:UIColor.black.withAlphaComponent(0.45),.strokeWidth:-2]
            let string=NSAttributedString(string:text,attributes:attrs),size=string.size()
            string.draw(at:CGPoint(x:(128-size.width)/2,y:(128-size.height)/2))
            if value==6 || value==9 { let path=UIBezierPath();path.move(to:CGPoint(x:44,y:111));path.addLine(to:CGPoint(x:84,y:111));MeadowPreviewPalette.ink.setStroke();path.lineWidth=3;path.stroke() }
        }
        glyphs[text]=im;return im
    }
    override func draw(_ rect:CGRect) {
        guard let ctx=UIGraphicsGetCurrentContext(),!dice.isEmpty else { return }
        for (index,die) in dice.enumerated() {
            let p=PolyhedralDice.sample(die:die,time:time,index:index,count:dice.count,resolvedAge:resolvedAge,visibleAge:visibleAge,exitAge:exitAge,locked:locked,confirmationAge:confirmationAge)
            guard p.alpha>0 else { continue }
            let colors:[String:UIColor]=["red":UIColor(red:0.78,green:0.16,blue:0.14,alpha:1),"yellow":UIColor(red:0.85,green:0.63,blue:0.16,alpha:1),"green":UIColor(red:0.13,green:0.58,blue:0.32,alpha:1),"blue":UIColor(red:0.12,green:0.44,blue:0.8,alpha:1)]
            let color=colors[die.color] ?? .gray
            let cx=bounds.midX+(CGFloat(index)-CGFloat(dice.count-1)/2)*PolyhedralDice.spacing(count:dice.count)
            ctx.saveGState();ctx.setAlpha(p.alpha);ctx.translateBy(x:cx,y:bounds.midY+p.offsetY-7)
            func text(_ value:String,_ y:CGFloat,_ size:CGFloat,_ alpha:Double=1) {
                let attrs:[NSAttributedString.Key:Any]=[.font:MeadowPreviewPalette.font(size,.heavy),.foregroundColor:MeadowPreviewPalette.ink.withAlphaComponent(alpha),.strokeColor:UIColor.black.withAlphaComponent(0.5),.strokeWidth:-2]
                let s=NSAttributedString(string:value,attributes:attrs);s.draw(at:CGPoint(x:-s.size().width/2,y:y))
            }
            if die.sides==0 {
                // A fixed amount has no die formula and must not look like a new random roll.
                let w=min(52,p.radius*1.6),h=min(40,p.radius*1.25)
                let plate=UIBezierPath(roundedRect:CGRect(x:-w/2,y:-h/2,width:w,height:h),cornerRadius:6)
                color.setFill();plate.fill();MeadowPreviewPalette.ink.setStroke();plate.lineWidth=1.5;plate.stroke()
                let size=min(30,h*0.8)
                if let value=die.value { text((die.color=="yellow" && value>0 ? "+":"")+String(value),-size*0.67,size) }
            } else {
                var red:CGFloat=0,green:CGFloat=0,blue:CGFloat=0,alpha:CGFloat=0;color.getRed(&red,green:&green,blue:&blue,alpha:&alpha)
                for face in p.faces {
                    guard let first=face.points.first else { continue }
                    let path=UIBezierPath();path.move(to:CGPoint(x:first.x*p.radius,y:first.y*p.radius))
                    for point in face.points.dropFirst() { path.addLine(to:CGPoint(x:point.x*p.radius,y:point.y*p.radius)) };path.close()
                    UIColor(red:red*face.shade,green:green*face.shade,blue:blue*face.shade,alpha:1).setFill();path.fill()
                    MeadowPreviewPalette.ink.withAlphaComponent(0.68).setStroke();path.lineWidth=1;path.lineJoinStyle = .round;path.stroke()
                    let c=face.center,r=face.right,u=face.up
                    ctx.saveGState()
                    ctx.concatenate(CGAffineTransform(a:(r.x-c.x)*p.radius*2,b:(r.y-c.y)*p.radius*2,c:(c.x-u.x)*p.radius*2,d:(c.y-u.y)*p.radius*2,tx:c.x*p.radius,ty:c.y*p.radius))
                    Self.glyph(face.value).draw(in:CGRect(x:-0.5,y:-0.5,width:1,height:1));ctx.restoreGState()
                }
            }
            ctx.restoreGState()
        }
    }
}
