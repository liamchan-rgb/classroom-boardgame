import UIKit
import ClassroomGameCore
import MeadowBattleSupport

final class MeadowPartyStageView:UIView {
    var onChoose:((String)->Void)?
    var onPresentationChanged:(()->Void)?
    private let world=UIView(),dim=UIView()
    private let clock=MeadowBattleSceneClock()
    private let fx=MeadowPartyEffectsView()
    private var monsterIDs=["m1","m2"]
    private var playerIDs=["p1","p2"]
    private var renderIDs:[String] {playerIDs+monsterIDs}
    private var actors:[String:MeadowBattleActorView]=[:]
    private let afterimages=(0..<3).map { _ in UIImageView() }
    private var monsters:[String:UIImageView]=[:],winds:[String:UIImageView]=[:]
    private var shadows:[String:MeadowBattleGroundingView]=[:]
    private var attached:[String:MeadowBattleAttachedSkillsView]=[:]
    private var labels:[String:MeadowBattleVitalsView]=[:]
    private var monsterFlash:[String:UIImageView]=[:]
    private let diceView=MeadowBattleDiceView()
    private var catalog=try? GameCatalog.initial()
    private var current:String?
    private var diceActor="p1",diceAction:PartyAction?,diceVisibleAt=0.0,diceSettledAt:Double?,diceExitAt:Double?,diceConfirmedAt:Double?
    private var dimFrom=0.0,dimTarget=0.0,dimChangedAt=0.0,castDim=0.0
    private var state:GameState?
    private var sceneTime=0.0,startAt=0.0
    private var intent:PartyIntent?
    private var impact:(()->OperationReceipt?)?
    private var completion:(()->Void)?
    private var naturalTwenty=false
    private var fired=false,meetsShield=false
    var actorInAction:String? { intent?.actor }
    private var focus:PartyAction?,focusTarget="p1",focusAt=0.0
    private var recovery:[String:Double]=[:],formation:[String:Double]=[:],birth:[String:Double]=[:],contact:[String:Double]=[:],broken:[String:Double]=[:],deaths:[String:Double]=[:],hurt:[String:Double]=[:]
    private var recoveryTier:[String:HealingEffectTier]=[:]
    private var fallen:[String:Double]=[:]
    private var victoryAt:Double?
    private var poseKeys:[String:String]=[:]
    private var messages:[MeadowPartyMessage]=[]
    private var emissions:[MeadowBattleLightEmission]=[]
    private var skillVFX:[MeadowPartySkillVFXEvent]=[]
    private struct PendingStatusCue {
        let unitID:String,heal:Int,shieldGain:Int
        let at:Double,point:CGPoint,supportUnit:Bool
    }
    private var pendingStatusCues:[PendingStatusCue]=[]
    private var statusSnapshots:[String:(health:Int,shield:Int)]=[:]
    var isPlaying:Bool { intent != nil }
    override init(frame:CGRect) {
        super.init(frame:frame);backgroundColor=MeadowPreviewPalette.panel;clipsToBounds=true;layer.cornerRadius=12
        addSubview(world);world.bounds=CGRect(x:0,y:0,width:1000,height:600);world.clipsToBounds=false
        for (i,name) in MeadowBattleCanvasGeometry.sceneLayerOrder.enumerated() {
            let image=MeadowBattlePlateProcessor.image(named:name,role:[.farForest,.ground,.midground,.foreground][i])
            let view=UIImageView(image:image);view.frame=CGRect(x:0,y:-159,width:1000,height:1000*1201/1309)
            view.layer.zPosition=i==3 ? 900:CGFloat(-100+i);world.addSubview(view)
        }
        dim.backgroundColor = .black;dim.frame=CGRect(x:0,y:-500,width:1000,height:1600);dim.layer.zPosition=100;dim.isUserInteractionEnabled=false;world.addSubview(dim)
        for id in renderIDs { installUnit(id) }
        diceView.layer.zPosition=1200;world.addSubview(diceView)
        for ghost in afterimages { ghost.isHidden=true;ghost.isUserInteractionEnabled=false;ghost.layer.magnificationFilter = .nearest;world.addSubview(ghost) }
        fx.frame=world.bounds;fx.layer.zPosition=1000;world.addSubview(fx)
        clock.onTick={ [weak self] delta in self?.advance(delta) }
    }
    private func installUnit(_ id:String) {
        let shadow:MeadowBattleGroundingView
        if id.hasPrefix("p") {
            let actor=MeadowBattleActorView(frame:.zero);actors[id]=actor;world.addSubview(actor)
            let skills=MeadowBattleAttachedSkillsView(frame:.zero);actor.addSubview(skills);attached[id]=skills
            shadow=MeadowBattleGroundingView(image:actor.silhouette,soleY:214,contacts:[])
            actor.addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(tapped(_:))));actor.accessibilityIdentifier=id
        } else {
            let image=UIImage(named:"MeadowBattleForestWarden")
            let view=UIImageView(image:image);monsters[id]=view;view.isUserInteractionEnabled=true;view.layer.magnificationFilter = .nearest
            let flash=UIImageView();flash.isUserInteractionEnabled=false;flash.layer.magnificationFilter = .nearest;monsterFlash[id]=flash;world.addSubview(flash)
            let skills=MeadowBattleAttachedSkillsView(frame:.zero);attached[id]=skills;world.addSubview(skills)
            world.addSubview(view);view.accessibilityIdentifier=id;view.addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(tapped(_:))))
            let wind=UIImageView();wind.layer.magnificationFilter = .nearest;wind.layer.zPosition=950;winds[id]=wind;world.addSubview(wind)
            shadow=MeadowBattleGroundingView(image:image,soleY:240,contacts:[.init(point:CGPoint(x:84,y:240),radius:15),.init(point:CGPoint(x:172,y:240),radius:15),.init(point:CGPoint(x:230,y:240),radius:15),.init(point:CGPoint(x:314,y:240),radius:15)])
        }
        shadows[id]=shadow;shadow.layer.zPosition=200;shadow.frame=world.bounds;world.addSubview(shadow)
        let label=MeadowBattleVitalsView();label.layer.zPosition=1100;labels[id]=label;world.addSubview(label)

    }
    func configureMonsters(_ ids:[String]) {
        guard ids != monsterIDs else{return}
        for id in monsterIDs {
            monsters.removeValue(forKey:id)?.removeFromSuperview();winds.removeValue(forKey:id)?.removeFromSuperview()
            attached.removeValue(forKey:id)?.removeFromSuperview();monsterFlash.removeValue(forKey:id)?.removeFromSuperview();shadows.removeValue(forKey:id)?.removeFromSuperview();labels.removeValue(forKey:id)?.removeFromSuperview()
        }
        monsterIDs=ids;for id in ids {installUnit(id)}
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tapped(_ r:UITapGestureRecognizer) { if !isPlaying,let id=r.view?.accessibilityIdentifier { onChoose?(id) } }
    /// Uses the displayed actors/vitals, including the world's current fit transform.
    func classroomTarget(at point:CGPoint)->String? {
        guard !isPlaying,bounds.contains(point) else{return nil}
        let p=convert(point,to:world)
        for id in renderIDs.reversed() {
            if let label=labels[id],!label.isHidden,label.alpha>0,label.frame.contains(p){return id}
        }
        let candidates=renderIDs.filter {id in
            let unit:UIView?=actors[id].map{$0 as UIView} ?? monsters[id].map{$0 as UIView}
            return unit.map{!$0.isHidden && $0.alpha>0 && $0.frame.contains(p)} ?? false
        }
        return candidates.min {a,b in
            guard let x=PartyVisual.foot(a),let y=PartyVisual.foot(b) else{return false}
            return hypot(p.x-x.x,p.y-(x.y-60))<hypot(p.x-y.x,p.y-(y.y-60))
        }
    }
    func start() { MeadowBattleVFXAssets.prewarm();victoryAt=nil;sceneTime=0;recovery=[:];recoveryTier=[:];formation=[:];birth=[:];contact=[:];broken=[:];deaths=[:];hurt=[:];messages=[];emissions=[];skillVFX=[];pendingStatusCues=[];statusSnapshots=[:];poseKeys=[:];fallen=[:];diceAction=nil;diceConfirmedAt=nil;diceView.confirmationAge=nil;diceView.dice=[];diceSettledAt=nil;diceExitAt=nil;dimFrom=0;dimTarget=0;clock.start() }
    func classroomPause(_ value:Bool){if value{clock.stop()}else{clock.start()}}
    func stop() { MeadowMonsterFrames.retain([]);clock.stop();intent=nil;impact=nil;completion=nil;focus=nil;skillVFX=[];pendingStatusCues=[];statusSnapshots=[:] }
    func displayedVitals(for unitID:String,health:Int,shield:Int)->(health:Int,shield:Int) { statusSnapshots[unitID] ?? (health,shield) }
    func show(_ value:GameState,friend:String,foe:String,current:String?,catalog:GameCatalog) {
        let ids=value.players.map(\.id)
        if ids != playerIDs {
            for id in playerIDs where !ids.contains(id){actors.removeValue(forKey:id)?.removeFromSuperview();shadows.removeValue(forKey:id)?.removeFromSuperview();attached.removeValue(forKey:id)?.removeFromSuperview();labels.removeValue(forKey:id)?.removeFromSuperview()}
            for id in ids where actors[id]==nil{installUnit(id)}
            playerIDs=ids
        }
        state=value;self.current=current;self.catalog=catalog;fx.friend=friend;fx.foe=foe
        MeadowMonsterFrames.retain(Set(value.units.values.filter{$0.kind == .monster && renderIDs.contains($0.id)}.compactMap{MonsterVisualSpec.find($0.templateID)?.id}))
        for id in renderIDs where value.units[id]?.isAlive==false {
            if id.hasPrefix("m"),deaths[id]==nil {deaths[id]=sceneTime-MeadowBattleVisualMotion.deathDuration}
            if id.hasPrefix("p"),fallen[id]==nil {fallen[id]=sceneTime-2}
        }
        for (id,label) in labels {
            guard let u=value.units[id] else { continue }
            let visible=displayedVitals(for:id,health:u.health,shield:u.shield)
            label.show(name:(id==current ? "▶ ":"")+u.name,hp:visible.health,maximum:(try? GameRules.attributes(u,catalog:catalog).maximumHealth) ?? u.baseAttributes.maximumHealth,shield:visible.shield,maximumShield:max(visible.shield,PartyVisual.shieldDisplayMaximum(unit:u,catalog:catalog)))
        }
        render()
    }
    private func maximumHealth(_ unit:GameUnit)->Int {
        guard let catalog else { return unit.baseAttributes.maximumHealth };return (try? GameRules.attributes(unit,catalog:catalog).maximumHealth) ?? unit.baseAttributes.maximumHealth
    }
    private func previewDarkness()->Double { dimFrom+(dimTarget-dimFrom)*PartyVisual.smooth((sceneTime-dimChangedAt)/0.28) }
    func preview(_ action:PartyAction?,target:String) {
        guard !isPlaying,action != focus || target != focusTarget else { return }
        dimFrom=previewDarkness();dimTarget=action.map(BattleDice.darkness) ?? 0;dimChangedAt=sceneTime
        focus=action;focusTarget=target;focusAt=sceneTime
        if let action,let state,let actorID=current,let actor=state.units[actorID],let targetUnit=state.units[target],let catalog {
            diceActor=actorID;diceAction=action;diceVisibleAt=sceneTime;diceSettledAt=nil;diceExitAt=nil
            diceView.locked=false;diceConfirmedAt=nil
            diceView.dice=BattleDice.channels(action,actor:actor,target:targetUnit,catalog:catalog)
        } else { diceExitAt=sceneTime }
    }
    func play(_ value:PartyIntent,before:GameState,confirmed:OperationReceipt?,onImpact:@escaping ()->OperationReceipt?,completion:@escaping ()->Void) {
        castDim=previewDarkness();dimFrom=0;dimTarget=0;dimChangedAt=sceneTime
        if let actor=before.units[value.actor],let target=before.units[value.target],let catalog {
            if diceAction != value.action || diceActor != value.actor { diceVisibleAt=sceneTime }
            diceAction=value.action;diceActor=value.actor;diceSettledAt=nil;diceExitAt=nil
            diceView.dice=BattleDice.channels(value.action,actor:actor,target:target,catalog:catalog,receipt:confirmed,sourceSkillID:value.sourceSkillID);diceView.locked=confirmed != nil;diceConfirmedAt=confirmed == nil ? nil:sceneTime
        }
        naturalTwenty=confirmed?.dice.contains { $0.naturalTwenty } ?? false
        intent=value;state=before;startAt=sceneTime;self.impact=onImpact;self.completion=completion;fired=false;focus=nil;meetsShield=(before.units[value.target]?.shield ?? 0)>0
        if let spec=value.action.skillVFX {
            let hitAge=value.impactAge
            let groundYs=value.targets.compactMap { PartyVisual.foot($0)?.y }
            let groundY=groundYs.isEmpty ? (PartyVisual.foot(value.actor)?.y ?? PartyVisual.height):groundYs.reduce(0,+)/Double(groundYs.count)
            skillVFX.append(MeadowPartySkillVFXEvent(spec:spec,startedAt:spec.startTime(actionStart:sceneTime,impactAge:hitAge),center:PartyVisual.skillEffectCenter(targets:value.targets,actor:value.actor,templates:before.units.mapValues(\.templateID)),groundY:groundY))
        }
        let delayed=sceneTime+max(0,value.action.impact-0.46)
        let statusAge=value.action.statusVFXCueAge ?? value.action.impact
        let statusCueIsLate=statusAge>value.action.impact+0.0001
        for id in value.targets {
            guard let unit=before.units[id] else { continue }
            if !statusCueIsLate,["support","guard"].contains(value.action.visual),unit.shield<([PartyAction.shieldPotion].contains(value.action) ? 8:4) { formation[id]=delayed }
        }
        render()
    }
    private func advance(_ delta:Double) {
        guard window != nil,!isHidden else { clock.stop();return }
        sceneTime += delta
        emissions.removeAll { sceneTime-$0.startedAt>3 };messages.removeAll { sceneTime-$0.at>1.0 }
        skillVFX.removeAll { sceneTime-$0.startedAt>$0.spec.duration }
        let due=pendingStatusCues.filter { $0.at<=sceneTime+1e-9 }
        if !due.isEmpty {
            pendingStatusCues.removeAll { $0.at<=sceneTime+1e-9 }
            due.forEach(revealStatusCue)
        }
        if let value=intent {
            let age=sceneTime-startAt
            let end=value.visualDuration
            let hit=value.impactAge
            if !fired,age>=hit {
                fired=true;let callback=impact;impact=nil
                if let receipt=callback?() { apply(receipt,intent:value) }
            }
            render()
            if age>=end { intent=nil;impact=nil;let finished=completion;completion=nil;MeadowBattleFrameTiming.flush();finished?() }
        } else { render() }
    }
    private func apply(_ receipt:OperationReceipt,intent:PartyIntent) {
        state=receipt.after
        if receipt.dice.contains(where: { $0.naturalTwenty }) { let p=PartyVisual.hitPoint(target:intent.target,weaponID:intent.weaponID,templateID:receipt.before.units[intent.target]?.templateID);messages.append(.init(text:"自然20",point:CGPoint(x:p.x,y:p.y-55),at:sceneTime,color:.systemCyan,atImpact:true)) }
        if let actor=receipt.before.units[intent.actor],let target=receipt.before.units[intent.target],let catalog {
            diceView.dice=BattleDice.channels(intent.action,actor:actor,target:target,catalog:catalog,receipt:receipt,sourceSkillID:intent.sourceSkillID);diceSettledAt=sceneTime
        }
        for id in renderIDs {
            guard let before=receipt.before.units[id],let after=receipt.after.units[id],let foot=PartyVisual.foot(id) else { continue }
            let heal=max(0,after.health-before.health),damage=max(0,before.health-after.health),gain=max(0,after.shield-before.shield),absorbed=max(0,before.shield-after.shield)
            let shieldHit=absorbed>0 && id.hasPrefix("p")
            let statusAt=startAt+(intent.action.statusVFXCueAge ?? intent.action.impact)
            let delayStatus=after.isAlive && (heal>0 || gain>0) && statusAt>sceneTime+0.0001
            let showsBesideOwner=intent.action.isRune || intent.action == .dragonFlame || intent.action == .starlightPulse || intent.action.isNodeSupport
            let registered=PartyVisual.hitPoint(target:id,shielded:shieldHit,weaponID:intent.weaponID,templateID:before.templateID)
            let point=["greatSword","legendaryStaff"].contains(intent.weaponID ?? "") && id.hasPrefix("m") ? CGPoint(x:registered.x,y:registered.y):CGPoint(x:foot.x+(shieldHit ? (5+240*0.41)*PartyVisual.heroScale:(id.hasPrefix("m") ? -80:0)),y:foot.y-(id.hasPrefix("p") ? 65:72))
            if delayStatus {
                statusSnapshots[id]=(before.health,before.shield)
                pendingStatusCues.append(.init(unitID:id,heal:heal,shieldGain:gain,at:statusAt,point:point,supportUnit:showsBesideOwner))
            }
            if heal>0 && !delayStatus {
                let shift=intent.actor==id ? PartyVisual.travel(intent,age:sceneTime-startAt):PartyPoint(0,0)
                recovery[id]=sceneTime
                recoveryTier[id]=HealingEffectTier.classify(actualHPGained:heal)
                messages.append(.init(text:"＋\(heal)",point:CGPoint(x:point.x+shift.x,y:point.y+shift.y),at:sceneTime,color:.systemGreen,supportUnit:showsBesideOwner ? id:nil))
            }
            if gain>0 && !delayStatus { birth[id]=sceneTime;messages.append(.init(text:"盾 ＋\(gain)",point:CGPoint(x:point.x,y:point.y+(intent.action.isRune || intent.action == .dragonFlame || intent.action.isNodeSupport ? 36:24)),at:sceneTime,color:.systemCyan,supportUnit:showsBesideOwner ? id:nil,supportLine:1)) }
            if after.damageBuff != before.damageBuff,let b=after.damageBuff { messages.append(.init(text:"伤害 ＋\(b.amount)",point:CGPoint(x:point.x,y:point.y-(intent.action.isRune || intent.action == .dragonFlame || intent.action.isNodeSupport ? 36:0)),at:sceneTime,color:MeadowPreviewPalette.gold,supportUnit:showsBesideOwner ? id:nil,supportLine:(heal>0 || gain>0) ? 2:0)) }
            if damage>0 || absorbed>0 {
                hurt[id]=sceneTime
                let hit=PartyVisual.hitPoint(target:id,shielded:absorbed>0,weaponID:intent.weaponID,templateID:before.templateID)
                messages.append(.init(text:damage>0 ? "−\(damage)":"格挡",point:CGPoint(x:hit.x,y:hit.y),at:sceneTime,color:damage>0 ? .white:.systemCyan,atImpact:true))
                let p=CGPoint(x:hit.x,y:hit.y)
                if absorbed>0 || intent.action.skillVFX == nil { emissions.append(.init(kind:absorbed>0 ? .shieldContact:.strike,startedAt:sceneTime,x:Double(p.x),y:Double(p.y),groundY:foot.y)) }
            }
            if absorbed>0 { contact[id]=sceneTime;if after.shield==0 { broken[id]=sceneTime;emissions.append(.init(kind:.shieldBreak,startedAt:sceneTime,x:foot.x,y:foot.y-60,groundY:foot.y)) } }
            if before.isAlive && !after.isAlive && after.kind == .monster { deaths[id]=sceneTime;emissions.append(.init(kind:.death,startedAt:sceneTime,x:registered.x,y:registered.y,groundY:foot.y)) }
            if before.isAlive && !after.isAlive && after.kind == .player { recovery[id]=nil;recoveryTier[id]=nil;fallen[id]=sceneTime }
        }
        onPresentationChanged?()
    }
    private func revealStatusCue(_ cue:PendingStatusCue) {
        statusSnapshots.removeValue(forKey:cue.unitID)
        if cue.heal>0 {
            recovery[cue.unitID]=cue.at
            recoveryTier[cue.unitID]=HealingEffectTier.classify(actualHPGained:cue.heal)
            let shift=intent?.actor==cue.unitID ? PartyVisual.travel(intent,age:sceneTime-startAt):PartyPoint(0,0)
            messages.append(.init(text:"＋\(cue.heal)",point:CGPoint(x:cue.point.x+shift.x,y:cue.point.y+shift.y),at:cue.at,color:.systemGreen,supportUnit:cue.supportUnit ? cue.unitID:nil))
        }
        if cue.shieldGain>0 {
            birth[cue.unitID]=cue.at
            messages.append(.init(text:"盾 ＋\(cue.shieldGain)",point:CGPoint(x:cue.point.x,y:cue.point.y+36),at:cue.at,color:.systemCyan,supportUnit:cue.supportUnit ? cue.unitID:nil,supportLine:1))
        }
        onPresentationChanged?()
    }
    private func render() {
        guard let state else { return }
        let defeated=state.units.values.filter { $0.kind == .monster }
        let won = !defeated.isEmpty && defeated.allSatisfy { !$0.isAlive } && state.players.contains { $0.isAlive }
        if won && intent == nil { if victoryAt == nil { victoryAt=sceneTime } }
        else if !won { victoryAt=nil }
        CATransaction.begin();CATransaction.setDisableActions(true);defer { CATransaction.commit() }
        let age=sceneTime-startAt;let moving=PartyVisual.travel(intent,age:age,shielded:meetsShield)
        let trails=PartyVisual.afterimages(intent,age:age)
        for (i,ghost) in afterimages.enumerated() {
            guard i<trails.count,let intent,let actor=actors[intent.actor],let foot=PartyVisual.foot(intent.actor) else { ghost.isHidden=true;continue }
            let trail=trails[i],pose=MeadowBattleAnimation.sample(clip:"attack",progress:CGFloat(trail.progress)),s=PartyVisual.heroScale
            ghost.image=actor.trailImage(progress:CGFloat(trail.progress));ghost.alpha=trail.alpha;ghost.isHidden=false;ghost.layer.zPosition=foot.y-1
            ghost.frame=CGRect(x:foot.x+trail.offset.x+(Double(pose.rootOffset.x)-123)*s,y:foot.y+trail.offset.y+(Double(pose.rootOffset.y)-214)*s,width:256*s,height:256*s)
        }
        for id in renderIDs {
            guard let unit=state.units[id],let f=PartyVisual.foot(id) else { continue }
            let shownVitals=displayedVitals(for:id,health:unit.health,shield:unit.shield)
            labels[id]?.isHidden=unit.kind == .monster && !unit.isAlive
            let offset=intent?.actor==id ? moving:PartyPoint(0,0)
            let foot=CGPoint(x:f.x+offset.x,y:f.y+offset.y)
            if let actor=actors[id] {
                let pose=PartyVisual.pose(unit:unit,intent:intent,age:age,time:sceneTime,hurtAge:hurt[id].map { sceneTime-$0 },blocked:shownVitals.shield>0 || (hurt[id] != nil && broken[id]==hurt[id]),downAge:fallen[id].map { sceneTime-$0 },victoryAge:victoryAt.map { sceneTime-$0 })
                actor.setWeaponAsset(HeroFrames.weaponVisual(unit.equipment.weapon)?.battleAsset)
                let displayedArmor=unit.appearance != nil ? unit.appearance!.armor(worn:unit.equipment.armor):unit.equipment.armor
                actor.setArmor(displayedArmor)
                let clip=pose.clip,progress=pose.progress
                actor.setPose(clip:clip,progress:CGFloat(progress))
                let s=CGFloat(PartyVisual.heroScale),root=actor.poseRootOffset
                actor.frame=CGRect(x:foot.x-123*s+root.x*s,y:foot.y-214*s+root.y*s,width:256*s,height:256*s)
                actor.layer.zPosition=CGFloat(f.y)
                let key="\(clip)-\(Int((progress*24).rounded()))-\(unit.equipment.weapon ?? "none")-\(displayedArmor ?? "none")"
                if key != poseKeys[id] { shadows[id]?.update(image:actor.poseSilhouette,soleY:actor.poseFootAnchorPx.y,contacts:actor.poseContacts.map { .init(point:$0,radius:12) });poseKeys[id]=key }
                attached[id]?.frame=actor.bounds
                attached[id]?.update(shield:shownVitals.shield,preview:0,time:sceneTime,formation:shownVitals.shield==0 ? formation[id].flatMap { sceneTime-$0<1.0 ? sceneTime-$0:nil }:nil,formationBase:0,birth:birth[id].map { sceneTime-$0 },contact:contact[id].map { sceneTime-$0 },broken:broken[id].map { sceneTime-$0 },recovery:unit.isAlive ? recovery[id].map { sceneTime-$0 }:nil,recoveryTier:recoveryTier[id])
                shadows[id]?.spriteFrame=actor.frame
                labels[id]?.frame=CGRect(x:f.x-88,y:f.y-170,width:176,height:44)
            } else if let view=monsters[id] {
                let species=MonsterVisualSpec.find(unit.templateID)
                let s=CGFloat(species?.scale ?? PartyVisual.enemyScale)
                view.frame=CGRect(x:foot.x-178.5*s,y:foot.y-240*s,width:384*s,height:256*s);view.layer.zPosition=CGFloat(f.y)
                monsterFlash[id]?.alpha=0
                let baseFrame=view.frame
                if let at=deaths[id] {
                    let d=sceneTime-at
                    if let species {
                        view.image=MeadowMonsterFrames.image(species.id,index:MonsterVisualSpec.deathFrame(d),death:true)
                        view.frame=CGRect(x:foot.x-178.5*s,y:foot.y-272*s,width:512*s,height:320*s)
                        view.isHidden=d>=MonsterVisualSpec.deathDuration;winds[id]?.isHidden=true
                    }else{
                        view.isHidden=d>=MeadowBattleVisualMotion.deathDuration;view.image=MeadowBattleVFXAssets.body[MeadowBattleVisualMotion.bodyFrame(d)]
                        winds[id]?.image=MeadowBattleVFXAssets.wind[MeadowBattleVisualMotion.windFrame(d)]
                        winds[id]?.frame=CGRect(x:CGFloat(f.x)-178.5*s,y:CGFloat(f.y)-272*s,width:448*s,height:320*s)
                        winds[id]?.isHidden=d>=MeadowBattleVisualMotion.deathDuration
                    }
                    shadows[id]?.alpha=CGFloat(1-PartyVisual.smooth(d/0.75))
                } else {
                    view.isHidden=false
                    let attacking=intent?.actor==id && intent?.action.isOffensive==true
                    let casting=intent?.actor==id && intent?.action.isOffensive==false
                    let motion=PartyVisual.monster(time:sceneTime+(PartyVisual.slot(id)=="m2" ? 0.7:0),attackAge:attacking ? age:nil,hurtAge:hurt[id].map { sceneTime-$0 },preparing:current==id && intent==nil)
                    let p=motion.progress
                    if let species {
                        let index=species.frame(time:sceneTime+Double(PartyVisual.slot(id)=="m2" ? 1:0),attackAge:attacking ? age:nil,castAge:casting ? age:nil,hurtAge:hurt[id].map{sceneTime-$0},preparing:current==id && intent==nil)
                        let key="species-\(species.id)-\(index)"
                        if poseKeys[id] != key {
                            view.image=MeadowMonsterFrames.image(species.id,index:index)
                            shadows[id]?.update(image:view.image,soleY:240,contacts:MeadowMonsterFrames.feet(species.id).map{.init(point:$0,radius:species.id=="slime" ? 25:12)})
                            monsterFlash[id]?.image=view.image?.withTintColor(.white,renderingMode:.alwaysOriginal);poseKeys[id]=key
                        }
                    }else{
                        view.frame=CGRect(x:foot.x-178.5*s+motion.recoil,y:foot.y-240*s*motion.scaleY,width:384*s,height:256*s*motion.scaleY)
                        view.image=MeadowBattleEnemyFrames.image(progress:CGFloat(p))
                        let key="monster-\(Int(p*8))"
                        if poseKeys[id] != key { shadows[id]?.update(image:view.image,soleY:240,contacts:MeadowBattleEnemyFrames.feet(progress:CGFloat(p)).map { .init(point:$0,radius:15) });poseKeys[id]=key;monsterFlash[id]?.image=view.image?.withTintColor(.white,renderingMode:.alwaysOriginal) }
                    }
                    winds[id]?.isHidden=true;shadows[id]?.alpha=1
                    monsterFlash[id]?.frame=view.frame;monsterFlash[id]?.alpha=motion.flash;monsterFlash[id]?.layer.zPosition=view.layer.zPosition+1
                }
                attached[id]?.frame=CGRect(x:foot.x-192*s,y:foot.y-321*s,width:384*s,height:384*s)
                attached[id]?.layer.zPosition=view.layer.zPosition+2
                attached[id]?.update(shield:unit.isAlive ? shownVitals.shield:0,preview:0,time:sceneTime,formation:shownVitals.shield==0 ? formation[id].flatMap{sceneTime-$0<1.0 ? sceneTime-$0:nil}:nil,formationBase:0,birth:birth[id].map{sceneTime-$0},contact:contact[id].map{sceneTime-$0},broken:broken[id].map{sceneTime-$0},recovery:nil,recoveryTier:nil)
                shadows[id]?.spriteFrame=species == nil ? view.frame:baseFrame
                labels[id]?.frame=CGRect(x:f.x-84,y:f.y-(species == nil ? 256*Double(s)+34:224*Double(s)+46),width:168,height:44)
            }
        }
        if let value=intent {
            let peak=max(BattleDice.darkness(value.action),value.action.isOffensive ? 0.58:0.32)
            let build=castDim+(peak-castDim)*PartyVisual.smooth(age/0.4)
            dim.alpha=CGFloat((value.action.isRune || value.action == .dragonFlame) ? SpellbladeEffects.darkness(value.action,age:age,from:castDim):build*(1-PartyVisual.smooth((age-1.2)/0.6)))
        } else { dim.alpha=CGFloat(previewDarkness()) }
        let anchor=PartyVisual.diceAnchor(actor:diceActor,intent:intent,age:age,shielded:meetsShield,diceCount:diceView.dice.count,monsterTemplateID:state.units[diceActor]?.templateID)
        diceView.frame=CGRect(x:anchor.x-110,y:anchor.y,width:220,height:100)
        diceView.time=sceneTime;diceView.visibleAge=sceneTime-diceVisibleAt
        diceView.confirmationAge=diceConfirmedAt.map { sceneTime-$0 }
        diceView.resolvedAge=diceSettledAt.map { sceneTime-$0 };diceView.exitAge=diceExitAt.map { sceneTime-$0 };diceView.setNeedsDisplay()
        fx.templates=state.units.mapValues(\.templateID);fx.naturalTwenty=naturalTwenty;fx.intent=intent;fx.meetsShield=meetsShield;fx.age=age;fx.time=sceneTime;fx.focus=focus;fx.focusTarget=focusTarget
        fx.messages=messages;fx.skillEffects=skillVFX;fx.particles=emissions.flatMap { e in MeadowBattleLightField.sample(e.kind,age:sceneTime-e.startedAt,originX:e.x,originY:e.y,groundY:e.groundY) }
        fx.recoveryLights=state.units.values.filter{renderIDs.contains($0.id)}.compactMap { unit in
            guard unit.isAlive,let at=recovery[unit.id],let foot=PartyVisual.foot(unit.id) else { return nil }
            let power=recoveryTier[unit.id]?.lightEnvelope(at:sceneTime-at) ?? 0,shift=intent?.actor==unit.id ? moving:PartyPoint(0,0)
            return (PartyPoint(foot.x+shift.x,foot.y+shift.y),power)
        }
        fx.monsterRecoveries=monsterIDs.compactMap {id in
            guard state.units[id]?.isAlive==true,let at=recovery[id],let tier=recoveryTier[id],let foot=PartyVisual.foot(id) else{return nil}
            return (foot,tier,sceneTime-at)
        }
        if let intent,(intent.action.isRune || intent.action == .dragonFlame),let catalog {
            fx.runes=SpellbladeEffects.sample(action:intent.action,age:age,actor:intent.actor,target:intent.target,recipients:SpellbladeEffects.recipients(intent,catalog:catalog),weaponID:intent.weaponID,targets:intent.targets,templates:state.units.mapValues(\.templateID))
        } else { fx.runes=nil }
        fx.setNeedsDisplay()
    }
    override func layoutSubviews() { super.layoutSubviews();let scale=bounds.width/1000;world.center=CGPoint(x:bounds.midX,y:bounds.midY);world.transform=CGAffineTransform(scaleX:scale,y:scale) }
}
struct MeadowPartyMessage { let text:String;let point:CGPoint;let at:Double;let color:UIColor;var atImpact=false;var supportUnit:String?=nil;var supportLine=0 }
struct MeadowPartySkillVFXEvent { let spec:PartySkillVFXSpec;let startedAt:Double;let center:PartyPoint;let groundY:Double }

