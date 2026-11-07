import UIKit
import ClassroomGameCore
import MeadowBattleSupport

/// A real two-player/two-target training encounter backed by the tabletop engine.
final class MeadowPartyBattleView:UIView {
    var classroomMode=false {didSet {if classroomMode {[back,reset,end,items].forEach{$0.removeFromSuperview()}}}}
    var classroomModelFactory:(()throws->PartyEncounter)?
    func classroomEnemyStep(){guard active,let target=model?.nextEnemyTarget() else{return};friend=target;performEnemy(target:target)}
    private var classroomPaused=false
    func classroomRefresh(){refresh()}
    func classroomSetPaused(_ value:Bool){classroomPaused=value;if value{scheduled?.cancel();scheduled=nil};stage.classroomPause(value);if !value{scheduleEnemy()}}
    var classroomBusy:Bool {stage.isPlaying || model?.pending != nil}
    var classroomActions:[PartyAction] {model?.playerActions() ?? []}
    func classroomAction(_ action:PartyAction,target:String){choose(target);perform(action)}
    func classroomFocus(_ action:PartyAction?,target:String){choose(target);focusedAction=action;stage.preview(action,target:action.map{self.target($0)} ?? target)}
    var onClose:(()->Void)?
    var campaignEngine:GameEngine?
    var onCommit:((OperationReceipt)->Void)?
    private var decisionTimer:Timer?

    private var model:PartyEncounter?
    var loadoutUnits:[String:GameUnit]?
    private var actionPointCapacity:[String:Int]=[:]
    private var apRound=0
    private var playerClassID="spellblade"
    private var active=false
    private var generation=0
    private var scheduled:DispatchWorkItem?
    private var friend="p1",foe="m1"
    private let title=MeadowPreviewPalette.label("小队支援",size:26,weight:.heavy)
    private let hint=MeadowPreviewPalette.label("",size:17,weight:.semibold)
    private let header=UIView(),panel=UIView()
    private let track=MeadowTurnTrackView(frame:.zero)
    private let health=MeadowBattleResourceBar(),ward=MeadowBattleResourceBar()
    private let ap=MeadowBattleActionPointsView()
    private let buff=MeadowPartyBuffButton(type:.system),shieldBuff=MeadowPartyBuffButton(type:.system)
    private let accessory=MeadowAccessoryBadge(type:.system)
    private let skillScroll=UIScrollView()
    private let mapBorder=UIView(),mapTitle=MeadowPreviewPalette.label("Meadow Journey",size:18)
    private let back=MeadowPreviewPalette.button("返回单人")
    private let reset=MeadowPreviewPalette.button("重置演练")
    private let end=MeadowPreviewPalette.button("结束行动")
    private let items=MeadowPreviewPalette.button("道具")
    private let stage=MeadowPartyStageView()

