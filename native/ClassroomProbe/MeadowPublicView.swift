import SwiftUI
import UIKit
import ClassroomGameCore

/// Public-only surface: no session reference, commands, notes or editor bindings.
struct MeadowPublicView:View {
    let frame:PublicPlayFrame
    @Environment(\.accessibilityReduceMotion) private var reduced
    private let ink=Color(red:0.96,green:0.9,blue:0.69)
    var body:some View {
        GeometryReader { geometry in
            let width=geometry.size.width/geometry.size.height > 1.5 ? 1920.0:1440.0
            let scale=min(geometry.size.width/width,geometry.size.height/1080)
            TimelineView(.animation(minimumInterval:1.0/60,paused:reduced || frame.snapshot.paused)) { context in
                let date=reduced ? Date.distantFuture:context.date
                VStack(spacing:16) {
                    header(date:date)
                    if MeadowPublicProjection.battle(frame,at:date) {
                        battle(date:date).frame(maxHeight:.infinity)
                        queue
                    } else {
                        map(date:date).frame(maxHeight:.infinity)
                    }
                    playerBars(date:date)
                    Text(feedback(date:date))
                        .font(.system(size:24,weight:.semibold)).lineLimit(2).frame(height:60).frame(maxWidth:.infinity)
                        .padding(.horizontal,20).background(Color.black.opacity(0.25),in:RoundedRectangle(cornerRadius:14))
                }.padding(36).frame(width:width,height:1080).scaleEffect(scale)
                    .frame(width:geometry.size.width,height:geometry.size.height)
            }
        }.foregroundStyle(ink).background(Color(red:0.045,green:0.09,blue:0.065)).preferredColorScheme(.dark)
    }
    private func feedback(date:Date)->String {
        if let cue=MeadowPublicProjection.active(frame,at:date) {
            let age=date.timeIntervalSince(cue.start)
            return age < 0.46 ? "动作演出":cue.text
        }
        return frame.log.last ?? "沿道路探索 · 操作由教师控制"
    }
    private func slot(_ unit:PublicGameUnit,units:[PublicGameUnit],size:CGSize)->CGPoint {
        let peers=units.filter { $0.player == unit.player }.sorted { $0.id < $1.id }
        let index=peers.firstIndex { $0.id == unit.id } ?? 0,row=index%4,col=index/4
        return CGPoint(x:size.width*(unit.player ? 0.19:0.77)+Double(col)*(unit.player ? -100:100)+Double(row%2)*50,
                       y:size.height*(peers.count>2 ? 0.34+Double(row)*0.15:0.60+Double(row)*0.18))
    }
    private func header(date:Date)->some View {
        HStack {
            Text(MeadowPublicProjection.battle(frame,at:date) ? "MEADOW · 战斗":"MEADOW · 探索").font(.system(size:32,weight:.bold))
            Spacer()
            Text(frame.snapshot.currentName.map { "行动中："+$0 } ?? "森林之旅").font(.system(size:28,weight:.bold))
            if frame.snapshot.round > 0 {
                Text("第\(frame.snapshot.round)轮 · \(Int(ceil(frame.snapshot.remainingSeconds)))秒").monospacedDigit()
            }
            if frame.snapshot.paused { Text("已暂停") }
        }.font(.system(size:24,weight:.semibold)).frame(height:60)
    }
    private func art(_ name:String)->some View {
        Group { if let image=MeadowBridgeAssets.image(name) { Image(uiImage:image).resizable().interpolation(.none) } }
    }
    private func map(date:Date)->some View {
        GeometryReader { g in
            ZStack {
                if let ground=MeadowBridgeAssets.mapGround {
                    Image(uiImage:ground).resizable().interpolation(.none).scaledToFill().frame(width:g.size.width,height:g.size.height).clipped()
                }
                Color.black.opacity(0.18)
                Canvas { context,size in
                    let nodes=Dictionary(uniqueKeysWithValues:frame.snapshot.nodes.map { ($0.id,$0) })
                    for road in frame.snapshot.roads {
                        guard let a=nodes[road.a],let b=nodes[road.b] else { continue }
                        let x=frame.camera.screen(MapPoint(x:a.x,y:a.y),width:size.width,height:size.height)
                        let y=frame.camera.screen(MapPoint(x:b.x,y:b.y),width:size.width,height:size.height)
                        var p=Path();p.move(to:CGPoint(x:x.x,y:x.y));p.addLine(to:CGPoint(x:y.x,y:y.y))
                        context.stroke(p,with:.color(.black.opacity(0.3)),style:StrokeStyle(lineWidth:20,lineCap:.round))
                        context.stroke(p,with:.color(Color(red:0.56,green:0.45,blue:0.25)),style:StrokeStyle(lineWidth:12,lineCap:.round))
                    }
                }
                ForEach(frame.snapshot.nodes) { node in
                    let p=frame.camera.screen(MapPoint(x:node.x,y:node.y),width:g.size.width,height:g.size.height)
                    VStack(spacing:4) {
                        Image(systemName:node.revealed ? "mappin.circle.fill":"questionmark.circle.fill").font(.system(size:34))
                        Text(node.name).font(.system(size:20,weight:.bold)).lineLimit(1).padding(5).background(.black.opacity(0.65),in:Capsule())
                    }.opacity(node.revealed ? 1:0.65).position(x:p.x,y:p.y)
                }
                ForEach(Array(frame.snapshot.units.filter(\.player).enumerated()),id:\.element.id) { index,unit in
                    if let world=MeadowPublicProjection.point(unit,frame:frame,at:date) {
                        let p=frame.camera.screen(world,width:g.size.width,height:g.size.height)
                        let peers=frame.snapshot.units.filter { $0.player && $0.nodeID == unit.nodeID }.sorted { $0.id < $1.id }
                        let slot=peers.firstIndex { $0.id == unit.id } ?? 0
                        mapActor(unit:unit,index:index,date:date).frame(width:90,height:110)
                            .position(x:p.x+Double(slot)*38,y:p.y-22)
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius:20))
        }
    }
    private func mapActor(unit:PublicGameUnit,index:Int,date:Date)->some View {
        let cue=frame.presentations.first { date < $0.end && $0.mapMoves.contains { $0.unitID == unit.id } }
        let age=cue.map { date.timeIntervalSince($0.start) } ?? -1
        let move=cue?.mapMoves.first { $0.unitID == unit.id }
        let now=move?.position(progress:age/1.3),prev=move?.position(progress:(age-0.01)/1.3)
        let dx=(now?.x ?? 0)-(prev?.x ?? 0),dy=(now?.y ?? 0)-(prev?.y ?? 0)
        let moving=age>=0 && age<1.3 && hypot(dx,dy)>0.000001
        let directions=[0,4,3,7,2,6,1,5]
        let direction=moving ? directions[(Int((atan2(dx,dy)/(.pi/4)).rounded())+8)%8]:0
        let column=moving ? 1+Int(age/0.12)%8:0
        let image=MeadowBridgeAssets.cell(direction>=4 ? "Hero1Diagonals":"Hero1Directions",column:column,row:direction%4,columns:13,rows:4)
        return VStack(spacing:0) {
            Group { if let image { Image(uiImage:image).resizable().interpolation(.none).scaledToFit() } }
            Text(unit.name).font(.system(size:16,weight:.bold)).lineLimit(1).padding(.horizontal,5).background(.black.opacity(0.7),in:Capsule())
        }
    }
    private func battle(date:Date)->some View {
        GeometryReader { g in
            let units=MeadowPublicProjection.participants(frame,at:date)
            let event=MeadowPublicProjection.active(frame,at:date)
            let age=event.map { date.timeIntervalSince($0.start) } ?? -1
            ZStack {
                art("MeadowCampFarForest").scaledToFill().frame(width:g.size.width,height:g.size.height).clipped()
                art("MeadowCampGround").scaledToFill().frame(width:g.size.width,height:g.size.height).clipped().opacity(0.55)
                art("MeadowCampMidground").scaledToFill().frame(width:g.size.width,height:g.size.height).clipped()
                Color.black.opacity(event?.units.contains(where: { $0.effects.contains("flame") || $0.effects.contains("projectile") }) == true ? 0.44:0.16)
                ForEach(units) { unit in
                    let height=min(210.0,g.size.height*0.43)
                    let point=slot(unit,units:units,size:g.size)
                    let cue=event?.units.first { $0.id == unit.id }
                    let target=units.first { candidate in candidate.player != unit.player && event?.units.contains(where: { $0.id == candidate.id && ["hurt","down"].contains($0.motion) }) == true }
                    let targetPoint=target.map { slot($0,units:units,size:g.size) } ?? point
                    let melee=unit.player && ["adventurer","spellblade"].contains(unit.templateID) && cue?.motion == "attack"
                    let approach=melee ? MeadowPublicProjection.approach(age):0
                    let travelX=(targetPoint.x-point.x-height*0.65)*approach
                    let travelY=(targetPoint.y-point.y)*approach
                    actor(unit,cue:cue,skillID:event?.skillID,age:age,time:date.timeIntervalSince1970,size:height)
                        .position(x:point.x+travelX,y:point.y+travelY).zIndex(point.y+travelY)
                }
                art("MeadowCampForeground").scaledToFill().frame(width:g.size.width,height:g.size.height).clipped().allowsHitTesting(false)
                VStack { HStack { Spacer();map(date:date).frame(width:230,height:125).opacity(0.85) };Spacer() }.padding(12)
                if let event {
                    HStack(spacing:12) {
                        ForEach(Array(event.dice.enumerated()),id:\.offset) { _,die in
                            ForEach(Array(die.values.enumerated()),id:\.offset) { _,value in
                                Text(String(value)).font(.system(size:28,weight:.heavy)).frame(width:48,height:48)
                                    .background(Color.red.opacity(0.85),in:RoundedRectangle(cornerRadius:9))
                            }
                        }
                    }.frame(maxHeight:.infinity,alignment:.top).padding(.top,18)
                }
            }.clipShape(RoundedRectangle(cornerRadius:20))
        }
    }
    private func actor(_ unit:PublicGameUnit,cue:UnitPresentation?,skillID:String?,age:Double,time:Double,size:Double)->some View {
        let hit=age>=0.46 && age<1.1
        let dead=unit.health<=0
        let species=MeadowPublicProjection.recognizedMonster(unit.templateID)
        let attacking=cue?.motion == "attack" && age>=0
        let lunge=0.0 // Registered body, status and shadow travel together in the stage.
        let clip=dead ? "defeat":cue?.motion == "hurt" && hit ? "hit":attacking ? "attack":"idle"
        let progress=clip == "idle" ? time.truncatingRemainder(dividingBy:2.4)/2.4 : min(1,max(0,(clip == "hit" || clip == "defeat" ? age-0.46:age)/0.9))
        return ZStack {
            Ellipse().fill(.black.opacity(0.4)).frame(width:size*0.45,height:16).offset(y:size*0.34)
            if cue?.effects.isEmpty == false && hit {
                Ellipse().fill(RadialGradient(colors:[effectColor(cue).opacity(0.7*(1-(age-0.46)/0.64)),.clear],center:.center,startRadius:0,endRadius:size*0.8))
                    .frame(width:size*2,height:size).offset(y:size*0.3).blendMode(.plusLighter)
            }
            if let cue,age>=0,!(cue.effects.contains("impact") || cue.effects.contains("natural20")) {
                // Recovery light sits behind the body, preserving its silhouette.
                effects(cue,skillID:skillID,age:age,size:size)
            }
            if unit.player && ["adventurer","spellblade"].contains(unit.templateID) {
                MeadowBridgeHero(clip:clip,progress:progress).frame(width:size*1.65,height:size*1.65)
                    .offset(x:lunge,y:-size*0.16)
            } else if unit.player {
                // Existing ranged classes retain their original appearance until a
                // reviewed Meadow rig is bound; never give an archer a melee pose.
                ArtImage(type:"classes",id:unit.templateID).frame(width:size,height:size)
            } else if let species {
                monster(species,dead:dead,cue:cue,age:age,time:time).frame(width:size*1.7,height:size*1.7).offset(y:-size*0.15)
            } else {
                // Keep unknown templates visible using the original module's art.
                ArtImage(type:"monsters",id:unit.templateID).frame(width:size,height:size)
            }
            if unit.shield>0 && !dead {
                Circle().stroke(Color.cyan.opacity(0.85),lineWidth:4).background(Circle().fill(.blue.opacity(0.1)))
                    .frame(width:size*1.15,height:size*1.15).offset(y:-size*0.1)
                    .opacity(cue?.effects.contains("shield") == true && unit.shield == cue?.shieldChange ? min(1,max(0,(age-0.72)/0.25)):1)
            }
            if let cue,age>=0 {
                if cue.effects.contains("impact") || cue.effects.contains("natural20") {
                    effects(cue,skillID:skillID,age:age,size:size).offset(x:lunge)
                }
                if cue.healthChange != 0 && age >= (cue.healthChange>0 ? 0.72:0.46) {
                    Text((cue.healthChange>0 ? "+":"")+String(cue.healthChange)).font(.system(size:40,weight:.heavy,design:.serif))
                        .foregroundStyle(cue.healthChange>0 ? Color.green:Color.white).shadow(color:.black,radius:2)
                        .offset(x:lunge,y:-size*0.35-max(0,age-0.46)*30).opacity(min(1,(1.3-age)/0.2))
                }
            }
            if !dead {
                VStack(spacing:3) {
                    Text(unit.name).font(.system(size:20,weight:.bold)).lineLimit(1)
                    ProgressView(value:Double(unit.health),total:Double(max(1,unit.maximumHealth))).tint(.green)
                    Text("\(unit.health)/\(unit.maximumHealth)").font(.system(size:17,weight:.bold))
                }.frame(width:150).padding(6).background(.black.opacity(0.7),in:RoundedRectangle(cornerRadius:8)).offset(y:-size*0.9)
            }
        }.frame(width:size,height:size)
    }
    private func monster(_ id:String,dead:Bool,cue:UnitPresentation?,age:Double,time:Double)->some View {
        let name="MeadowMonster"+id.prefix(1).uppercased()+id.dropFirst()
        let hurt=cue?.motion == "hurt" && age>=0.46
        let attack=cue?.motion == "attack" && age>=0
        let deathAge=max(0,age-0.46)
        let frame=dead ? min(39,Int(deathAge/0.8*40)):hurt ? 48+min(7,Int((age-0.46)/0.4*8)):attack ? 12+min(23,Int(age/0.96*24)):Int(time.truncatingRemainder(dividingBy:2.4)/2.4*12)
        let image=MeadowBridgeAssets.cell(name+(dead ? "Death":"Motion"),column:frame%8,row:frame/8,columns:8,rows:dead ? 5:7)
        return Group { if let image { Image(uiImage:image).resizable().interpolation(.none).scaledToFit() } }.opacity(dead && (age<0 || deathAge>=0.8) ? 0:1)
    }
    private func effectColor(_ cue:UnitPresentation?)->Color {
        if cue?.effects.contains("heal") == true || cue?.effects.contains("revive") == true { return .green }
        if cue?.effects.contains("flame") == true { return .orange };return .cyan
    }
    private func effects(_ cue:UnitPresentation,skillID:String?,age:Double,size:Double)->some View {
        let t=max(0,min(1,(age-0.46)/0.64))
        return ZStack {
            if age>=0.46 && (cue.effects.contains("impact") || cue.effects.contains("natural20")) {
                art("BattleVFXBurst").scaledToFit().frame(width:size*1.2*(0.5+t),height:size*1.2*(0.5+t)).opacity((1-t)*(1-t)).blendMode(.plusLighter)
            }
            if let image=skillImage(cue,skillID:skillID,age:age) {
                Image(uiImage:image).resizable().interpolation(.none).scaledToFit().frame(width:size*1.8,height:size*1.8).blendMode(.plusLighter)
            }
            ForEach(0..<(age>=0.46 && !cue.effects.isEmpty ? 18:0),id:\.self) { i in
                let a=Double(i)*2.399, radius=size*(0.1+t*0.9)
                RoundedRectangle(cornerRadius:1).fill(i%3 == 0 ? Color.yellow:effectColor(cue))
                    .frame(width:i%3 == 0 ? 5:3,height:8).rotationEffect(.radians(a+t*2))
                    .offset(x:cos(a)*radius,y:sin(a)*radius*0.6-t*size*0.25).opacity(1-t)
            }
        }.allowsHitTesting(false)
    }
    private func skillImage(_ cue:UnitPresentation,skillID:String?,age:Double)->UIImage? {
        let impact=cue.effects.contains("impact") || cue.effects.contains("natural20")
        let recovery=cue.effects.contains("heal") || cue.effects.contains("revive") || cue.effects.contains("shield")
        guard impact || recovery else { return nil }
        let mainCast=["runeWard","dragonSoulWard","dragonScaleWard","rally"].contains(skillID ?? "")
        let start=impact ? (skillID == "runeSlash" ? 0.22:0.46):mainCast ? 0.0:0.72
        guard age>=start else { return nil }
        let progress = impact && skillID == "runeSlash" ? (age<0.46 ? (age-0.22)/0.24*0.5:0.5+(age-0.46)/0.84*0.5):max(0,age-start)/(1.3-start)
        let index=min(19,Int(progress*20))
        if impact && skillID == "runeSlash" { return MeadowBridgeAssets.image(String(format:"MeadowRuneSlashAttack%02d",index+1)) }
        if impact && skillID == "dragonFlame" { return MeadowBridgeAssets.image(String(format:"MeadowDragonFlame%02d",index+1)) }
        if cue.effects.contains("shield") && skillID == "runeWard" { return MeadowBridgeAssets.image(String(format:"MeadowRuneWardCast%02d",index+1)) }
        let sheets:[String:(String,Int,Int)]=[
            "starlightPulse":("MeadowBattleVFXStarlightPulse",5,4),"rally":("MeadowBattleVFXRally",5,4),
            "sweep":("MeadowBattleVFXSweep",5,4),"dragonSoulWard":("MeadowBattleVFXDragonSoulWard",5,4),
            "dragonScaleWard":("MeadowBattleVFXDragonScaleWard",4,5)]
        if let sheet=sheets[skillID ?? ""] { return MeadowBridgeAssets.cell(sheet.0,column:index%sheet.1,row:index/sheet.1,columns:sheet.1,rows:sheet.2) }
        if cue.effects.contains("heal") || cue.effects.contains("revive") {
            let tier=cue.healthChange<4 ? "Micro":cue.healthChange<8 ? "Standard":"Strong"
            return MeadowBridgeAssets.cell("BattleVFXHealing"+tier+"Sheet",column:index%5,row:index/5,columns:5,rows:4)
        }
        return nil
    }
    private var queue:some View {
        HStack(spacing:20) {
            Text("行动顺序").bold()
            ForEach(frame.snapshot.queueIDs,id:\.self) { id in
                if let unit=frame.snapshot.units.first(where: { $0.id == id }) {
                    Text(unit.name).fontWeight(unit.current ? .heavy:.regular).padding(8)
                        .background(unit.current ? Color.yellow.opacity(0.25):Color.clear,in:Capsule())
                }
            }
        }.font(.system(size:22)).frame(height:58).frame(maxWidth:.infinity).background(.black.opacity(0.25),in:RoundedRectangle(cornerRadius:12))
    }
    private func playerBars(date:Date)->some View {
        let units=MeadowPublicProjection.units(frame,at:date).filter(\.player)
        return HStack(spacing:12) {
            ForEach(units) { unit in
                VStack(alignment:.leading,spacing:7) {
                    Text(unit.name).font(.system(size:24,weight:.bold)).lineLimit(1)
                    Text("生命 \(unit.health)/\(unit.maximumHealth) · 盾 \(unit.shield)").font(.system(size:20,weight:.semibold))
                    ProgressView(value:Double(unit.health),total:Double(max(1,unit.maximumHealth))).tint(.green)
                    HStack(spacing:5) {
                        ForEach(0..<max(0,min(20,unit.ap)),id:\.self) { _ in Image(systemName:"diamond.fill").foregroundStyle(.yellow) }
                        if unit.ap>20 { Text("×\(unit.ap)") }
                        Spacer(minLength:0)
                        Text("金 \(unit.coins) · 分 \(unit.score)")
                    }.font(.system(size:18,weight:.bold))
                }.padding(12).frame(maxWidth:.infinity).background(.black.opacity(0.35),in:RoundedRectangle(cornerRadius:12))
            }
        }.frame(height:136)
    }
}