private final class MeadowPartyEffectsView:UIView {
    var templates:[String:String]=[:]
    private func hitPoint(_ id:String,shielded:Bool=false,weaponID:String?=nil)->PartyPoint {PartyVisual.hitPoint(target:id,shielded:shielded,weaponID:weaponID,templateID:templates[id])}
    var intent:PartyIntent?,focus:PartyAction?
    var friend="p1",foe="m1",focusTarget="p1"
    var meetsShield=false
    var age=0.0,time=0.0
    var messages:[MeadowPartyMessage]=[]
    var naturalTwenty=false
    var runes:RuneEffectSample?
    var particles:[MeadowBattleLightParticle]=[]
    var skillEffects:[MeadowPartySkillVFXEvent]=[]
    var recoveryLights:[(PartyPoint,Double)]=[]
    var monsterRecoveries:[(PartyPoint,HealingEffectTier,Double)]=[]
    override init(frame:CGRect) { super.init(frame:frame);isOpaque=false;isUserInteractionEnabled=false }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect:CGRect) {
        guard let ctx=UIGraphicsGetCurrentContext() else { return }
        func sprite(_ im:UIImage,_ p:PartyPoint,_ w:Double,_ h:Double,_ alpha:Double) { guard alpha>0 else { return };im.draw(in:CGRect(x:p.x-w/2,y:p.y-h/2,width:w,height:h),blendMode:.plusLighter,alpha:CGFloat(alpha)) }
        func glow(_ p:PartyPoint,_ rx:Double,_ ry:Double,_ alpha:Double,_ color:UIColor) { guard alpha>0 else { return };MeadowBattleGlowCache.image(color).draw(in:CGRect(x:p.x-rx,y:p.y-ry,width:rx*2,height:ry*2),blendMode:.plusLighter,alpha:CGFloat(alpha)) }
        for (foot,power) in recoveryLights { glow(foot,105,27,power*0.65,.systemGreen);glow(PartyPoint(foot.x,foot.y-70),42,85,power*0.12,.systemGreen) }
        for (foot,tier,age) in monsterRecoveries {
            guard let blend=tier.frameBlend(at:age) else{continue}
            let frames=MeadowBattleVFXAssets.healingFrames(for:tier),w=320.0,h=tier == .standard ? 267.0:320.0
            let box=CGRect(x:foot.x-w/2,y:foot.y-h*tier.canvasGroundAnchorY,width:w,height:h)
            frames[blend.lower].draw(in:box,blendMode:.plusLighter,alpha:CGFloat(1-blend.upperWeight))
            if blend.upper != blend.lower {frames[blend.upper].draw(in:box,blendMode:.plusLighter,alpha:CGFloat(blend.upperWeight))}
        }
        if intent==nil {
            for (id,color) in [(friend,UIColor.systemGreen),(foe,MeadowPreviewPalette.gold)] {
                if let p=PartyVisual.foot(id) { ctx.setStrokeColor(color.withAlphaComponent(0.65).cgColor);ctx.setLineWidth(2);ctx.strokeEllipse(in:CGRect(x:p.x-36,y:p.y-7,width:72,height:14)) }
            }
        }
        if let intent {
            let visual=intent.action.visual
            if intent.action == .support {
                let from=PartyVisual.chest(intent.actor),to=PartyVisual.chest(intent.target)
                let alpha=PartyVisual.pulse(age,0.05,0.36,1.12)
                let path=UIBezierPath();path.move(to:CGPoint(x:from.x,y:from.y));path.addQuadCurve(to:CGPoint(x:to.x,y:to.y),controlPoint:CGPoint(x:(from.x+to.x)/2,y:min(from.y,to.y)-90))
                ctx.saveGState();ctx.setBlendMode(.plusLighter);ctx.setShadow(offset:.zero,blur:14,color:UIColor.systemGreen.cgColor)
                UIColor.systemGreen.withAlphaComponent(CGFloat(alpha*0.25)).setStroke();path.lineWidth=8;path.stroke();MeadowPreviewPalette.gold.withAlphaComponent(CGFloat(alpha*0.8)).setStroke();path.lineWidth=2;path.stroke();ctx.restoreGState()
                for p in PartyVisual.trail(age:age,from:from,to:to) { sprite(MeadowBattleVFXAssets.healStar,PartyPoint(p.x,p.y),p.size,p.size,p.alpha) }
                let power=PartyVisual.pulse(age,0,0.56,1.5)
                if let foot=PartyVisual.foot(intent.target) { glow(foot,110,26,power*0.5,.systemGreen) }
            }
            if intent.action.isItem,age<intent.action.impact,let foot=PartyVisual.foot(intent.target) {
                let name="MeadowParty"+intent.action.rawValue.prefix(1).uppercased()+intent.action.rawValue.dropFirst()
                if let image=UIImage(named:name) { sprite(image,PartyPoint(foot.x,foot.y-130-age*15),38,38,PartyVisual.pulse(age,0,0.25,0.85)) }
            }
            if intent.ranged,let foot=PartyVisual.foot(intent.actor) {
                let tip=BowRig.releaseArrowTip
                let from=PartyPoint(foot.x+(tip.x-123)*PartyVisual.heroScale,foot.y+(tip.y-214)*PartyVisual.heroScale)
                let to=hitPoint(intent.target,shielded:meetsShield)
                let projectile=intent.enemy ? MonsterVisualSpec.find(intent.monsterTemplateID)?.projectile(age:age,foot:foot,target:to):BowRig.projectile(age:age,from:from,to:to,impact:intent.action.impact,scale:PartyVisual.heroScale)
                if let arrow=projectile {
                    let a=arrow.tail,b=arrow.tip
                    ctx.saveGState();ctx.setLineCap(.round)
                    let missileColor=intent.monsterTemplateID=="ruinDragon" ? UIColor.systemCyan:MeadowPreviewPalette.gold
                    ctx.setShadow(offset:.zero,blur:8,color:missileColor.cgColor)
                    ctx.setStrokeColor(missileColor.withAlphaComponent(0.5).cgColor);ctx.setLineWidth(5)
                    ctx.move(to:CGPoint(x:a.x,y:a.y));ctx.addLine(to:CGPoint(x:b.x,y:b.y));ctx.strokePath()
                    ctx.setStrokeColor(MeadowPreviewPalette.ink.cgColor);ctx.setLineWidth(2)
                    ctx.move(to:CGPoint(x:a.x,y:a.y));ctx.addLine(to:CGPoint(x:b.x,y:b.y));ctx.strokePath();ctx.restoreGState()
                }
            }
            if intent.weaponID=="greatSword",!intent.enemy,visual=="attack",let from=PartyVisual.foot(intent.actor) {
                let points=GreatSwordRig.trail(age:age,from:from,to:hitPoint(intent.target,shielded:meetsShield,weaponID:intent.weaponID),scale:PartyVisual.heroScale)
                if points.count>1 {
                    let power=PartyVisual.pulse(GreatSwordRig.artTime(age:age),0.86,1.0275,1.20)
                    ctx.saveGState();ctx.setBlendMode(.plusLighter);ctx.setLineCap(.round)
                    ctx.setShadow(offset:.zero,blur:7,color:MeadowPreviewPalette.gold.cgColor)
                    for (width,alpha) in [(10.0,0.22),(4.0,0.70),(1.5,0.95)] {
                        ctx.setLineWidth(width);ctx.setStrokeColor(MeadowPreviewPalette.ink.withAlphaComponent(CGFloat(power*alpha)).cgColor)
                        ctx.beginPath();ctx.move(to:CGPoint(x:points[0].x,y:points[0].y));for p in points.dropFirst() { ctx.addLine(to:CGPoint(x:p.x,y:p.y)) };ctx.strokePath()
                    };ctx.restoreGState()
                }
            }
            if intent.magical,let foot=PartyVisual.foot(intent.actor),let targetFoot=PartyVisual.foot(intent.target) {
                let sample=LegendaryStaffRig.effect(age:age,foot:foot,target:hitPoint(intent.target,shielded:meetsShield,weaponID:intent.weaponID),groundY:targetFoot.y,scale:PartyVisual.heroScale,naturalTwenty:naturalTwenty)
                MeadowStaffEffectPainter.draw(sample,in:ctx)
            }
            if visual=="attack",intent.action.skillVFX == nil,!intent.magical,let foot=PartyVisual.foot(intent.target) {
                let a=age-(intent.enemy ? 0.46:1.048),p=hitPoint(intent.target,shielded:meetsShield,weaponID:intent.weaponID)
                let power=PartyVisual.pulse(a,-0.035,0.035,0.52)
                glow(p,140,140,power*0.48,.orange);glow(foot,170,30,power*0.65,.orange)
                if a>=0,a<0.7 {
                    sprite(MeadowBattleVFXAssets.burst,p,150+a*140,150+a*140,power)
                    if !intent.enemy && !intent.ranged { sprite(MeadowBattleVFXAssets.heavyArc,p,210+a*240,210+a*240,power*0.9) }
                }
            }
            if visual=="ambush",let foot=PartyVisual.foot(intent.target) {
                let at=PartyPoint(foot.x-80,foot.y-72),power=PartyVisual.pulse(age,0.72,0.755,1.14)
                glow(at,128,115,power*0.52,.systemYellow);glow(foot,170,27,power*0.70,.systemGreen)
                sprite(MeadowBattleVFXAssets.burst,at,130,130,power*0.72)
                sprite(MeadowBattleVFXAssets.groundSpark,PartyPoint(foot.x-40,foot.y-3),170,22,power*0.70)
                for slash in PartyVisual.ambushSlashes(age:age,at:at) {
                    let path=UIBezierPath();for (j,p) in slash.points.enumerated() { if j==0 { path.move(to:CGPoint(x:p.x,y:p.y)) } else { path.addLine(to:CGPoint(x:p.x,y:p.y)) } }
                    ctx.saveGState();ctx.setBlendMode(.plusLighter);ctx.setLineCap(.round)
                    UIColor.systemGreen.withAlphaComponent(slash.alpha*0.35).setStroke();path.lineWidth=12;path.stroke()
                    MeadowPreviewPalette.ink.withAlphaComponent(slash.alpha).setStroke();path.lineWidth=3;path.stroke();ctx.restoreGState()
                }
            }
        }
        for event in skillEffects {
            let age=time-event.startedAt
            guard age>=0,age<event.spec.duration,let frames=MeadowBattleVFXAssets.skillFrames(for:event.spec.id),frames.count==event.spec.frameCount else { continue }
            let position=age*event.spec.framesPerSecond
            let lower=min(event.spec.frameCount-1,max(0,Int(position)))
            let upper=min(event.spec.frameCount-1,lower+1)
            let mix=PartyVisual.smooth(position-Double(lower))
            let rect=CGRect(x:event.center.x-event.spec.anchorX,y:event.center.y-event.spec.anchorY,width:Double(event.spec.frameWidth),height:Double(event.spec.frameHeight))
            let light=PartyVisual.pulse(age,0,event.spec.peakTime,event.spec.duration)
            let color:UIColor
            switch event.spec.id {
            case "starlightPulse":color=UIColor(red:0.36,green:0.31,blue:1,alpha:1)
            case "rally":color=MeadowPreviewPalette.gold
            case "sweep":color=UIColor(red:0.42,green:0.78,blue:1,alpha:1)
            case "dragonSoulWard":color=UIColor(red:0.29,green:0.67,blue:1,alpha:1)
            default:color=UIColor(red:1,green:0.55,blue:0.18,alpha:1)
            }
            glow(event.center,Double(event.spec.frameWidth)*0.34,Double(event.spec.frameHeight)*0.29,light*0.13,color)
            glow(PartyPoint(event.center.x,event.groundY-5),Double(event.spec.frameWidth)*0.31,15,light*0.24,color)
            frames[lower].draw(in:rect,blendMode:.plusLighter,alpha:CGFloat(1-mix))
            if upper != lower,mix>0 { frames[upper].draw(in:rect,blendMode:.plusLighter,alpha:CGFloat(mix)) }
        }
        if let runes { MeadowRuneEffectPainter.draw(runes,in:ctx) }
        var pools=0
        for p in particles {
            let at=PartyPoint(p.x,p.y)
            if p.id%6==0 { glow(at,22,20,p.alpha*0.2,p.cyan ? .cyan:.orange) }
            if let age=p.groundAge,age<0.24,pools<12 {
                let point=PartyPoint(p.groundX,p.groundY),a=(1-age/0.24)*p.alpha
                glow(point,34,10,a*0.6,p.cyan ? .cyan:.orange);sprite(p.cyan ? MeadowBattleVFXAssets.wardHit:MeadowBattleVFXAssets.groundSpark,point,30,12,a);pools += 1
            }
            ctx.saveGState();ctx.translateBy(x:p.x,y:p.y);ctx.rotate(by:p.angle)
            let image=p.cyan ? MeadowBattleVFXAssets.shard:MeadowBattleVFXAssets.ember
            image.draw(in:CGRect(x:-p.size/2,y:-p.size/3,width:p.size,height:p.size*0.67),blendMode:.plusLighter,alpha:CGFloat(p.alpha));ctx.restoreGState()
        }
        for m in messages {
            let age=time-m.at,alpha=1-PartyVisual.smooth((age-0.65)/0.35)
            let attrs:[NSAttributedString.Key:Any]=[.font:MeadowPreviewPalette.font(24,.heavy),.foregroundColor:m.color.withAlphaComponent(CGFloat(alpha)),.strokeColor:UIColor.black.withAlphaComponent(CGFloat(alpha)),.strokeWidth:-3]
            let label=NSAttributedString(string:m.text,attributes:attrs),size=label.size()
            let p:PartyPoint
            if let id=m.supportUnit,let foot=PartyVisual.foot(id) { p=PartyVisual.supportLabelOrigin(at:foot,width:size.width,line:m.supportLine,age:age) }
            else { p=m.atImpact ? PartyVisual.damageLabelOrigin(at:PartyPoint(m.point.x,m.point.y),width:size.width,height:size.height,age:age):PartyPoint(m.point.x+90,m.point.y-55-age*26) }
            label.draw(at:CGPoint(x:p.x,y:p.y))
        }
    }
}

