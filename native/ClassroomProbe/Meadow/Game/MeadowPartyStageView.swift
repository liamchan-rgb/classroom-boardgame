import UIKit
import ClassroomGameCore
import MeadowBattleSupport

final class MeadowPartyStageView:UIView {
    var onChoose:((String)->Void)?
    var onPresentationChanged:(()->Void)?
    private let world=UIView(),dim=UIView(),wash=UIView()
    private let clock=MeadowBattleSceneClock()
    private let fx=MeadowPartyEffectsView()
    private var monsterIDs=["m1","m2"],playerIDs=["p1","p2"]
    private var renderIDs:[String] {playerIDs+monsterIDs}
    /// World zoom of the current formation (`MeadowBattleFormation`): the world is 1000Z x 600Z, so a bigger party gets more meadow, not smaller people.
    private(set) var zoom=1.0
    private var worldWidth:Double { 1000*zoom }
    private var worldHeight:Double { 600*zoom }
    private var plates:[UIImageView]=[]
    /// The wide scene (`MeadowCampWide*`, built by scripts/build-wide-battle-scene.py from the camp clearing and the map's scenery props):
    /// twice as wide, with the usual scene untouched in its middle. Loaded the first time the pane is wide (the map drawer closed).
    private var widePlates:[UIImageView]=[]
    private var showsWideScene=false
    private static let wideNames=["MeadowCampWideFarForest","MeadowCampWideGround","MeadowCampWideMidground","MeadowCampWideForeground"]
    /// The pane shows more than the world's width: the wide plates replace the usual ones.
    private func updateWideScene() {
        guard bounds.width>0,bounds.height>0 else { return }
        let wide=bounds.width/baseScale>CGFloat(worldWidth)*1.01
        if wide,widePlates.isEmpty {
            for (i,name) in Self.wideNames.enumerated() {
                let view=UIImageView(image:MeadowBattlePlateProcessor.image(named:name,role:[.farForest,.ground,.midground,.foreground][i]))
                view.layer.zPosition=plates[i].layer.zPosition;view.alpha=0;world.addSubview(view);widePlates.append(view)
            }
        }
        let w=CGFloat(worldWidth),ph=w*1201/1309
        for view in widePlates { view.frame=CGRect(x:-w*654/1309,y:-159*CGFloat(zoom),width:w*2,height:ph) }
        guard wide != showsWideScene else { return }
        showsWideScene=wide
        if wide { widePlates.forEach { $0.alpha=1 } }
        // The usual plates stay under the wide ones (same picture in the middle) until the pane is narrow again.
        UIView.animate(withDuration:0.25) { self.widePlates.forEach { $0.alpha=wide ? 1:0 };self.plates.last?.alpha=wide ? 0:1 }
    }
    /// Ground marks under the picked ally and enemy (below the characters).
    private let friendMarker=MeadowTargetMarkerView(),foeMarker=MeadowTargetMarkerView()
    /// World units per point when the camera is at rest. The world fills the pane's width - unless the pane is wide (the map drawer
    /// closed): then the units keep the size they have beside the map (about 800Z world units of height in view) and the pane shows
    /// more of the meadow to the left and right instead of a closer shot.
    private var baseScale:CGFloat { min(bounds.width/CGFloat(worldWidth),max(bounds.height/CGFloat(800*zoom),bounds.width/CGFloat(worldWidth*2))) }
    /// The world y at the middle of the pane. Normally the world's own middle; on a wide pane (the map drawer closed) less height is in
    /// view, so the view is centred on where the units stand (heads to feet), without leaving the plates.
    private var viewCentreY:Double=300
    private func updateViewCentre() {
        let h=worldHeight
        guard bounds.width>0,bounds.height>0 else { viewCentreY=h/2;return }
        let visible=Double(bounds.height/baseScale)
        let feet=renderIDs.compactMap { id in PartyVisual.foot(id).map { (id,$0.y) } }
        var centre=h/2
        if let top=feet.map({ $0.1-($0.0.hasPrefix("p") ? 215:290) }).min(),let bottom=feet.map({ $0.1+34 }).max(),top<h/2-visible/2 || bottom>h/2+visible/2 {
            let low = -159*zoom+visible/2,high=758*zoom-visible/2
            centre=low<high ? min(high,max(low,(top+bottom)/2)):h/2
        }
        viewCentreY=centre
        let origin=CGFloat(centre-h/2)
        if world.bounds.origin.y != origin { world.bounds.origin.y=origin }
    }
    /// PvP: the hero team on the right (mirrored).
    private var rivalIDs:[String]=[]
    private var actors:[String:MeadowBattleActorView]=[:]
    private let afterimages=(0..<3).map { _ in UIImageView() }
    private var monsters:[String:UIImageView]=[:],winds:[String:UIImageView]=[:]
    private var shadows:[String:MeadowBattleGroundingView]=[:]
    /// The old sprite shield (`MeadowBattleAttachedSkillsView`) is gone from the party stage: shields are procedural shells (`MeadowSkillProcedural.shieldShell`).
    private var attached:[String:MeadowBattleAttachedSkillsView]=[:]
    private var contactAngle:[String:Double]=[:]
    private var labels:[String:MeadowBattleVitalsView]=[:]
    private var monsterFlash:[String:UIImageView]=[:]
    private let diceView=MeadowBattleDiceView(),dicePlate=UIView()
    /// Floating captions for actions ("P1 · 符文斩"): they fade in above the actor, drift up and fade out.
    private var captions:[UIView]=[]
    private var catalog=try? GameCatalog.initial()
    private var current:String?
    /// The targets picked in the battle UI (their health bars stay in full view).
    private var chosenFriend="p1",chosenFoe="m1"
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
    /// Presentation-only hit feel (see MeadowBattleHitFeel): per struck monster, and the latest blow for the camera.
    private var hitFeel:[String:MeadowPartyHitEvent]=[:]
    private var kickFeel:(at:Double,tier:MeadowBattleHitTier,direction:Double)?
    private var emissions:[MeadowBattleLightEmission]=[]
    private var skillVFX:[MeadowPartySkillVFXEvent]=[]
    private var procVFX:[MeadowPartyProcEvent]=[]
    /// Where every unit is drawn right now (after travel and knock-back); effects follow these.
    private var liveFeet:[String:PartyPoint]=[:]
    private var washBase=UIColor.clear
    /// The system's Reduce Motion switch only turns the camera work off when this is asked for (`MeadowCameraRespectsReduceMotion`); by default the camera always works.
    private static var reduceMotion:Bool { UIAccessibility.isReduceMotionEnabled && UserDefaults.standard.bool(forKey:"MeadowCameraRespectsReduceMotion") }
    private let barTop=UIView(),barBottom=UIView()
    private var cameraTransform:CGAffineTransform?,cameraWidth:CGFloat=0
    /// When a fallen hero was brought back (they fade back in as the revive light gathers).
    private var revivedAt:[String:Double]=[:]
    /// When each unit's current damage buff was granted, and buffs the lab shows without the rules (amount).
    private var buffBirth:[String:Double]=[:],labBuff:[String:Int]=[:]
    /// The GPU drawer for procedural skills (nil: Metal unavailable, the effects layer draws them with CoreGraphics).
    private var gpu:MeadowSkillGPUView?
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
            view.layer.zPosition=i==3 ? 900:CGFloat(-100+i);world.addSubview(view);plates.append(view)
        }
        dim.backgroundColor = .black;dim.frame=CGRect(x:0,y:-500,width:1000,height:1600);dim.layer.zPosition=100;dim.isUserInteractionEnabled=false;world.addSubview(dim)
        // Pane-wide colour wash for skill light and screen flashes: same coverage as `dim`, so neither has an edge at the world rectangle.
        wash.backgroundColor = .clear;wash.frame=dim.frame;wash.layer.zPosition=999;wash.isUserInteractionEnabled=false;world.addSubview(wash)
        for marker in [friendMarker,foeMarker] { marker.layer.zPosition=150;world.addSubview(marker) }
        for bar in [barTop,barBottom] { bar.backgroundColor = .black;bar.isUserInteractionEnabled=false;bar.frame = .zero;addSubview(bar) }
        for id in renderIDs { installUnit(id) }
        for ghost in afterimages { ghost.isHidden=true;ghost.isUserInteractionEnabled=false;ghost.layer.magnificationFilter = .nearest;world.addSubview(ghost) }
        fx.frame=fx.worldRect;fx.contentScaleFactor=fx.drawScale;fx.layer.zPosition=1000;world.addSubview(fx)
        if let view=MeadowSkillGPUView(worldRect:fx.worldRect) { view.layer.zPosition=1000;fx.layer.zPosition=1001;world.insertSubview(view,belowSubview:fx);gpu=view;fx.gpuDrawsSkills=true }
        fx.onFlash={ [weak self] flash in guard let self else { return };self.wash.backgroundColor=flash ?? self.washBase }
        // The dice always roll in the same place: the top middle of the pane, on a dark plate, not above whoever acts.
        dicePlate.backgroundColor=UIColor(red:0.04,green:0.07,blue:0.05,alpha:0.78);dicePlate.layer.cornerRadius=16;dicePlate.layer.borderWidth=1.5;dicePlate.layer.borderColor=MeadowPreviewPalette.gold.withAlphaComponent(0.8).cgColor
        dicePlate.isUserInteractionEnabled=false;dicePlate.alpha=0;addSubview(dicePlate);addSubview(diceView)
        clock.onTick={ [weak self] delta in self?.advance(delta) }
        applyFormation(pvp:false)
    }
    private func installUnit(_ id:String) {
        let shadow:MeadowBattleGroundingView
        if id.hasPrefix("p") {
            let actor=MeadowBattleActorView(frame:.zero);actors[id]=actor;world.addSubview(actor)
            shadow=MeadowBattleGroundingView(image:actor.silhouette,soleY:214,contacts:[])
            actor.addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(tapped(_:))));actor.accessibilityIdentifier=id
        } else {
            let image=UIImage(named:"MeadowBattleForestWarden")
            let view=UIImageView(image:image);monsters[id]=view;view.isUserInteractionEnabled=true;view.layer.magnificationFilter = .nearest
            let flash=UIImageView();flash.isUserInteractionEnabled=false;flash.layer.magnificationFilter = .nearest;monsterFlash[id]=flash;world.addSubview(flash)
            world.addSubview(view);view.accessibilityIdentifier=id;view.addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(tapped(_:))))
            let wind=UIImageView();wind.layer.magnificationFilter = .nearest;wind.layer.zPosition=950;winds[id]=wind;world.addSubview(wind)
            shadow=MeadowBattleGroundingView(image:image,soleY:240,contacts:[.init(point:CGPoint(x:84,y:240),radius:15),.init(point:CGPoint(x:172,y:240),radius:15),.init(point:CGPoint(x:230,y:240),radius:15),.init(point:CGPoint(x:314,y:240),radius:15)])
        }
        shadows[id]=shadow;shadow.layer.zPosition=200;shadow.bounds=CGRect(origin:.zero,size:world.bounds.size);shadow.center=CGPoint(x:world.bounds.width/2,y:world.bounds.height/2);world.addSubview(shadow)
        let label=MeadowBattleVitalsView();label.layer.zPosition=1100;labels[id]=label;world.addSubview(label)

    }
    func configureMonsters(_ ids:[String]) { configureUnits(players:playerIDs,foes:ids,pvp:false) }
    /// Who is on the field: up to 7 heroes on the left, and on the right up to 3 monsters - or, in PvP, another hero team drawn mirrored.
    /// Places everyone by `MeadowBattleFormation` and grows the world to fit; units keep their size.
    func configureUnits(players:[String],foes:[String],pvp:Bool) {
        let gone=Set(renderIDs).subtracting(players+foes)
        for id in gone {
            actors.removeValue(forKey:id)?.removeFromSuperview();monsters.removeValue(forKey:id)?.removeFromSuperview();winds.removeValue(forKey:id)?.removeFromSuperview()
            attached.removeValue(forKey:id)?.removeFromSuperview();monsterFlash.removeValue(forKey:id)?.removeFromSuperview();shadows.removeValue(forKey:id)?.removeFromSuperview();labels.removeValue(forKey:id)?.removeFromSuperview()
            poseKeys[id]=nil
        }
        let added=(players+foes).filter { !renderIDs.contains($0) }
        if pvp { playerIDs=players+foes;monsterIDs=[];rivalIDs=foes } else { playerIDs=players;monsterIDs=foes;rivalIDs=[] }
        for id in added { installUnit(id) }
        applyFormation(pvp:pvp)
    }
    /// Sets `PartyVisual.feet` / `mirrored` for the units on the field and sizes the world, plates, overlays and effect layers to the zoom.
    private func applyFormation(pvp:Bool) {
        let left=playerIDs.filter { !rivalIDs.contains($0) },right=pvp ? rivalIDs:monsterIDs
        let layout=MeadowBattleFormation.layout(players:left.map(PartyVisual.slot),foes:right.map(PartyVisual.slot),pvp:pvp)
        var feet=PartyVisual.classicFeet
        for (slot,p) in layout.feet { feet[slot]=PartyPoint(p.x,p.y) }
        PartyVisual.feet=feet;PartyVisual.mirrored=layout.mirrored
        zoom=layout.zoom
        let z=CGFloat(zoom),w=CGFloat(worldWidth),h=CGFloat(worldHeight)
        world.bounds=CGRect(x:0,y:0,width:w,height:h)
        for plate in plates { plate.frame=CGRect(x:0,y:-159*z,width:w,height:w*1201/1309) }
        dim.frame=CGRect(x:-w,y:-500*z,width:w*3,height:1600*z);wash.frame=dim.frame
        for shadow in shadows.values { shadow.transform = .identity;shadow.bounds=CGRect(x:0,y:0,width:w,height:h);shadow.center=CGPoint(x:w/2,y:h/2) }
        // The effect layers reach half a world past each side, so light is not cut at the world's edge on a wide pane.
        let rect=CGRect(x:-w*0.4,y:-200*z,width:w*1.8,height:w)
        fx.worldRect=rect;fx.drawScale=MeadowPartyEffectsView.baseDrawScale/z/1.3;fx.frame=rect;fx.contentScaleFactor=fx.drawScale
        gpu?.setWorldRect(rect)
        updateViewCentre();updateWideScene();cameraTransform=nil;poseKeys=[:];setNeedsLayout()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    /// The name of what is being done floats up from above the actor: fades in, drifts, fades out. Gold for the heroes, red for monsters.
    private func caption(_ value:PartyIntent,before:GameState) {
        guard let foot=PartyVisual.foot(value.actor),let unit=before.units[value.actor] else { return }
        let skill=value.sourceSkillID.flatMap { id in try? catalog?.skill(id).name } ?? value.action.title
        let who=unit.name.components(separatedBy:" · ").first ?? unit.name
        let color:UIColor=unit.kind == .monster ? UIColor(red:1,green:0.55,blue:0.45,alpha:1):UIColor(red:1,green:0.88,blue:0.5,alpha:1)
        // A frosted capsule with clean, unoutlined text: an outline stroke on Chinese glyphs reads as broken black line segments.
        let label=UILabel();label.isUserInteractionEnabled=false;label.textAlignment = .center
        let font=MeadowPreviewPalette.font(34,.semibold)
        let text=NSMutableAttributedString()
        let symbol=unit.kind == .monster ? "flame.fill":"sparkles"
        if let icon=UIImage(systemName:symbol,withConfiguration:UIImage.SymbolConfiguration(pointSize:28,weight:.bold))?.withTintColor(color,renderingMode:.alwaysOriginal) {
            let attachment=NSTextAttachment(image:icon);attachment.bounds=CGRect(x:0,y:-3,width:icon.size.width,height:icon.size.height)
            text.append(NSAttributedString(attachment:attachment));text.append(NSAttributedString(string:"  "))
        }
        text.append(NSAttributedString(string:skill,attributes:[.font:font,.foregroundColor:UIColor.white,.kern:1.5]))
        text.append(NSAttributedString(string:"  "+who,attributes:[.font:MeadowPreviewPalette.font(22,.medium),.foregroundColor:color.withAlphaComponent(0.95)]))
        label.attributedText=text;label.sizeToFit()
        let pill=UIView(frame:CGRect(x:0,y:0,width:label.bounds.width+44,height:label.bounds.height+18));pill.isUserInteractionEnabled=false
        let blur=UIVisualEffectView(effect:UIBlurEffect(style:.systemUltraThinMaterialDark));blur.frame=pill.bounds
        blur.layer.cornerRadius=pill.bounds.height/2;blur.layer.cornerCurve = .continuous;blur.clipsToBounds=true
        pill.backgroundColor=UIColor(red:0.05,green:0.08,blue:0.07,alpha:0.45);pill.layer.cornerRadius=pill.bounds.height/2;pill.layer.cornerCurve = .continuous
        pill.layer.borderWidth=1.2;pill.layer.borderColor=color.withAlphaComponent(0.65).cgColor
        pill.layer.shadowColor=color.cgColor;pill.layer.shadowOpacity=0.35;pill.layer.shadowRadius=14;pill.layer.shadowOffset = .zero
        pill.addSubview(blur);label.center=CGPoint(x:pill.bounds.midX,y:pill.bounds.midY);pill.addSubview(label)
        let top=foot.y-(unit.kind == .monster ? 330:262)
        let x=min(worldWidth-Double(pill.bounds.width)/2-8,max(Double(pill.bounds.width)/2+8,foot.x))
        pill.center=CGPoint(x:x,y:top+18);pill.alpha=0;pill.transform=CGAffineTransform(scaleX:0.8,y:0.8);pill.layer.zPosition=1150
        captions.forEach { $0.removeFromSuperview() };captions=[pill];world.addSubview(pill)
        UIView.animate(withDuration:0.28,delay:0,options:[.curveEaseOut]) { pill.alpha=1;pill.transform = .identity }
        UIView.animate(withDuration:1.9,delay:0,options:[.curveEaseOut]) { pill.center.y=top-26 }
        UIView.animate(withDuration:0.55,delay:1.3,options:[.curveEaseIn],animations:{ pill.alpha=0 }) { [weak self,weak pill] _ in
            pill?.removeFromSuperview();self?.captions.removeAll { $0 === pill }
        }
    }
    /// With many units on the field only the one acting, the picked targets and whoever was just hurt keep the full name-and-numbers header;
    /// everyone else shows a slim bar (the turn-order row above names them). The classic 2-hero battle keeps every header in full.
    private func compactVitals(_ id:String) {
        guard let label=labels[id] else { return }
        let full=zoom<=1.0 || id==current || id==chosenFriend || id==chosenFoe || (hurt[id].map { sceneTime-$0<2.5 } ?? false) || (recovery[id].map { sceneTime-$0<2.0 } ?? false)
        label.compact = !full
        if !full { let f=label.frame;label.frame=CGRect(x:f.midX-36,y:f.maxY-14,width:72,height:12) }
    }
    /// Puts a sprite view at `rect` (world units); with `mirroredAbout` it is flipped left-right about that x (a hero of the PvP right-hand team).
    private func place(_ view:UIView,_ rect:CGRect,mirroredAbout axis:CGFloat?) {
        view.transform=axis == nil ? .identity:CGAffineTransform(scaleX:-1,y:1)
        view.bounds=CGRect(origin:.zero,size:rect.size)
        view.center=CGPoint(x:axis.map { 2*$0-rect.midX } ?? rect.midX,y:rect.midY)
    }
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
    func classroomPause(_ value:Bool){if value{clock.stop()}else{clock.start()}}
    func start() { MeadowBattleVFXAssets.prewarm();victoryAt=nil;sceneTime=0;recovery=[:];recoveryTier=[:];formation=[:];birth=[:];contact=[:];contactAngle=[:];revivedAt=[:];buffBirth=[:];labBuff=[:];broken=[:];deaths=[:];hurt=[:];hitFeel=[:];kickFeel=nil;messages=[];emissions=[];skillVFX=[];procVFX=[];pendingStatusCues=[];statusSnapshots=[:];poseKeys=[:];fallen=[:];diceAction=nil;diceConfirmedAt=nil;diceView.confirmationAge=nil;diceView.dice=[];diceSettledAt=nil;diceExitAt=nil;dimFrom=0;dimTarget=0;clock.start() }
    func stop() { MeadowMonsterFrames.retain([]);clock.stop();intent=nil;impact=nil;completion=nil;focus=nil;skillVFX=[];procVFX=[];pendingStatusCues=[];statusSnapshots=[:] }
    func displayedVitals(for unitID:String,health:Int,shield:Int)->(health:Int,shield:Int) { statusSnapshots[unitID] ?? (health,shield) }
    func show(_ value:GameState,friend:String,foe:String,current:String?,catalog:GameCatalog) {
        // The classroom battle has 1-6 students and the teacher (P7): the field is laid out for whoever plays.
        let ids=value.players.map(\.id)
        if ids != playerIDs { configureUnits(players:ids,foes:monsterIDs,pvp:false) }
        state=value;self.current=current;self.catalog=catalog;fx.friend=friend;fx.foe=foe;fx.current=current;chosenFriend=friend;chosenFoe=foe
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
        if value.action.isOffensive { MeadowBattleHaptics.prepare() }
        caption(value,before:before)
        castDim=previewDarkness();dimFrom=0;dimTarget=0;dimChangedAt=sceneTime
        if let actor=before.units[value.actor],let target=before.units[value.target],let catalog {
            if diceAction != value.action || diceActor != value.actor { diceVisibleAt=sceneTime }
            diceAction=value.action;diceActor=value.actor;diceSettledAt=nil;diceExitAt=nil
            diceView.dice=BattleDice.channels(value.action,actor:actor,target:target,catalog:catalog,receipt:confirmed,sourceSkillID:value.sourceSkillID);diceView.locked=confirmed != nil;diceConfirmedAt=confirmed == nil ? nil:sceneTime
        }
        naturalTwenty=confirmed?.dice.contains { $0.naturalTwenty } ?? false
        intent=value;state=before;startAt=sceneTime;self.impact=onImpact;self.completion=completion;fired=false;focus=nil;meetsShield=(before.units[value.target]?.shield ?? 0)>0
        spawnProjectile(value,before:before)
        if let procName=MeadowSkillProcedural.procID(for:value.action.rawValue),let proc=MeadowSkillProcedural.info[procName] {
            let templates=before.units.mapValues(\.templateID)
            func target(_ id:String)->MeadowSkillProcedural.Target? {
                guard let foot=PartyVisual.foot(id) else { return nil }
                let chest=PartyVisual.skillEffectCenter(targets:[id],actor:value.actor,templates:templates)
                return .init(chest:.init(chest.x,chest.y),foot:.init(foot.x,foot.y))
            }
            if let casterFoot=PartyVisual.foot(value.actor) {
                let casterChest=PartyVisual.skillEffectCenter(targets:[value.actor],actor:value.actor,templates:templates)
                let list=value.targets.compactMap(target)
                if let first=list.first {
                    let geo=MeadowSkillProcedural.Geometry(caster:.init(casterChest.x,casterChest.y),casterFoot:.init(casterFoot.x,casterFoot.y),targets:list,ground:first.foot.y)
                    // The effect starts early enough that its release lands on the rule's impact moment, inside the existing cast motion.
                    let start=sceneTime+max(0,value.impactAge-proc.release)
                    let ids=value.targets.filter { PartyVisual.foot($0) != nil }
                    procVFX.append(MeadowPartyProcEvent(skill:procName,start:start,direction:first.chest.x>=geo.caster.x ? 1:-1,geo:geo,casterID:value.actor,targetIDs:ids))
                }
            }
        } else if let spec=value.action.skillVFX {
            let hitAge=value.impactAge
            let groundYs=value.targets.compactMap { PartyVisual.foot($0)?.y }
            let groundY=groundYs.isEmpty ? (PartyVisual.foot(value.actor)?.y ?? PartyVisual.height):groundYs.reduce(0,+)/Double(groundYs.count)
            let templates=before.units.mapValues(\.templateID)
            var event=MeadowPartySkillVFXEvent(spec:spec,startedAt:spec.startTime(actionStart:sceneTime,impactAge:hitAge),center:PartyVisual.skillEffectCenter(targets:value.targets,actor:value.actor,templates:templates),groundY:groundY)
            event.actionStart=sceneTime;event.impactAt=sceneTime+hitAge
            if let foot=PartyVisual.foot(value.actor) { event.casterFoot=foot;event.casterChest=PartyPoint(foot.x+5*PartyVisual.heroScale*PartyVisual.facing(value.actor),foot.y-70*PartyVisual.heroScale) }
            event.targets=value.targets.compactMap { id in PartyVisual.foot(id).map { MeadowPartySkillTarget(chest:PartyVisual.skillEffectCenter(targets:[id],actor:value.actor,templates:templates),foot:$0) } }
            skillVFX.append(event)
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
        emissions.removeAll { sceneTime-$0.startedAt>3 };messages.removeAll { sceneTime-$0.at>MeadowBattleNumber.life }
        hitFeel=hitFeel.filter { sceneTime-$0.value.at<1.0 }
        if let k=kickFeel,sceneTime-k.at>=1.0 { kickFeel=nil }
        skillVFX.removeAll { sceneTime-$0.startedAt>$0.lifetime }
        procVFX.removeAll { sceneTime-$0.start>($0.info?.duration ?? 0)+0.1 }
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
    /// One blow on a target as a procedural effect: style by weapon / attacker, size by how hard it really was.
    private func spawnBlow(_ intent:PartyIntent,target id:String,hit:PartyPoint,foot:PartyPoint,templates:[String:String],tier:MeadowBattleHitTier,blocked:Bool,delay:Double) {
        let name:String
        if blocked { name="hitWard" }
        else if intent.enemy {
            // Every species hits in its own way (see `MeadowSkillProcedural.hitEffect`).
            switch intent.monsterTemplateID ?? "" { case "slime":name="hitSlime";case "wolf":name="hitWolf";case "goblinArcher":name="hitArrowM";case "stoneGuardian":name="hitStone";case "caveTroll":name="hitTroll";case "ruinDragon":name="hitDragon";default:name="hitClaw" }
        }
        else if intent.action == .ambush { name="hitAmbush" }
        else { switch intent.weaponID ?? "" { case "greatSword":name="hitGreat";case "huntingBow":name="hitBow";case "legendaryStaff":name="hitStaff";default:name="hitBlade" } }
        spawnProc(name,intent,target:id,hit:hit,foot:foot,templates:templates,power:tier.intensity*(intent.action == .heavyStrike ? 1.2:1),delay:delay)
    }
    /// One procedural effect at a target, aimed along the line from the attacker to it (so sparks, plates and dust all fly the way the blow went).
    private func spawnProc(_ name:String,_ intent:PartyIntent,target id:String,hit:PartyPoint,foot:PartyPoint,templates:[String:String],power:Double,delay:Double) {
        let casterChest=PartyVisual.skillEffectCenter(targets:[intent.actor],actor:intent.actor,templates:templates),casterFoot=PartyVisual.foot(intent.actor) ?? hit
        let geo=MeadowSkillProcedural.Geometry(caster:.init(casterChest.x,casterChest.y),casterFoot:.init(casterFoot.x,casterFoot.y),targets:[.init(chest:.init(hit.x,hit.y),foot:.init(foot.x,foot.y))],ground:foot.y)
        var event=MeadowPartyProcEvent(skill:name,start:sceneTime+delay,direction:hit.x>=casterChest.x ? 1:-1,geo:geo,casterID:intent.actor,targetIDs:[id])
        event.power=power
        procVFX.append(event)
    }
    /// Arrows, staff orbs and monster missiles: a procedural flight from the real launch point to the target, timed to the rule's impact.
    private func spawnProjectile(_ value:PartyIntent,before:GameState) {
        guard MeadowSkillProcedural.procID(for:value.action.rawValue) == nil,let foot=PartyVisual.foot(value.actor) else { return }
        let templates=before.units.mapValues(\.templateID)
        let to=PartyVisual.hitPoint(target:value.target,weaponID:value.weaponID,templateID:templates[value.target]),targetFoot=PartyVisual.foot(value.target) ?? to
        let name:String,from:PartyPoint,launch:Double,charge:Double
        if value.enemy {
            guard value.enemyRanged,let spec=MonsterVisualSpec.find(value.monsterTemplateID) else { return }
            name=spec.id == "ruinDragon" ? "projDragon":"projArcher";launch=0.24;charge=0
            from=PartyPoint(foot.x+(spec.id == "goblinArcher" ? -82:-143)*spec.scale,foot.y-(spec.id == "goblinArcher" ? 144:149)*spec.scale)
        } else if value.ranged {
            let tip=BowRig.releaseArrowTip
            name="projBow";launch=BowRig.releaseAge;charge=0
            from=PartyPoint(foot.x+(tip.x-123)*PartyVisual.heroScale*PartyVisual.facing(value.actor),foot.y+(tip.y-214)*PartyVisual.heroScale)
        } else if value.magical {
            let g=LegendaryStaffRig.gem(progress:LegendaryStaffRig.progress(age:LegendaryStaffRig.releaseAge))
            name="projStaff";launch=LegendaryStaffRig.releaseAge;charge=0.49
            from=PartyPoint(foot.x+(g.x-123)*PartyVisual.heroScale*PartyVisual.facing(value.actor),foot.y+(g.y-214)*PartyVisual.heroScale)
        } else { return }
        let casterChest=PartyVisual.skillEffectCenter(targets:[value.actor],actor:value.actor,templates:templates)
        let geo=MeadowSkillProcedural.Geometry(caster:.init(from.x,from.y),casterFoot:.init(foot.x,foot.y),targets:[.init(chest:.init(to.x,to.y),foot:.init(targetFoot.x,targetFoot.y))],ground:targetFoot.y)
        procVFX.append(MeadowPartyProcEvent(skill:name,start:sceneTime+launch-charge,direction:to.x>=casterChest.x ? 1:-1,geo:geo,casterID:value.actor,targetIDs:[value.target]))
    }
    /// The roll that ends the fight: a long, loud effect on the target, a hard push-in, and a run of heavy haptics.
    private func spawnNaturalTwenty(_ intent:PartyIntent,receipt:OperationReceipt) {
        spawnNaturalTwenty(actor:intent.actor,target:intent.target,weaponID:intent.weaponID,templates:receipt.before.units.mapValues(\.templateID))
    }
    func spawnNaturalTwenty(actor:String,target:String,weaponID:String?,templates:[String:String],delay:Double=0) {
        guard let foot=PartyVisual.foot(target) else { return }
        let chest=PartyVisual.hitPoint(target:target,weaponID:weaponID,templateID:templates[target]),casterChest=PartyVisual.skillEffectCenter(targets:[actor],actor:actor,templates:templates),casterFoot=PartyVisual.foot(actor) ?? foot
        let geo=MeadowSkillProcedural.Geometry(caster:.init(casterChest.x,casterChest.y),casterFoot:.init(casterFoot.x,casterFoot.y),targets:[.init(chest:.init(chest.x,chest.y),foot:.init(foot.x,foot.y))],ground:foot.y)
        procVFX.append(MeadowPartyProcEvent(skill:"natural20",start:sceneTime+delay,direction:chest.x>=casterChest.x ? 1:-1,geo:geo,casterID:actor,targetIDs:[target]))
        MeadowBattleHaptics.naturalTwenty()
    }
    private func apply(_ receipt:OperationReceipt,intent:PartyIntent) {
        state=receipt.after
        if receipt.dice.contains(where: { $0.naturalTwenty }) { let p=PartyVisual.hitPoint(target:intent.target,weaponID:intent.weaponID,templateID:receipt.before.units[intent.target]?.templateID);messages.append(.init(text:"20!",point:CGPoint(x:p.x,y:p.y-55),at:sceneTime,color:MeadowPreviewPalette.gold,atImpact:true,kind:.crit,rank:2,follow:intent.target)) }
        if let actor=receipt.before.units[intent.actor],let target=receipt.before.units[intent.target],let catalog {
            diceView.dice=BattleDice.channels(intent.action,actor:actor,target:target,catalog:catalog,receipt:receipt,sourceSkillID:intent.sourceSkillID);diceSettledAt=sceneTime
        }
        let rolledTwenty=receipt.dice.contains { $0.naturalTwenty }
        if rolledTwenty { spawnNaturalTwenty(intent,receipt:receipt) }
        let plainAttack = !intent.enemy && intent.action.visual == "attack" && intent.action.skillVFX == nil
        var strongestHit=0,killedAny=false,blockedAny=false,numberOrder=0
        for id in renderIDs {
            guard let before=receipt.before.units[id],let after=receipt.after.units[id],let foot=PartyVisual.foot(id) else { continue }
            let heal=max(0,after.health-before.health),damage=max(0,before.health-after.health),gain=max(0,after.shield-before.shield),absorbed=max(0,before.shield-after.shield)
            let shieldHit=absorbed>0 && id.hasPrefix("p")
            let statusAt=startAt+(intent.action.statusVFXCueAge ?? intent.action.impact)
            let delayStatus=after.isAlive && (heal>0 || gain>0) && statusAt>sceneTime+0.0001
            let showsBesideOwner=intent.action.isRune || intent.action == .dragonFlame || intent.action == .starlightPulse || intent.action.isNodeSupport
            let registered=PartyVisual.hitPoint(target:id,shielded:shieldHit,weaponID:intent.weaponID,templateID:before.templateID)
            let point=["greatSword","legendaryStaff"].contains(intent.weaponID ?? "") && id.hasPrefix("m") ? CGPoint(x:registered.x,y:registered.y):CGPoint(x:foot.x+(shieldHit ? (5+240*0.41)*PartyVisual.heroScale*PartyVisual.facing(id):(id.hasPrefix("m") ? -80:0)),y:foot.y-(id.hasPrefix("p") ? 65:72))
            if delayStatus {
                statusSnapshots[id]=(before.health,before.shield)
                pendingStatusCues.append(.init(unitID:id,heal:heal,shieldGain:gain,at:statusAt,point:point,supportUnit:showsBesideOwner))
            }
            if heal>0 && !delayStatus {
                let shift=intent.actor==id ? PartyVisual.travel(intent,age:sceneTime-startAt):PartyPoint(0,0)
                recovery[id]=sceneTime
                recoveryTier[id]=HealingEffectTier.classify(actualHPGained:heal)
                messages.append(.init(text:"+\(heal)",point:CGPoint(x:point.x+shift.x,y:point.y+shift.y),at:sceneTime,color:.systemGreen,supportUnit:showsBesideOwner ? id:nil,kind:.heal))
            }
            if gain>0 && !delayStatus { birth[id]=sceneTime;messages.append(.init(text:"+\(gain)",point:CGPoint(x:point.x,y:point.y+(intent.action.isRune || intent.action == .dragonFlame || intent.action.isNodeSupport ? 36:24)),at:sceneTime,color:.systemCyan,supportUnit:showsBesideOwner ? id:nil,supportLine:1,kind:.shield)) }
            if after.damageBuff != before.damageBuff,after.damageBuff != nil { buffBirth[id]=sceneTime }
            if after.damageBuff != before.damageBuff,let b=after.damageBuff { messages.append(.init(text:"↑\(b.amount)",point:CGPoint(x:point.x,y:point.y-(intent.action.isRune || intent.action == .dragonFlame || intent.action.isNodeSupport ? 36:0)),at:sceneTime,color:MeadowPreviewPalette.gold,supportUnit:showsBesideOwner ? id:nil,supportLine:(heal>0 || gain>0) ? 2:0,kind:.buff)) }
            if damage>0 || absorbed>0 {
                hurt[id]=sceneTime
                let hit=PartyVisual.hitPoint(target:id,shielded:absorbed>0,weaponID:intent.weaponID,templateID:before.templateID)
                let killedHere=before.isAlive && !after.isAlive
                let hitTier=MeadowBattleHitTier.classify(damage:damage,killed:killedHere)
                if damage>0 { strongestHit=max(strongestHit,damage);if killedHere { killedAny=true } } else { blockedAny=true }
                let popsHere=plainAttack && damage>0 && id.hasPrefix("m")
                if popsHere { hitFeel[id]=MeadowPartyHitEvent(at:sceneTime,tier:hitTier,direction:1,point:CGPoint(x:hit.x,y:hit.y),footX:CGFloat(foot.x),floorY:CGFloat(foot.y)) }
                // Several targets: their numbers follow one another by a beat instead of all appearing on the same frame.
                messages.append(.init(text:damage>0 ? "−\(damage)":"BLOCK",point:CGPoint(x:hit.x,y:hit.y),at:sceneTime+0.07*Double(numberOrder),color:damage>0 ? .white:.systemCyan,atImpact:true,hitTier:popsHere ? hitTier:nil,kind:damage>0 ? .damage:.block,rank:hitTier.rawValue,follow:id));numberOrder += 1
                if !rolledTwenty && MeadowSkillProcedural.procID(for:intent.action.rawValue) == nil { spawnBlow(intent,target:id,hit:hit,foot:foot,templates:receipt.before.units.mapValues(\.templateID),tier:hitTier,blocked:damage == 0 && absorbed>0,delay:0.07*Double(max(0,numberOrder-1))) }
            }
            if absorbed>0 {
                contact[id]=sceneTime
                do { let templates=receipt.before.units.mapValues(\.templateID),from=PartyVisual.skillEffectCenter(targets:[intent.actor],actor:intent.actor,templates:templates),at=PartyVisual.skillEffectCenter(targets:[id],actor:intent.actor,templates:templates);contactAngle[id]=atan2(from.y-at.y,from.x-at.x) }
                if after.shield==0 {
                    broken[id]=sceneTime
                    spawnProc("shieldBreak",intent,target:id,hit:registered,foot:foot,templates:receipt.before.units.mapValues(\.templateID),power:1.0+Double(min(absorbed,12))/12.0*0.5,delay:0)
                    if MeadowSkillProcedural.procID(for:intent.action.rawValue) == nil { kickFeel=(sceneTime,.medium,intent.enemy ? -1:1) }
                }
            }
            if before.isAlive && !after.isAlive && after.kind == .monster {
                deaths[id]=sceneTime
                let deathName:String
                switch before.templateID { case "slime":deathName="deathSlime";case "wolf":deathName="deathWolf";case "goblinArcher":deathName="deathGoblin";case "stoneGuardian":deathName="deathStone";case "caveTroll":deathName="deathTroll";case "ruinDragon":deathName="deathDragon";default:deathName="deathBurst" }
                spawnProc(deathName,intent,target:id,hit:registered,foot:foot,templates:receipt.before.units.mapValues(\.templateID),power:1.0,delay:0)
            }
            if !before.isAlive && after.isAlive && after.kind == .player {
                fallen[id]=nil;revivedAt[id]=sceneTime
                spawnProc("revive",intent,target:id,hit:PartyPoint(foot.x,foot.y-60),foot:foot,templates:receipt.before.units.mapValues(\.templateID),power:1.0,delay:0)
            }
            if before.isAlive && !after.isAlive && after.kind == .player {
                recovery[id]=nil;recoveryTier[id]=nil;fallen[id]=sceneTime;revivedAt[id]=nil
                spawnProc("playerDown",intent,target:id,hit:PartyPoint(foot.x,foot.y-40),foot:foot,templates:receipt.before.units.mapValues(\.templateID),power:1.0,delay:0)
            }
        }
        if strongestHit>0 {
            let tier=MeadowBattleHitTier.classify(damage:strongestHit,killed:killedAny)
            MeadowBattleHaptics.hit(tier,killed:killedAny)
            if let procName=MeadowSkillProcedural.procID(for:intent.action.rawValue) {
                // A procedural skill has its own lens work; the real damage decides how hard it shakes after the release.
                for i in procVFX.indices where procVFX[i].casterID == intent.actor && procVFX[i].skill == procName { procVFX[i].power=tier.intensity*(killedAny ? 1.12:1) }
            } else { kickFeel=(sceneTime,tier,intent.enemy ? -1:1) }
        } else if blockedAny { MeadowBattleHaptics.blocked() }
        onPresentationChanged?()
    }
    private func revealStatusCue(_ cue:PendingStatusCue) {
        statusSnapshots.removeValue(forKey:cue.unitID)
        if cue.heal>0 {
            recovery[cue.unitID]=cue.at
            recoveryTier[cue.unitID]=HealingEffectTier.classify(actualHPGained:cue.heal)
            let shift=intent?.actor==cue.unitID ? PartyVisual.travel(intent,age:sceneTime-startAt):PartyPoint(0,0)
            messages.append(.init(text:"+\(cue.heal)",point:CGPoint(x:cue.point.x+shift.x,y:cue.point.y+shift.y),at:cue.at,color:.systemGreen,supportUnit:cue.supportUnit ? cue.unitID:nil,kind:.heal))
        }
        if cue.shieldGain>0 {
            birth[cue.unitID]=cue.at
            messages.append(.init(text:"+\(cue.shieldGain)",point:CGPoint(x:cue.point.x,y:cue.point.y+36),at:cue.at,color:.systemCyan,supportUnit:cue.supportUnit ? cue.unitID:nil,supportLine:1,kind:.shield))
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
            let r=CGRect(x:foot.x+trail.offset.x+(Double(pose.rootOffset.x)-123)*s,y:foot.y+trail.offset.y+(Double(pose.rootOffset.y)-214)*s,width:256*s,height:256*s)
            place(ghost,r,mirroredAbout:PartyVisual.facing(intent.actor)<0 ? CGFloat(foot.x+trail.offset.x):nil)
        }
        for id in renderIDs {
            guard let unit=state.units[id],let f=PartyVisual.foot(id) else { continue }
            let shownVitals=displayedVitals(for:id,health:unit.health,shield:unit.shield)
            labels[id]?.isHidden=unit.kind == .monster && !unit.isAlive
            let offset=intent?.actor==id ? moving:PartyPoint(0,0)
            let foot=CGPoint(x:f.x+offset.x,y:f.y+offset.y)
            liveFeet[id]=PartyPoint(Double(foot.x),Double(foot.y))
            if let actor=actors[id] {
                let pose=PartyVisual.pose(unit:unit,intent:intent,age:age,time:sceneTime,hurtAge:hurt[id].map { sceneTime-$0 },blocked:shownVitals.shield>0 || (hurt[id] != nil && broken[id]==hurt[id]),downAge:fallen[id].map { sceneTime-$0 },victoryAge:victoryAt.map { sceneTime-$0 })
                actor.setWeaponAsset(HeroFrames.weaponVisual(unit.equipment.weapon)?.battleAsset)
                let displayedArmor=unit.appearance != nil ? unit.appearance!.armor(worn:unit.equipment.armor):unit.equipment.armor
                actor.setArmor(displayedArmor)
                actor.setHead(hair:unit.appearance.map{$0.hair ?? ($0.body=="wayfarer" ? "hair-silver":"hair-chestnut")},face:unit.appearance.map{$0.face ?? ($0.body=="wayfarer" ? "face-amber":"face-blue")})
                let clip=pose.clip,progress=pose.progress
                actor.setPose(clip:clip,progress:CGFloat(progress))
                let s=CGFloat(PartyVisual.heroScale),root=actor.poseRootOffset
                let mirrored=PartyVisual.facing(id)<0,spriteRect=CGRect(x:foot.x-123*s+root.x*s,y:foot.y-214*s+root.y*s,width:256*s,height:256*s)
                place(actor,spriteRect,mirroredAbout:mirrored ? foot.x:nil)
                // The shadow is drawn from the unmirrored sprite and the whole shadow layer is flipped about the same foot.
                shadows[id]?.transform=mirrored ? CGAffineTransform(translationX:2*(foot.x-CGFloat(worldWidth)/2),y:0).scaledBy(x:-1,y:1):.identity
                actor.layer.zPosition=CGFloat(f.y)
                // A fallen hero is taken off the field (a soul crystal marks the spot, see downAura) and fades back in when revived.
                let shown:CGFloat=unit.isAlive ? CGFloat(revivedAt[id].map { MeadowSkillProcedural.smooth((sceneTime-$0-0.35)/0.5) } ?? 1):CGFloat(1-MeadowSkillProcedural.smooth(((fallen[id].map { sceneTime-$0 } ?? 10)-0.45)/0.4))
                actor.alpha=shown;shadows[id]?.alpha=shown
                let key="\(clip)-\(Int((progress*24).rounded()))-\(unit.equipment.weapon ?? "none")-\(displayedArmor ?? "none")-\(unit.appearance?.visualKey ?? "original")"
                if key != poseKeys[id] { shadows[id]?.update(image:actor.poseSilhouette,soleY:actor.poseFootAnchorPx.y,contacts:actor.poseContacts.map { .init(point:$0,radius:12) });poseKeys[id]=key }
                attached[id]?.update(shield:shownVitals.shield,preview:0,time:sceneTime,formation:shownVitals.shield==0 ? formation[id].flatMap { sceneTime-$0<1.0 ? sceneTime-$0:nil }:nil,formationBase:0,birth:birth[id].map { sceneTime-$0 },contact:contact[id].map { sceneTime-$0 },broken:broken[id].map { sceneTime-$0 },recovery:unit.isAlive ? recovery[id].map { sceneTime-$0 }:nil,recoveryTier:recoveryTier[id])
                shadows[id]?.spriteFrame=spriteRect
                labels[id]?.frame=CGRect(x:f.x-100,y:f.y-170,width:200,height:44);compactVitals(id)
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
                    let feelActive=hitFeel[id].map { sceneTime-$0.at<0.9 } ?? false
                    let motion=PartyVisual.monster(time:sceneTime+(PartyVisual.slot(id)=="m2" ? 0.7:0),attackAge:attacking ? age:nil,hurtAge:feelActive ? nil:hurt[id].map { sceneTime-$0 },preparing:current==id && intent==nil)
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
                var shadowShift:CGFloat=0
                if deaths[id]==nil,let h=hitFeel[id],sceneTime-h.at<0.9 {
                    let a=sceneTime-h.at,sq=MeadowBattleHitFeel.squash(age:a,tier:h.tier)
                    shadowShift=CGFloat(MeadowBattleHitFeel.knockback(age:a,tier:h.tier,canvasWidth:PartyVisual.width))
                    let f=view.frame,footX=f.minX+f.width*178.5/384,footY=f.minY+f.height*240/256
                    let w=f.width*CGFloat(sq.x),hgt=f.height*CGFloat(sq.y)
                    view.frame=CGRect(x:footX-w*178.5/384+shadowShift,y:footY-hgt*240/256,width:w,height:hgt)
                    monsterFlash[id]?.frame=view.frame;monsterFlash[id]?.alpha=CGFloat(0.45*MeadowBattleHitFeel.flash(age:a))
                }
                liveFeet[id]=PartyPoint(Double(foot.x+shadowShift),Double(foot.y))
                attached[id]?.frame=CGRect(x:foot.x-192*s,y:foot.y-321*s,width:384*s,height:384*s)
                attached[id]?.layer.zPosition=view.layer.zPosition+2
                attached[id]?.update(shield:unit.isAlive ? shownVitals.shield:0,preview:0,time:sceneTime,formation:shownVitals.shield==0 ? formation[id].flatMap{sceneTime-$0<1.0 ? sceneTime-$0:nil}:nil,formationBase:0,birth:birth[id].map{sceneTime-$0},contact:contact[id].map{sceneTime-$0},broken:broken[id].map{sceneTime-$0},recovery:nil,recoveryTier:nil)
                shadows[id]?.spriteFrame=species == nil ? view.frame:baseFrame.offsetBy(dx:shadowShift,dy:0)
                labels[id]?.frame=CGRect(x:f.x-96,y:f.y-(species == nil ? 256*Double(s)+34:224*Double(s)+46),width:192,height:44);compactVitals(id)
            }
        }
        // Ground marks under the picked targets (hidden while an action plays).
        for (marker,id,color) in [(friendMarker,chosenFriend,UIColor(red:0.30,green:0.95,blue:0.62,alpha:1)),(foeMarker,chosenFoe,UIColor(red:1.0,green:0.36,blue:0.26,alpha:1))] {
            guard intent==nil,victoryAt==nil,let unit=state.units[id],renderIDs.contains(id),let foot=liveFeet[id],unit.isAlive || unit.kind == .player else { marker.hide();continue }
            let r:CGFloat=unit.kind == .monster ? 132*CGFloat(MonsterVisualSpec.find(unit.templateID)?.scale ?? PartyVisual.enemyScale):58
            let cx=unit.kind == .monster ? foot.x+14:foot.x
            marker.show(at:CGPoint(x:cx,y:foot.y-2),radius:r,color:color)
        }
        if let value=intent {
            let peak=max(BattleDice.darkness(value.action),value.action.isOffensive ? 0.58:0.32)
            let build=castDim+(peak-castDim)*PartyVisual.smooth(age/0.4)
            dim.alpha=CGFloat((value.action.isRune || value.action == .dragonFlame) ? SpellbladeEffects.darkness(value.action,age:age,from:castDim):build*(1-PartyVisual.smooth((age-1.2)/0.6)))
        } else { dim.alpha=CGFloat(previewDarkness()) }
        // One pane-wide grade for every skill: a dark tint (the dim view) and a faint colour wash. Both overlays cover the whole
        // pane, so the brightness is the same everywhere; nothing is filled only inside the world rectangle any more.
        var grade=0.0,gradeTint=UIColor.black,washColor=UIColor.clear
        for e in procVFX {
            guard let info=e.info else { continue }
            let lit=MeadowSkillProcedural.light(skill:e.skill,t:sceneTime-e.start),a=lit*info.dim*0.55
            if a>grade { grade=a;gradeTint=UIColor(red:CGFloat(info.dimTint.r*0.1),green:CGFloat(info.dimTint.g*0.1),blue:CGFloat(info.dimTint.b*0.12),alpha:1) }
            if lit>0.01 && info.dim>0 { let tone=MeadowSkillProcedural.tone(e.skill);washColor=UIColor(red:CGFloat(tone.r/255),green:CGFloat(tone.g/255),blue:CGFloat(tone.b/255),alpha:CGFloat(lit*0.035)) }
        }
        for e in skillVFX {
            let age=sceneTime-e.startedAt
            guard age>=0,age<e.spec.duration else { continue }
            let a=MeadowSkillAmbientLight.level(age:age,peak:e.spec.peakTime,duration:e.spec.duration)*0.26
            if a>grade { grade=a;gradeTint=UIColor(red:0.06,green:0.05,blue:0.10,alpha:1) }
        }
        dim.backgroundColor=grade>0.004 ? gradeTint:.black
        dim.alpha=max(dim.alpha,CGFloat(grade))
        washBase=washColor;wash.backgroundColor=washColor
        let diceScale=max(0.9,min(1.7,bounds.width/620)),diceCount=max(1,diceView.dice.count)
        diceView.transform = .identity;diceView.bounds=CGRect(x:0,y:0,width:220,height:100)
        diceView.center=CGPoint(x:bounds.midX,y:14+50*diceScale);diceView.transform=CGAffineTransform(scaleX:diceScale,y:diceScale)
        let diceShown = !diceView.dice.isEmpty && (diceExitAt.map { sceneTime-$0<0.3 } ?? true) && (intent != nil || focus != nil)
        let plateWidth=min(bounds.width-24,(CGFloat(diceCount)*70+50)*diceScale)
        dicePlate.frame=CGRect(x:bounds.midX-plateWidth/2,y:8,width:plateWidth,height:100*diceScale+8)
        dicePlate.alpha += ((diceShown ? 1:0)-dicePlate.alpha)*0.25
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
        let healTemplates=state.units.mapValues(\.templateID)
        fx.monsterRecoveries=monsterIDs.compactMap {id in
            guard state.units[id]?.isAlive==true,let at=recovery[id],let tier=recoveryTier[id],let foot=liveFeet[id] ?? PartyVisual.foot(id) else{return nil}
            let baseFoot=PartyVisual.foot(id) ?? foot,baseChest=PartyVisual.skillEffectCenter(targets:[id],actor:id,templates:healTemplates)
            return (foot:foot,chest:PartyPoint(foot.x+(baseChest.x-baseFoot.x),foot.y+(baseChest.y-baseFoot.y)),tier:tier,age:sceneTime-at)
        }
        fx.allyRecoveries=state.units.values.filter{renderIDs.contains($0.id) && $0.kind != .monster}.compactMap { unit in
            guard unit.isAlive,let at=recovery[unit.id],let tier=recoveryTier[unit.id],let foot=PartyVisual.foot(unit.id) else { return nil }
            let base=liveFeet[unit.id] ?? foot
            return (foot:base,chest:PartyPoint(base.x+5*PartyVisual.heroScale*PartyVisual.facing(unit.id),base.y-70*PartyVisual.heroScale),tier:tier,age:sceneTime-at)
        }
        fx.procEffects=procVFX;fx.liveFeet=liveFeet
        fx.buffs=state.units.values.filter { renderIDs.contains($0.id) && $0.isAlive }.compactMap { unit in
            guard let amount=unit.damageBuff?.amount ?? labBuff[unit.id],amount>0,let baseFoot=PartyVisual.foot(unit.id) else { return nil }
            let foot=liveFeet[unit.id] ?? baseFoot,baseChest=PartyVisual.skillEffectCenter(targets:[unit.id],actor:unit.id,templates:healTemplates)
            return (foot:foot,chest:PartyPoint(foot.x+(baseChest.x-baseFoot.x),foot.y+(baseChest.y-baseFoot.y)),level:Double(amount)/3.0,age:buffBirth[unit.id].map { sceneTime-$0 } ?? 10)
        }
        fx.downed=state.units.values.filter { renderIDs.contains($0.id) && $0.kind == .player && !$0.isAlive }.compactMap { unit in
            guard let foot=liveFeet[unit.id] ?? PartyVisual.foot(unit.id) else { return nil }
            return (foot:foot,age:fallen[unit.id].map { sceneTime-$0 } ?? 10)
        }
        fx.shields=state.units.values.filter { renderIDs.contains($0.id) && $0.isAlive }.compactMap { unit in
            let shield=displayedVitals(for:unit.id,health:unit.health,shield:unit.shield).shield
            guard shield>0,let baseFoot=PartyVisual.foot(unit.id) else { return nil }
            let foot=liveFeet[unit.id] ?? baseFoot,baseChest=PartyVisual.skillEffectCenter(targets:[unit.id],actor:unit.id,templates:healTemplates)
            let monster=unit.kind == .monster,defaultAngle=monster ? Double.pi:0.0
            return (foot:foot,chest:PartyPoint(foot.x+(baseChest.x-baseFoot.x),foot.y+(baseChest.y-baseFoot.y)),level:min(1.5,max(0.25,Double(shield)/8.0)),age:birth[unit.id].map { sceneTime-$0 } ?? 10,hitAge:contact[unit.id].map { sceneTime-$0 } ?? -1,hitAngle:contactAngle[unit.id] ?? defaultAngle,wide:monster ? 1.35:1.0)
        }
        if let gpu {
            // Skills are drawn on the GPU; a full-screen flash goes to the pane-wide wash.
            if let flash=gpu.draw(fx.skillPrimitives()) { wash.backgroundColor=UIColor(red:CGFloat(flash.color.r/255),green:CGFloat(flash.color.g/255),blue:CGFloat(flash.color.b/255),alpha:CGFloat(min(1,flash.alpha*0.85))) }
        }
        if let intent,(intent.action.isRune || intent.action == .dragonFlame),let catalog,MeadowSkillProcedural.procID(for:intent.action.rawValue) == nil {
            fx.runes=SpellbladeEffects.sample(action:intent.action,age:age,actor:intent.actor,target:intent.target,recipients:SpellbladeEffects.recipients(intent,catalog:catalog),weaponID:intent.weaponID,targets:intent.targets,templates:state.units.mapValues(\.templateID))
        } else { fx.runes=nil }
        fx.hits=Array(hitFeel.values)
        var kick=MeadowBattleHitFeel.Camera.zero
        let still=Self.reduceMotion
        if let k=kickFeel,sceneTime-k.at<0.9,!still { kick=MeadowBattleHitFeel.camera(age:sceneTime-k.at,tier:k.tier,direction:k.direction) }
        var trauma=0.0
        if !still {
            for e in procVFX {
                let t=sceneTime-e.start
                let c=MeadowSkillProcedural.scaled(MeadowSkillProcedural.camera(skill:e.skill,t:t,direction:e.direction),skill:e.skill,t:t,power:e.power)
                kick.dx+=c.dx;kick.dy+=c.dy;kick.zoom+=c.zoom;kick.rotation+=c.rotation
                trauma+=MeadowSkillProcedural.trauma(skill:e.skill,t:t,power:e.power)
            }
            // A plain blow (or a broken shield) shakes by its hit tier.
            if let k=kickFeel { let a=sceneTime-k.at;if a>=0 { trauma+=[0.45,0.7,1.0][min(2,max(0,k.tier.rawValue))]*exp(-a*4.0) } }
        }
        // The shake itself: a continuous multi-axis rattle driven by the summed trauma (see MeadowSkillProcedural.shake).
        let rattle=MeadowSkillProcedural.shake(trauma:min(1,trauma),time:sceneTime)
        // Director shot: close-up on whoever casts, a swing to the targets on release, a slow pull back.
        var shot=MeadowSkillProcedural.Shot.idle
        if !still {
            for e in procVFX {
                let s=MeadowSkillProcedural.shot(skill:e.skill,t:sceneTime-e.start,geo:e.geometry(live:liveFeet))
                if s.weight>shot.weight { shot=s }
            }
        }
        let worldScale=baseScale,layoutUnit=bounds.width/760
        // Zoom enough to keep the world's edge out of view while it rattles.
        let cover=CGFloat(abs(rattle.dx)+abs(kick.dx))*layoutUnit/(bounds.width/2)+CGFloat(abs(rattle.rotation)+abs(kick.rotation))*0.6
        let totalZoom=CGFloat(kick.zoom+shot.zoom+rattle.zoom)+cover,sceneScale=worldScale*(1+totalZoom)
        var shotX=CGFloat(0),shotY=CGFloat(0)
        if shot.weight>0 {
            // Slide toward the focus, but never further than the zoom lets the plates cover (the world is 1000Z wide, the plates run y -159Z...758Z).
            let maxX=worldWidth/2*(1-1/(1+Double(totalZoom))),slackY=max(0,min(viewCentreY+159*zoom,758*zoom-viewCentreY)-Double(bounds.height/(2*sceneScale)))+30
            shotX=CGFloat(min(maxX,max(-maxX,-(shot.focusX-worldWidth/2)*shot.weight)))*sceneScale
            shotY=CGFloat(min(slackY,max(-slackY,-(shot.focusY-viewCentreY)*0.8*shot.weight)))*sceneScale
        }
        var worldTransform=CGAffineTransform(translationX:(CGFloat(kick.dx+rattle.dx))*layoutUnit+shotX,y:(CGFloat(kick.dy+rattle.dy))*layoutUnit+shotY)
        worldTransform=worldTransform.rotated(by:CGFloat(kick.rotation+rattle.rotation)).scaledBy(x:sceneScale,y:sceneScale)
        world.transform=worldTransform;cameraTransform=worldTransform;cameraWidth=bounds.width+bounds.height*4096
        // Cinema bars: while the lens is on a close-up, black bars slide in at the top and bottom, so the camera work reads at a glance.
        let barH=bounds.height*0.065*CGFloat(shot.weight)
        barTop.frame=CGRect(x:0,y:0,width:bounds.width,height:barH);barBottom.frame=CGRect(x:0,y:bounds.height-barH,width:bounds.width,height:barH)
        fx.setNeedsDisplay()
    }
    /// UIKit lays this view out again whenever a subview changes size - and the camera's zoom changes the world's size every frame. Layout
    /// used to reset the world to its plain scale, which silently undid the whole camera (zoom, shake, director shot); it now keeps the camera.
    override func layoutSubviews() {
        super.layoutSubviews();let scale=baseScale;updateViewCentre();updateWideScene()
        gpu?.setResolution(max(1,min(3,UIScreen.main.scale*scale*1.15)))
        world.center=CGPoint(x:bounds.midX,y:bounds.midY)
        if let camera=cameraTransform,cameraWidth==bounds.width+bounds.height*4096 { world.transform=camera } else { world.transform=CGAffineTransform(scaleX:scale,y:scale) }
    }
}
struct MeadowPartyMessage {
    let text:String;let point:CGPoint;let at:Double;let color:UIColor;var atImpact=false;var supportUnit:String?=nil;var supportLine=0;var hitTier:MeadowBattleHitTier?=nil
    /// Look of the number (`MeadowBattleNumber`), the hit tier (0 light ... 2 heavy) for damage, and the unit it is stuck to (it moves with that unit's knock-back).
    var kind:MeadowBattleNumber.Kind = .heal;var rank=1;var follow:String?=nil
}
/// One player blow on a monster, for the shared hit-feel graphics (world coordinates).
struct MeadowPartyHitEvent { let at:Double;let tier:MeadowBattleHitTier;let direction:Double;let point:CGPoint;let footX:CGFloat;let floorY:CGFloat }
/// A procedural skill on stage (`MeadowSkillProcedural`): its own start, and where everything is.
struct MeadowPartyProcEvent {
    let skill:String,start:Double,direction:Double
    /// The geometry at cast time, plus who is who, so the effect can follow each unit's live position every frame.
    let geo:MeadowSkillProcedural.Geometry,casterID:String,targetIDs:[String]
    /// How hard the blow really was (1 medium, 0.7 light, 1.45 heavy); set when the rules report the damage. Scales the lens shake after the release.
    var power=1.0
    var info:MeadowSkillProcedural.Info? { MeadowSkillProcedural.info[skill] }
    /// Geometry with every foot replaced by the unit's current on-screen foot (travel, knock-back); chests keep their offset from the foot.
    func geometry(live:[String:PartyPoint])->MeadowSkillProcedural.Geometry {
        func move(_ foot:MeadowSkillProcedural.Pt,_ chest:MeadowSkillProcedural.Pt,_ id:String)->(foot:MeadowSkillProcedural.Pt,chest:MeadowSkillProcedural.Pt) {
            guard let p=live[id] else { return (foot,chest) }
            return (.init(p.x,p.y),.init(p.x+(chest.x-foot.x),p.y+(chest.y-foot.y)))
        }
        let c=move(geo.casterFoot,geo.caster,casterID)
        var targets:[MeadowSkillProcedural.Target]=[]
        for (i,t) in geo.targets.enumerated() where i<targetIDs.count { let m=move(t.foot,t.chest,targetIDs[i]);targets.append(.init(chest:m.chest,foot:m.foot)) }
        var g=MeadowSkillProcedural.Geometry(caster:c.chest,casterFoot:c.foot,targets:targets.isEmpty ? geo.targets:targets,ground:targets.first?.foot.y ?? geo.ground)
        g.power=power
        return g
    }
}
enum MeadowSkillProceduralDrawing {
    static func heal(_ tier:HealingEffectTier)->String { switch tier { case .micro:return "healMicro";case .standard:return "healStandard";case .strong:return "healStrong" } }
    static func active(_ tier:HealingEffectTier,age:Double)->Bool { guard let info=MeadowSkillProcedural.info[heal(tier)] else { return false };return age>=0 && age<info.duration }
    /// Everything one healing effect draws (the effect and its soft light), as primitives.
    static func healPrims(_ tier:HealingEffectTier,age:Double,foot:PartyPoint,chest:PartyPoint)->[MeadowSkillProcedural.Prim] {
        let id=heal(tier)
        guard let info=MeadowSkillProcedural.info[id],age>=0,age<info.duration else { return [] }
        let geo=MeadowSkillProcedural.Geometry(caster:.init(chest.x,chest.y),casterFoot:.init(foot.x,foot.y),targets:[.init(chest:.init(chest.x,chest.y),foot:.init(foot.x,foot.y))],ground:foot.y)
        return MeadowSkillProcedural.ambient(skill:id,t:age,target:.init(chest.x,chest.y),floorY:foot.y,rx:70)+MeadowSkillProcedural.primitives(skill:id,t:age,geo:geo)
    }
    static func drawHeal(_ tier:HealingEffectTier,age:Double,foot:PartyPoint,chest:PartyPoint,in ctx:CGContext,bounds:CGRect) {
        let id=heal(tier)
        guard let info=MeadowSkillProcedural.info[id],age>=0,age<info.duration else { return }
        let geo=MeadowSkillProcedural.Geometry(caster:.init(chest.x,chest.y),casterFoot:.init(foot.x,foot.y),targets:[.init(chest:.init(chest.x,chest.y),foot:.init(foot.x,foot.y))],ground:foot.y)
        MeadowSkillProceduralPainter.draw(MeadowSkillProcedural.primitives(skill:id,t:age,geo:geo),in:ctx,bounds:bounds)
        MeadowSkillProceduralPainter.drawAmbient(skill:id,t:age,in:ctx,bounds:bounds,target:CGPoint(x:chest.x,y:chest.y),floorY:CGFloat(foot.y),rx:70)
    }
}
struct MeadowPartySkillTarget { let chest:PartyPoint;let foot:PartyPoint }
/// A skill on stage: the sprite (`startedAt`), plus what surrounds it - the charge-up on the caster inside the cast motion
/// (`actionStart` ... `startedAt`), the reaction of each target from `impactAt`, and the afterglow once the sprite ends.
struct MeadowPartySkillVFXEvent {
    let spec:PartySkillVFXSpec;let startedAt:Double;let center:PartyPoint;let groundY:Double
    var actionStart=0.0,impactAt=0.0
    var casterChest:PartyPoint?,casterFoot:PartyPoint?
    var targets:[MeadowPartySkillTarget]=[]
    /// Seconds after `startedAt` when nothing of this skill is left to draw.
    var lifetime:Double { max(spec.duration+MeadowSkillAmbientLight.afterglowLife,(impactAt-startedAt)+MeadowSkillAmbientLight.wardReactionLife)+0.05 }
}

private final class MeadowPartyEffectsView:UIView {
    var templates:[String:String]=[:]
    private func hitPoint(_ id:String,shielded:Bool=false,weaponID:String?=nil)->PartyPoint {PartyVisual.hitPoint(target:id,shielded:shielded,weaponID:weaponID,templateID:templates[id])}
    var intent:PartyIntent?,focus:PartyAction?
    var friend="p1",foe="m1",focusTarget="p1"
    /// The unit whose turn it is: a gold marker bobs above its head while nothing is playing.
    var current:String?
    var meetsShield=false
    var age=0.0,time=0.0
    var messages:[MeadowPartyMessage]=[]
    var naturalTwenty=false
    var runes:RuneEffectSample?
    var particles:[MeadowBattleLightParticle]=[]
    var hits:[MeadowPartyHitEvent]=[]
    var skillEffects:[MeadowPartySkillVFXEvent]=[]
    static let pixelSkillIDs:Set<String>=["rally","sweep"]
    var recoveryLights:[(PartyPoint,Double)]=[]
    var monsterRecoveries:[(foot:PartyPoint,chest:PartyPoint,tier:HealingEffectTier,age:Double)]=[]
    var allyRecoveries:[(foot:PartyPoint,chest:PartyPoint,tier:HealingEffectTier,age:Double)]=[]
    var procEffects:[MeadowPartyProcEvent]=[]
    var liveFeet:[String:PartyPoint]=[:]
    /// Reports the strongest full-screen flash of this frame (or nil) to the stage, which shows it on a pane-wide overlay.
    var onFlash:((UIColor?)->Void)?
    /// Every standing shield: where the unit is, how full it is, how old it is, and when/where it last blocked a blow.
    var shields:[(foot:PartyPoint,chest:PartyPoint,level:Double,age:Double,hitAge:Double,hitAngle:Double,wide:Double)]=[]
    /// Fallen heroes (foot, seconds since the fall): a pale light waits over each.
    var downed:[(foot:PartyPoint,age:Double)]=[]
    /// Raised damage: a standing fury around each buffed unit (foot, chest, strength, seconds since granted).
    var buffs:[(foot:PartyPoint,chest:PartyPoint,level:Double,age:Double)]=[]
    /// True when the GPU view draws the procedural skills and healing; this layer then leaves them out.
    var gpuDrawsSkills=false
    /// Everything the procedural skills draw this frame (soft light first, then the shapes), for the GPU.
    func shieldPrimitives()->[MeadowSkillProcedural.Prim] {
        var all:[MeadowSkillProcedural.Prim]=[]
        for sh in shields {
            var geo=MeadowSkillProcedural.Geometry(caster:.init(sh.chest.x,sh.chest.y),casterFoot:.init(sh.foot.x,sh.foot.y),targets:[.init(chest:.init(sh.chest.x,sh.chest.y),foot:.init(sh.foot.x,sh.foot.y))],ground:sh.foot.y)
            geo.power=sh.level;geo.hitAge=sh.hitAge;geo.hitAngle=sh.hitAngle;geo.wide=sh.wide
            all += MeadowSkillProcedural.shieldShell(sh.age,geo,0)
        }
        for b in buffs {
            var geo=MeadowSkillProcedural.Geometry(caster:.init(b.chest.x,b.chest.y),casterFoot:.init(b.foot.x,b.foot.y),targets:[.init(chest:.init(b.chest.x,b.chest.y),foot:.init(b.foot.x,b.foot.y))],ground:b.foot.y)
            geo.power=b.level
            all += MeadowSkillProcedural.buffAura(b.age,geo,0)
        }
        for d in downed {
            let geo=MeadowSkillProcedural.Geometry(caster:.init(d.foot.x,d.foot.y),casterFoot:.init(d.foot.x,d.foot.y),targets:[.init(chest:.init(d.foot.x,d.foot.y-30),foot:.init(d.foot.x,d.foot.y))],ground:d.foot.y)
            all += MeadowSkillProcedural.downAura(d.age,geo,0)
        }
        return all
    }
    func skillPrimitives()->[MeadowSkillProcedural.Prim] {
        var all=shieldPrimitives()
        for r in monsterRecoveries+allyRecoveries { all += MeadowSkillProceduralDrawing.healPrims(r.tier,age:r.age,foot:r.foot,chest:r.chest) }
        for e in procEffects {
            let t=time-e.start
            guard let info=e.info,t>=0,t<info.duration else { continue }
            let geo=e.geometry(live:liveFeet)
            guard !geo.targets.isEmpty else { continue }
            let n=Double(geo.targets.count),mx=geo.targets.reduce(0){$0+$1.chest.x}/n,my=geo.targets.reduce(0){$0+$1.chest.y}/n,fy=geo.targets.reduce(0){$0+$1.foot.y}/n
            let spread=geo.targets.map { abs($0.chest.x-mx) }.max() ?? 0
            all += MeadowSkillProcedural.ambient(skill:e.skill,t:t,target:.init(mx,my),floorY:fy,rx:90+spread)
            all += MeadowSkillProcedural.primitives(skill:e.skill,t:t,geo:geo)
        }
        return all
    }
    /// The effects layer covers more than the 1000x600 world: glows that reach past the world's edge are not cut off there (that cut was a hard
    /// horizontal edge). Drawing is in world coordinates; the layer is drawn at a lower resolution, which soft light does not mind and which keeps long skills fast.
    /// Grows with the formation's world zoom (0, -200Z, 1000Z, 1000Z); the draw scale shrinks by the same factor, so the pixel cost stays put.
    var worldRect=CGRect(x:0,y:-200,width:1000,height:1000)
    static let baseDrawScale:CGFloat=1.5
    var drawScale:CGFloat=1.5
    /// Blows (plain attacks, strong strike, ambush) are procedural effects now; the old sprite / flare impact drawing stays off.
    static let proceduralBlows=true
    override func didMoveToWindow() { super.didMoveToWindow();contentScaleFactor=drawScale }
    override init(frame:CGRect) { super.init(frame:frame);isOpaque=false;isUserInteractionEnabled=false }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    /// A floating number: springs in, floats up and fades late (`MeadowBattleNumber`). It stays stuck to its unit as the unit is knocked back.
    private func drawNumber(_ m:MeadowPartyMessage,in ctx:CGContext) {
        let age=time-m.at,alpha=MeadowBattleNumber.alpha(age:age),scale=CGFloat(MeadowBattleNumber.scale(age:age,kind:m.kind,rank:m.rank))
        guard alpha>0.003,scale>0.01 else { return }
        let size=MeadowBattleNumber.fontSize(kind:m.kind,rank:m.rank),a=CGFloat(alpha)
        let fill:UIColor = m.kind == .damage ? (m.rank >= 2 ? UIColor(red:1,green:0.886,blue:0.51,alpha:1):.white):m.color
        let attrs=MeadowBattleText.attributes(m.text,size:CGFloat(size),fill:fill,alpha:a)
        let label=NSAttributedString(string:m.text,attributes:attrs),box=label.size()
        let rise=CGFloat(MeadowBattleNumber.rise(age:age,kind:m.kind)),sway=CGFloat(MeadowBattleNumber.sway(age:age,seed:abs(Int(m.point.x))))
        var cx:CGFloat,cy:CGFloat
        if let id=m.supportUnit,let base=PartyVisual.foot(id) {
            // Beside the owner, under every HP header; stacked lines are spaced by the font size.
            let live=liveFeet[id].map { CGPoint(x:$0.x,y:$0.y) } ?? CGPoint(x:base.x,y:base.y)
            let line=CGFloat(MeadowBattleNumber.lineHeight(kind:m.kind,rank:m.rank))*CGFloat(m.supportLine)
            cx=max(4,live.x-14-box.width)+box.width/2;cy=live.y-86+line-rise+box.height/2
        } else if m.atImpact {
            var p=m.point
            if let id=m.follow,let base=PartyVisual.foot(id),let live=liveFeet[id] { p.x += CGFloat(live.x-base.x);p.y += CGFloat(live.y-base.y) }
            cx=p.x+sway;cy=p.y-rise-6
        } else {
            cx=m.point.x+60+box.width/2+sway;cy=m.point.y-55-rise+box.height/2
        }
        let half=box.width*scale/2
        cx=min(worldRect.maxX-4-half,max(worldRect.minX+4+half,cx))
        ctx.saveGState();ctx.setBlendMode(.normal)
        ctx.setShadow(offset:.zero,blur:CGFloat(size)*0.4,color:fill.withAlphaComponent(a*0.55).cgColor)
        ctx.translateBy(x:cx,y:cy);ctx.scaleBy(x:scale,y:scale)
        label.draw(at:CGPoint(x:-box.width/2,y:-box.height/2))
        ctx.restoreGState()
    }
    override func draw(_ rect:CGRect) {
        guard let ctx=UIGraphicsGetCurrentContext() else { return }
        ctx.translateBy(x:-worldRect.minX,y:-worldRect.minY)
        let bounds=worldRect
        func sprite(_ im:UIImage,_ p:PartyPoint,_ w:Double,_ h:Double,_ alpha:Double) { guard alpha>0 else { return };im.draw(in:CGRect(x:p.x-w/2,y:p.y-h/2,width:w,height:h),blendMode:.plusLighter,alpha:CGFloat(alpha)) }
        func glow(_ p:PartyPoint,_ rx:Double,_ ry:Double,_ alpha:Double,_ color:UIColor) { guard alpha>0 else { return };MeadowBattleGlowCache.image(color).draw(in:CGRect(x:p.x-rx,y:p.y-ry,width:rx*2,height:ry*2),blendMode:.plusLighter,alpha:CGFloat(alpha)) }
        for (foot,power) in recoveryLights { glow(foot,105,27,power*0.65,.systemGreen);glow(PartyPoint(foot.x,foot.y-70),42,85,power*0.12,.systemGreen) }
        if !gpuDrawsSkills { for r in monsterRecoveries+allyRecoveries { MeadowSkillProceduralDrawing.drawHeal(r.tier,age:r.age,foot:r.foot,chest:r.chest,in:ctx,bounds:bounds) } }
        if intent==nil {
            // The picked targets: a bouncing arrow above the head, in the colour of the mark on the ground under them.
            for (id,color) in [(friend,UIColor(red:0.30,green:0.95,blue:0.62,alpha:1)),(foe,UIColor(red:1.0,green:0.36,blue:0.26,alpha:1))] where id != current {
                guard let foot=PartyVisual.foot(id) else { continue }
                let px=CGFloat(foot.x),top=CGFloat(foot.y)-CGFloat(id.hasPrefix("m") ? 272:200)+CGFloat(abs(sin(time*4))*9)
                ctx.beginPath();ctx.move(to:CGPoint(x:px-14,y:top-16));ctx.addLine(to:CGPoint(x:px+14,y:top-16));ctx.addLine(to:CGPoint(x:px,y:top+4));ctx.closePath()
                ctx.setFillColor(color.cgColor);ctx.setStrokeColor(UIColor.white.cgColor);ctx.setLineWidth(3);ctx.setLineJoin(.round);ctx.drawPath(using:.fillStroke)
            }
            // Whose turn it is: a gold arrow and tag bobbing above the head (above the health header).
            if let id=current,let foot=PartyVisual.foot(id) {
                let px=CGFloat(foot.x),top=CGFloat(foot.y)-CGFloat(id.hasPrefix("m") ? 266:196)+CGFloat(sin(time*6)*4)
                let tag=NSAttributedString(string:"行动中",attributes:[.font:UIFont.systemFont(ofSize:19,weight:.heavy),.foregroundColor:UIColor(red:0.12,green:0.1,blue:0.04,alpha:1)])
                let size=tag.size(),pill=CGRect(x:px-size.width/2-9,y:top-size.height-5,width:size.width+18,height:size.height+4)
                ctx.setFillColor(MeadowPreviewPalette.gold.cgColor);ctx.addPath(UIBezierPath(roundedRect:pill,cornerRadius:pill.height/2).cgPath);ctx.fillPath()
                tag.draw(at:CGPoint(x:pill.minX+9,y:pill.minY+2))
                ctx.beginPath();ctx.move(to:CGPoint(x:px-9,y:top-4));ctx.addLine(to:CGPoint(x:px+9,y:top-4));ctx.addLine(to:CGPoint(x:px,y:top+8));ctx.closePath()
                ctx.setFillColor(MeadowPreviewPalette.gold.cgColor);ctx.fillPath()
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
            if !Self.proceduralBlows,intent.ranged,let foot=PartyVisual.foot(intent.actor) {
                let tip=BowRig.releaseArrowTip
                let from=PartyPoint(foot.x+(tip.x-123)*PartyVisual.heroScale*PartyVisual.facing(intent.actor),foot.y+(tip.y-214)*PartyVisual.heroScale)
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
            if !Self.proceduralBlows,intent.magical,let foot=PartyVisual.foot(intent.actor),let targetFoot=PartyVisual.foot(intent.target) {
                let sample=LegendaryStaffRig.effect(age:age,foot:foot,target:hitPoint(intent.target,shielded:meetsShield,weaponID:intent.weaponID),groundY:targetFoot.y,scale:PartyVisual.heroScale,naturalTwenty:naturalTwenty)
                MeadowStaffEffectPainter.draw(sample,in:ctx)
            }
            if !Self.proceduralBlows,visual=="attack",intent.action.skillVFX == nil,!intent.magical,let foot=PartyVisual.foot(intent.target) {
                let a=age-(intent.enemy ? 0.46:1.048),p=hitPoint(intent.target,shielded:meetsShield,weaponID:intent.weaponID)
                let power=PartyVisual.pulse(a,-0.035,0.035,0.52)
                if !intent.enemy && !hits.isEmpty {
                    // Player blows use the sharp contact flare below; only a faint floor glow and the sweep arc stay.
                    glow(foot,110,24,power*0.30,.orange)
                    if a>=0,a<0.7,!intent.ranged { sprite(MeadowBattleVFXAssets.heavyArc,p,170+a*220,170+a*220,power*0.55) }
                } else {
                    glow(p,140,140,power*0.48,.orange);glow(foot,170,30,power*0.65,.orange)
                    if a>=0,a<0.7 {
                        sprite(MeadowBattleVFXAssets.burst,p,150+a*140,150+a*140,power)
                        if !intent.enemy && !intent.ranged { sprite(MeadowBattleVFXAssets.heavyArc,p,210+a*240,210+a*240,power*0.9) }
                    }
                }
            }
            if !Self.proceduralBlows,visual=="ambush",let foot=PartyVisual.foot(intent.target) {
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
            // The five hand-built pixel sheets (scripts/battle-vfx) hold each frame and are scaled without smoothing, so the
            // pixels stay crisp and nothing swims between frames; any other sheet keeps the soft cross-fade.
            let pixelArt=Self.pixelSkillIDs.contains(event.spec.id)
            let mix=pixelArt ? 0 : PartyVisual.smooth(position-Double(lower))
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
            // Ambient light (MeadowSkillAmbientLight): a faint wash over the whole stage, a wide pool of light on the floor
            // with a rim, and (below) a squashed reflection and glowing motes that drift over the characters.
            let lit=MeadowSkillAmbientLight.level(age:age,peak:event.spec.peakTime,duration:event.spec.duration)
            let floorWidth=Double(event.spec.frameWidth)
            if lit>0 {
                // The flat dim and tint for this light are applied by the stage on pane-wide overlays (see `render()`), not here.
                glow(event.center,max(Double(bounds.width),floorWidth)*0.62,max(600,floorWidth)*0.52,lit*0.16,color)
                glow(PartyPoint(event.center.x,event.groundY-2),floorWidth*0.62,28,lit*0.34,color)
                ctx.saveGState();ctx.setBlendMode(.plusLighter);ctx.setStrokeColor(color.withAlphaComponent(CGFloat(lit*0.32)).cgColor);ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in:CGRect(x:event.center.x-floorWidth*0.36,y:event.groundY-9,width:floorWidth*0.72,height:18));ctx.restoreGState()
            }
            ctx.saveGState();ctx.interpolationQuality = pixelArt ? .none : .default
            frames[lower].draw(in:rect,blendMode:.plusLighter,alpha:CGFloat(1-mix))
            if upper != lower,mix>0 { frames[upper].draw(in:rect,blendMode:.plusLighter,alpha:CGFloat(mix)) }
            ctx.restoreGState()
            if lit>0 {
                // Squashed reflection on the floor, only below the ground line.
                ctx.saveGState();ctx.interpolationQuality = pixelArt ? .none : .default
                ctx.clip(to:CGRect(x:rect.minX-20,y:event.groundY,width:rect.width+40,height:90))
                ctx.translateBy(x:0,y:event.groundY);ctx.scaleBy(x:1,y:-0.30);ctx.translateBy(x:0,y:-event.groundY)
                frames[lower].draw(in:rect,blendMode:.plusLighter,alpha:CGFloat(0.16*(1-mix)*lit))
                if upper != lower,mix>0 { frames[upper].draw(in:rect,blendMode:.plusLighter,alpha:CGFloat(0.16*mix*lit)) }
                ctx.restoreGState()
            }
            if !UIAccessibility.isReduceMotionEnabled {
                let hot=UIColor(red:1,green:0.96,blue:0.86,alpha:1)
                for m in MeadowSkillAmbientLight.motes(skill:event.spec.id,age:age,duration:event.spec.duration,spread:floorWidth*0.36) {
                    let p=PartyPoint(event.center.x+m.dx,event.center.y+m.dy)
                    glow(p,m.radius*1.5,m.radius*1.5,m.alpha*0.8,color)
                    ctx.saveGState();ctx.setBlendMode(.plusLighter);ctx.setFillColor((m.hot ? hot : color).withAlphaComponent(CGFloat(m.alpha)).cgColor)
                    ctx.fill(CGRect(x:p.x-m.core/2,y:p.y-m.core/2,width:m.core,height:m.core));ctx.restoreGState()
                }
            }
        }
        // Stagecraft around the five pixel skills (MeadowSkillAmbientLight): charge-up, target reaction, afterglow.
        for event in skillEffects where Self.pixelSkillIDs.contains(event.spec.id) {
            let id=event.spec.id,tone=MeadowSkillAmbientLight.tone(for:id)
            let color=UIColor(red:CGFloat(tone.r),green:CGFloat(tone.g),blue:CGFloat(tone.b),alpha:1),hot=UIColor(red:1,green:0.96,blue:0.86,alpha:1)
            let calm=UIAccessibility.isReduceMotionEnabled
            func specks(_ motes:[MeadowSkillAmbientLight.Mote],_ o:PartyPoint,_ strength:Double) {
                guard !calm else { return }
                for m in motes where m.alpha>0.01 {
                    let p=PartyPoint(o.x+m.dx,o.y+m.dy)
                    glow(p,m.radius*1.4,m.radius*1.4,m.alpha*strength,color)
                    ctx.saveGState();ctx.setBlendMode(.plusLighter);ctx.setFillColor((m.hot ? hot:color).withAlphaComponent(CGFloat(m.alpha)).cgColor)
                    ctx.fill(CGRect(x:p.x-m.core/2,y:p.y-m.core/2,width:m.core,height:m.core));ctx.restoreGState()
                }
            }
            func rim(_ c:PartyPoint,_ rx:Double,_ ry:Double,_ alpha:Double) {
                guard alpha>0.01 else { return }
                ctx.saveGState();ctx.setBlendMode(.plusLighter);ctx.setStrokeColor(color.withAlphaComponent(CGFloat(min(1,alpha))).cgColor);ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in:CGRect(x:c.x-rx,y:c.y-ry,width:rx*2,height:ry*2));ctx.restoreGState()
            }
            // 1. Charge-up on the caster, in the last half second before the sprite starts (inside the existing cast motion).
            let chargeStart=max(event.actionStart,event.startedAt-MeadowSkillAmbientLight.chargeWindow)
            if let chest=event.casterChest,let foot=event.casterFoot,event.startedAt-chargeStart>0.12,time>=chargeStart,time<event.startedAt,
               let c=MeadowSkillAmbientLight.charge(skill:id,progress:(time-chargeStart)/(event.startedAt-chargeStart)) {
                glow(chest,52,52,c.level*0.5,color)
                rim(foot,c.ringRadius,c.ringRadius*0.3,c.ringAlpha*0.7)
                specks(c.motes,chest,0.75)
            }
            // 3. Target reactions from the impact.
            for target in event.targets {
                guard let r=MeadowSkillAmbientLight.reaction(skill:id,age:time-event.impactAt) else { continue }
                glow(target.chest,46,66,r.glow*0.45,color)
                if r.aura>0.01 {
                    glow(target.chest,34,62,r.aura*0.16,color)
                    rim(target.foot,40,12,r.aura*0.5)
                    if !calm { for k in 0..<4 {
                        let th=r.spin+Double(k)*Double.pi/2,p=PartyPoint(target.foot.x+cos(th)*40,target.foot.y+sin(th)*12)
                        ctx.saveGState();ctx.setBlendMode(.plusLighter);ctx.setFillColor(hot.withAlphaComponent(CGFloat(r.aura)).cgColor);ctx.fill(CGRect(x:p.x-1.5,y:p.y-1.5,width:3,height:3));ctx.restoreGState()
                    } }
                }
                specks(r.motes,target.chest,0.6)
            }
            // 4. Afterglow: a fading pool of light and a few embers once the sprite has ended.
            if let g=MeadowSkillAmbientLight.afterglow(skill:id,age:time-(event.startedAt+event.spec.duration),spread:Double(event.spec.frameWidth)*0.3) {
                glow(PartyPoint(event.center.x,event.groundY-2),Double(event.spec.frameWidth)*0.5,22,g.pool,color)
                specks(g.motes,event.center,0.6)
            }
        }
        // Continuous procedural skills (MeadowSkillProcedural): ambient light first, then the effect itself.
        if !gpuDrawsSkills { MeadowSkillProceduralPainter.draw(shieldPrimitives(),in:ctx,bounds:bounds) }
        var flashColor:UIColor?=nil,flashAlpha=0.0
        for e in procEffects where !gpuDrawsSkills {
            let t=time-e.start
            guard let info=e.info,t>=0,t<info.duration else { continue }
            let geo=e.geometry(live:liveFeet)
            guard !geo.targets.isEmpty else { continue }
            // The ambient light centres on the whole group of targets and widens with their spread.
            let n=Double(geo.targets.count),mx=geo.targets.reduce(0){$0+$1.chest.x}/n,my=geo.targets.reduce(0){$0+$1.chest.y}/n,fy=geo.targets.reduce(0){$0+$1.foot.y}/n
            let spread=geo.targets.map { abs($0.chest.x-mx) }.max() ?? 0
            MeadowSkillProceduralPainter.drawAmbient(skill:e.skill,t:t,in:ctx,bounds:bounds,target:CGPoint(x:mx,y:my),floorY:CGFloat(fy),rx:90+spread,fillBounds:false)
            MeadowSkillProceduralPainter.draw(MeadowSkillProcedural.primitives(skill:e.skill,t:t,geo:geo),in:ctx,bounds:bounds) { c,a in
                if a>flashAlpha { flashAlpha=a;flashColor=UIColor(red:CGFloat(c.r/255),green:CGFloat(c.g/255),blue:CGFloat(c.b/255),alpha:CGFloat(min(1,a*0.85))) }
            }
        }
        if !gpuDrawsSkills { onFlash?(flashColor) }
        for h in hits where !Self.proceduralBlows {
            let a=time-h.at
            glow(PartyPoint(Double(h.point.x),Double(h.point.y)),120,120,MeadowBattleHitFeel.flash(age:a)*0.55,UIColor(red:1,green:0.75,blue:0.27,alpha:1))
            MeadowBattleHitFeelPainter.draw(in:ctx,age:a,tier:h.tier,direction:h.direction,impact:h.point,floorY:h.floorY,footX:h.footX,unit:MeadowBattleHitFeelPainter.partyStageUnit)
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
        for m in messages { drawNumber(m,in:ctx) }
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

// MARK: effect review (the lab: MeadowEffectsLabViewController)
extension MeadowPartyStageView {
    /// Plays one procedural effect on the stage without involving the rules. `id` is any id of `MeadowSkillProcedural.skillIDs`, or one of
    /// the lab's own: `projBow`/`projStaff`/`projArcher`/`projDragon` fly from the actor to the first target, `natural20`, `shieldDome`, `deathX`, ...
    func labPlay(_ id:String,actor:String,targets:[String],power:Double,weaponID:String?=nil,delay:Double=0) {
        guard let state,let aFoot=PartyVisual.foot(actor),let first=targets.first,let tFoot=PartyVisual.foot(first) else { return }
        let templates=state.units.mapValues(\.templateID)
        let aChest=PartyVisual.skillEffectCenter(targets:[actor],actor:actor,templates:templates)
        let hit=PartyVisual.hitPoint(target:first,weaponID:weaponID,templateID:templates[first])
        func spawn(_ name:String,from:PartyPoint,to:[(chest:PartyPoint,foot:PartyPoint)],ids:[String],pw:Double) {
            guard let f=to.first else { return }
            let geo=MeadowSkillProcedural.Geometry(caster:.init(from.x,from.y),casterFoot:.init(aFoot.x,aFoot.y),targets:to.map { .init(chest:.init($0.chest.x,$0.chest.y),foot:.init($0.foot.x,$0.foot.y)) },ground:f.foot.y)
            var event=MeadowPartyProcEvent(skill:name,start:sceneTime+delay,direction:f.chest.x>=aChest.x ? 1:-1,geo:geo,casterID:actor,targetIDs:ids)
            event.power=pw;procVFX.append(event)
        }
        let heals:[String:HealingEffectTier]=["healMicro":.micro,"healStandard":.standard,"healStrong":.strong]
        if let tier=heals[id] { for t in targets { recovery[t]=sceneTime+delay;recoveryTier[t]=tier };return }
        if id == "natural20" { spawnNaturalTwenty(actor:actor,target:first,weaponID:weaponID,templates:templates,delay:delay);return }
        if id.hasPrefix("proj") {
            let templateID=templates[actor] ?? ""
            let from:PartyPoint
            switch id {
            case "projBow":
                let tip=BowRig.releaseArrowTip;from=PartyPoint(aFoot.x+(tip.x-123)*PartyVisual.heroScale*PartyVisual.facing(actor),aFoot.y+(tip.y-214)*PartyVisual.heroScale)
            case "projStaff":
                let g=LegendaryStaffRig.gem(progress:LegendaryStaffRig.progress(age:LegendaryStaffRig.releaseAge));from=PartyPoint(aFoot.x+(g.x-123)*PartyVisual.heroScale*PartyVisual.facing(actor),aFoot.y+(g.y-214)*PartyVisual.heroScale)
            default:
                let spec=MonsterVisualSpec.find(templateID),goblin=id == "projArcher",scale=spec?.scale ?? 0.88
                from=PartyPoint(aFoot.x+(goblin ? -82:-143)*scale,aFoot.y-(goblin ? 144:149)*scale)
            }
            spawn(id,from:from,to:[(chest:hit,foot:tFoot)],ids:[first],pw:power);return
        }
        if MeadowSkillProcedural.isBlow(id) || id == "playerDown" {
            for t in targets {
                guard let f=PartyVisual.foot(t) else { continue }
                let h=PartyVisual.hitPoint(target:t,weaponID:weaponID,templateID:templates[t])
                spawn(id,from:aChest,to:[(chest:id == "playerDown" ? PartyPoint(f.x,f.y-40):h,foot:f)],ids:[t],pw:power)
            }
            return
        }
        // A skill: the same event the battle makes - the caster, and every target at once.
        let list=targets.compactMap { t -> (chest:PartyPoint,foot:PartyPoint)? in
            guard let f=PartyVisual.foot(t) else { return nil }
            return (chest:PartyVisual.skillEffectCenter(targets:[t],actor:actor,templates:templates),foot:f)
        }
        spawn(id,from:aChest,to:list,ids:targets,pw:power)
    }
    /// A shield of `value` on `id`, generated now.
    func labSetShield(_ id:String,_ value:Int) {
        state?.units[id]?.shield=value;statusSnapshots.removeValue(forKey:id)
        if value>0 { birth[id]=sceneTime } else { broken[id]=sceneTime }
    }
    /// A blow lands on the shield of `id` from `attacker`; `value` is what is left afterwards.
    func labBlock(_ id:String,from attacker:String,remaining value:Int) {
        guard let state else { return }
        let templates=state.units.mapValues(\.templateID),a=PartyVisual.skillEffectCenter(targets:[attacker],actor:attacker,templates:templates),t=PartyVisual.skillEffectCenter(targets:[id],actor:attacker,templates:templates)
        contact[id]=sceneTime;contactAngle[id]=atan2(a.y-t.y,a.x-t.x);self.state?.units[id]?.shield=value
        labPlay("hitWard",actor:attacker,targets:[id],power:1.0)
    }
    func labBreak(_ id:String,from attacker:String) {
        state?.units[id]?.shield=0;broken[id]=sceneTime;contact[id]=sceneTime
        labPlay("shieldBreak",actor:attacker,targets:[id],power:1.2)
        kickFeel=(sceneTime,.medium,1)
    }
    func labKill(_ id:String,from attacker:String) {
        guard let template=state?.units[id]?.templateID else { return }
        let name:String
        switch template { case "slime":name="deathSlime";case "wolf":name="deathWolf";case "goblinArcher":name="deathGoblin";case "stoneGuardian":name="deathStone";case "caveTroll":name="deathTroll";case "ruinDragon":name="deathDragon";default:name="deathBurst" }
        labPlay(name,actor:attacker,targets:[id],power:1.0)
        state?.units[id]?.health=0;deaths[id]=sceneTime
    }
    func labDown(_ id:String,from attacker:String) {
        labPlay("playerDown",actor:attacker,targets:[id],power:1.0)
        state?.units[id]?.health=0;fallen[id]=sceneTime
    }
    func labShake(_ tier:MeadowBattleHitTier,delay:Double=0) { kickFeel=(sceneTime+delay,tier,1) }
    /// The state the lab is showing (to build real intents for `play`).
    var labState:GameState? { state }
    /// A damage buff of `amount` on `id` as the lab shows it (0 removes it).
    func labSetBuff(_ id:String,_ amount:Int) { labBuff[id]=amount>0 ? amount:nil;if amount>0 { buffBirth[id]=sceneTime } }
    func labSetWeapon(_ id:String,_ weapon:String?) { state?.units[id]?.equipment.weapon=weapon }
    /// A floating number on `target`, `delay` seconds from now.
    func labNumber(_ text:String,target:String,kind:MeadowBattleNumber.Kind,rank:Int,delay:Double) {
        guard let state else { return }
        let p=PartyVisual.hitPoint(target:target,templateID:state.units[target]?.templateID)
        let color:UIColor = kind == .heal ? .systemGreen:kind == .shield ? .systemCyan:.white
        messages.append(.init(text:text,point:CGPoint(x:p.x,y:p.y),at:sceneTime+delay,color:color,atImpact:true,kind:kind,rank:rank,follow:target))
    }
    func labRevive(_ id:String) {
        guard let unit=state?.units[id],!unit.isAlive else { return }
        state?.units[id]?.health=max(1,unit.baseAttributes.maximumHealth/2);fallen[id]=nil;revivedAt[id]=sceneTime
        labPlay("revive",actor:id,targets:[id],power:1.0)
    }
    /// Back to a clean stage with the given state.
    func labReset(_ value:GameState,catalog:GameCatalog,foe:String="m1") {
        procVFX=[];messages=[];deaths=[:];fallen=[:];contact=[:];contactAngle=[:];revivedAt=[:];buffBirth=[:];labBuff=[:];birth=[:];broken=[:];recovery=[:];recoveryTier=[:];hitFeel=[:];kickFeel=nil;hurt=[:];statusSnapshots=[:];emissions=[]
        show(value,friend:"p1",foe:foe,current:nil,catalog:catalog)
    }
}
