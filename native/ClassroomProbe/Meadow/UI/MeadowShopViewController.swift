import UIKit
import ClassroomGameCore
import MeadowWorldSupport
import MeadowBattleSupport

/// The travelling merchant's shop (mirrored live to the public screen):
/// - Categorized catalog (`全部 / 武器 / 护甲 / 饰品 / 补给`) with live item counts + optional rarity filter pills;
/// - In `全部` mode, items are cleanly grouped under visual category section dividers and sorted by rarity & price;
/// - Every item card shows rarity bar/pill, pixel icon, gold price, owned count, and green "▲ 提升" tag for the buyer;
/// - Right detail panel shows compact rarity header + live buyer equipment upgrade comparison BEFORE purchase + transaction box.
final class MeadowShopViewController:UIViewController {
    override var canBecomeFirstResponder:Bool {true}
    override func viewDidAppear(_ animated:Bool) {super.viewDidAppear(animated);becomeFirstResponder()}
    override func pressesBegan(_ presses:Set<UIPress>,with event:UIPressesEvent?) {
        if ClassroomGlobalTools.handlePresses?(presses)==true {return}
        super.pressesBegan(presses,with:event)
    }

    private let session:MeadowCampaignSession
    private let nodeID:Int
    private var actor:String
    private var selling=false
    private var selectedCategory:ShopItemCategory = .all
    private var selectedRarity:MeadowItemRarity? = nil
    private var selected:String?
    var onTrade:((GameState)->Void)?
    /// Free prize spins still owed (one entry per spin, by student): a mini-game win opens the shop wheel with these.
    /// The teacher picks the tier; a spin for someone listed is free and uses up one of their entries.
    var rewardSpins:[String]=[]
    var onRewardSpinUsed:((String)->Void)?
    /// Swap to the bag for the member shown (same page spot, no trip back to the map).
    var onSwitchToBag:((String)->Void)?
    private let bagButton=MeadowPreviewPalette.button("行囊")

    private let header=UIView(),catalogPanel=UIView(),grid=UIScrollView(),detail=UIView()
    private let categoryBar=UISegmentedControl()
    private let rarityBar=UIStackView()
    private var rarityButtons:[(rarity:MeadowItemRarity?,button:UIButton)]=[]
    private let detailScroll=UIScrollView(),detailContent=UIView()

    private let titleLabel=MeadowPreviewPalette.label("",size:24,weight:.heavy)
    private let coinsLabel=MeadowPreviewPalette.label("",size:18,weight:.bold)
    private let buyers=UISegmentedControl(),mode=UISegmentedControl(items:["购买","出售","抽奖"])
    private let lottery=MeadowLotteryView()
    private var lotteryMode:Bool {mode.selectedSegmentIndex==2}
    private let close=MeadowPreviewPalette.iconButton("xmark")
    private let timerButton=ClassroomGlobalTools.timerButton()
    private let action=MeadowPreviewPalette.button("购买"),toast=MeadowPreviewPalette.label("",size:15,weight:.heavy)

    private struct SectionGroup {
        let header:UIView?
        let cards:[(id:String,view:UIView)]
    }
    private var sectionGroups:[SectionGroup]=[]
    private var emptyNotice:UILabel?
    private weak var detailIconRef:UIImageView?