/// Both battle layouts draw the same continuously sampled staff geometry.
enum MeadowStaffEffectPainter {
    static func draw(_ q:StaffEffectSample,in ctx:CGContext) {
        func glow(_ p:PartyPoint,_ rx:Double,_ ry:Double,_ alpha:Double) {
            guard alpha>0 else { return }
            MeadowBattleGlowCache.image(.systemCyan).draw(in:CGRect(x:p.x-rx,y:p.y-ry,width:rx*2,height:ry*2),blendMode:.plusLighter,alpha:CGFloat(min(1,alpha)))
        }
        let s=q.scale,p=q.impactPower
        ctx.saveGState();ctx.setBlendMode(.plusLighter);ctx.setLineCap(.round)
        glow(q.gem,48*s,40*s,q.charge*0.36)
        if let head=q.head {
            glow(head,40*s,30*s,0.45)
            for (w,a) in [(13.0,0.41),(5.0,0.73),(2.0,0.98)] {
                ctx.setStrokeColor((w==2 ? UIColor.white:UIColor.systemCyan).withAlphaComponent(a).cgColor);ctx.setLineWidth(w*s)
                ctx.beginPath();for (i,p) in q.trail.enumerated() { if i==0 { ctx.move(to:CGPoint(x:p.x,y:p.y)) } else { ctx.addLine(to:CGPoint(x:p.x,y:p.y)) } };ctx.strokePath()
            }
            ctx.setFillColor(UIColor.white.withAlphaComponent(0.94).cgColor);ctx.fillEllipse(in:CGRect(x:head.x-5*s,y:head.y-5*s,width:10*s,height:10*s))
        }
        glow(q.impact,108*s,100*s,p*0.58);glow(q.ground,112*s,22*s,p*0.52)
        if p>0 {
            let r=q.burstRadius,x=q.impact.x,y=q.impact.y
            let path=UIBezierPath();let pts=[CGPoint(x:x,y:y-r*1.4),CGPoint(x:x+r*0.23,y:y-r*0.2),CGPoint(x:x+r,y:y),CGPoint(x:x+r*0.23,y:y+r*0.2),CGPoint(x:x,y:y+r*1.4),CGPoint(x:x-r*0.23,y:y+r*0.2),CGPoint(x:x-r,y:y),CGPoint(x:x-r*0.23,y:y-r*0.2)]
            path.move(to:pts[0]);for v in pts.dropFirst() { path.addLine(to:v) };path.close();UIColor.systemCyan.withAlphaComponent(min(0.8,p*0.78)).setFill();path.fill()
            ctx.setFillColor(UIColor.white.withAlphaComponent(min(1,p)).cgColor);ctx.fillEllipse(in:CGRect(x:x-r*0.18,y:y-r*0.18,width:r*0.36,height:r*0.36))
        }
        for ray in q.rays {
            ctx.setStrokeColor(UIColor.systemCyan.withAlphaComponent(ray.alpha).cgColor);ctx.setLineWidth(2*s);ctx.beginPath()
            for (i,p) in ray.points.enumerated() { if i==0 { ctx.move(to:CGPoint(x:p.x,y:p.y)) } else { ctx.addLine(to:CGPoint(x:p.x,y:p.y)) } };ctx.strokePath()
        }
        for mote in q.motes {
            let p=PartyPoint(mote.x,mote.y)
            if mote.id%6==0 { glow(p,18*s,14*s,mote.alpha*0.2) }
            ctx.setFillColor((mote.id%3==0 ? UIColor.white:UIColor.systemCyan).withAlphaComponent(mote.alpha).cgColor);ctx.fillEllipse(in:CGRect(x:p.x-mote.size/2,y:p.y-mote.size/2,width:mote.size,height:mote.size))
            if abs(p.y-q.ground.y)<5*s { glow(p,24*s,6*s,mote.alpha*0.25) }
        }
        ctx.restoreGState()
    }
}
final class MeadowStaffEffectsView:UIView {
    var sample:StaffEffectSample?
    override init(frame:CGRect) { super.init(frame:frame);isOpaque=false;isUserInteractionEnabled=false }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect:CGRect) { if let q=sample,let ctx=UIGraphicsGetCurrentContext() { MeadowStaffEffectPainter.draw(q,in:ctx) } }
}

