import UIKit
import ClassroomGameCore
import MeadowWorldSupport
import MeadowBattleSupport

/// The travelling merchant's shop: a grid of item cards with pictures and prices, a detail panel with the picture large, what the
/// item does, the price and what the buyer will have left, and buy / sell. Buying puts one item into the buyer's own pack (not
/// equipped); selling takes one out. Trades go through the same rule command as before (`tradeAtSite`), one item per press.
final class MeadowShopViewController:UIViewController {
    private let session:MeadowCampaignSession
    private let nodeID:Int
    private var actor:String
    private var selling=false
    private var selected:String?
    var onTrade:((GameState)->Void)?

    private let header=UIView(),grid=UIScrollView(),detail=UIView()
    private let titleLabel=MeadowPreviewPalette.label("",size:26,weight:.heavy)
    private let coinsLabel=MeadowPreviewPalette.label("",size:18,weight:.bold)
    private let buyers=UISegmentedControl(),mode=UISegmentedControl(items:["购买","出售","抽奖"])
    private let lottery=MeadowLotteryView()
    private var lotteryMode:Bool {mode.selectedSegmentIndex==2}
    private let close=MeadowPreviewPalette.iconButton("xmark")
    private let bigIcon=UIImageView(),nameLabel=MeadowPreviewPalette.label("",size:24,weight:.heavy),infoLabel=MeadowPreviewPalette.label("",size:16)
    private let priceLabel=MeadowPreviewPalette.label("",size:20,weight:.heavy),afterLabel=MeadowPreviewPalette.label("",size:15)
    private let action=MeadowPreviewPalette.button("购买"),toast=MeadowPreviewPalette.label("",size:16,weight:.bold)
    private var cards:[(id:String,view:UIButton)]=[]

