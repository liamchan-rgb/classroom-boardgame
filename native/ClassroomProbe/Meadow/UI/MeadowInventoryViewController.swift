import UIKit
import UniformTypeIdentifiers
import MeadowWorldSupport
import MeadowBattleSupport
import ClassroomGameCore

/// UIKit inventory. The camp model is the single source of counts and actions.
final class MeadowInventoryViewController:UIViewController,UIDocumentPickerDelegate {
    let session:CampInventorySession
    var performEquip:((ItemSlot,String?)throws->Void)?
    var performAppearance:((String)throws->Void)?
    var performImport:((Data)throws->Void)?
    var onChange:(()->Void)?
    var onClose:(()->Void)?
    var startupIssue:String?
    private let header=UIView(),left=UIScrollView(),middle=UIView(),right=UIView()
    private let titleLabel=MeadowPreviewPalette.label("行囊与装备",size:25,weight:.heavy)
    private let saveLabel=MeadowPreviewPalette.label("",size:15)
    private let close=MeadowPreviewPalette.button("返回林地")
    private let exportButton=MeadowPreviewPalette.button("导出")
    private let importButton=MeadowPreviewPalette.button("导入")
    private let footer=MeadowPreviewPalette.label("林地演练使用独立补给，不扣除营地背包。",size:15)
    private let hero=UIImageView(),walk=MeadowPreviewPalette.button("查看步态")
    private let clothes=UISegmentedControl(items:HeroFrames.appearanceTitles)
    private let slots=ItemSlot.allCases.map { _ in UIButton(type:.system) }
    private let vitals=MeadowBattleResourceBar()
    private let filterButton=MeadowPreviewPalette.button("全部物品 ▾")
    private let list=UIScrollView(),empty=MeadowPreviewPalette.label("背包里暂时没有这类物品",size:17)
    private let detailScroll=UIScrollView(),detailContent=UIView()
    private let primary=MeadowPreviewPalette.button("装备")
    private let actions=MeadowBattleActionPointsView()
    private let statsLabel=MeadowPreviewPalette.label("",size:16)
    private var filter="all",selected:String?,target="p1",walking=false
    private var rows:[UIButton]=[]
    private let filters=[("all","全部物品"),("weapon","武器"),("armor","护甲"),("accessory","饰品"),("supplies","道具")]
    init(session:CampInventorySession) { self.session=session;super.init(nibName:nil,bundle:nil);modalPresentationStyle = .fullScreen;isModalInPresentation=true }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var prefersStatusBarHidden:Bool { true }
    override var supportedInterfaceOrientations:UIInterfaceOrientationMask { .landscape }
    override func viewDidLoad() {
        super.viewDidLoad();view.backgroundColor=UIColor(red:0.045,green:0.085,blue:0.058,alpha:1)
        [header,left,middle,right].forEach { MeadowPreviewPalette.stylePanel($0);view.addSubview($0) }
        [titleLabel,saveLabel,close,exportButton,importButton].forEach(header.addSubview)
        view.addSubview(footer);right.addSubview(detailScroll);detailScroll.addSubview(detailContent);right.addSubview(primary)
        primary.addAction(UIAction { [weak self] _ in self?.activateSelected() },for:.touchUpInside)
        close.addAction(UIAction { [weak self] _ in guard let self else{return};self.hero.stopAnimating();self.dismiss(animated:true) { self.onClose?() } },for:.touchUpInside)
        exportButton.addAction(UIAction { [weak self] _ in self?.exportSave() },for:.touchUpInside)
        importButton.addAction(UIAction { [weak self] _ in self?.openImport() },for:.touchUpInside)
        hero.contentMode = .scaleAspectFit;hero.layer.magnificationFilter = .nearest;hero.layer.minificationFilter = .nearest;hero.isAccessibilityElement=true;hero.accessibilityLabel="P1当前衣装与装备预览"
        [hero,walk,clothes,vitals,actions,statsLabel].forEach(left.addSubview)
        walk.addAction(UIAction { [weak self] _ in guard let self else{return};self.walking.toggle();self.refreshHero() },for:.touchUpInside)
        clothes.addTarget(self,action:#selector(changeClothes),for:.valueChanged)
        clothes.setTitleTextAttributes([.font:MeadowPreviewPalette.font(16),.foregroundColor:MeadowPreviewPalette.ink],for:.normal)
        clothes.setTitleTextAttributes([.font:MeadowPreviewPalette.font(16),.foregroundColor:MeadowPreviewPalette.ink],for:.selected)
        clothes.selectedSegmentTintColor=UIColor(red:0.40,green:0.35,blue:0.19,alpha:1)
        for (index,button) in slots.enumerated() {
            left.addSubview(button);button.titleLabel?.font=MeadowPreviewPalette.font(17);button.titleLabel?.numberOfLines=2;button.contentHorizontalAlignment = .left
            button.setTitleColor(MeadowPreviewPalette.ink,for:.normal);button.layer.borderWidth=1;button.layer.borderColor=MeadowPreviewPalette.border.cgColor;button.layer.cornerRadius=5
            button.addAction(UIAction { [weak self] _ in self?.selectSlot(ItemSlot.allCases[index]) },for:.touchUpInside)
        }
        middle.addSubview(filterButton);middle.addSubview(list);list.addSubview(empty)
        filterButton.showsMenuAsPrimaryAction=true;list.alwaysBounceVertical=true;left.alwaysBounceVertical=true;detailScroll.alwaysBounceVertical=true
        for scroll in [left,list,detailScroll] { scroll.indicatorStyle = .white }
        refresh()
    }
    func refresh() {
        let unit=session.loadout.units["p1"]!,catalog=session.loadout.engine.catalog
        let entries=CampInventoryProjection.entries(unit,catalog:catalog,filter:filter)
        if !entries.contains(where:{$0.id==selected}) { selected=entries.first?.id }
        for row in rows { row.removeFromSuperview() };rows=[]
        for entry in entries {
            let row=UIButton(type:.system);row.backgroundColor=MeadowPreviewPalette.panel.withAlphaComponent(0.65)
            row.layer.cornerRadius=6;row.layer.borderWidth=entry.id==selected ? 2:1;row.layer.borderColor=(entry.id==selected ? MeadowPreviewPalette.gold:MeadowPreviewPalette.border).cgColor
            let icon=UIImageView(image:inventoryIcon(entry.id));icon.contentMode = .scaleAspectFit;icon.tag=1
            let name=MeadowPreviewPalette.label(entry.name,size:18,weight:.bold);name.numberOfLines=2;name.tag=2
            let amount=MeadowPreviewPalette.label("背包 ×\(entry.quantity)"+(entry.equipped ? " · 已装备":""),size:15);amount.tag=3
            [icon,name,amount].forEach { $0.isUserInteractionEnabled=false;row.addSubview($0) }
            row.accessibilityLabel=entry.name+"，背包\(entry.quantity)"+(entry.equipped ? "，已装备":"")
            row.accessibilityIdentifier="inventoryItem-"+entry.id
            row.addAction(UIAction { [weak self] _ in self?.selected=entry.id;self?.refresh() },for:.touchUpInside)
            list.addSubview(row);rows.append(row)
        }
        empty.isHidden = !entries.isEmpty
        for (i,slot) in ItemSlot.allCases.enumerated() {
            let name=unit.equipment[slot].flatMap { try? catalog.item($0).name } ?? (slot == .weapon ? "空手":"未装备")
            slots[i].setTitle("  "+CampInventoryProjection.slotTitle(slot)+"\n  "+name,for:.normal)
        }
        clothes.selectedSegmentIndex=HeroFrames.appearanceIDs.firstIndex(of:session.appearanceID) ?? 0
        let stats=try? GameRules.attributes(unit,catalog:catalog)
        vitals.show("生命",value:unit.health,maximum:stats?.maximumHealth ?? 12,color:.systemGreen)
        actions.show(value:unit.ap,maximum:stats?.maximumAP ?? 8)
        statsLabel.text="额外伤害＋\(stats?.damage ?? 0) · 金币 \(unit.coins)"
        filterButton.configuration?.title=(filters.first{$0.0==filter}?.1 ?? "全部物品")+" ▾"
        filterButton.menu=UIMenu(children:filters.map { id,title in UIAction(title:title,state:id==filter ? .on:.off) { [weak self] _ in self?.filter=id;self?.selected=nil;self?.list.setContentOffset(.zero,animated:false);self?.refresh() } })
        if session.loadIssue != nil || startupIssue != nil { saveLabel.text="保存未启用 · 当前临时试装";saveLabel.textColor = .systemOrange }
        else if let saved=session.lastSaved { let f=DateFormatter();f.dateFormat="HH:mm:ss";saveLabel.text="P1 · 营地 · 已保存 "+f.string(from:saved);saveLabel.textColor=MeadowPreviewPalette.ink }
        else { saveLabel.text="P1 · 营地 · 临时配置" }
        refreshHero();view.setNeedsLayout()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews();let s=view.safeAreaInsets
        let layout=CampInventoryLayout(width:Double(view.bounds.width),height:Double(view.bounds.height),left:Double(s.left),right:Double(s.right),top:Double(s.top),bottom:Double(s.bottom))
        header.frame=rect(layout.header);left.frame=rect(layout.equipment);middle.frame=rect(layout.bag);right.frame=rect(layout.detail);footer.frame=rect(layout.footer)
        let w=header.bounds.width;titleLabel.frame=CGRect(x:12,y:2,width:max(1,w-284),height:29);saveLabel.frame=CGRect(x:12,y:31,width:max(1,w-284),height:22)
        close.frame=CGRect(x:w-118,y:9,width:108,height:38);exportButton.frame=CGRect(x:w-184,y:9,width:60,height:38);importButton.frame=CGRect(x:w-250,y:9,width:60,height:38)
        let lw=left.bounds.width,heroHeight=min(240,max(133,left.bounds.height*0.30)),shift=heroHeight-133
        hero.frame=CGRect(x:12,y:9,width:lw-24,height:heroHeight)
        walk.frame=CGRect(x:12,y:147+shift,width:lw-24,height:36);clothes.frame=CGRect(x:12,y:191+shift,width:lw-24,height:32)
        vitals.frame=CGRect(x:12,y:232+shift,width:lw-24,height:43)
        actions.frame=CGRect(x:12,y:282+shift,width:lw-24,height:43);statsLabel.frame=CGRect(x:12,y:335+shift,width:lw-24,height:26)
        for (i,button) in slots.enumerated() { button.frame=CGRect(x:12,y:370+shift+CGFloat(i)*61,width:lw-24,height:54) }
        left.contentSize=CGSize(width:lw,height:564+shift)
        filterButton.frame=CGRect(x:10,y:9,width:middle.bounds.width-20,height:38)
        list.frame=CGRect(x:8,y:55,width:middle.bounds.width-16,height:max(1,middle.bounds.height-63))
        for (i,row) in rows.enumerated() {
            row.frame=CGRect(x:0,y:CGFloat(i)*86,width:list.bounds.width,height:78)
            row.viewWithTag(1)?.frame=CGRect(x:8,y:15,width:42,height:48)
            row.viewWithTag(2)?.frame=CGRect(x:58,y:7,width:row.bounds.width-64,height:43)
            row.viewWithTag(3)?.frame=CGRect(x:58,y:51,width:row.bounds.width-64,height:22)
        }
        list.contentSize=CGSize(width:list.bounds.width,height:CGFloat(rows.count)*86);empty.frame=CGRect(x:8,y:12,width:list.bounds.width-16,height:70);empty.numberOfLines=3
        detailScroll.frame=CGRect(x:0,y:0,width:right.bounds.width,height:max(1,right.bounds.height-66))
        primary.frame=CGRect(x:12,y:max(0,right.bounds.height-54),width:right.bounds.width-24,height:44)
        layoutDetail()
    }
    private func layoutDetail() {
        detailContent.subviews.forEach { $0.removeFromSuperview() }
        let w=right.bounds.width;var y:CGFloat=12
        func text(_ value:String,_ size:CGFloat=17,_ weight:UIFont.Weight = .medium) {
            let l=MeadowPreviewPalette.label(value,size:size,weight:weight);l.numberOfLines=0;l.textColor=MeadowPreviewPalette.ink
            let h=ceil(l.sizeThatFits(CGSize(width:w-24,height:10000)).height);l.frame=CGRect(x:12,y:y,width:w-24,height:max(24,h));detailContent.addSubview(l);y+=max(24,h)+9
        }
        func button(_ title:String,_ enabled:Bool=true,_ action:@escaping ()->Void) {
            let b=MeadowPreviewPalette.button(title);b.isEnabled=enabled;b.alpha=enabled ? 1:0.45;b.frame=CGRect(x:12,y:y,width:w-24,height:44)
            b.addAction(UIAction { _ in action() },for:.touchUpInside);detailContent.addSubview(b);y+=54
        }
        if let issue=session.loadIssue ?? startupIssue {
            text(issue,16)
            if session.savingBlocked { button("保留旧档并启用保存") { [weak self] in self?.attempt { try self?.session.preserveOldAndEnableSaving() } } }
        }
        if let selected,let d=try? CampInventoryProjection.detail(selected,session:session,target:target) {
            let icon=UIImageView(image:inventoryIcon(selected));icon.contentMode = .scaleAspectFit;icon.frame=CGRect(x:(w-68)/2,y:y,width:68,height:68);detailContent.addSubview(icon);y+=78
            text(d.name,22,.bold);text("背包 ×\(d.quantity)"+(d.equipped ? " · 当前装备":""),16)
            text(d.summary,18);text(d.category=="supplies" ? "使用效果":"换装对比",18,.bold)
            if d.category=="supplies" {
                let targets=UISegmentedControl(items:["P1","P2"]);targets.selectedSegmentIndex=target=="p1" ? 0:1
                for state in [UIControl.State.normal,.selected] { targets.setTitleTextAttributes([.font:MeadowPreviewPalette.font(16),.foregroundColor:MeadowPreviewPalette.ink],for:state) }
                targets.selectedSegmentTintColor=UIColor(red:0.40,green:0.35,blue:0.19,alpha:1)
                targets.addAction(UIAction { [weak self,weak targets] _ in self?.target=targets?.selectedSegmentIndex==1 ? "p2":"p1";self?.view.setNeedsLayout() },for:.valueChanged)
                targets.frame=CGRect(x:12,y:y,width:w-24,height:36);detailContent.addSubview(targets);y+=46
            }
            for line in d.comparison { text(line,16) }
            if !d.reason.isEmpty { text(d.reason,16) }
            primary.configuration?.title=d.actionTitle;primary.isEnabled=d.enabled;primary.alpha=d.enabled ? 1:0.45;primary.isHidden=false
        } else { text("选择物品查看详情与换装对比。",18);primary.isHidden=true }
        button("立即保存",!session.savingBlocked && startupIssue==nil) { [weak self] in self?.attempt { try self?.session.saveNow() } }
        detailContent.frame=CGRect(x:0,y:0,width:w,height:y+8);detailScroll.contentSize=detailContent.bounds.size
    }
    private func refreshHero() {
        let unit=session.loadout.units["p1"]!,index=HeroFrames.appearanceIDs.firstIndex(of:session.appearanceID) ?? 0
        let images=HeroFrames.inventoryImages(appearanceIndex:index,weaponID:unit.equipment.weapon,armorID:unit.equipment.armor)
        hero.stopAnimating();hero.image=images.first
        if walking,images.count>1 { hero.animationImages=Array(images.dropFirst());hero.animationDuration=Double(images.count-1)*0.12;hero.animationRepeatCount=0;hero.startAnimating() }
        else { hero.animationImages=nil }
        walk.configuration?.title=walking ? "查看站姿":"查看步态"
    }
    private func selectSlot(_ slot:ItemSlot) { filter=slot.rawValue;selected=session.loadout.units["p1"]?.equipment[slot];list.setContentOffset(.zero,animated:false);refresh() }
    @objc private func changeClothes() {
        guard HeroFrames.appearanceIDs.indices.contains(clothes.selectedSegmentIndex) else{return}
        let id=HeroFrames.appearanceIDs[clothes.selectedSegmentIndex];attempt { try performAppearance?(id) }
    }
    private func activateSelected() {
        guard let selected,let item=try? session.loadout.engine.catalog.item(selected) else{return}
        attempt {
            if let slot=item.slot { let equipped=session.loadout.units["p1"]?.equipment[slot]==selected;try performEquip?(slot,equipped ? nil:selected) }
            else { try session.use(item:selected,target:target) }
        }
    }
    private func attempt(_ operation:()throws->Void) {
        do { try operation();onChange?();refresh() }
        catch { refresh();let a=UIAlertController(title:"操作未完成",message:error.localizedDescription,preferredStyle:.alert);a.addAction(UIAlertAction(title:"知道了",style:.default));present(a,animated:true) }
    }
    private func exportSave() {
        do {
            let u=FileManager.default.temporaryDirectory.appendingPathComponent("Meadow-Camp-"+UUID().uuidString+".json");try session.exportData().write(to:u,options:.atomic)
            let sheet=UIActivityViewController(activityItems:[u],applicationActivities:nil);sheet.popoverPresentationController?.sourceView=exportButton;sheet.popoverPresentationController?.sourceRect=exportButton.bounds;present(sheet,animated:true)
        } catch { attempt { throw error } }
    }
    private func openImport() {
        let picker=UIDocumentPickerViewController(forOpeningContentTypes:[.json],asCopy:true);picker.delegate=self;picker.allowsMultipleSelection=false;present(picker,animated:true)
    }
    func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) {
        guard let url=urls.first else{return};let scoped=url.startAccessingSecurityScopedResource();defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data=try Data(contentsOf:url);let save=try session.inspectImport(data),unit=save.archive.state.units["p1"]!
            let names=try unit.equipment.itemIDs.map { try save.archive.catalog.item($0).name }
            let a=UIAlertController(title:"载入营地配置？",message:"P1："+names.joined(separator:"、")+"\n当前配置会另存一份后再载入。",preferredStyle:.alert)
            a.addAction(UIAlertAction(title:"取消",style:.cancel));a.addAction(UIAlertAction(title:"载入",style:.default) { [weak self] _ in self?.attempt { try self?.performImport?(data) } });present(a,animated:true)
        } catch { attempt { throw error } }
    }
    private func rect(_ r:InventoryRect)->CGRect { CGRect(x:r.x,y:r.y,width:r.width,height:r.height) }
    private func inventoryIcon(_ id:String)->UIImage? {
        let asset=HeroFrames.weaponVisual(id)?.iconAsset ?? HeroFrames.armorVisual(id)?.iconAsset ?? HeroFrames.accessoryVisual(id)?.iconAsset ?? ["smallPotion":"MeadowPartySmallPotion","largePotion":"MeadowPartyLargePotion","shieldPotion":"MeadowPartyShieldPotion","revivalStone":"MeadowPartyRevivalStone"][id]
        return asset.flatMap { UIImage(named:$0) }
    }
}