/// The offline renderer consumes the exact same points, widths and envelopes.
enum MeadowRuneEffectPainter {
    private static let slashFrames:[UIImage]=((1...8).compactMap { UIImage(named:String(format:"MeadowRuneSlash%02d",$0)) })
    static func color(_ name:String)->UIColor {
        switch name {
        case "violet":return UIColor(red:0.36,green:0.25,blue:1,alpha:1)
        case "cyan":return UIColor(red:0.12,green:0.75,blue:1,alpha:1)
        case "blue":return UIColor(red:0.14,green:0.38,blue:1,alpha:1)
        case "gold":return UIColor(red:0.99,green:0.78,blue:0.27,alpha:1)
        case "fireRed":return UIColor(red:1.00,green:0.18,blue:0.08,alpha:1)
        case "fireOrange":return UIColor(red:1.00,green:0.39,blue:0.10,alpha:1)
        case "fireGold":return UIColor(red:1.00,green:0.73,blue:0.23,alpha:1)
        case "fireWhite":return UIColor(red:1.00,green:0.91,blue:0.61,alpha:1)
        case "green":return UIColor(red:0.16,green:1,blue:0.48,alpha:1)
        default:return UIColor(red:0.96,green:0.98,blue:1,alpha:1)
        }
    }
    static func draw(_ q:RuneEffectSample,in ctx:CGContext) {
        ctx.saveGState();defer { ctx.restoreGState() };ctx.setBlendMode(.plusLighter);ctx.setLineCap(.round);ctx.setLineJoin(.round)
        func glow(_ p:PartyPoint,_ rx:Double,_ ry:Double,_ alpha:Double,_ name:String) {
            guard alpha>0 else{return}
            MeadowBattleGlowCache.image(color(name)).draw(in:CGRect(x:p.x-rx,y:p.y-ry,width:rx*2,height:ry*2),blendMode:.plusLighter,alpha:CGFloat(min(1,alpha)))
        }
        if let index=q.spriteFrame,slashFrames.indices.contains(index),let center=q.spriteCenter {
            let size=q.spriteSize ?? 256,alpha=q.spriteAlpha ?? 1
            for v in q.glows { glow(v.point,v.rx,v.ry,v.alpha,v.color) }
            if alpha>0 {
                ctx.saveGState();ctx.interpolationQuality = .none
                slashFrames[index].draw(in:CGRect(x:center.x-size/2,y:center.y-size/2,width:size,height:size),blendMode:.plusLighter,alpha:CGFloat(alpha))
                ctx.restoreGState()
            }
            return
        }
        for v in q.glows { glow(v.point,v.rx,v.ry,v.alpha,v.color) }
        for layer in q.spriteLayers {
            guard let image=MeadowBattleVFXAssets.effectImage(named:layer.asset),layer.alpha>0 else { continue }
            let size=layer.size,center=layer.center
            ctx.saveGState();ctx.interpolationQuality = .none
            image.draw(in:CGRect(x:center.x-size/2,y:center.y-size/2,width:size,height:size),blendMode:.plusLighter,alpha:CGFloat(layer.alpha*0.92))
            ctx.restoreGState()
        }
        for s in q.strokes where s.points.count>1 {
            ctx.setStrokeColor(color(s.color).withAlphaComponent(CGFloat(s.alpha)).cgColor);ctx.setLineWidth(s.width)
            ctx.beginPath();ctx.move(to:CGPoint(x:s.points[0].x,y:s.points[0].y));for p in s.points.dropFirst() { ctx.addLine(to:CGPoint(x:p.x,y:p.y)) };ctx.strokePath()
        }
        for m in q.motes {
            if m.id%6==0 { glow(m.point,18,14,m.alpha*0.20,m.color) }
            if let age=m.groundAge,age<0.23 {
                let a=m.alpha*(1-age/0.23)
                glow(m.ground,34,9,a*0.72,m.color)
                if m.id%3==0 { MeadowBattleVFXAssets.groundSpark.draw(in:CGRect(x:m.ground.x-23,y:m.ground.y-6,width:46,height:12),blendMode:.plusLighter,alpha:CGFloat(a*0.78)) }
            }
            ctx.saveGState();ctx.translateBy(x:m.point.x,y:m.point.y);ctx.rotate(by:m.angle)
            ctx.setFillColor(color(m.color).withAlphaComponent(CGFloat(m.alpha)).cgColor)
            ctx.move(to:CGPoint(x:0,y:-m.size/2));ctx.addLine(to:CGPoint(x:m.size/3,y:0));ctx.addLine(to:CGPoint(x:0,y:m.size/2));ctx.addLine(to:CGPoint(x:-m.size/3,y:0));ctx.closePath();ctx.fillPath();ctx.restoreGState()
        }
    }
}