    private var skills:[MeadowPreviewCard]=[]
    private var focusedAction:PartyAction?
    override init(frame:CGRect) {
        super.init(frame:frame);backgroundColor = .clear
        MeadowPreviewPalette.stylePanel(header);MeadowPreviewPalette.stylePanel(panel)
        [header,stage,track,panel,mapBorder,mapTitle].forEach(addSubview)
        mapBorder.layer.cornerRadius=14;mapBorder.layer.borderWidth=1;mapBorder.layer.borderColor=MeadowPreviewPalette.border.cgColor;mapBorder.isUserInteractionEnabled=false
        mapTitle.backgroundColor=MeadowPreviewPalette.panel;mapTitle.textAlignment = .center;mapTitle.layer.cornerRadius=8;mapTitle.clipsToBounds=true;mapTitle.isUserInteractionEnabled=false
        [health,ward,ap,buff,shieldBuff,accessory,skillScroll].forEach(panel.addSubview)
        skillScroll.showsHorizontalScrollIndicator=true
        [title,hint,back,reset,end].forEach(header.addSubview)
        back.addAction(UIAction { [weak self] _ in self?.setActive(false);self?.onClose?() },for:.touchUpInside)
        reset.configuration?.title="演练设置";reset.showsMenuAsPrimaryAction=true
        configureTrainingMenu()
        end.addAction(UIAction { [weak self] _ in self?.perform(.endTurn) },for:.touchUpInside)
        for _ in 0..<6 { let card=MeadowPreviewCard(title:"",text:"");skills.append(card);skillScroll.addSubview(card) }
        skillScroll.addSubview(items);items.showsMenuAsPrimaryAction=true
        stage.onChoose={ [weak self] id in guard let self,!self.classroomMode else{return};self.choose(id) }
        stage.onPresentationChanged={ [weak self] in self?.refresh() }
        accessibilityIdentifier="meadowPartySupportEncounter"
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setActive(_ value:Bool) {
        active=value
        decisionTimer?.invalidate();decisionTimer=nil
        if value {
            restart()
            if campaignEngine != nil && !classroomMode { decisionTimer=Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in self?.advanceDecisionClock() } }
        } else {
            generation += 1;scheduled?.cancel();scheduled=nil;model?.cancel();stage.stop();accessory.dismiss()
        }
    }
    private func configureTrainingMenu() {
        let choices=[("adventurer","冒险者"),("spellblade","魔剑士"),("dragonKnight","龙骑士")]
        let classes=choices.map { id,name in UIAction(title:"P1 · "+name,state:playerClassID==id ? .on:.off) { [weak self] _ in
            guard let self else{return};self.playerClassID=id;self.configureTrainingMenu();self.restart()
        } }
        let again=UIAction(title:"重置当前演练") { [weak self] _ in self?.restart() }
        reset.menu=UIMenu(children:[again,UIMenu(title:"P1职业",children:classes)])
    }
    private func restart() {
        generation += 1;scheduled?.cancel();scheduled=nil;stage.stop();accessory.dismiss()
        do { if classroomMode {guard let factory=classroomModelFactory else{throw GameError("教师后台尚未准备战斗。")};model=try factory()}else{model = try campaignEngine.map { try PartyEncounter(engine:$0) } ?? PartyEncounter(loadouts:loadoutUnits,playerClassID:playerClassID)} } catch { hint.text="演练加载失败：\(error.localizedDescription)";return }
        friend="p1";foe=model?.monsterIDs.first ?? "m1";actionPointCapacity=[:];apRound=0
        reset.isHidden=campaignEngine != nil;back.configuration?.title=campaignEngine == nil ? "返回单人":"返回行程"
        stage.configureMonsters(model?.monsterIDs ?? ["m1","m2"]);stage.start();refresh();scheduleEnemy()
    }
    private func advanceDecisionClock() {
        guard active,campaignEngine != nil,let model,model.pending==nil,!stage.isPlaying,!model.terminal else{return}
        do {if let receipt=try model.engine.advanceClock(by:0.25){onCommit?(receipt);refresh();scheduleEnemy()}}
        catch {hint.text="保存失败："+error.localizedDescription;decisionTimer?.invalidate()}
    }
    private func choose(_ id:String) {
        guard model?.pending==nil else { return }
        if id.hasPrefix("p") { friend=id } else { foe=id };refresh()
    }
    private func target(_ action:PartyAction)->String {model?.preferredTarget(for:action,ally:friend,enemy:foe) ?? (action.isOffensive ? foe:friend)}
    private func perform(_ action:PartyAction) {
        guard active,let model,let intent=model.prepare(action,target:target(action)) else { return }
        let token=generation;refresh()
        stage.play(intent,before:model.state,confirmed:model.confirmedReceipt,onImpact:{ [weak self] in
            guard let self,self.active,self.generation==token else { return nil }
            do { let receipt=try model.commit(intent.id);if let receipt{self.onCommit?(receipt)};return receipt }
            catch { self.hint.text=error.localizedDescription;return nil }
        },completion:{ [weak self] in
            guard let self,self.active,self.generation==token else { return }
            self.refresh();self.scheduleEnemy()
        })
    }
    private func scheduleEnemy() {
        guard !classroomMode else{return}
        scheduled?.cancel();scheduled=nil
        guard active,!classroomPaused,let model,let current=model.current,model.state.units[current]?.kind == .monster,!model.terminal else { return }
        let token=generation
        let task=DispatchWorkItem { [weak self] in
            guard let self,self.active,self.generation==token,let id=model.nextEnemyTarget() else { return }
            self.friend=id;self.performEnemy(target:id)
        }
        scheduled=task;DispatchQueue.main.asyncAfter(deadline:.now()+0.65,execute:task)
    }
    private func performEnemy(target:String) {
        guard let model,let actorID=model.current,let actor=model.state.units[actorID] else { return }
        let targetNode=model.state.units[target]?.nodeID
        let nodePlayers=model.state.players.filter { $0.isAlive && $0.nodeID==targetNode }
        let hasSweep=(try? GameRules.skills(actor,catalog:model.engine.catalog).contains("sweep")) ?? false
        let action:PartyAction=hasSweep && nodePlayers.count>1 && model.preview(.sweep,target:target).allowed ? .sweep:.attack
        guard let intent=campaignEngine == nil ? model.prepare(action,target:target):model.prepareMonsterStep() else { return }
        let token=generation;refresh()
        stage.play(intent,before:model.state,confirmed:model.confirmedReceipt,onImpact:{ [weak self] in
            guard let self,self.active,self.generation==token else { return nil }
            do { let receipt=try model.commit(intent.id);if let receipt{self.onCommit?(receipt)};return receipt } catch { self.hint.text=error.localizedDescription;return nil }
        },completion:{ [weak self] in guard let self,self.active,self.generation==token else { return };self.refresh();self.scheduleEnemy() })
    }
    private func refresh() {
        guard let model else { return }
        let state=model.state;let current=model.current
        if state.units[foe]?.isAlive != true,let live=model.monsterIDs.first(where:{ state.units[$0]?.isAlive==true }) { foe=live }
        let busy=stage.isPlaying || model.pending != nil
        title.text=model.terminal ? (state.players.contains(where: \.isAlive) ? "小队胜利":"小队倒地") : (campaignEngine == nil ? "小队支援":"林地遭遇")+" · 第\(model.round)轮"
        let showing=busy ? (stage.actorInAction ?? model.pending?.actor ?? current):current
        let name=showing.flatMap { state.units[$0]?.name } ?? "演练结束"
        hint.text=busy ? "\(name) · 动作进行中" : classroomMode ? "\(name)行动"+(state.pauseReasons.isEmpty ? "":" · 已暂停") : "\(name)行动 · 友方 \(friend.uppercased()) / 敌方 \(model.state.units[foe]?.name ?? foe) · 点角色选目标"
        let displayActor=showing ?? "p1"
        if let unit=state.units[displayActor] {
            let visible=stage.displayedVitals(for:displayActor,health:unit.health,shield:unit.shield)
            health.show("生命",value:visible.health,maximum:(try? GameRules.attributes(unit,catalog:model.engine.catalog).maximumHealth) ?? unit.baseAttributes.maximumHealth,color:.systemGreen)
            ward.show("护盾",value:visible.shield,maximum:max(visible.shield,PartyVisual.shieldDisplayMaximum(unit:unit,catalog:model.engine.catalog)),color:.systemCyan)
            let stats=(try? GameRules.attributes(unit,catalog:model.engine.catalog)) ?? unit.baseAttributes
            if apRound != model.round { apRound=model.round;actionPointCapacity=[:] }
            let capacity=max(stats.baseAP,max(unit.ap,actionPointCapacity[displayActor] ?? 0))
            actionPointCapacity[displayActor]=capacity
            ap.show(value:unit.ap,maximum:capacity,owner:displayActor.hasPrefix("p") ? displayActor.uppercased():unit.name)
            accessory.show(try? AccessoryReadout.make(unit,catalog:model.engine.catalog),host:self)
            if let b=unit.damageBuff { buff.show(title:"增伤＋\(b.amount)",detail:"剩余 \(b.roundsLeft) 轮\n普攻和伤害技能生效",symbol:"arrow.up",color:MeadowPreviewPalette.gold) } else { buff.hide() }
            if visible.shield>0 { shieldBuff.show(title:"护盾 · \(visible.shield)",detail:"优先抵挡伤害\n新旧授盾取较高值",symbol:"shield.fill",color:.systemCyan) } else { shieldBuff.hide() }
        }
        let queue=state.battle?.queue ?? ["p1","p2"]+model.monsterIDs
        let names=Dictionary(uniqueKeysWithValues:queue.map{($0,state.units[$0]?.name ?? $0)})
        track.show(ids:queue,names:names,current:showing,done:state.battle?.acted.subtracting(Set([showing ?? ""])) ?? [],down:Set(state.units.values.filter { !$0.isAlive }.map(\.id)))
        stage.show(state,friend:friend,foe:foe,current:current,catalog:model.engine.catalog)
        let actions:[PartyAction]=busy ? showing.map { model.actions(for:$0) } ?? []:model.playerActions()
        if busy { focusedAction=nil }
        for (i,b) in skills.enumerated() {
            b.isHidden=i>=actions.count
            guard i<actions.count else { continue }
            let a=actions[i];let result=model.preview(a,target:target(a))
            let allowed=active && !busy && result.allowed
            b.update(title:a.title+" · \(model.cost(a)) AP",detail:(!busy && !result.allowed) ? result.message:detail(a,model:model,actor:displayActor),enabled:allowed)
            b.previewStrength=0;b.previewColor = .clear
            b.button.removeTarget(nil,action:nil,for:.touchUpInside)
            b.button.removeAction(identifiedBy:UIAction.Identifier("party-skill"),for:.touchUpInside)
            b.button.addAction(UIAction(identifier:UIAction.Identifier("party-skill"),handler:{ [weak self] _ in guard let self,!self.classroomMode else{return};self.perform(a) }),for:.touchUpInside)
            b.onFocus={ [weak self] focused in
                guard let self,!self.classroomMode else { return }
                if focused { self.focusedAction=a;self.stage.preview(a,target:self.target(a));self.hint.text=model.actionReadout(a,ally:self.friend,enemy:self.foe).text.replacingOccurrences(of:"\n",with:" · ") }
                else if self.focusedAction==a { self.focusedAction=nil;self.stage.preview(nil,target:self.target(a)) }
            }
            b.button.accessibilityHint=model.actionReadout(a,ally:friend,enemy:foe).text
        }
        end.isEnabled=active && !busy && current?.hasPrefix("p")==true && !model.terminal
        var menu:[UIAction]=[]
        for a in [PartyAction.smallPotion,.largePotion,.shieldPotion,.revivalStone] {
            let count=current.flatMap { state.units[$0]?.inventory[a.rawValue] } ?? 0
            let readout=model.actionReadout(a,ally:friend,enemy:foe)
            let allowed=readout.allowed
            menu.append(UIAction(title:"\(a.title) ×\(count) · \(a == .revivalStone ? 2:1) AP"+(allowed ? "":" · "+readout.availability),image:UIImage(named:"MeadowParty"+a.rawValue.prefix(1).uppercased()+a.rawValue.dropFirst()),attributes:allowed && !busy ? []:.disabled,handler:{ [weak self] _ in guard let self,!self.classroomMode else{return};self.perform(a) }))
        }
        let inventoryInfo=UIAction(title:"查看双方个人资源",image:UIImage(systemName:"list.bullet.rectangle")){[weak self] _ in
            guard let self else{return};self.showResourceSummary(model)
        }
        menu.append(inventoryInfo)
        items.menu=UIMenu(title:(current.flatMap{state.units[$0]?.name} ?? "等待行动")+" · 对 \(friend.uppercased()) 使用",children:menu)
        items.isEnabled=active && !busy && current?.hasPrefix("p")==true && !model.terminal
        setNeedsLayout()
    }
    private func showResourceSummary(_ model:PartyEncounter) {
        var responder:UIResponder?=self
        while let node=responder, !(node is UIViewController) {responder=node.next}
        guard let controller=responder as? UIViewController,controller.presentedViewController==nil else{return}
        let actions=model.playerActions().map{model.actionReadout($0,ally:friend,enemy:foe).text}.joined(separator:"\n\n")
        let alert=UIAlertController(title:"个人资源与当前技能",message:"查看时快照，回合计时继续。\n\n"+model.partyResourceSummary+"\n\n"+actions,preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"关闭",style:.cancel));controller.present(alert,animated:true)
    }
    private func detail(_ a:PartyAction,model:PartyEncounter,actor:String)->String {
        guard a != .attack else {
            guard let unit=model.state.units[actor],let weapon=unit.equipment.weapon,let item=try? model.engine.catalog.item(weapon),let dice=item.attack?.dice else { return "未装备武器 · 请回营地装备" }
            let damage=(try? GameRules.attributes(unit,catalog:model.engine.catalog).damage) ?? 0
            return "\(item.name) · \(dice.count)D\(dice.sides)"+(damage>0 ? "＋\(damage)":"")
        }
        let damage=model.state.units[actor].flatMap { try? GameRules.attributes($0,catalog:model.engine.catalog).damage } ?? 0
        let modifier=damage>0 ? " · 增伤＋\(damage)":""
        let uses=model.state.units[actor]?.skillUses[a.rawValue] ?? 0
        let limit=(try? model.engine.catalog.skill(a.rawValue).uses) ?? 2
        let rest=max(0,limit-uses)
        switch a {
        case .runeSlash:return "2D12＋2"+modifier+" · 自身恢复4 / 盾4 · 余\(rest)"
        case .runeWard:return "目标地点：队友恢复8 / 盾6 · 余\(rest)"
        case .battleRune:return "目标地点：盾4 / 增伤3 · 2轮 · 余\(rest)"
        case .dragonFlame:return "目标地点：1D20＋6\(modifier) · 自身恢复6 / 盾6 / 增伤＋2 · 余\(rest)"
        case .starlightPulse:return "目标地点：1D12＋4\(modifier) · 自身恢复6 / 盾6 · 余\(rest)"
        case .sweep:return "目标地点：1D12\(modifier) · 余\(rest)"
        case .dragonSoulWard:return "目标地点：恢复10 / 盾10 / 增伤3 · 2轮 · 余\(rest)"
        case .dragonScaleWard:return "目标地点：恢复12 / 盾10 / 增伤2 · 1轮 · 余\(rest)"
        case .dragonOrder:return "目标地点：恢复6 / 盾8 / 增伤4 · 2轮 · 余\(rest)"
        case .ambush:return "2D8＋2"+modifier+" · 自身恢复3 · 余\(rest)"
        case .support:return "1 AP · 治疗6 / 盾4 · 余\(rest)"
        case .rally:return "1 AP · 节点友方增伤2 / 1轮 · 余\(rest)"
        case .heavyStrike:return "1D6＋2"+modifier+" · 余\(rest)"
        case .breather:return "1 AP · 自身恢复4 · 余\(rest)"
        default:return "1 AP · 自身护盾4 · 余\(rest)"
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let layout=MeadowBattleLayout(size:bounds.size,safeArea:safeAreaInsets,mode:.playerTurn)
        header.frame=layout.header;stage.frame=layout.battlefield;track.frame=layout.track;panel.frame=layout.details
        mapBorder.frame=layout.map;mapTitle.frame=CGRect(x:layout.map.minX+12,y:layout.map.minY+12,width:180,height:32)
        let w=header.bounds.width
        if classroomMode {[back,reset,end,items].forEach{$0.removeFromSuperview()}}
        back.frame=CGRect(x:w-124,y:16,width:112,height:44)
        end.frame=CGRect(x:w-310,y:16,width:178,height:44)
        reset.frame=CGRect(x:w-414,y:20,width:96,height:36)
        title.frame=CGRect(x:16,y:8,width:max(1,w-(classroomMode ? 32:446)),height:32)
        hint.frame=CGRect(x:16,y:43,width:max(1,w-(classroomMode ? 32:446)),height:23)
        let pw=panel.bounds.width,gap:CGFloat=10,bw=max(1,(pw-28-143-gap*3)/3)
        for (i,bar) in [health,ward,ap].enumerated() { bar.frame=CGRect(x:14+CGFloat(i)*(bw+gap),y:9,width:bw,height:43) }
        accessory.frame=CGRect(x:pw-145,y:8,width:38,height:38)
        buff.frame=CGRect(x:pw-100,y:8,width:38,height:38);shieldBuff.frame=CGRect(x:pw-55,y:8,width:38,height:38)
        skillScroll.frame=CGRect(x:14,y:62,width:max(1,pw-28),height:max(1,panel.bounds.height-72))
        let visible=skills.filter { !$0.isHidden };let n=CGFloat(visible.count)
        let cw=max(190,(skillScroll.bounds.width-110-n*10)/max(1,n))
        for (i,card) in visible.enumerated() { card.frame=CGRect(x:CGFloat(i)*(cw+10),y:0,width:cw,height:skillScroll.bounds.height) }
        items.frame=CGRect(x:n*(cw+10),y:0,width:100,height:skillScroll.bounds.height)
        skillScroll.contentSize=CGSize(width:items.frame.maxX,height:skillScroll.bounds.height)
    }
}

