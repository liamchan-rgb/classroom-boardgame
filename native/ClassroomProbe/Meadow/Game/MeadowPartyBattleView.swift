import UIKit
import ClassroomGameCore
import MeadowBattleSupport
import MeadowWorldSupport

/// A real two-player/two-target training encounter backed by the tabletop engine.
final class MeadowPartyBattleView:UIView {
    var classroomMode=false {didSet {if classroomMode {[back,reset,end,items].forEach{$0.removeFromSuperview()};header.isHidden=true;addSubview(leave);disarmLeave()}}}
    var classroomModelFactory:(()throws->PartyEncounter)?
    func classroomEnemyStep(){guard active,let target=model?.nextEnemyTarget() else{return};friend=target;performEnemy(target:target)}
    private var classroomPaused=false
    func classroomRefresh(){refresh()}
    func classroomSetPaused(_ value:Bool){classroomPaused=value;if value{scheduled?.cancel();scheduled=nil};stage.classroomPause(value);if !value{scheduleEnemy()}}
    var classroomBusy:Bool {stage.isPlaying || model?.pending != nil}
    var classroomActions:[PartyAction] {model?.playerActions() ?? []}
    func classroomAction(_ action:PartyAction,target:String){choose(target);perform(action)}
    func classroomFocus(_ action:PartyAction?,target:String){choose(target);focusedAction=action;stage.preview(action,target:action.map{self.target($0)} ?? target);highlightCard(action)}
    /// The skill the teacher's pointer is on grows and glows on the TV, so the class sees which one is being previewed.
    private var highlighted:PartyAction?
    private func highlightCard(_ action:PartyAction?) {
        guard action != highlighted else{return}
        highlighted=action
        let actions=model?.playerActions() ?? []
        for (i,card) in skills.enumerated() {
            let on=action != nil && i<actions.count && actions[i]==action
            if on {skillScroll.bringSubviewToFront(card)}
            card.layer.shadowColor=MeadowPreviewPalette.gold.cgColor;card.layer.shadowOffset = .zero
            UIView.animate(withDuration:0.22,delay:0,usingSpringWithDamping:0.62,initialSpringVelocity:0.6,options:[.allowUserInteraction,.beginFromCurrentState]){
                card.transform=on ? CGAffineTransform(scaleX:1.12,y:1.12).translatedBy(x:0,y:-6):.identity
                card.layer.shadowRadius=on ? 16:0;card.layer.shadowOpacity=on ? 0.9:0
            }
        }
        // Back to normal: refresh restores each card's own border and dimming.
        if action==nil {refresh()}
    }
    enum ClassroomHit {case action(PartyAction),target(String),toggleMap,leave}
    func classroomHit(at point:CGPoint)->ClassroomHit? {
        guard classroomMode,active,!classroomBusy,let model else{return nil}
        layoutIfNeeded()
        let actions=model.playerActions()
        for (index,card) in skills.enumerated() where index<actions.count && !card.isHidden {
            let p=convert(point,to:skillScroll)
            if skillScroll.bounds.contains(p),card.frame.contains(p){return .action(actions[index])}
        }
        if !drawer.isHidden,drawer.frame.insetBy(dx:-8,dy:-8).contains(point){return .toggleMap}
        if leave.superview != nil,!leave.isHidden,leave.frame.insetBy(dx:-6,dy:-6).contains(point) {return .leave}
        if let id=track.unit(at:convert(point,to:track)){return .target(id)}
        return stage.classroomTarget(at:convert(point,to:stage)).map{.target($0)}
    }
    func classroomPlayerDropFrames(in host:UIView)->[String:CGRect] {
        guard classroomMode,active,!track.isHidden else{return [:]}
        // No layoutIfNeeded(): asked from SwiftUI updates (drop-target overlay), where it would re-enter SwiftUI layout.
        return track.tokenFrames(in:host)
    }
    /// The teacher's click on the pull tab (the public screen has no touch of its own).
    func classroomToggleMap(){toggleMap()}
    /// "撤离" in the header (classroom only): leave the fight and go back to the map.
    private let leave=MeadowPreviewPalette.iconButton("figure.walk.departure","撤离")
    private var leaveArmed=false
    private var leaveDisarm:DispatchWorkItem?
    /// Two taps: the first arms the button (it turns red and asks again), the second confirms (returns true).
    func classroomLeaveTap()->Bool {
        if leaveArmed {disarmLeave();return true}
        armLeave();return false
    }
    private func armLeave() {
        leaveArmed=true;leave.configuration?.title="再点一次撤离";leave.configuration?.baseBackgroundColor=UIColor(red:0.86,green:0.30,blue:0.26,alpha:0.92);leave.configuration?.baseForegroundColor = .white
        setNeedsLayout()
        leaveDisarm?.cancel();let work=DispatchWorkItem{[weak self] in self?.disarmLeave()};leaveDisarm=work
        DispatchQueue.main.asyncAfter(deadline:.now()+3,execute:work)
    }
    private func disarmLeave() {
        leaveDisarm?.cancel();leaveDisarm=nil;leaveArmed=false
        leave.configuration?.title="撤离";leave.configuration?.baseBackgroundColor=UIColor.white.withAlphaComponent(0.55);leave.configuration?.baseForegroundColor=MeadowPreviewPalette.ink
        setNeedsLayout()
    }
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
    /// Who fought the last battle, kept after it ends so the turn bar does not fill up with the other teams.
    private var lastQueue:[String]=[]
    /// How the fight ended, judged by its own fighters (another team elsewhere being alive is not a win).
    private func endTitle(_ state:GameState,short:Bool)->String {
        if model?.isDuel == true {return "PVP结束"}
        if let outcome=state.lastOutcome,state.battle==nil {
            if outcome.winners.contains("players") {return short ? "战斗胜利":"小队胜利"}
            if outcome.winners.contains("monsters") {return "小队倒地"}
            return "已撤离"
        }
        let fighters=(state.battle?.queue ?? lastQueue).compactMap{state.units[$0]}.filter{$0.kind == .player}
        return fighters.contains(where:\.isAlive) ? (short ? "战斗胜利":"小队胜利"):"小队倒地"
    }
    private let title=MeadowPreviewPalette.label("小队支援",size:26,weight:.heavy)
    private let hint=MeadowPreviewPalette.label("",size:17,weight:.semibold)
    private let header=UIView(),panel=UIView()
    private let track=MeadowTurnOrderView(frame:.zero)
    /// Touch has no hover: the first tap on a skill previews it (the lens darkens, the hint says so), the second tap commits it.
    private var armed:PartyAction?
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
    /// The map drawer: a pull tab on the edge between the map and the battlefield. Closed, the battlefield takes the map's place.
    private let drawer=UIButton(type:.system)
    private(set) var mapHidden=UserDefaults.standard.bool(forKey:"MeadowBattleMapHidden")
    var onMapHiddenChanged:(()->Void)?
    
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
        drawer.backgroundColor=MeadowPreviewPalette.primary;drawer.tintColor = .white
        drawer.layer.cornerRadius=10;drawer.layer.borderWidth=1.5;drawer.layer.borderColor=UIColor.white.cgColor
        drawer.layer.shadowColor=UIColor.black.cgColor;drawer.layer.shadowOpacity=0.5;drawer.layer.shadowRadius=5;drawer.layer.shadowOffset = .zero
        drawer.accessibilityIdentifier="battleMapDrawer"
        drawer.addAction(UIAction { [weak self] _ in self?.toggleMap() },for:.touchUpInside)
        addSubview(drawer)
        track.onSelect={ [weak self] id in guard let self,!self.classroomMode else{return};self.choose(id) }
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
    /// Slides the map away (or back): the battlefield glides over the map's place on a spring, the pull tab travels with its edge and its arrow turns over.
    private func toggleMap() {
        mapHidden.toggle();UserDefaults.standard.set(mapHidden,forKey:"MeadowBattleMapHidden")
        onMapHiddenChanged?()
        setNeedsLayout()
        UIView.animate(withDuration:0.55,delay:0,usingSpringWithDamping:0.82,initialSpringVelocity:0.6,options:[.allowUserInteraction,.beginFromCurrentState]) { self.layoutIfNeeded() }
        UIView.animate(withDuration:0.1,animations:{ self.drawer.transform=CGAffineTransform(scaleX:1.25,y:0.9) }) { _ in
            UIView.animate(withDuration:0.4,delay:0,usingSpringWithDamping:0.45,initialSpringVelocity:0.8,options:.allowUserInteraction) { self.drawer.transform = .identity }
        }
    }
    private func configureTrainingMenu() {
        let catalog = try? GameCatalog.initial()
        func badge(_ id: String) -> UIImage? {
            let cap = id.prefix(1).uppercased() + id.dropFirst()
            guard let img = UIImage(named: "ClassBadge" + cap) else { return nil }
            let size = CGSize(width: 24, height: 24)
            return UIGraphicsImageRenderer(size: size).image { r in
                r.cgContext.interpolationQuality = .none
                img.draw(in: CGRect(origin: .zero, size: size))
            }.withRenderingMode(.alwaysOriginal)
        }
        let tierMenus = MeadowPartyConfiguration.classTiers.map { tier in
            UIMenu(title: tier.title, children: tier.ids.map { id in
                let name = (try? catalog?.playerClass(id).name) ?? id
                return UIAction(title: "P1 · " + name, image: badge(id), state: playerClassID == id ? .on : .off) { [weak self] _ in
                    guard let self else { return }
                    self.playerClassID = id; self.configureTrainingMenu(); self.restart()
                }
            })
        }
        let again = UIAction(title: "重置当前演练") { [weak self] _ in self?.restart() }
        reset.menu = UIMenu(children: [again, UIMenu(title: "P1职业（14 职业）", children: tierMenus)])
    }
    private func restart() {
        generation += 1;scheduled?.cancel();scheduled=nil;stage.stop();accessory.dismiss()
        // After the fight ended (result card still up) there is nothing to reload: keep showing the finished fight.
        if classroomMode,let current=model,(campaignEngine ?? current.engine).state.battle == nil {stage.start();refresh();return}
        do { if classroomMode {guard let factory=classroomModelFactory else{throw GameError("教师后台尚未准备战斗。")};model=try factory()}else{model = try campaignEngine.map { try PartyEncounter(engine:$0) } ?? PartyEncounter(loadouts:loadoutUnits,playerClassID:playerClassID)} } catch { hint.text="演练加载失败：\(error.localizedDescription)";return }
        friend="p1";foe=model?.monsterIDs.first ?? "m1";actionPointCapacity=[:];apRound=0
        lastQueue=model?.state.battle?.queue ?? []
        reset.isHidden=campaignEngine != nil;back.configuration?.title=campaignEngine == nil ? "返回单人":"返回行程"
        if let model,model.isDuel {stage.configureUnits(players:model.duelLeft,foes:model.duelRight,pvp:true)}
        else {stage.configureMonsters(model?.monsterIDs ?? ["m1","m2"])}
        stage.start();refresh();scheduleEnemy()
    }
    private func advanceDecisionClock() {
        guard active,campaignEngine != nil,let model,model.pending==nil,!stage.isPlaying,!model.terminal else{return}
        do {if let receipt=try model.engine.advanceClock(by:0.25){onCommit?(receipt);refresh();scheduleEnemy()}}
        catch {hint.text="保存失败："+error.localizedDescription;decisionTimer?.invalidate()}
    }
    private func choose(_ id:String) {
        guard model?.pending==nil else { return }
        disarm()
        if let model,model.isDuel {
            // Duel: a hero of the acting team is the friendly target, a hero of the other team the enemy.
            let mine=model.current.flatMap{model.state.units[$0]?.teamID}
            if model.state.units[id]?.teamID==mine { friend=id } else { foe=id };refresh();return
        }
        if id.hasPrefix("p") { friend=id } else { foe=id };refresh()
    }
    private func target(_ action:PartyAction)->String {model?.preferredTarget(for:action,ally:friend,enemy:foe) ?? (action.isOffensive ? foe:friend)}
    private func disarm() { if armed != nil { armed=nil;stage.preview(nil,target:friend) } }
    /// A skill card was pressed: with a pointer (hover already previewed it) or on the second tap, it goes; otherwise it is only previewed.
    private func pressed(_ action:PartyAction) {
        if armed==action || focusedAction==action { perform(action);return }
        armed=action;focusedAction=nil;stage.preview(action,target:target(action))
        let readout=model?.actionReadout(action,ally:friend,enemy:foe).text.replacingOccurrences(of:"\n",with:" · ")
        hint.text="已预览「\(action.title)」· 再点一次确认出手"+(readout.map { " · "+$0 } ?? "")
    }
    private func perform(_ action:PartyAction) {
        guard active,let model,let intent=model.prepare(action,target:target(action)) else { return }
        armed=nil;let token=generation;refresh()
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
        if model.isDuel {
            // Keep the targets relative to whoever is acting: friend on their team, foe on the other.
            let mine=current.flatMap{state.units[$0]?.teamID}
            let fighters=model.duelLeft+model.duelRight
            if state.units[friend]?.teamID != mine || !fighters.contains(friend) { friend=current ?? friend }
            if state.units[foe]?.isAlive != true || state.units[foe]?.teamID==mine || !fighters.contains(foe),
               let live=fighters.first(where:{ state.units[$0]?.isAlive==true && state.units[$0]?.teamID != mine }) { foe=live }
        } else {
            if state.units[foe]?.isAlive != true,let live=model.monsterIDs.first(where:{ state.units[$0]?.isAlive==true }) { foe=live }
            // The friendly target is always someone in this fight (P1 may be in another team's encounter).
            if let queue=state.battle?.queue,!queue.contains(friend),let first=current.flatMap({ queue.contains($0) && state.units[$0]?.kind == .player ? $0:nil }) ?? queue.first(where:{ state.units[$0]?.kind == .player }) { friend=first }
        }
        let busy=stage.isPlaying || model.pending != nil
        title.text=model.isDuel ? (model.terminal ? "PVP结束":"队伍PVP · 第\(model.round)轮") : model.terminal ? endTitle(state,short:false) : (campaignEngine == nil ? "小队支援":"林地遭遇")+" · 第\(model.round)轮"
        let showing=busy ? (stage.actorInAction ?? model.pending?.actor ?? current):current
        let name=showing.flatMap { state.units[$0]?.shortName } ?? "—"
        if busy { armed=nil }
        if armed==nil { hint.text=busy ? "\(name) · ⋯" : classroomMode ? "▶ \(name)"+(state.pauseReasons.isEmpty ? "":"  ⏸") : "\(name)行动 · 友方 \(model.state.units[friend]?.shortName ?? friend.uppercased()) / 敌方 \(model.state.units[foe]?.name ?? foe) · 点角色或上方顺序条选目标" }
        let displayActor=showing ?? "p1"
        if let unit=state.units[displayActor] {
            let visible=stage.displayedVitals(for:displayActor,health:unit.health,shield:unit.shield)
            health.show("生命",value:visible.health,maximum:(try? GameRules.attributes(unit,catalog:model.engine.catalog).maximumHealth) ?? unit.baseAttributes.maximumHealth,color:.systemGreen)
            ward.show("护盾",value:visible.shield,maximum:max(visible.shield,PartyVisual.shieldDisplayMaximum(unit:unit,catalog:model.engine.catalog)),color:.systemCyan)
            let stats=(try? GameRules.attributes(unit,catalog:model.engine.catalog)) ?? unit.baseAttributes
            if apRound != model.round { apRound=model.round;actionPointCapacity=[:] }
            let capacity=max(stats.baseAP,max(unit.ap,actionPointCapacity[displayActor] ?? 0))
            actionPointCapacity[displayActor]=capacity
            ap.show(value:unit.ap,maximum:capacity,owner:unit.shortName)
            accessory.show(try? AccessoryReadout.make(unit,catalog:model.engine.catalog),host:self)
            if let b=unit.damageBuff { buff.show(title:"增伤＋\(b.amount)",detail:"剩余 \(b.roundsLeft) 轮\n普攻和伤害技能生效",symbol:"arrow.up",color:MeadowPreviewPalette.gold) } else { buff.hide() }
            if visible.shield>0 { shieldBuff.show(title:"护盾 · \(visible.shield)",detail:"优先抵挡伤害\n新旧授盾取较高值\n战斗结束后清空",symbol:"shield.fill",color:.systemCyan) } else { shieldBuff.hide() }
        }
        // Someone joined the running fight (the teacher's hero, a late student): place them and play the entrance.
        let entering=(state.battle?.queue ?? []).filter{state.units[$0]?.kind == .player && !lastQueue.isEmpty && !lastQueue.contains($0)}
        if model.isDuel,model.syncDuelSides() {stage.configureUnits(players:model.duelLeft,foes:model.duelRight,pvp:true)}
        if let q=state.battle?.queue {lastQueue=q}
        // A finished fight keeps showing who was in it (not the whole class).
        let queue=state.battle?.queue ?? (lastQueue.isEmpty ? ["p1","p2"]+model.monsterIDs:lastQueue)
        let acted=state.battle?.acted ?? []
        let entries:[MeadowTurnOrderView.Entry]=queue.compactMap { id in
            guard let unit=state.units[id] else { return nil }
            let shown=stage.displayedVitals(for:id,health:unit.health,shield:unit.shield)
            let maximum=(try? GameRules.attributes(unit,catalog:model.engine.catalog).maximumHealth) ?? unit.baseAttributes.maximumHealth
            var face:UIImage?
            if unit.kind == .player,PixelHeroAtlas.enabled {
                let slot=state.players.firstIndex{$0.id==id} ?? MeadowPartyStageView.playerSlot(id)
                face=PixelHeroAtlas.portrait(PixelHeroLook.battle(unit:unit,slot:slot)){[weak self] in self?.classroomRefresh()}
            }
            return MeadowTurnOrderView.Entry(id:id,name:unit.shortName,hp:shown.health,maxHP:maximum,shield:shown.shield,enemy:model.isDuel ? model.duelRight.contains(id):unit.kind == .monster,acted:acted.contains(id) && id != showing,down:!unit.isAlive,portrait:face)
        }
        track.show(entries:entries,current:showing,round:model.round,selected:[friend,foe],finished:model.terminal ? endTitle(state,short:true):nil)
        UIView.animate(withDuration:0.2) { self.panel.alpha=busy ? 0.55:1 }
        stage.show(state,friend:friend,foe:foe,current:current,catalog:model.engine.catalog)
        for id in entering {stage.playEntrance(id)}
        let actions:[PartyAction]=busy ? showing.map { model.actions(for:$0) } ?? []:model.playerActions()
        if busy { focusedAction=nil }
        for (i,b) in skills.enumerated() {
            b.isHidden=i>=actions.count
            guard i<actions.count else { continue }
            let a=actions[i];let result=model.preview(a,target:target(a))
            let allowed=active && !busy && result.allowed
            if classroomMode {
                // Compact card: icon + name, AP pip, one short stat (dice / uses left). Colour carries the kind of action.
                let look=Self.look(a)
                b.updateCompact(name:a.title,cost:model.cost(a),uses:usesLeft(a,model:model,actor:displayActor),symbol:look.symbol,tint:look.tint,stat:shortStat(a,model:model,actor:displayActor),enabled:allowed)
            } else {
                b.update(title:a.title+" · \(model.cost(a)) AP",detail:(!busy && !result.allowed) ? result.message:detail(a,model:model,actor:displayActor),enabled:allowed)
            }
            b.previewStrength=0;b.previewColor = .clear
            b.button.removeTarget(nil,action:nil,for:.touchUpInside)
            b.button.removeAction(identifiedBy:UIAction.Identifier("party-skill"),for:.touchUpInside)
            b.button.addAction(UIAction(identifier:UIAction.Identifier("party-skill"),handler:{ [weak self] _ in guard let self,!self.classroomMode else{return};self.pressed(a) }),for:.touchUpInside)
            b.onFocus={ [weak self] focused in
                guard let self,!self.classroomMode else { return }
                if focused { self.focusedAction=a;self.armed=nil;self.stage.preview(a,target:self.target(a));self.hint.text=model.actionReadout(a,ally:self.friend,enemy:self.foe).text.replacingOccurrences(of:"\n",with:" · ") }
                else if self.focusedAction==a { self.focusedAction=nil;if self.armed==nil { self.stage.preview(nil,target:self.target(a)) } }
            }
            b.button.accessibilityHint=model.actionReadout(a,ally:friend,enemy:foe).text
        }
        end.isEnabled=active && !busy && current?.hasPrefix("p")==true && !model.terminal
        var menu:[UIAction]=[]
        let classicItems:Set<PartyAction>=[.smallPotion,.largePotion,.shieldPotion,.revivalStone]
        let visibleConsumables=PartyAction.allConsumables.filter { a in
            classicItems.contains(a) || (current.flatMap { state.units[$0]?.inventory[a.rawValue] } ?? 0) > 0
        }
        for a in visibleConsumables {
            let count=current.flatMap { state.units[$0]?.inventory[a.rawValue] } ?? 0
            let readout=model.actionReadout(a,ally:friend,enemy:foe)
            let allowed=readout.allowed
            menu.append(UIAction(title:"\(a.title) ×\(count) · \(a == .revivalStone ? 2:1) AP"+(allowed ? "":" · "+readout.availability),image:MeadowItemIcon.image(a.rawValue,side:28),attributes:allowed && !busy ? []:.disabled,handler:{ [weak self] _ in guard let self,!self.classroomMode else{return};self.perform(a) }))
        }
        let inventoryInfo=UIAction(title:"查看双方个人资源",image:UIImage(systemName:"list.bullet.rectangle")){[weak self] _ in
            guard let self else{return};self.showResourceSummary(model)
        }
        menu.append(inventoryInfo)
        items.menu=UIMenu(title:(current.flatMap{state.units[$0]?.name} ?? "等待行动")+" · 对 \(state.units[friend]?.shortName ?? friend.uppercased()) 使用",children:menu)
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
    static func look(_ a:PartyAction)->(symbol:String,tint:UIColor) {
        switch a {
        case .dragonFlame,.fireball,.emberNova:return ("flame.fill",UIColor(red:1,green:0.55,blue:0.25,alpha:1))
        case .frostNova:return ("snowflake",UIColor(red:0.42,green:0.84,blue:1,alpha:1))
        case .quickShot,.piercingArrow,.galeBarrage,.galeVolley:return ("wind",UIColor(red:0.32,green:0.88,blue:0.78,alpha:1))
        case .thornSnare,.elderBloom,.barkAegis,.wildwoodBreeze,.oakBulwark:return ("leaf.fill",UIColor(red:0.42,green:0.88,blue:0.48,alpha:1))
        case .sonicNote,.healingLullaby,.heroicAnthem:return ("music.note",UIColor(red:1.0,green:0.62,blue:0.78,alpha:1))
        case .meteorStarfall,.astralDome,.arcaneOverdrive,.astralJudgement,.runeSlash,.starlightPulse:return ("wand.and.rays",UIColor(red:0.72,green:0.55,blue:1,alpha:1))
        case .holyBolt,.judgmentStrike,.radiantBaptism,.seraphAegis,.valkyrieGuard,.skybreaker:return ("sun.max.fill",UIColor(red:1.0,green:0.82,blue:0.35,alpha:1))
        case .ambush:return ("eye.slash.fill",UIColor(red:0.72,green:0.55,blue:1,alpha:1))
        case .endTurn:return ("hourglass",UIColor(white:0.8,alpha:1))
        default:break
        }
        switch a.visual {
        case "heal":return ("heart.fill",UIColor(red:0.45,green:0.90,blue:0.55,alpha:1))
        case "guard","runeWard":return ("shield.fill",UIColor(red:0.45,green:0.80,blue:1,alpha:1))
        case "support","battleRune":return ("sparkles",UIColor(red:1,green:0.84,blue:0.38,alpha:1))
        case "revive":return ("arrow.counterclockwise.heart.fill",UIColor(red:0.45,green:0.90,blue:0.55,alpha:1))
        default:return ("burst.fill",UIColor(red:1,green:0.42,blue:0.38,alpha:1))
        }
    }
    /// Every card says what the action does in the same words: 伤害 (with the actor's bonus folded in) / 治疗 / 护盾 / 增伤.
    private func shortStat(_ a:PartyAction,model:PartyEncounter,actor:String)->String? {
        guard let unit=model.state.units[actor] else{return nil}
        let bonus=(try? GameRules.attributes(unit,catalog:model.engine.catalog).damage) ?? 0
        func hit(_ dice:String,_ flat:Int)->String {let total=flat+bonus;return "伤害 "+dice+(total>0 ? "+\(total)":"")}
        if a == .attack {
            guard let weapon=unit.equipment.weapon,let dice=(try? model.engine.catalog.item(weapon))?.attack?.dice else{return "无武器"}
            return hit("\(dice.count)D\(dice.sides)",dice.flat)
        }
        if a == .endTurn { return "保留行动" }
        if a.isItem { return nil }
        if let skill=try? model.engine.catalog.skill(a.rawValue) {
            var parts:[String]=[]
            for e in skill.effects {
                switch e.kind {
                case .damage:
                    if let d=e.dice { parts.append(hit("\(d.count)D\(d.sides)",d.flat)) }
                case .heal: parts.append("治疗 \(e.amount)")
                case .shield: parts.append("护盾 \(e.amount)")
                case .damageBuff: parts.append("增伤 \(e.amount)")
                }
            }
            if !parts.isEmpty { return parts.joined(separator:" · ") }
        }
        return nil
    }
    private func usesLeft(_ a:PartyAction,model:PartyEncounter,actor:String)->Int? {
        guard let unit=model.state.units[actor],let limit=(try? model.engine.catalog.skill(a.rawValue))?.uses else{return nil}
        return max(0,limit-(unit.skillUses[a.rawValue] ?? 0))
    }
    private func detail(_ a:PartyAction,model:PartyEncounter,actor:String)->String {
        guard a != .attack else {
            guard let unit=model.state.units[actor],let weapon=unit.equipment.weapon,let item=try? model.engine.catalog.item(weapon),let dice=item.attack?.dice else { return "未装备武器 · 请回营地装备" }
            let damage=(try? GameRules.attributes(unit,catalog:model.engine.catalog).damage) ?? 0
            let totalFlat=dice.flat+damage
            return "\(item.name) · \(dice.count)D\(dice.sides)"+(totalFlat>0 ? "＋\(totalFlat)":"")
        }
        let damage=model.state.units[actor].flatMap { try? GameRules.attributes($0,catalog:model.engine.catalog).damage } ?? 0
        let modifier=damage>0 ? " · 增伤＋\(damage)":""
        let uses=model.state.units[actor]?.skillUses[a.rawValue] ?? 0
        guard let skill=try? model.engine.catalog.skill(a.rawValue) else { return a.title }
        let rest=skill.uses.map { max(0,$0-uses) }
        let prefix:String = {
            switch skill.target {
            case .enemiesAtNode: return "同点全敌："
            case .alliesAtNode: return "同点全友："
            case .ally: return "友方："
            case .selfOnly: return "自身："
            case .enemy: return ""
            }
        }()
        var parts:[String]=[]
        for e in skill.effects {
            let who=e.scope == .caster && skill.target != .selfOnly ? "自身":""
            switch e.kind {
            case .damage:
                if let d=e.dice {
                    let base="\(d.count)D\(d.sides)"+(d.flat>0 ? "＋\(d.flat)":"")
                    parts.append(base+modifier)
                }
            case .heal: parts.append("\(who)恢复\(e.amount)")
            case .shield: parts.append("\(who)盾\(e.amount)")
            case .damageBuff: parts.append("\(who)增伤＋\(e.amount)(\(e.rounds)轮)")
            }
        }
        let tail=rest.map { " · 余\($0)" } ?? ""
        return prefix+parts.joined(separator:" / ")+tail
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        // Classroom: no title bar; the battlefield takes its height (the dice and the fight read better on the TV).
        let layout=MeadowBattleLayout(size:bounds.size,safeArea:safeAreaInsets,mode:.playerTurn,showsHeader:!classroomMode)
        header.frame=layout.header;track.frame=layout.track;panel.frame=layout.details
        let field=mapHidden ? layout.map.union(layout.battlefield):layout.battlefield
        stage.frame=field
        mapBorder.frame=layout.map;mapTitle.frame=CGRect(x:layout.map.minX+12,y:layout.map.minY+12,width:180,height:32)
        mapBorder.alpha=mapHidden ? 0:1;mapTitle.alpha=mapHidden ? 0:1
        // The pull tab rides the battlefield's left edge (inside it when the map is away).
        let saved=drawer.transform;drawer.transform = .identity
        drawer.frame=CGRect(x:mapHidden ? field.minX:field.minX-17,y:field.midY-46,width:34,height:92)
        drawer.transform=saved
        drawer.setImage(UIImage(systemName:mapHidden ? "chevron.right.2":"chevron.left.2",withConfiguration:UIImage.SymbolConfiguration(pointSize:17,weight:.heavy)),for:.normal)
        drawer.accessibilityLabel=mapHidden ? "显示地图":"隐藏地图"
        bringSubviewToFront(drawer)
        let w=header.bounds.width
        if classroomMode {[back,reset,end,items].forEach{$0.removeFromSuperview()}}
        back.frame=CGRect(x:w-124,y:16,width:112,height:44)
        end.frame=CGRect(x:w-310,y:16,width:178,height:44)
        reset.frame=CGRect(x:w-414,y:20,width:96,height:36)
        let leaveW:CGFloat=leaveArmed ? 176:104
        // "撤离" floats in the battlefield's top-right corner.
        leave.frame=CGRect(x:field.maxX-leaveW-12,y:field.minY+12,width:leaveW,height:44);bringSubviewToFront(leave)
        let reserved:CGFloat=classroomMode ? leaveW+44:446
        title.frame=CGRect(x:16,y:8,width:max(1,w-reserved),height:32)
        hint.frame=CGRect(x:16,y:43,width:max(1,w-reserved),height:23)
        let pw=panel.bounds.width,gap:CGFloat=10,bw=max(1,(pw-28-143-gap*3)/3)
        // 50 tall: the AP diamonds sit 26 pt down and are 18 pt high, so a shorter bar clipped their lower tips.
        for (i,bar) in [health,ward,ap].enumerated() { bar.frame=CGRect(x:14+CGFloat(i)*(bw+gap),y:8,width:bw,height:50) }
        accessory.frame=CGRect(x:pw-145,y:8,width:38,height:38)
        buff.frame=CGRect(x:pw-100,y:8,width:38,height:38);shieldBuff.frame=CGRect(x:pw-55,y:8,width:38,height:38)
        skillScroll.frame=CGRect(x:14,y:66,width:max(1,pw-28),height:max(1,panel.bounds.height-76))
        let visible=skills.filter { !$0.isHidden };let n=CGFloat(visible.count)
        let cw=classroomMode ? max(1,(skillScroll.bounds.width-max(0,n-1)*10)/max(1,n)):max(190,(skillScroll.bounds.width-110-n*10)/max(1,n))
        for (i,card) in visible.enumerated() { let t=card.transform;card.transform = .identity;card.frame=CGRect(x:CGFloat(i)*(cw+10),y:0,width:cw,height:skillScroll.bounds.height);card.transform=t }
        skillScroll.clipsToBounds = !classroomMode
        items.frame=CGRect(x:n*(cw+10),y:0,width:100,height:skillScroll.bounds.height)
        skillScroll.contentSize=CGSize(width:classroomMode ? skillScroll.bounds.width:items.frame.maxX,height:skillScroll.bounds.height)
        if classroomMode {skillScroll.isScrollEnabled=false;skillScroll.contentOffset = .zero}
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
    func show(title:String,detail:String,symbol:String,color:UIColor) { isHidden=false;setImage(UIImage(systemName:symbol),for:.normal);tintColor=MeadowPreviewPalette.readable(color);layer.borderColor=MeadowPreviewPalette.readable(color).cgColor;tip.text=" \(title)\n \(detail.replacingOccurrences(of:"\n",with:"\n "))";accessibilityLabel=title+"，"+detail;disclose() }
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
