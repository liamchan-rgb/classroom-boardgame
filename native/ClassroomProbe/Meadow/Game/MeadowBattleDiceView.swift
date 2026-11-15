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
            // White numerals with a dark rim: readable on every gem colour and against any backdrop.
            let attrs:[NSAttributedString.Key:Any]=[.font:MeadowPreviewPalette.font(value>9 ? 84:96,.black),.foregroundColor:UIColor.white,.strokeColor:UIColor.black.withAlphaComponent(0.55),.strokeWidth:-3.5]
            let string=NSAttributedString(string:text,attributes:attrs),size=string.size()
            string.draw(at:CGPoint(x:(128-size.width)/2,y:(128-size.height)/2))
            if value==6 || value==9 { let path=UIBezierPath(roundedRect:CGRect(x:46,y:108,width:36,height:6),cornerRadius:3);UIColor.white.setFill();path.fill() }
        }
        glyphs[text]=im;return im
    }
    /// Gem palette: (light, base, deep) per die colour.
    private static let gems:[String:(UIColor,UIColor,UIColor)]=[
        "red":(UIColor(red:1.00,green:0.55,blue:0.50,alpha:1),UIColor(red:0.86,green:0.20,blue:0.22,alpha:1),UIColor(red:0.42,green:0.04,blue:0.10,alpha:1)),
        "yellow":(UIColor(red:1.00,green:0.92,blue:0.60,alpha:1),UIColor(red:0.95,green:0.70,blue:0.20,alpha:1),UIColor(red:0.52,green:0.30,blue:0.04,alpha:1)),
        "green":(UIColor(red:0.62,green:0.98,blue:0.70,alpha:1),UIColor(red:0.18,green:0.70,blue:0.42,alpha:1),UIColor(red:0.04,green:0.30,blue:0.16,alpha:1)),
        "blue":(UIColor(red:0.62,green:0.86,blue:1.00,alpha:1),UIColor(red:0.20,green:0.52,blue:0.92,alpha:1),UIColor(red:0.06,green:0.18,blue:0.48,alpha:1))]
    private static func mix(_ a:UIColor,_ b:UIColor,_ t:CGFloat)->UIColor {
        var r1:CGFloat=0,g1:CGFloat=0,b1:CGFloat=0,a1:CGFloat=0,r2:CGFloat=0,g2:CGFloat=0,b2:CGFloat=0,a2:CGFloat=0
        a.getRed(&r1,green:&g1,blue:&b1,alpha:&a1);b.getRed(&r2,green:&g2,blue:&b2,alpha:&a2)
        let t=max(0,min(1,t));return UIColor(red:r1+(r2-r1)*t,green:g1+(g2-g1)*t,blue:b1+(b2-b1)*t,alpha:1)
    }
    override func draw(_ rect:CGRect) {
        guard let ctx=UIGraphicsGetCurrentContext(),!dice.isEmpty else { return }
        let space=CGColorSpaceCreateDeviceRGB()
        for (index,die) in dice.enumerated() {
            let p=PolyhedralDice.sample(die:die,time:time,index:index,count:dice.count,resolvedAge:resolvedAge,visibleAge:visibleAge,exitAge:exitAge,locked:locked,confirmationAge:confirmationAge)
            guard p.alpha>0 else { continue }
            let gem=Self.gems[die.color] ?? (UIColor(white:0.85,alpha:1),UIColor(white:0.6,alpha:1),UIColor(white:0.25,alpha:1))
            let cx=bounds.midX+(CGFloat(index)-CGFloat(dice.count-1)/2)*PolyhedralDice.spacing(count:dice.count)
            ctx.saveGState();ctx.setAlpha(p.alpha);ctx.translateBy(x:cx,y:bounds.midY+p.offsetY-7)
            // Soft contact shadow under every die / token.
            ctx.saveGState()
            ctx.setFillColor(UIColor.black.withAlphaComponent(0.22).cgColor)
            ctx.fillEllipse(in:CGRect(x:-p.radius*0.85,y:p.radius*0.92-p.offsetY*0.3,width:p.radius*1.7,height:p.radius*0.34))
            ctx.restoreGState()
            if die.sides==0 {
                // A fixed amount has no die formula and must not look like a new random roll: a minted coin-badge.
                let r=min(24,p.radius*0.78)
                let coin=UIBezierPath(ovalIn:CGRect(x:-r,y:-r,width:r*2,height:r*2))
                ctx.saveGState();coin.addClip()
                if let g=CGGradient(colorsSpace:space,colors:[gem.0.cgColor,gem.1.cgColor,gem.2.cgColor] as CFArray,locations:[0,0.55,1]) {
                    ctx.drawLinearGradient(g,start:CGPoint(x:-r*0.4,y:-r),end:CGPoint(x:r*0.4,y:r),options:[])
                }
                ctx.restoreGState()
                let inner=UIBezierPath(ovalIn:CGRect(x:-r+4,y:-r+4,width:r*2-8,height:r*2-8))
                UIColor.white.withAlphaComponent(0.55).setStroke();inner.lineWidth=1.2;inner.stroke()
                gem.2.setStroke();coin.lineWidth=2;coin.stroke()
                let gloss=UIBezierPath(ovalIn:CGRect(x:-r*0.62,y:-r*0.86,width:r*1.24,height:r*0.62))
                UIColor.white.withAlphaComponent(0.28).setFill();gloss.fill()
                if let value=die.value {
                    let label=(die.color=="yellow" && value>0 ? "+":"")+String(value)
                    let size=min(26,r*(label.count>2 ? 0.82:1.0))
                    let shadow=NSShadow();shadow.shadowColor=UIColor.black.withAlphaComponent(0.55);shadow.shadowBlurRadius=2;shadow.shadowOffset=CGSize(width:0,height:1)
                    let s=NSAttributedString(string:label,attributes:[.font:MeadowPreviewPalette.font(size,.black),.foregroundColor:UIColor.white,.shadow:shadow])
                    s.draw(at:CGPoint(x:-s.size().width/2,y:-s.size().height/2))
                }
            } else {
                for face in p.faces {
                    guard let first=face.points.first else { continue }
                    let path=UIBezierPath();path.move(to:CGPoint(x:first.x*p.radius,y:first.y*p.radius))
                    for point in face.points.dropFirst() { path.addLine(to:CGPoint(x:point.x*p.radius,y:point.y*p.radius)) };path.close()
                    // Faces turned to the light pick up the light tone; faces turned away sink into the deep tone.
                    let lit=CGFloat(face.shade)
                    let top=lit>0.85 ? Self.mix(gem.1,gem.0,(lit-0.85)/0.15):Self.mix(gem.2,gem.1,lit/0.85)
                    let bottom=Self.mix(gem.2,top,0.55)
                    ctx.saveGState();path.addClip()
                    let box=path.bounds
                    if let g=CGGradient(colorsSpace:space,colors:[top.cgColor,bottom.cgColor] as CFArray,locations:[0,1]) {
                        ctx.drawLinearGradient(g,start:CGPoint(x:box.midX,y:box.minY),end:CGPoint(x:box.midX,y:box.maxY),options:[])
                    }
                    ctx.restoreGState()
                    UIColor.white.withAlphaComponent(0.22+0.25*max(0,lit-0.8)).setStroke();path.lineWidth=1.1;path.lineJoinStyle = .round;path.stroke()
                    let c=face.center,r=face.right,u=face.up
                    ctx.saveGState()
                    ctx.concatenate(CGAffineTransform(a:(r.x-c.x)*p.radius*2,b:(r.y-c.y)*p.radius*2,c:(c.x-u.x)*p.radius*2,d:(c.y-u.y)*p.radius*2,tx:c.x*p.radius,ty:c.y*p.radius))
                    Self.glyph(face.value).draw(in:CGRect(x:-0.5,y:-0.5,width:1,height:1));ctx.restoreGState()
                }
                // A dark rim around the whole silhouette keeps the die crisp over bright or busy backgrounds.
                let rim=UIBezierPath()
                for face in p.faces { guard let first=face.points.first else{continue};rim.move(to:CGPoint(x:first.x*p.radius,y:first.y*p.radius));for point in face.points.dropFirst(){rim.addLine(to:CGPoint(x:point.x*p.radius,y:point.y*p.radius))};rim.close() }
                ctx.saveGState();ctx.setBlendMode(.destinationOver)
                gem.2.withAlphaComponent(0.95).setStroke();rim.lineWidth=3.2;rim.lineJoinStyle = .round;rim.stroke()
                ctx.restoreGState()
            }
            ctx.restoreGState()
        }
    }
}