    init(session:MeadowCampaignSession,node:Int,actor:String) {
        self.session=session;self.nodeID=node;self.actor=actor
        super.init(nibName:nil,bundle:nil);modalPresentationStyle = .fullScreen
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override var supportedInterfaceOrientations:UIInterfaceOrientationMask{.landscape}

    /// The buyer's own place: a shop site keeps its ratios, anywhere else trades at base price.
    private var node:MapNode? {let at=unit?.nodeID ?? nodeID;return session.engine.state.map.nodes.first{$0.id==at}}
    private var unit:GameUnit? {session.engine.state.units[actor]}
    /// The peddler travels with the party: every living member of the buyer's team can trade, wherever they stand.
    private var people:[GameUnit] {let team=session.engine.state.units[actor]?.teamID;return session.engine.state.players.filter{$0.isAlive && $0.teamID==team}}
    private func price(_ item:ItemDefinition,buy:Bool)->Int {
        guard let node else{return buy ? item.purchasePrice ?? 0:item.sellPrice}
        return (try? CampaignSiteRules.tradePrice(item:item,buy:buy,node:node,seed:session.engine.state.map.seed)) ?? (buy ? item.purchasePrice ?? 0:item.sellPrice)
    }
    private var items:[ItemDefinition] {
        let catalog=session.engine.catalog.items
        if selling { return catalog.filter{(unit?.inventory[$0.id] ?? 0)>0 && $0.sellPrice>0} }
        return catalog.filter{$0.purchasePrice != nil && $0.setID==nil}
    }

    override func viewDidLoad() {
        super.viewDidLoad();view.backgroundColor=UIColor(red:0.045,green:0.085,blue:0.058,alpha:1)
        MeadowGlassBackdrop.install(in:view)
        [header,grid,detail].forEach{MeadowPreviewPalette.stylePanel($0,liveBlur:true);view.addSubview($0)}
        [titleLabel,coinsLabel,buyers,mode,close].forEach(header.addSubview)
        [bigIcon,nameLabel,infoLabel,priceLabel,afterLabel,action].forEach(detail.addSubview)
        bigIcon.contentMode = .scaleAspectFit;bigIcon.layer.magnificationFilter = .nearest
        infoLabel.numberOfLines=0;afterLabel.numberOfLines=0;nameLabel.numberOfLines=2;infoLabel.textColor=MeadowPreviewPalette.muted
        priceLabel.textColor=MeadowPreviewPalette.gold
        toast.textAlignment = .center;toast.backgroundColor=MeadowPreviewPalette.gold;toast.textColor=MeadowPreviewPalette.panel;toast.layer.cornerRadius=12;toast.clipsToBounds=true;toast.alpha=0
        view.addSubview(toast)
        for control in [buyers,mode] {
            for state in [UIControl.State.normal,.selected] {control.setTitleTextAttributes([.font:MeadowPreviewPalette.font(16),.foregroundColor:MeadowPreviewPalette.ink],for:state)}
            control.selectedSegmentTintColor=UIColor(red:0.40,green:0.35,blue:0.19,alpha:1)
        }
        for (i,p) in people.enumerated() { buyers.insertSegment(withTitle:p.name,at:i,animated:false) }
        buyers.addAction(UIAction{[weak self] _ in guard let self else{return};let list=self.people;if list.indices.contains(self.buyers.selectedSegmentIndex){self.actor=list[self.buyers.selectedSegmentIndex].id};self.selected=nil;self.reload()},for:.valueChanged)
        mode.selectedSegmentIndex=0
        mode.addAction(UIAction{[weak self] _ in guard let self else{return};self.selling=self.mode.selectedSegmentIndex==1;self.selected=nil;self.reload()},for:.valueChanged)
        // Prize wheel: the rules draw the prize (recorded and undoable); the wheel only shows it.
        lottery.catalog=session.engine.catalog
        lottery.onSpin={[weak self] tier in
            guard let self else{return nil}
            let before=self.session.engine.state
            do{
                let receipt=try self.session.spinLottery(actor:self.actor,tier:tier)
                self.onTrade?(before);self.reload()
                return receipt.events.first{$0.kind=="lottery"}?.amount
            }catch{self.flash("未完成："+error.localizedDescription);return nil}
        }
        lottery.onFinished={[weak self] tier,slot in
            guard let self,CampaignLottery.tiers.indices.contains(tier),CampaignLottery.tiers[tier].prizes.indices.contains(slot) else{return}
            let prize=CampaignLottery.tiers[tier].prizes[slot]
            if let id=prize.item {
                let item=try? self.session.engine.catalog.item(id)
                self.flash((item?.setID != nil ? "套装部件！":"抽中 ")+(item?.name ?? id)+(prize.count>1 ? " ×\(prize.count)":""))
            } else {self.flash("抽中 \(prize.coins) 金币")}
        }
        view.addSubview(lottery)
        close.addAction(UIAction{[weak self] _ in self?.dismiss(animated:true)},for:.touchUpInside)
        action.addAction(UIAction{[weak self] _ in self?.trade()},for:.touchUpInside)
        grid.alwaysBounceVertical=true
        reload()
    }

    private func reload() {
        guard let unit else{return}
        grid.isHidden=lotteryMode;detail.isHidden=lotteryMode;lottery.isHidden = !lotteryMode
        view.bringSubviewToFront(toast)
        let shopSite=node.map{CampaignSiteRules.configuration(node:$0,seed:session.engine.state.map.seed)?.kind == .shop} ?? false
        titleLabel.attributedText=MeadowGlassText.iconLine("cart.fill",shopSite ? "商店":"行商",size:26)
        coinsLabel.attributedText=MeadowGlassText.iconLine("bitcoinsign.circle.fill","\(unit.coins)",size:18,tint:MeadowPreviewPalette.gold)
        buyers.selectedSegmentIndex=people.firstIndex{$0.id==actor} ?? 0
        let list=items
        if !list.contains(where:{$0.id==selected}) { selected=list.first?.id }
        cards.forEach{$0.view.removeFromSuperview()};cards=[]
        for item in list {
            let p=price(item,buy:!selling),owned=unit.inventory[item.id] ?? 0
            var c=UIButton.Configuration.filled()
            c.image=MeadowItemIcon.image(item.id,item:item,side:64);c.imagePlacement = .top;c.imagePadding=6
            c.title=item.name;c.subtitle="◎ \(p)"+(owned>0 ? "  ×\(owned)":"")
            c.titleAlignment = .center;c.cornerStyle = .large
            c.titleTextAttributesTransformer=UIConfigurationTextAttributesTransformer{v in var v=v;v.font=MeadowPreviewPalette.font(16,.bold);return v}
            c.subtitleTextAttributesTransformer=UIConfigurationTextAttributesTransformer{v in var v=v;v.font=MeadowPreviewPalette.font(13,.medium);return v}
            let chosen=item.id==selected,affordable=selling || unit.coins>=p
            c.baseBackgroundColor=chosen ? MeadowPreviewPalette.gold:UIColor.white.withAlphaComponent(0.10)
            c.background.strokeColor=UIColor.white.withAlphaComponent(chosen ? 0.6:0.18);c.background.strokeWidth=1
            c.baseForegroundColor=chosen ? MeadowPreviewPalette.panel:(affordable ? MeadowPreviewPalette.ink:MeadowPreviewPalette.muted)
            let card=UIButton(configuration:c);card.alpha=affordable || chosen ? 1:0.6
            card.accessibilityIdentifier="shopItem-"+item.id
            card.addAction(UIAction{[weak self,weak card] _ in
                guard let self else{return};self.selected=item.id;self.reload()
                if let card=self.cards.first(where:{$0.id==item.id})?.view ?? card {card.transform=CGAffineTransform(scaleX:0.92,y:0.92);UIView.animate(withDuration:0.35,delay:0,usingSpringWithDamping:0.5,initialSpringVelocity:0.8,options:.allowUserInteraction){card.transform = .identity}}
            },for:.touchUpInside)
            grid.addSubview(card);cards.append((item.id,card))
        }
        if list.isEmpty {
            var c=UIButton.Configuration.plain();c.image=UIImage(systemName:selling ? "bag":"shippingbox");c.imagePlacement = .top;c.imagePadding=8;c.title=selling ? "行囊空":"无货";c.baseForegroundColor=MeadowPreviewPalette.muted
            let empty=UIButton(configuration:c);empty.isEnabled=false;grid.addSubview(empty);cards=[("",empty)]
        }
        showDetail()
        view.setNeedsLayout()
    }

    private func showDetail() {
        guard let unit,let id=selected,let item=try? session.engine.catalog.item(id) else {
            bigIcon.image=UIImage(systemName:"hand.tap");bigIcon.tintColor=MeadowPreviewPalette.muted;nameLabel.text="";infoLabel.text="";priceLabel.text="";afterLabel.text="";action.isHidden=true;return
        }
        action.isHidden=false
        let p=price(item,buy:!selling),owned=unit.inventory[id] ?? 0
        bigIcon.image=MeadowItemIcon.image(id,item:item)
        nameLabel.text=item.name
        let kind=item.slot.map{CampInventoryProjection.slotTitle($0)} ?? (item.kind == .revivalStone ? "复活道具":"补给")
        let summary=CampInventoryProjection.summary(item)
        infoLabel.text=kind+(summary.isEmpty ? "":"\n"+summary)+(item.setID != nil ? "\n套装部件":"")
        priceLabel.attributedText=MeadowGlassText.iconLine(selling ? "arrow.down.circle.fill":"tag.fill","\(p)",size:22,tint:MeadowPreviewPalette.gold)
        let bag=MeadowGlassText.iconLine("bag.fill","\(owned) → \(selling ? owned-1:owned+1)",size:16,tint:MeadowPreviewPalette.muted)
        let coin=MeadowGlassText.iconLine("bitcoinsign.circle","\(unit.coins) → \(selling ? unit.coins+p:unit.coins-p)",size:16,tint:MeadowPreviewPalette.muted)
        let after=NSMutableAttributedString(attributedString:bag);after.append(NSAttributedString(string:"\n"));after.append(coin)
        afterLabel.attributedText=after
        let allowed=selling ? owned>0:unit.coins>=p
        action.configuration?.image=UIImage(systemName:selling ? "arrow.down.to.line":"cart.badge.plus")
        action.configuration?.imagePadding=8
        action.configuration?.title=selling ? "+\(p)":(allowed ? "-\(p)":"金币不足")
        action.isEnabled=allowed
    }

    private func trade() {
        guard let id=selected else{return}
        let before=session.engine.state
        do {
            try session.tradeAtSite(actor:actor,item:id,buy:!selling)
            onTrade?(before)
            let name=(try? session.engine.catalog.item(id).name) ?? id
            flash(selling ? "已卖出 \(name)":"\(name) 已放入行囊")
            // The bought item flies from the detail picture to the coin line.
            let ghost=UIImageView(image:bigIcon.image);ghost.contentMode = .scaleAspectFit;ghost.frame=view.convert(bigIcon.frame,from:detail);view.addSubview(ghost)
            UIView.animate(withDuration:0.55,delay:0,options:.curveEaseIn,animations:{
                ghost.frame=CGRect(origin:self.view.convert(self.coinsLabel.center,from:self.header),size:CGSize(width:16,height:16));ghost.alpha=0.2
            }){_ in ghost.removeFromSuperview()}
            reload()
        } catch {
            flash("未完成："+error.localizedDescription)
        }
    }

    private func flash(_ text:String) {
        toast.text=text;toast.layer.removeAllAnimations();toast.alpha=0;toast.transform=CGAffineTransform(translationX:0,y:16)
        UIView.animate(withDuration:0.25,animations:{self.toast.alpha=1;self.toast.transform = .identity}){_ in
            UIView.animate(withDuration:0.35,delay:1.6,options:[]){self.toast.alpha=0}
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let s=view.safeAreaInsets,b=view.bounds.inset(by:UIEdgeInsets(top:max(12,s.top),left:max(16,s.left),bottom:max(12,s.bottom),right:max(16,s.right)))
        header.frame=CGRect(x:b.minX,y:b.minY,width:b.width,height:110)
        let w=header.bounds.width
        titleLabel.frame=CGRect(x:16,y:10,width:w*0.45,height:34);coinsLabel.frame=CGRect(x:16,y:48,width:w*0.45,height:24)
        close.frame=CGRect(x:w-64,y:12,width:50,height:44)
        mode.frame=CGRect(x:w-340,y:12,width:260,height:40)
        buyers.frame=CGRect(x:w*0.5,y:62,width:w*0.5-14,height:36)
        let top=header.frame.maxY+12,panel=min(380,b.width*0.34)
        detail.frame=CGRect(x:b.maxX-panel,y:top,width:panel,height:b.maxY-top)
        grid.frame=CGRect(x:b.minX,y:top,width:b.width-panel-12,height:b.maxY-top)
        let gw=grid.bounds.width-24,columns=max(2,Int(gw/170)),cw=(gw-CGFloat(columns-1)*12)/CGFloat(columns),ch:CGFloat=150
        for (i,card) in cards.enumerated() { card.view.frame=CGRect(x:12+CGFloat(i%columns)*(cw+12),y:12+CGFloat(i/columns)*(ch+12),width:cw,height:ch) }
        grid.contentSize=CGSize(width:grid.bounds.width,height:24+CGFloat((cards.count+columns-1)/columns)*(ch+12))
        let dw=detail.bounds.width
        bigIcon.frame=CGRect(x:(dw-140)/2,y:18,width:140,height:140)
        nameLabel.frame=CGRect(x:18,y:168,width:dw-36,height:60)
        let infoH=infoLabel.sizeThatFits(CGSize(width:dw-36,height:400)).height
        infoLabel.frame=CGRect(x:18,y:230,width:dw-36,height:infoH)
        priceLabel.frame=CGRect(x:18,y:infoLabel.frame.maxY+14,width:dw-36,height:28)
        let afterH=afterLabel.sizeThatFits(CGSize(width:dw-36,height:400)).height
        afterLabel.frame=CGRect(x:18,y:priceLabel.frame.maxY+8,width:dw-36,height:afterH)
        action.frame=CGRect(x:18,y:detail.bounds.height-70,width:dw-36,height:52)
        toast.frame=CGRect(x:grid.frame.midX-180,y:b.maxY-64,width:360,height:44)
        lottery.frame=CGRect(x:b.minX,y:top,width:b.width,height:b.maxY-top)
        if lotteryMode {toast.frame=CGRect(x:b.midX-200,y:b.maxY-64,width:400,height:44)}
    }
}
