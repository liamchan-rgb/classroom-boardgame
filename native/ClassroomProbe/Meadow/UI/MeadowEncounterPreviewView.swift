import UIKit
import MeadowWorldSupport
import MeadowBattleSupport

/// A crisp, dense nonmodal encounter preview card with per-monster frosted sub-cards, colored stat badges, and zero slack whitespace.
final class MeadowEncounterPreviewView:UIView {
    var classroomReadOnly=false {didSet {if classroomReadOnly {close.removeFromSuperview();enter.removeFromSuperview()}}}
    var onClose:(()->Void)?
    var onInteract:(()->Void)?
    private let kindPill=UILabel()
    private let title=MeadowPreviewPalette.label("",size:18,weight:.heavy)
    private let status=MeadowPreviewPalette.label("",size:13.5,weight:.semibold)
    private let close=MeadowPreviewPalette.button("×")
    private let enter=MeadowPreviewPalette.button("开始战斗")
    private let scroll=UIScrollView(),stack=UIStackView()
    private var renderedMonsters:[MeadowMonsterReadout]?
    var preferredHeight:CGFloat {
        let rows=max(1,renderedMonsters?.count ?? 1)
        let footerH:CGFloat=classroomReadOnly ? 38:52
        return min(440,48+footerH+CGFloat(rows)*118)
    }