private final class MeadowPartyBuffButton:UIButton {
    private let tip=UILabel();private var pinned=false,hover=false
    override init(frame:CGRect) {
        super.init(frame:frame);layer.borderWidth=1.5;layer.cornerRadius=4;backgroundColor=MeadowPreviewPalette.panel
        tip.font=MeadowPreviewPalette.font(17);tip.numberOfLines=0;tip.backgroundColor=MeadowPreviewPalette.panel;tip.textColor=MeadowPreviewPalette.ink;tip.layer.borderWidth=1;tip.layer.borderColor=MeadowPreviewPalette.gold.cgColor;tip.isHidden=true;tip.isUserInteractionEnabled=false
        addSubview(tip);addGestureRecognizer(UIHoverGestureRecognizer(target:self,action:#selector(hovered(_:))))
        addAction(UIAction { [weak self] _ in guard let self else { return };self.pinned.toggle();self.disclose() },for:.touchUpInside);isPointerInteractionEnabled=true
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show(title:String,detail:String,symbol:String,color:UIColor) { isHidden=false;setImage(UIImage(systemName:symbol),for:.normal);tintColor=color;layer.borderColor=color.cgColor;tip.text=" \(title)\n \(detail.replacingOccurrences(of:"\n",with:"\n "))";accessibilityLabel=title+"，"+detail;disclose() }
    func hide() { isHidden=true;pinned=false;hover=false;disclose() }
    @objc private func hovered(_ r:UIHoverGestureRecognizer) { hover=r.state == .began || r.state == .changed;disclose() }
    private func disclose() {
        tip.isHidden=isHidden || !(pinned || hover || isFocused)
        guard !tip.isHidden else { return }
        var host=superview
        while host != nil && !(host is MeadowPartyBattleView) { host=host?.superview }
        guard let host else { tip.isHidden=true;return }
        if tip.superview !== host { host.addSubview(tip);tip.layer.zPosition=2000 }
        let rect=convert(bounds,to:host)
        tip.frame=CGRect(x:max(12,min(host.bounds.width-280,rect.maxX-268)),y:max(12,rect.minY-117),width:268,height:108)
    }
    override func didUpdateFocus(in context:UIFocusUpdateContext,with coordinator:UIFocusAnimationCoordinator) { super.didUpdateFocus(in:context,with:coordinator);disclose() }
    override func layoutSubviews() { super.layoutSubviews();if !tip.isHidden { disclose() } }
    override func didMoveToWindow() { super.didMoveToWindow();if window==nil { pinned=false;hover=false;tip.isHidden=true } }
    deinit { tip.removeFromSuperview() }
}
