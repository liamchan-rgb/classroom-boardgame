import UIKit
import MeadowWorldSupport
import MeadowBattleSupport

/// A nonmodal selection card: inspecting a building never pauses or rerolls the
/// expedition, and road clicks can immediately replace the movement target.
final class MeadowEncounterPreviewView:UIView {
    var classroomReadOnly=false {didSet {if classroomReadOnly {close.removeFromSuperview();enter.removeFromSuperview()}}}
    var onClose:(()->Void)?
    var onInteract:(()->Void)?
    private let title=MeadowPreviewPalette.label("",size:19)
    private let status=MeadowPreviewPalette.label("",size:15)
    private let close=MeadowPreviewPalette.button("×")
    private let enter=MeadowPreviewPalette.button("开始战斗")
    private let scroll=UIScrollView(),stack=UIStackView()
    private var renderedMonsters:[MeadowMonsterReadout]?
    var preferredHeight:CGFloat {min(430,110+CGFloat(max(1,renderedMonsters?.count ?? 1))*109)}
    override init(frame:CGRect){
        super.init(frame:frame);MeadowPreviewPalette.stylePanel(self)
        accessibilityIdentifier="campaignEncounterPreview"
        addSubview(title);addSubview(close);addSubview(scroll);addSubview(status);addSubview(enter)
        title.numberOfLines=1;title.adjustsFontSizeToFitWidth=true;title.minimumScaleFactor=0.8
        status.numberOfLines=2
        close.addAction(UIAction{[weak self] _ in self?.onClose?()},for:.touchUpInside)
        enter.addAction(UIAction{[weak self] _ in self?.onInteract?()},for:.touchUpInside)
        stack.axis = .vertical;stack.spacing=8;scroll.addSubview(stack);stack.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo:scroll.contentLayoutGuide.topAnchor),stack.leadingAnchor.constraint(equalTo:scroll.contentLayoutGuide.leadingAnchor),stack.trailingAnchor.constraint(equalTo:scroll.contentLayoutGuide.trailingAnchor),stack.bottomAnchor.constraint(equalTo:scroll.contentLayoutGuide.bottomAnchor),stack.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor)])
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override func layoutSubviews(){
        super.layoutSubviews()
        title.frame=CGRect(x:12,y:8,width:bounds.width-64,height:28)
        close.frame=CGRect(x:bounds.width-46,y:6,width:36,height:30)
        scroll.frame=CGRect(x:12,y:44,width:bounds.width-24,height:max(1,bounds.height-110))
        status.frame=CGRect(x:12,y:bounds.height-58,width:bounds.width-152,height:48)
        enter.frame=CGRect(x:bounds.width-134,y:bounds.height-53,width:122,height:38)
    }
    func show(_ value:MeadowEncounterReadout,completed:Bool){
        title.text=(value.boss ? "首领预览 · ":"怪物预览 · ")+value.title
        let alive=value.monsters.filter{$0.health>0}.count
        status.text=value.cleared ? "此处敌人已清理":completed ? "行程已结算\n只读预览":value.canInteract ? "\(alive)只存活\n已抵达，可开战":"\(alive)只存活\n抵达后可开战"
        enter.isEnabled=value.canInteract;enter.configuration?.title=value.cleared ? "已清理":"开始战斗"
        guard renderedMonsters != value.monsters else{return};renderedMonsters=value.monsters
        for v in stack.arrangedSubviews{stack.removeArrangedSubview(v);v.removeFromSuperview()}
        if value.monsters.isEmpty{let label=MeadowPreviewPalette.label("此地点没有怪物",size:17);stack.addArrangedSubview(label)}
        for monster in value.monsters {
            let row=UIStackView();row.axis = .horizontal;row.spacing=10;row.alignment = .center
            let image=UIImageView(image:Self.thumbnail(monster.templateID));image.contentMode = .scaleAspectFit;image.layer.magnificationFilter = .nearest
            image.alpha=monster.health>0 ? 1:0.3;image.isAccessibilityElement=true;image.accessibilityLabel=monster.name
            image.widthAnchor.constraint(equalToConstant:82).isActive=true;image.heightAnchor.constraint(equalToConstant:68).isActive=true
            let column=UIStackView();column.axis = .vertical;column.spacing=3
            let name=MeadowPreviewPalette.label(monster.name+(monster.health==0 ? " · 已击败":""),size:17)
            let health=MeadowBattleResourceBar();health.show("生命",value:monster.health,maximum:monster.maximumHealth,color:.systemGreen);health.heightAnchor.constraint(equalToConstant:34).isActive=true
            let detail=MeadowPreviewPalette.label("护盾 \(monster.shield) · 普攻 \(monster.attack) · 行动",size:14)
            let points=MeadowPreviewPalette.label(String(repeating:"◆",count:max(0,monster.baseAP)),size:15);points.textColor=MeadowPreviewPalette.gold
            points.accessibilityLabel="开场行动点 \(monster.baseAP)"
            points.widthAnchor.constraint(equalToConstant:64).isActive=true;points.heightAnchor.constraint(equalToConstant:20).isActive=true
            let statistics=UIStackView(arrangedSubviews:[detail,points]);statistics.axis = .horizontal;statistics.spacing=4;statistics.alignment = .center
            let skills=MeadowPreviewPalette.label(monster.skills.isEmpty ? "技能：无":"技能："+monster.skills.joined(separator:"、"),size:14);skills.numberOfLines=0
            column.addArrangedSubview(name);if monster.health>0{column.addArrangedSubview(health)};column.addArrangedSubview(statistics);column.addArrangedSubview(skills)
            row.addArrangedSubview(image);row.addArrangedSubview(column);stack.addArrangedSubview(row)
        }
        scroll.setContentOffset(.zero,animated:false)
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