    override init(frame:CGRect){
        super.init(frame:frame);MeadowPreviewPalette.stylePanel(self)
        backgroundColor=UIColor(red:0.95,green:0.98,blue:0.98,alpha:0.95)
        layer.borderWidth=1.6;layer.borderColor=UIColor.white.cgColor
        accessibilityIdentifier="campaignEncounterPreview"

        kindPill.font=MeadowPreviewPalette.font(11.5,.heavy);kindPill.textColor = .white;kindPill.textAlignment = .center
        kindPill.layer.cornerRadius=7;kindPill.clipsToBounds=true

        [kindPill,title,close,scroll,status,enter].forEach(addSubview)
        title.numberOfLines=1;title.adjustsFontSizeToFitWidth=true;title.minimumScaleFactor=0.75
        status.numberOfLines=2;status.textColor=MeadowPreviewPalette.muted
        close.addAction(UIAction{[weak self] _ in self?.onClose?()},for:.touchUpInside)
        enter.addAction(UIAction{[weak self] _ in self?.onInteract?()},for:.touchUpInside)

        stack.axis = .vertical;stack.spacing=7;scroll.addSubview(stack);stack.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo:scroll.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo:scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo:scroll.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo:scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor)
        ])
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}

    override func layoutSubviews(){
        super.layoutSubviews()
        let rightPad:CGFloat = classroomReadOnly ? 12 : 48
        kindPill.frame=CGRect(x:12,y:10,width:42,height:22)
        title.frame=CGRect(x:60,y:8,width:max(40,bounds.width-60-rightPad),height:26)
        close.frame=CGRect(x:bounds.width-44,y:6,width:34,height:28)
        let footerH:CGFloat = classroomReadOnly ? 32 : 48
        scroll.frame=CGRect(x:10,y:38,width:bounds.width-20,height:max(1,bounds.height-38-footerH-6))
        if classroomReadOnly {
            status.frame=CGRect(x:12,y:bounds.height-32,width:bounds.width-24,height:26)
        } else {
            status.frame=CGRect(x:12,y:bounds.height-48,width:bounds.width-146,height:40)
            enter.frame=CGRect(x:bounds.width-130,y:bounds.height-46,width:118,height:36)
        }
    }

    func show(_ value:MeadowEncounterReadout,completed:Bool){
        kindPill.text=value.boss ? "首领":"遭遇"
        kindPill.backgroundColor=value.boss ? UIColor(red:0.78,green:0.18,blue:0.16,alpha:1) : MeadowPreviewPalette.primary
        title.text=value.title
        let alive=value.monsters.filter{$0.health>0}.count
        status.text=value.cleared ? "此处敌人已清理":completed ? "行程已结算 · 只读预览":value.canInteract ? "\(alive) 只存活 · 已抵达可开战":"\(alive) 只存活 · 抵达后可开战"
        enter.isEnabled=value.canInteract;enter.configuration?.title=value.cleared ? "已清理":"开始战斗"
        guard renderedMonsters != value.monsters else{return};renderedMonsters=value.monsters
        for v in stack.arrangedSubviews{stack.removeArrangedSubview(v);v.removeFromSuperview()}
        if value.monsters.isEmpty{
            let label=MeadowPreviewPalette.label("此地点没有怪物",size:15,weight:.semibold);label.textColor=MeadowPreviewPalette.muted
            stack.addArrangedSubview(label)
        }
        for monster in value.monsters {
            let subcard=UIView()
            subcard.backgroundColor=UIColor.white.withAlphaComponent(monster.health>0 ? 0.78 : 0.45)
            subcard.layer.cornerRadius=12;subcard.layer.cornerCurve = .continuous
            subcard.layer.borderWidth=1.2
            subcard.layer.borderColor=(value.boss && monster.health>0 ? UIColor(red:0.86,green:0.30,blue:0.24,alpha:0.55) : MeadowPreviewPalette.ink.withAlphaComponent(0.12)).cgColor

            let row=UIStackView();row.axis = .horizontal;row.spacing=9;row.alignment = .center
            row.translatesAutoresizingMaskIntoConstraints=false
            subcard.addSubview(row)
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo:subcard.topAnchor,constant:7),
                row.bottomAnchor.constraint(equalTo:subcard.bottomAnchor,constant:-7),
                row.leadingAnchor.constraint(equalTo:subcard.leadingAnchor,constant:8),
                row.trailingAnchor.constraint(equalTo:subcard.trailingAnchor,constant:-8),
            ])

            let portraitWrap=UIView()
            portraitWrap.backgroundColor=MeadowPreviewPalette.ink.withAlphaComponent(0.06)
            portraitWrap.layer.cornerRadius=9;portraitWrap.clipsToBounds=true
            portraitWrap.widthAnchor.constraint(equalToConstant:72).isActive=true
            portraitWrap.heightAnchor.constraint(equalToConstant:62).isActive=true
            let image=UIImageView(image:Self.thumbnail(monster.templateID));image.contentMode = .scaleAspectFit;image.layer.magnificationFilter = .nearest
            image.alpha=monster.health>0 ? 1:0.32;image.isAccessibilityElement=true;image.accessibilityLabel=monster.name
            image.translatesAutoresizingMaskIntoConstraints=false;portraitWrap.addSubview(image)
            NSLayoutConstraint.activate([
                image.topAnchor.constraint(equalTo:portraitWrap.topAnchor,constant:3),
                image.bottomAnchor.constraint(equalTo:portraitWrap.bottomAnchor,constant:-3),
                image.leadingAnchor.constraint(equalTo:portraitWrap.leadingAnchor,constant:3),
                image.trailingAnchor.constraint(equalTo:portraitWrap.trailingAnchor,constant:-3),
            ])

            let column=UIStackView();column.axis = .vertical;column.spacing=4
            let name=MeadowPreviewPalette.label(monster.name+(monster.health==0 ? " · 已击败":""),size:15.5,weight:.heavy)
            name.textColor=monster.health>0 ? MeadowPreviewPalette.ink : MeadowPreviewPalette.muted
            column.addArrangedSubview(name)

            if monster.health>0 {
                let health=MeadowBattleResourceBar()
                health.show("生命",value:monster.health,maximum:monster.maximumHealth,color:UIColor(red:0.18,green:0.68,blue:0.32,alpha:1))
                health.heightAnchor.constraint(equalToConstant:30).isActive=true
                column.addArrangedSubview(health)
            }

            let statsRow=UIStackView();statsRow.axis = .horizontal;statsRow.spacing=5;statsRow.alignment = .center
            statsRow.addArrangedSubview(Self.badgePill("攻 \(monster.attack)",bg:UIColor(red:0.80,green:0.22,blue:0.20,alpha:0.13),fg:UIColor(red:0.72,green:0.15,blue:0.14,alpha:1)))
            if monster.shield>0 {
                statsRow.addArrangedSubview(Self.badgePill("盾 \(monster.shield)",bg:UIColor(red:0.12,green:0.50,blue:0.86,alpha:0.14),fg:UIColor(red:0.08,green:0.40,blue:0.76,alpha:1)))
            }
            let apPill=Self.badgePill(String(repeating:"◆",count:max(1,monster.baseAP)),bg:UIColor(red:0.88,green:0.58,blue:0.08,alpha:0.15),fg:MeadowPreviewPalette.gold)
            apPill.accessibilityLabel="开场行动点 \(monster.baseAP)"
            statsRow.addArrangedSubview(apPill)
            statsRow.addArrangedSubview(UIView())
            column.addArrangedSubview(statsRow)

            if !monster.skills.isEmpty {
                let skills=MeadowPreviewPalette.label("技能："+monster.skills.joined(separator:" · "),size:12.5,weight:.semibold)
                skills.textColor=MeadowPreviewPalette.muted;skills.numberOfLines=2
                column.addArrangedSubview(skills)
            }

            row.addArrangedSubview(portraitWrap);row.addArrangedSubview(column)
            stack.addArrangedSubview(subcard)
        }
        scroll.setContentOffset(.zero,animated:false)
    }

    private static func badgePill(_ text:String,bg:UIColor,fg:UIColor)->UILabel {
        let l=UILabel()
        l.text="  \(text)  "
        l.font=MeadowPreviewPalette.font(12,.heavy)
        l.textColor=fg;l.backgroundColor=bg
        l.layer.cornerRadius=6;l.clipsToBounds=true
        l.heightAnchor.constraint(equalToConstant:20).isActive=true
        return l
    }

    private static var thumbnails:[String:UIImage]=[:]
    private static func thumbnail(_ id:String)->UIImage? {
        if let image=thumbnails[id]{return image}
        let spec=MonsterVisualSpec.find(id)
        guard let sheet=UIImage(named:spec.map{$0.asset+"Motion"} ?? "MeadowBattleForestWarden")?.cgImage,
              let tile=sheet.cropping(to:CGRect(x:0,y:0,width:384,height:256)),
              let context=CGContext(data:nil,width:384,height:256,bitsPerComponent:8,bytesPerRow:384*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue) else{return nil}
        context.draw(tile,in:CGRect(x:0,y:0,width:384,height:256))
        guard let bytes=context.data?.assumingMemoryBound(to:UInt8.self) else{return nil}
        var minX=384,minY=256,maxX=0,maxY=0
        for y in 0..<256 {for x in 0..<384 where bytes[(y*384+x)*4+3]>0 {minX=min(minX,x);minY=min(minY,y);maxX=max(maxX,x+1);maxY=max(maxY,y+1)}}
        guard maxX>minX,maxY>minY,let cropped=context.makeImage()?.cropping(to:CGRect(x:minX,y:minY,width:maxX-minX,height:maxY-minY)) else{return nil}
        let image=UIImage(cgImage:cropped);thumbnails[id]=image;return image
    }
}
