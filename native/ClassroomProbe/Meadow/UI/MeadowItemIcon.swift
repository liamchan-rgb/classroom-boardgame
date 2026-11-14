import UIKit
import ClassroomGameCore

/// The picture of an item, wherever items are listed (shop, backpack, gains). Items with their own art use it (weapons, armour,
/// accessories, potions, revival stone); the rest (set pieces without art yet) get a drawn badge: a framed tile in the colour of
/// their set with a symbol for their kind, so every row still has a recognisable picture.
enum MeadowItemIcon {
    private static var cache:[String:UIImage]=[:]

    static func image(_ id:String,item:ItemDefinition?=nil)->UIImage {
        if let image=cache[id] { return image }
        // 像素图标（和人物同一套像素画法）：稀有以上带发光动画（PixelIconFX<Id>，24 帧横排，12 帧 / 秒），其余是静态图
        let cap=id.prefix(1).uppercased()+id.dropFirst()
        if let animated=animatedPixelIcon(cap) ?? UIImage(named:"PixelIcon"+cap) { cache[id]=animated;return animated }
        let asset=HeroFrames.weaponVisual(id)?.iconAsset ?? HeroFrames.armorVisual(id)?.iconAsset ?? HeroFrames.accessoryVisual(id)?.iconAsset
            ?? ["smallPotion":"MeadowPartySmallPotion","largePotion":"MeadowPartyLargePotion","shieldPotion":"MeadowPartyShieldPotion","revivalStone":"MeadowPartyRevivalStone"][id]
        let image=asset.flatMap { UIImage(named:$0) } ?? badge(id,item:item)
        cache[id]=image
        return image
    }

    private static func badge(_ id:String,item:ItemDefinition?)->UIImage {
        let set=item?.setID ?? (id.hasPrefix("starlight") ? "starlight":id.hasPrefix("dragon") ? "dragonMark":nil)
        let tint:UIColor = set=="starlight" ? UIColor(red:0.45,green:0.78,blue:1,alpha:1):set=="dragonMark" ? UIColor(red:0.95,green:0.38,blue:0.30,alpha:1):MeadowPreviewPalette.gold
        let symbol:String
        switch item?.slot {
        case .weapon?: symbol="bolt.fill"
        case .armor?: symbol="shield.lefthalf.filled"
        case .accessory?: symbol="seal.fill"
        default: symbol=item?.kind == .revivalStone ? "heart.circle.fill":"cross.vial.fill"
        }
        let size=CGSize(width:128,height:128)
        return UIGraphicsImageRenderer(size:size).image { r in
            let c=r.cgContext,box=CGRect(origin:.zero,size:size).insetBy(dx:8,dy:8)
            let path=UIBezierPath(roundedRect:box,cornerRadius:22)
            c.saveGState();path.addClip()
            let colors=[tint.withAlphaComponent(0.55).cgColor,UIColor(red:0.08,green:0.12,blue:0.09,alpha:1).cgColor] as CFArray
            if let g=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,1]) { c.drawRadialGradient(g,startCenter:CGPoint(x:64,y:50),startRadius:4,endCenter:CGPoint(x:64,y:64),endRadius:80,options:[]) }
            c.restoreGState()
            tint.setStroke();path.lineWidth=5;path.stroke()
            let config=UIImage.SymbolConfiguration(pointSize:52,weight:.bold)
            if let glyph=UIImage(systemName:symbol,withConfiguration:config)?.withTintColor(.white,renderingMode:.alwaysOriginal) {
                glyph.draw(in:CGRect(x:64-glyph.size.width/2,y:64-glyph.size.height/2,width:glyph.size.width,height:glyph.size.height))
            }
        }
    }

    /// The image scaled to a square of `side` points (for button images). Animated icons stay animated.
    static func image(_ id:String,item:ItemDefinition?=nil,side:CGFloat)->UIImage {
        let source=image(id,item:item)
        func scaled(_ frame:UIImage)->UIImage {
            UIGraphicsImageRenderer(size:CGSize(width:side,height:side)).image { r in
                r.cgContext.interpolationQuality = .none
                let k=min(side/frame.size.width,side/frame.size.height),w=frame.size.width*k,h=frame.size.height*k
                frame.draw(in:CGRect(x:(side-w)/2,y:(side-h)/2,width:w,height:h))
            }
        }
        if let frames=source.images,frames.count>1 { return UIImage.animatedImage(with:frames.map(scaled),duration:source.duration) ?? scaled(frames[0]) }
        return scaled(source)
    }

    /// 发光动画：素材是一条横排的帧，切开做成会动的 UIImage（UIImageView / 按钮直接播放）
    private static func animatedPixelIcon(_ cap:String)->UIImage? {
        guard let strip=UIImage(named:"PixelIconFX"+cap)?.cgImage,strip.height>0 else { return nil }
        let side=strip.height,count=strip.width/side
        guard count>1 else { return nil }
        let frames=(0..<count).compactMap { k in strip.cropping(to:CGRect(x:k*side,y:0,width:side,height:side)).map { UIImage(cgImage:$0) } }
        return UIImage.animatedImage(with:frames,duration:Double(count)/12)
    }
}