    init(session:MeadowCampaignSession,node:Int,actor:String) {
        self.session=session;self.nodeID=node;self.actor=actor
        super.init(nibName:nil,bundle:nil);modalPresentationStyle = .fullScreen
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override var supportedInterfaceOrientations:UIInterfaceOrientationMask{.landscape}

    private var node:MapNode? {let at=unit?.nodeID ?? nodeID;return session.engine.state.map.nodes.first{$0.id==at}}
    private var unit:GameUnit? {session.engine.state.units[actor]}
    private var people:[GameUnit] {session.engine.state.players.filter{$0.isAlive}}

    private func price(_ item:ItemDefinition,buy:Bool)->Int {
        guard let node else{return buy ? item.purchasePrice ?? 0:item.sellPrice}
        return (try? CampaignSiteRules.tradePrice(item:item,buy:buy,node:node,seed:session.engine.state.map.seed)) ?? (buy ? item.purchasePrice ?? 0:item.sellPrice)
    }

    private var baseItems:[ItemDefinition] {
        let catalog=session.engine.catalog.items
        if selling { return catalog.filter{(unit?.inventory[$0.id] ?? 0)>0 && $0.sellPrice>0} }
        return catalog.filter{$0.purchasePrice != nil && $0.setID==nil}
    }

    private var filteredItems:[ItemDefinition] {
        baseItems.filter { item in
            guard selectedCategory.matches(item) else { return false }
            if let r=selectedRarity, MeadowItemRarity.of(item.id,item:item) != r { return false }
            return true
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor=UIColor(red:0.80,green:0.88,blue:0.88,alpha:1)
        MeadowGlassBackdrop.install(in:view)

        [header,catalogPanel,detail].forEach{MeadowPreviewPalette.stylePanel($0,liveBlur:true);view.addSubview($0)}
        [titleLabel,coinsLabel,buyers,mode,close,timerButton,bagButton].forEach(header.addSubview)
        bagButton.addAction(UIAction{[weak self] _ in guard let self else{return};self.onSwitchToBag?(self.actor)},for:.touchUpInside)

        // Category segmented bar + Rarity pill strip inside catalogPanel
        for (i,cat) in ShopItemCategory.allCases.enumerated() {
            categoryBar.insertSegment(withTitle:cat.title,at:i,animated:false)
        }
        categoryBar.selectedSegmentIndex=0
        categoryBar.addAction(UIAction{[weak self] _ in
            guard let self else{return}
            let idx=max(0,self.categoryBar.selectedSegmentIndex)
            self.selectedCategory=ShopItemCategory.allCases[idx]
            self.grid.setContentOffset(.zero,animated:false)
            self.reload()
        },for:.valueChanged)

        rarityBar.axis = .horizontal
        rarityBar.spacing = 6
        rarityBar.distribution = .fillEqually
        let rarityChoices:[(MeadowItemRarity?,String)]=[(nil,"全品质"),(.common,"普通"),(.rare,"稀有"),(.epic,"史诗"),(.legendary,"传说")]
        for (r,title) in rarityChoices {
            let b=UIButton(type:.system)
            b.setTitle(title,for:.normal)
            b.titleLabel?.font=MeadowPreviewPalette.font(12.5,.heavy)
            b.layer.cornerRadius=12;b.layer.cornerCurve = .continuous;b.layer.borderWidth=1.2
            b.addAction(UIAction{[weak self] _ in
                self?.selectedRarity=r
                self?.grid.setContentOffset(.zero,animated:false)
                self?.reload()
            },for:.touchUpInside)
            rarityBar.addArrangedSubview(b)
            rarityButtons.append((r,b))
        }

        grid.alwaysBounceVertical=true
        [categoryBar,rarityBar,grid].forEach(catalogPanel.addSubview)

        detailScroll.alwaysBounceVertical=true
        detailScroll.addSubview(detailContent)
        detail.addSubview(detailScroll)
        detail.addSubview(action)

        toast.textAlignment = .center;toast.backgroundColor=MeadowPreviewPalette.primary;toast.textColor = .white
        toast.layer.cornerRadius=12;toast.clipsToBounds=true;toast.alpha=0
        view.addSubview(toast)

        for control in [buyers,mode,categoryBar] {
            control.setTitleTextAttributes([.font:MeadowPreviewPalette.font(14.5,.bold),.foregroundColor:MeadowPreviewPalette.ink],for:.normal)
            control.setTitleTextAttributes([.font:MeadowPreviewPalette.font(14.5,.heavy),.foregroundColor:UIColor.white],for:.selected)
            control.selectedSegmentTintColor=MeadowPreviewPalette.primary
        }
        for (i,p) in people.enumerated() { buyers.insertSegment(withTitle:p.shortName,at:i,animated:false) }
        buyers.addAction(UIAction{[weak self] _ in
            guard let self else{return}
            let list=self.people
            if list.indices.contains(self.buyers.selectedSegmentIndex){self.actor=list[self.buyers.selectedSegmentIndex].id}
            self.reload()
        },for:.valueChanged)

        mode.selectedSegmentIndex=rewardSpins.isEmpty ? 0:2
        mode.addAction(UIAction{[weak self] _ in
            guard let self else{return}
            self.selling=self.mode.selectedSegmentIndex==1
            self.selected=nil
            self.grid.setContentOffset(.zero,animated:false)
            self.reload()
        },for:.valueChanged)

        // Prize wheel: rules draw the prize (recorded & undoable); wheel animates it.
        lottery.catalog=session.engine.catalog
        lottery.onSpin={[weak self] tier in
            guard let self else{return nil}
            let before=self.session.engine.state
            do{
                let free=self.rewardSpins.contains(self.actor)
                let receipt=free ? try self.session.spinRewardLottery(actor:self.actor,tier:tier):try self.session.spinLottery(actor:self.actor,tier:tier)
                if free,let i=self.rewardSpins.firstIndex(of:self.actor) {self.rewardSpins.remove(at:i);self.onRewardSpinUsed?(self.actor)}
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
        reload()
    }

    private func updateFilterBars() {
        let base=baseItems
        for (i,cat) in ShopItemCategory.allCases.enumerated() {
            let count=base.filter{cat.matches($0)}.count
            categoryBar.setTitle(count>0 ? "\(cat.title)(\(count))" : cat.title, forSegmentAt:i)
        }
        categoryBar.selectedSegmentIndex=ShopItemCategory.allCases.firstIndex(of:selectedCategory) ?? 0

        let catItems=base.filter{selectedCategory.matches($0)}
        for (r,btn) in rarityButtons {
            let active = r == selectedRarity
            let count = r == nil ? catItems.count : catItems.filter{MeadowItemRarity.of($0.id,item:$0) == r}.count
            let baseTitle = r?.title ?? "全品质"
            btn.setTitle(r == nil ? baseTitle : "\(baseTitle)(\(count))", for: .normal)
            if active {
                let bg = r?.badgeColor ?? MeadowPreviewPalette.primary
                btn.backgroundColor = bg
                btn.setTitleColor(.white, for: .normal)
                btn.layer.borderColor = bg.cgColor
            } else {
                btn.backgroundColor = r?.surfaceTint ?? UIColor.white.withAlphaComponent(0.55)
                btn.setTitleColor(r?.inkColor ?? MeadowPreviewPalette.ink, for: .normal)
                btn.layer.borderColor = (r?.borderColor ?? UIColor.white.withAlphaComponent(0.8)).cgColor
            }
            btn.alpha = (count == 0 && !active) ? 0.45 : 1.0
        }
    }

    private func reload() {
        guard let unit else{return}
        catalogPanel.isHidden=lotteryMode;detail.isHidden=lotteryMode;lottery.isHidden = !lotteryMode
        bagButton.isHidden=onSwitchToBag==nil
        let owed=rewardSpins.filter{$0==actor}.count
        lottery.freeSpins=owed
        view.bringSubviewToFront(toast)
        let shopSite=node.map{CampaignSiteRules.configuration(node:$0,seed:session.engine.state.map.seed)?.kind == .shop} ?? false
        titleLabel.attributedText=MeadowGlassText.iconLine("cart.fill",shopSite ? "商店":"行商",size:23,tint:MeadowPreviewPalette.gold,weight:.heavy)
        coinsLabel.attributedText=MeadowGlassText.iconLine("bitcoinsign.circle.fill","\(unit.coins)",size:18,tint:MeadowPreviewPalette.gold,weight:.heavy)
        buyers.selectedSegmentIndex=people.firstIndex{$0.id==actor} ?? 0

        updateFilterBars()

        let list=filteredItems
        if !list.contains(where:{$0.id==selected}) { selected=list.first?.id }

        // Clear old grid contents
        for g in sectionGroups {
            g.header?.removeFromSuperview()
            g.cards.forEach{$0.view.removeFromSuperview()}
        }
        sectionGroups=[]
        emptyNotice?.removeFromSuperview();emptyNotice=nil

        let catalog=session.engine.catalog
        let groups=ShopItemCategory.grouped(list,filter:selectedCategory) { a,b in
            let ra=MeadowItemRarity.of(a.id,item:a),rb=MeadowItemRarity.of(b.id,item:b)
            if ra != rb { return ra < rb }
            let pa=self.price(a,buy:!self.selling),pb=self.price(b,buy:!self.selling)
            if pa != pb { return pa < pb }
            return a.name < b.name
        }

        let showSectionHeaders = (selectedCategory == .all)
        for group in groups {
            var hdrView:UIView?=nil
            if showSectionHeaders {
                let h=UIView()
                h.backgroundColor=UIColor.white.withAlphaComponent(0.62)
                h.layer.cornerRadius=9;h.layer.borderWidth=1;h.layer.borderColor=UIColor.white.withAlphaComponent(0.85).cgColor
                let lbl=UILabel()
                lbl.attributedText=MeadowGlassText.iconLine(group.category.symbol,"\(group.category.title) · \(group.items.count)件",size:14,tint:MeadowPreviewPalette.primary,weight:.heavy)
                lbl.tag=1
                h.addSubview(lbl)
                grid.addSubview(h)
                hdrView=h
            }
            var groupCards:[(id:String,view:UIView)]=[]
            for item in group.items {
                let p=price(item,buy:!selling),owned=unit.inventory[item.id] ?? 0
                let rarity=MeadowItemRarity.of(item.id,item:item)
                let chosen=item.id==selected,affordable=selling || unit.coins>=p
                let worn=item.slot.map{unit.equipment[$0]==item.id} ?? false
                var upgradeTag:String?=nil
                if !selling,let slot=item.slot,!worn,let comp=try? session.simulatedEquipmentComparison(actor:actor,slot:slot,item:item.id) {
                    if comp.upgradeScore(catalog:catalog) > 0.25 { upgradeTag="▲ 提升" }
                }
                let card=MeadowItemCardButton()
                card.configure(
                    item:item,
                    rarity:rarity,
                    chosen:chosen,
                    equipped:false,
                    statusText:owned>0 ? (selling ? "×\(owned)":"有\(owned)"):(worn ? "穿着":nil),
                    statusColor:worn ? UIColor(red:0.08,green:0.48,blue:0.42,alpha:1):nil,
                    footerText:"\(p) 金币",
                    footerColor:affordable ? MeadowPreviewPalette.gold : UIColor(red:0.78,green:0.24,blue:0.20,alpha:1),
                    upgradeTag:upgradeTag,
                    dimmed:!affordable
                )
                card.accessibilityIdentifier="shopItem-"+item.id
                card.addAction(UIAction{[weak self] _ in
                    guard let self else{return}
                    self.selected=item.id
                    self.reload()
                },for:.touchUpInside)
                grid.addSubview(card)
                groupCards.append((item.id,card))
            }
            sectionGroups.append(SectionGroup(header:hdrView,cards:groupCards))
        }

        if sectionGroups.isEmpty {
            let notice=MeadowPreviewPalette.label(selling ? "该分类下行囊没有可出售物品":"该筛选条件下暂无商品",size:16,weight:.semibold)
            notice.textColor=MeadowPreviewPalette.muted;notice.textAlignment = .center
            grid.addSubview(notice);emptyNotice=notice
        }

        view.setNeedsLayout()
        layoutDetail()
    }

    private func layoutDetail() {
        detailContent.subviews.forEach{$0.removeFromSuperview()}
        detailIconRef=nil
        let width=detail.bounds.width,pad:CGFloat=14,innerW=max(80,width-pad*2)
        var y:CGFloat=12

        guard let unit,let id=selected,let item=try? session.engine.catalog.item(id) else {
            let l=UILabel(frame:CGRect(x:pad,y:28,width:innerW,height:32))
            l.attributedText=MeadowGlassText.iconLine("hand.tap","点击左侧商品查看详情与装备提升",size:15.5,tint:MeadowPreviewPalette.muted,weight:.semibold)
            l.textAlignment = .center
            detailContent.addSubview(l)
            action.isHidden=true
            detailContent.frame=CGRect(x:0,y:0,width:width,height:80);detailScroll.contentSize=detailContent.bounds.size
            return
        }

        let catalog=session.engine.catalog
        let rarity=MeadowItemRarity.of(id,item:item)
        let p=price(item,buy:!selling),owned=unit.inventory[id] ?? 0
        let worn=item.slot.map{unit.equipment[$0]==id} ?? false

        // 1. Compact horizontal rarity header
        let subParts=[worn ? "当前已穿戴":nil, owned>0 ? "行囊已有 \(owned) 件":"未拥有"].compactMap{$0}
        let headerCard=MeadowEquipmentDetailUI.identityHeader(item:item,rarity:rarity,subtitle:subParts.joined(separator:" · "),catalog:catalog,width:innerW)
        headerCard.frame.origin=CGPoint(x:pad,y:y)
        detailContent.addSubview(headerCard)
        detailIconRef=headerCard.subviews.compactMap{$0.subviews.first as? UIImageView}.first
        y+=headerCard.frame.height+10

        // 2. Concise stat summary banner
        let summary=CampInventoryProjection.summary(item)
        if !summary.isEmpty {
            let strip=UILabel()
            strip.attributedText=MeadowGlassText.iconLine("sparkles",summary,size:14.5,tint:MeadowPreviewPalette.gold,weight:.bold)
            strip.numberOfLines=0
            let sh=max(26,ceil(strip.sizeThatFits(CGSize(width:innerW-16,height:400)).height)+10)
            let bg=UIView(frame:CGRect(x:pad,y:y,width:innerW,height:sh))
            bg.backgroundColor=UIColor.white.withAlphaComponent(0.65)
            bg.layer.cornerRadius=10;bg.layer.borderWidth=1;bg.layer.borderColor=UIColor.white.withAlphaComponent(0.85).cgColor
            strip.frame=CGRect(x:8,y:4,width:innerW-16,height:sh-8)
            bg.addSubview(strip);detailContent.addSubview(bg)
            y+=sh+10
        }

        // 3. Live Buyer Equipment Comparison BEFORE buying!
        if let slot=item.slot {
            let wornName=unit.equipment[slot].flatMap{try? catalog.item($0).name} ?? (slot == .weapon ? "空手":"未装备")
            if worn {
                let already=UILabel(frame:CGRect(x:pad,y:y,width:innerW,height:32))
                already.attributedText=MeadowGlassText.iconLine("checkmark.seal.fill","\(unit.shortName) 当前正装备此件",size:14,tint:UIColor(red:0.08,green:0.48,blue:0.42,alpha:1),weight:.heavy)
                already.textAlignment = .center
                already.backgroundColor=UIColor(red:0.86,green:0.96,blue:0.94,alpha:0.9)
                already.layer.cornerRadius=10;already.clipsToBounds=true
                detailContent.addSubview(already);y+=40
            } else if let comp=try? session.simulatedEquipmentComparison(actor:actor,slot:slot,item:id) {
                let card=MeadowEquipmentDetailUI.comparisonCard(
                    title:"\(unit.shortName) 装备后对比",
                    subtitle:"当前「\(wornName)」→「\(item.name)」",
                    comparison:comp,
                    catalog:catalog,
                    width:innerW
                )
                card.frame.origin=CGPoint(x:pad,y:y);detailContent.addSubview(card);y+=card.frame.height+10
                if let sid=item.setID,let setCard=MeadowEquipmentDetailUI.setBonusCard(setID:sid,beforeUnit:comp.before,afterUnit:comp.after,catalog:catalog,width:innerW) {
                    setCard.frame.origin=CGPoint(x:pad,y:y);detailContent.addSubview(setCard);y+=setCard.frame.height+10
                }
            }
        }

        // 4. Crisp Transaction Summary Box (Price + Pack + Coins before→after)
        let allowed=selling ? owned>0 : unit.coins>=p
        let txBox=UIView(frame:CGRect(x:pad,y:y,width:innerW,height:74))
        txBox.backgroundColor=UIColor.white.withAlphaComponent(0.70)
        txBox.layer.cornerRadius=13;txBox.layer.borderWidth=1.2
        txBox.layer.borderColor=(allowed ? UIColor.white : UIColor(red:0.85,green:0.32,blue:0.28,alpha:0.75)).cgColor

        let priceL=UILabel(frame:CGRect(x:12,y:8,width:innerW-24,height:26))
        priceL.attributedText=MeadowGlassText.iconLine(selling ? "arrow.down.circle.fill":"tag.fill",(selling ? "回收价 ":"售价 ")+"\(p) 金币",size:19,tint:MeadowPreviewPalette.gold,weight:.heavy)
        txBox.addSubview(priceL)

        let bagL=UILabel(frame:CGRect(x:12,y:40,width:(innerW-28)/2,height:24))
        bagL.attributedText=MeadowGlassText.iconLine("bag.fill","行囊 \(owned) → \(selling ? max(0,owned-1):owned+1)",size:13.5,tint:MeadowPreviewPalette.ink,weight:.bold)
        txBox.addSubview(bagL)

        let coinAfter=selling ? unit.coins+p : unit.coins-p
        let coinL=UILabel(frame:CGRect(x:12+(innerW-28)/2+4,y:40,width:(innerW-28)/2,height:24))
        coinL.attributedText=MeadowGlassText.iconLine("bitcoinsign.circle.fill","金币 \(unit.coins) → \(coinAfter)",size:13.5,tint:allowed ? MeadowPreviewPalette.gold : UIColor(red:0.80,green:0.20,blue:0.18,alpha:1),weight:.bold)
        coinL.textAlignment = .right
        txBox.addSubview(coinL)

        detailContent.addSubview(txBox)
        y+=txBox.frame.height+10

        action.isHidden=false
        action.configuration?.image=UIImage(systemName:selling ? "arrow.down.to.line":"cart.badge.plus")
        action.configuration?.imagePadding=8
        action.configuration?.title=selling ? "卖出一个 · +\(p) 金币":(allowed ? "买一个 · \(p) 金币":"金币不足（差 \(p-unit.coins)）")
        action.configuration?.baseBackgroundColor=selling ? UIColor(red:0.74,green:0.46,blue:0.10,alpha:1) : (allowed ? MeadowPreviewPalette.primary : UIColor(red:0.55,green:0.58,blue:0.60,alpha:0.8))
        action.isEnabled=allowed

        detailContent.frame=CGRect(x:0,y:0,width:width,height:y+8)
        detailScroll.contentSize=detailContent.bounds.size
    }

    private func trade() {
        guard let id=selected else{return}
        let before=session.engine.state
        do {
            try session.tradeAtSite(actor:actor,item:id,buy:!selling)
            onTrade?(before)
            let name=(try? session.engine.catalog.item(id).name) ?? id
            flash(selling ? "已卖出 \(name)":"\(name) 已放入行囊")
            if let iconRef=detailIconRef,let img=iconRef.image {
                let ghost=UIImageView(image:img);ghost.contentMode = .scaleAspectFit
                ghost.frame=view.convert(iconRef.bounds,from:iconRef)
                view.addSubview(ghost)
                UIView.animate(withDuration:0.52,delay:0,options:.curveEaseIn,animations:{
                    ghost.frame=CGRect(origin:self.view.convert(self.coinsLabel.center,from:self.header),size:CGSize(width:16,height:16));ghost.alpha=0.2
                }){_ in ghost.removeFromSuperview()}
            }
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
        let s=view.safeAreaInsets
        let b=view.bounds.inset(by:UIEdgeInsets(top:max(10,s.top),left:max(14,s.left),bottom:max(10,s.bottom),right:max(14,s.right)))

        header.frame=CGRect(x:b.minX,y:b.minY,width:b.width,height:58)
        let w=header.bounds.width
        titleLabel.frame=CGRect(x:16,y:11,width:104,height:36)
        coinsLabel.frame=CGRect(x:122,y:15,width:102,height:28)
        mode.frame=CGRect(x:228,y:11,width:228,height:36)
        close.frame=CGRect(x:w-58,y:8,width:48,height:42)
        timerButton.frame=CGRect(x:w-118,y:8,width:52,height:42)
        let right:CGFloat=bagButton.isHidden ? 130:212
        bagButton.frame=CGRect(x:w-200,y:8,width:76,height:42)
        let bx=mode.frame.maxX+18,bw=min(CGFloat(people.count)*104,w-right-bx)
        buyers.frame=CGRect(x:w-right-max(80,bw),y:11,width:max(80,bw),height:36)

        let top=header.frame.maxY+12
        let panelW=min(420,max(320,b.width*0.35))
        detail.frame=CGRect(x:b.maxX-panelW,y:top,width:panelW,height:b.maxY-top)
        catalogPanel.frame=CGRect(x:b.minX,y:top,width:max(200,b.width-panelW-12),height:b.maxY-top)

        // Catalog filter bars + grouped grid
        let cwAll=catalogPanel.bounds.width
        categoryBar.frame=CGRect(x:12,y:10,width:cwAll-24,height:36)
        rarityBar.frame=CGRect(x:12,y:52,width:cwAll-24,height:28)
        grid.frame=CGRect(x:10,y:86,width:cwAll-20,height:max(1,catalogPanel.bounds.height-96))

        let gw=grid.bounds.width
        let columns=max(2,Int((gw+10)/154))
        let cardW=(gw-CGFloat(columns-1)*9)/CGFloat(columns)
        let cardH:CGFloat=128
        var gy:CGFloat=4
        for group in sectionGroups {
            if let hdr=group.header {
                hdr.frame=CGRect(x:0,y:gy,width:gw,height:30)
                hdr.viewWithTag(1)?.frame=CGRect(x:10,y:0,width:gw-20,height:30)
                gy+=38
            }
            for (i,entry) in group.cards.enumerated() {
                entry.view.frame=CGRect(x:CGFloat(i%columns)*(cardW+9),y:gy+CGFloat(i/columns)*(cardH+9),width:cardW,height:cardH)
            }
            let rowCount=(group.cards.count+columns-1)/columns
            gy+=CGFloat(rowCount)*(cardH+9)+6
        }
        emptyNotice?.frame=CGRect(x:0,y:32,width:gw,height:48)
        grid.contentSize=CGSize(width:gw,height:max(1,gy+8))

        // Detail scroll + sticky CTA
        detailScroll.frame=CGRect(x:0,y:0,width:detail.bounds.width,height:max(1,detail.bounds.height-68))
        action.frame=CGRect(x:14,y:detail.bounds.height-58,width:detail.bounds.width-28,height:46)
        layoutDetail()

        toast.frame=CGRect(x:catalogPanel.frame.midX-180,y:b.maxY-58,width:360,height:42)
        lottery.frame=CGRect(x:b.minX,y:top,width:b.width,height:b.maxY-top)
        if lotteryMode { toast.frame=CGRect(x:b.midX-200,y:b.maxY-58,width:400,height:42) }
    }
}
