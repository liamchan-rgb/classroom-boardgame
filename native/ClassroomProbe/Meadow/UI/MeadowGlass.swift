import UIKit
import ClassroomGameCore

/// Soft meadow-coloured light behind full-screen glass sheets (shop, pack): blurred colour blobs so the frosted
/// panels above have something to frost.
enum MeadowGlassBackdrop {
    static func install(in view:UIView) {
        let backdrop=UIView(frame:view.bounds);backdrop.autoresizingMask=[.flexibleWidth,.flexibleHeight];backdrop.isUserInteractionEnabled=false
        let gradient=CAGradientLayer()
        gradient.colors=[UIColor(red:0.05,green:0.14,blue:0.10,alpha:1).cgColor,UIColor(red:0.08,green:0.16,blue:0.20,alpha:1).cgColor,UIColor(red:0.16,green:0.13,blue:0.08,alpha:1).cgColor]
        gradient.startPoint=CGPoint(x:0,y:0);gradient.endPoint=CGPoint(x:1,y:1)
        gradient.frame=CGRect(x:0,y:0,width:3000,height:2000)
        backdrop.layer.addSublayer(gradient)
        // Soft colour pools as radial gradients (static; no blur view).
        for (x,y,r,color) in [(0.18,0.22,520.0,UIColor(red:0.35,green:0.70,blue:0.45,alpha:0.30)),(0.82,0.78,560.0,UIColor(red:0.95,green:0.70,blue:0.35,alpha:0.22)),(0.70,0.15,420.0,UIColor(red:0.40,green:0.62,blue:0.90,alpha:0.20))] {
            let pool=CAGradientLayer();pool.type = .radial
            pool.colors=[color.cgColor,color.withAlphaComponent(0).cgColor]
            pool.startPoint=CGPoint(x:0.5,y:0.5);pool.endPoint=CGPoint(x:1,y:1)
            pool.frame=CGRect(x:x*1400-r,y:y*1000-r,width:r*2,height:r*2)
            backdrop.layer.addSublayer(pool)
        }
        view.insertSubview(backdrop,at:0)
    }
}

/// The glass "sheen" of a panel: a light top highlight fading down (static), plus, on request, a real blur for
/// panels that sit over a static backdrop (shop / pack sheets), where the blur costs nothing per frame.
final class MeadowGlassSheen: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    static func install(in view: UIView, liveBlur: Bool) {
        // A scroll view would scroll its sheen away with the content: it keeps the plain tint.
        guard !(view is UIScrollView), !view.subviews.contains(where: { $0 is MeadowGlassSheen }) else { return }
        let sheen = MeadowGlassSheen(frame: view.bounds)
        sheen.autoresizingMask = [.flexibleWidth, .flexibleHeight]; sheen.isUserInteractionEnabled = false
        sheen.layer.cornerRadius = view.layer.cornerRadius; sheen.layer.cornerCurve = .continuous; sheen.clipsToBounds = true
        if let g = sheen.layer as? CAGradientLayer {
            g.colors = [UIColor.white.withAlphaComponent(0.13).cgColor, UIColor.white.withAlphaComponent(0.03).cgColor, UIColor.white.withAlphaComponent(0).cgColor]
            g.locations = [0, 0.35, 1]
        }
        if liveBlur {
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
            blur.frame = sheen.bounds; blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]; blur.isUserInteractionEnabled = false
            sheen.insertSubview(blur, at: 0)
            view.backgroundColor = UIColor(red: 0.05, green: 0.10, blue: 0.08, alpha: 0.42)
        }
        view.insertSubview(sheen, at: 0)
    }
}

/// An SF Symbol followed by a short number or word, for icon-first labels.
enum MeadowGlassText {
    static func iconLine(_ symbol:String,_ text:String,size:CGFloat,tint:UIColor=MeadowPreviewPalette.ink,weight:UIFont.Weight = .bold)->NSAttributedString {
        let font=MeadowPreviewPalette.font(size,weight)
        let line=NSMutableAttributedString()
        if let image=UIImage(systemName:symbol,withConfiguration:UIImage.SymbolConfiguration(font:font))?.withTintColor(tint,renderingMode:.alwaysOriginal) {
            line.append(NSAttributedString(attachment:NSTextAttachment(image:image)))
            line.append(NSAttributedString(string:" "))
        }
        line.append(NSAttributedString(string:text,attributes:[.font:font,.foregroundColor:MeadowPreviewPalette.ink]))
        return line
    }
}


/// Text style for floating battle numbers and words. Digits keep the heavy outlined look; anything with
/// Chinese (or other CJK) characters drops the outline — an outline on those glyphs reads as a pile of
/// black line segments — and uses a semibold rounded face lifted by a soft shadow instead.
enum MeadowBattleText {
    static func hasCJK(_ text:String)->Bool {text.unicodeScalars.contains{$0.value>=0x2E80}}
    static func attributes(_ text:String,size:CGFloat,fill:UIColor,alpha:CGFloat,stroke:CGFloat = -4)->[NSAttributedString.Key:Any] {
        if hasCJK(text) {
            let shadow=NSShadow();shadow.shadowColor=UIColor.black.withAlphaComponent(0.75*alpha);shadow.shadowBlurRadius=size*0.18;shadow.shadowOffset=CGSize(width:0,height:size*0.05)
            let base=UIFont.systemFont(ofSize:size*0.9,weight:.semibold)
            let font=UIFont(descriptor:base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor,size:size*0.9)
            return [.font:font,.foregroundColor:fill.withAlphaComponent(alpha),.shadow:shadow,.kern:size*0.04]
        }
        return [.font:UIFont.systemFont(ofSize:size,weight:.heavy),.foregroundColor:fill.withAlphaComponent(alpha),.strokeColor:UIColor(red:0.10,green:0.07,blue:0.04,alpha:alpha),.strokeWidth:stroke]
    }
}

extension GameDifficulty {
    /// The teacher's last choice, used for the next new journey (a per-device convenience, not saved game state).
    static var lastChosen:GameDifficulty {
        get {UserDefaults.standard.string(forKey:"classroom.difficulty").flatMap(GameDifficulty.init(rawValue:)) ?? .normal}
        set {UserDefaults.standard.set(newValue.rawValue,forKey:"classroom.difficulty")}
    }
}