/// Uses the expedition's live engine; never stages a separate camp inventory.
final class MeadowCampaignInventoryViewController:UIViewController {
    let session:MeadowCampaignSession
    var performEquip:((String,ItemSlot,String?)throws->Void)?
    var onChange:(()->Void)?,onClose:(()->Void)?
    var onActorChanged:((String)->Void)?
    private var actor:String,target:String,selected:String?,filter="all"
    private let header=UIView(),left=UIScrollView(),middle=UIView(),right=UIView()
    private let titleLabel=MeadowPreviewPalette.label("行程行囊",size:24,weight:.heavy)
    private let saveLabel=MeadowPreviewPalette.label("随操作自动保存到当前行程",size:14)
    private let members=UISegmentedControl()
    private let close=MeadowPreviewPalette.button("返回行程")
    private let refillActions=MeadowPreviewPalette.button("手动整备")
    private let hero=UIImageView(),health=MeadowBattleResourceBar(),ap=MeadowBattleActionPointsView()
    private let stats=MeadowPreviewPalette.label("",size:16)
    private let slots=ItemSlot.allCases.map{_ in MeadowPreviewPalette.button("")}
    private let filterButton=MeadowPreviewPalette.button("全部物品 ▾"),list=UIScrollView()
    private let detailContent=UIView()
    private let detail=UIScrollView(),primary=MeadowPreviewPalette.button("使用")
    private let footer=MeadowPreviewPalette.label("手动整备补足各成员基础行动 · 用药和救援消耗使用者的行动与个人物品",size:14)
    private var rows:[UIButton]=[]
    private let filters=[("all","全部物品"),("weapon","武器"),("armor","护甲"),("accessory","饰品"),("supplies","补给")]
    private let visualEquipment:Set<String>=["trainingSword","huntingBow","greatSword","legendaryStaff","leatherArmor","runeArmor","powerBadge","actionRing"]
    init(session:MeadowCampaignSession,actor:String) {
        self.session=session;self.actor=session.playerIDs.contains(actor) ? actor:"p1";target=self.actor
        super.init(nibName:nil,bundle:nil);modalPresentationStyle = .fullScreen;isModalInPresentation=true
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override var prefersStatusBarHidden:Bool{true}
    override var supportedInterfaceOrientations:UIInterfaceOrientationMask{.landscape}
    override func viewDidLoad(){
        super.viewDidLoad();view.backgroundColor=UIColor(red:0.045,green:0.085,blue:0.058,alpha:1)
        [header,left,middle,right].forEach{MeadowPreviewPalette.stylePanel($0);view.addSubview($0)}
        [titleLabel,saveLabel,members,close].forEach(header.addSubview);view.addSubview(footer)
        [refillActions,hero,health,ap,stats].forEach(left.addSubview);hero.contentMode = .scaleAspectFit;hero.layer.magnificationFilter = .nearest
        refillActions.accessibilityIdentifier="campaignRefillInventoryActions"
        refillActions.accessibilityLabel="手动补足各成员基础行动"
        refillActions.addAction(UIAction{[weak self] _ in
            guard let self else{return}
            do{try self.session.refillInventoryActions();self.saveLabel.text="各成员已按自身基础行动补足";self.onChange?();self.refresh()}
            catch{self.refresh();let alert=UIAlertController(title:"整备未完成",message:error.localizedDescription,preferredStyle:.alert);alert.addAction(UIAlertAction(title:"知道了",style:.default));self.present(alert,animated:true)}
        },for:.touchUpInside)
        stats.numberOfLines=0;footer.numberOfLines=2
        left.alwaysBounceVertical=true;list.alwaysBounceVertical=true;detail.alwaysBounceVertical=true
        middle.addSubview(filterButton);middle.addSubview(list);right.addSubview(detail);detail.addSubview(detailContent);right.addSubview(primary)
        close.addAction(UIAction{[weak self] _ in self?.dismiss(animated:true){self?.onClose?()}},for:.touchUpInside)
        for (i,id) in session.playerIDs.enumerated(){members.insertSegment(withTitle:id.uppercased()+" 行囊",at:i,animated:false)}
        for state in [UIControl.State.normal,.selected] {members.setTitleTextAttributes([.font:MeadowPreviewPalette.font(16),.foregroundColor:MeadowPreviewPalette.ink],for:state)}
        members.selectedSegmentTintColor=UIColor(red:0.40,green:0.35,blue:0.19,alpha:1)
        members.addAction(UIAction{[weak self] _ in
            guard let self else{return};self.actor=self.session.playerIDs[max(0,self.members.selectedSegmentIndex)];self.target=self.actor;self.selected=nil;self.filter="all";self.onActorChanged?(self.actor);self.refresh()
        },for:.valueChanged)
        for (i,slot) in ItemSlot.allCases.enumerated(){
            left.addSubview(slots[i]);slots[i].titleLabel?.numberOfLines=2
            slots[i].addAction(UIAction{[weak self] _ in guard let self else{return};self.filter=slot.rawValue;self.selected=self.session.engine.state.units[self.actor]?.equipment[slot];self.refresh()},for:.touchUpInside)
        }
        filterButton.showsMenuAsPrimaryAction=true
        primary.addAction(UIAction{[weak self] _ in self?.activate()},for:.touchUpInside)
        refresh()
    }
    private func refresh(){
        guard let unit=session.engine.state.units[actor] else{return};let catalog=session.engine.catalog
        let entries=CampInventoryProjection.entries(unit,catalog:catalog,filter:filter)
        if !entries.contains(where:{$0.id==selected}){selected=entries.first?.id}
        rows.forEach{$0.removeFromSuperview()};rows=[]
        for e in entries {
            let row=MeadowPreviewPalette.button(e.name+"\n背包 ×\(e.quantity)"+(e.equipped ? " · 已装备":""))
            row.configuration?.title=e.name;row.configuration?.subtitle="背包 ×\(e.quantity)"+(e.equipped ? " · 已装备":"")
            row.configuration?.baseBackgroundColor=e.id==selected ? MeadowPreviewPalette.gold:MeadowPreviewPalette.panel
            row.configuration?.baseForegroundColor=e.id==selected ? MeadowPreviewPalette.panel:MeadowPreviewPalette.ink
            row.configuration?.subtitleTextAttributesTransformer=UIConfigurationTextAttributesTransformer { value in var v=value;v.font=MeadowPreviewPalette.font(15,.medium);return v }
            row.accessibilityIdentifier="campaignInventoryItem-"+e.id
            row.addAction(UIAction{[weak self] _ in self?.selected=e.id;self?.refresh()},for:.touchUpInside)
            list.addSubview(row);rows.append(row)
        }
        if rows.isEmpty{let row=MeadowPreviewPalette.button("暂无此类物品");row.isEnabled=false;list.addSubview(row);rows=[row]}
        members.selectedSegmentIndex=session.playerIDs.firstIndex(of:actor) ?? 0
        refillActions.isEnabled=session.inventoryActionRefillNeeded;refillActions.alpha=refillActions.isEnabled ? 1:0.45
        let a=try? GameRules.attributes(unit,catalog:catalog)
        health.show("生命",value:unit.health,maximum:a?.maximumHealth ?? 1,color:.systemGreen);ap.show(value:unit.ap,maximum:a?.maximumAP ?? 8)
        stats.text="\(unit.name)\n金币 \(unit.coins) · 积分 \(unit.score)\n额外伤害 ＋\(a?.damage ?? 0)"+(actor=="p2" ? "\nP2装备规则可用，地图形象暂沿用原资源。":"")
        hero.image=actor=="p1" ? HeroFrames.inventoryImages(appearanceIndex:HeroFrames.appearanceIDs.firstIndex(of:session.snapshot.appearanceID) ?? 0,weaponID:unit.equipment.weapon,armorID:unit.equipment.armor).first:nil
        for (i,slot) in ItemSlot.allCases.enumerated(){
            let name=unit.equipment[slot].flatMap{try? catalog.item($0).name} ?? "未装备"
            slots[i].configuration?.title=CampInventoryProjection.slotTitle(slot)+" · "+name
        }
        filterButton.configuration?.title=(filters.first{$0.0==filter}?.1 ?? "全部物品")+" ▾"
        filterButton.menu=UIMenu(children:filters.map{id,title in UIAction(title:title,state:id==filter ? .on:.off){[weak self] _ in self?.filter=id;self?.selected=nil;self?.refresh()}})
        view.setNeedsLayout()
    }
    override func viewDidLayoutSubviews(){
        super.viewDidLayoutSubviews();let s=view.safeAreaInsets
        let l=CampInventoryLayout(width:Double(view.bounds.width),height:Double(view.bounds.height),left:Double(s.left),right:Double(s.right),top:Double(s.top),bottom:Double(s.bottom))
        func frame(_ r:InventoryRect)->CGRect{CGRect(x:r.x,y:r.y,width:r.width,height:r.height)}
        header.frame=frame(l.header);left.frame=frame(l.equipment);middle.frame=frame(l.bag);right.frame=frame(l.detail);footer.frame=frame(l.footer)
        let w=header.bounds.width;titleLabel.frame=CGRect(x:12,y:2,width:max(1,w-650),height:29);saveLabel.frame=CGRect(x:12,y:31,width:max(1,w-650),height:22)
        members.frame=CGRect(x:w-634,y:12,width:500,height:34);close.frame=CGRect(x:w-122,y:9,width:112,height:38)
        let lw=left.bounds.width,hh:CGFloat=actor=="p1" ? 150:0
        refillActions.frame=CGRect(x:10,y:8,width:lw-20,height:38)
        hero.frame=CGRect(x:8,y:56,width:lw-16,height:hh);health.frame=CGRect(x:10,y:hh+64,width:lw-20,height:42);ap.frame=CGRect(x:10,y:hh+113,width:lw-20,height:38)
        stats.frame=CGRect(x:10,y:hh+159,width:lw-20,height:actor=="p2" ? 100:72)
        let sy=hh+(actor=="p2" ? 268:240)
        for (i,b) in slots.enumerated(){b.frame=CGRect(x:10,y:sy+CGFloat(i)*56,width:lw-20,height:48)}
        left.contentSize=CGSize(width:lw,height:sy+172)
        filterButton.frame=CGRect(x:8,y:8,width:middle.bounds.width-16,height:38);list.frame=CGRect(x:8,y:54,width:middle.bounds.width-16,height:max(1,middle.bounds.height-62))
        for(i,row) in rows.enumerated(){row.frame=CGRect(x:0,y:CGFloat(i)*82,width:list.bounds.width,height:74)}
        list.contentSize=CGSize(width:list.bounds.width,height:CGFloat(rows.count)*82)
        detail.frame=CGRect(x:0,y:0,width:right.bounds.width,height:max(1,right.bounds.height-64));primary.frame=CGRect(x:10,y:right.bounds.height-54,width:right.bounds.width-20,height:44)
        layoutDetail()
    }
    private func layoutDetail(){
        detailContent.subviews.forEach{$0.removeFromSuperview()}
        detailContent.frame=CGRect(x:0,y:0,width:detail.bounds.width,height:100);detail.contentSize=detailContent.bounds.size
        let width=detail.bounds.width;var y:CGFloat=12
        func text(_ value:String,_ size:CGFloat=17){let label=MeadowPreviewPalette.label(value,size:size);label.numberOfLines=0;let h=max(24,label.sizeThatFits(CGSize(width:max(1,width-24),height:10000)).height);label.frame=CGRect(x:12,y:y,width:width-24,height:h);detailContent.addSubview(label);y+=h+12}
        primary.isHidden=true
        guard let id=selected,let item=try? session.engine.catalog.item(id),let unit=session.engine.state.units[actor] else{text("选择物品查看详情");return}
        text(item.name,22);text(CampInventoryProjection.summary(item));text("背包 ×\(unit.inventory[id] ?? 0)")
        primary.isHidden=false;primary.isEnabled=false
        if let slot=item.slot {
            let equipped=unit.equipment[slot]==id;primary.configuration?.title=equipped ? "卸下装备":"装备"
            if actor != "p1" || !visualEquipment.contains(id){text("专属外观尚有缺口，暂用现有形象；属性与技能按实际装备生效。")}
            do{
                let comparison=try session.equipmentComparison(actor:actor,slot:slot,item:equipped ? nil:id)
                text(comparison.summary)
                text("换装不回血、不补行动或移动。地图移动上限按全队最大行动上限平均计算；基础行动加成不提高移动上限。",15);primary.isEnabled=true
            }catch{text(error.localizedDescription)}
        }else{
            let targets=UISegmentedControl(items:session.playerIDs.map{$0.uppercased()});targets.selectedSegmentIndex=session.playerIDs.firstIndex(of:target) ?? 0
            for state in [UIControl.State.normal,.selected] {targets.setTitleTextAttributes([.font:MeadowPreviewPalette.font(16),.foregroundColor:MeadowPreviewPalette.ink],for:state)}
            targets.selectedSegmentTintColor=UIColor(red:0.40,green:0.35,blue:0.19,alpha:1)
            targets.frame=CGRect(x:12,y:y,width:width-24,height:36);detailContent.addSubview(targets);y+=48
            targets.addAction(UIAction{[weak self,weak targets] _ in guard let self else{return};self.target=self.session.playerIDs[max(0,targets?.selectedSegmentIndex ?? 0)];self.view.setNeedsLayout()},for:.valueChanged)
            primary.configuration?.title=item.kind == .revivalStone ? "复活队友 · 2 AP":"使用补给 · 1 AP"
            if let receiver=session.engine.state.units[target],let a=try? GameRules.attributes(receiver,catalog:session.engine.catalog){text("使用者：\(actor.uppercased())\n目标：\(target.uppercased())\n生命 \(receiver.health) → \(item.kind == .revivalStone ? (a.maximumHealth+1)/2:min(a.maximumHealth,receiver.health+item.heal))/\(a.maximumHealth)\n护盾 \(receiver.shield) → \(max(receiver.shield,item.shield))")}
            do{let command=try session.inventoryItemCommand(actor:actor,item:id,target:target),preview=session.engine.preview(command);primary.isEnabled=preview.allowed;if !preview.allowed{text(preview.message)}}catch{text(error.localizedDescription)}
        }
        detailContent.frame=CGRect(x:0,y:0,width:width,height:y+12);detail.contentSize=detailContent.bounds.size
    }
    private func activate(){
        guard let id=selected,let item=try? session.engine.catalog.item(id) else{return}
        do{
            if let slot=item.slot {
                guard let performEquip else{throw GameError("装备入口不可用。")}
                try performEquip(actor,slot,session.engine.state.units[actor]?.equipment[slot]==id ? nil:id)
            }else{try session.useInventory(actor:actor,item:id,target:target)}
            saveLabel.text="操作已保存到当前行程";onChange?();refresh()
        }catch{refresh();let alert=UIAlertController(title:"操作未完成",message:error.localizedDescription,preferredStyle:.alert);alert.addAction(UIAlertAction(title:"知道了",style:.default));present(alert,animated:true)}
    }
}
