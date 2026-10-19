import SwiftUI
import UIKit
import ClassroomGameCore

struct PVEPublicView:View {
    let frame:PublicPlayFrame
    let image:UIImage?
    let showingBook:Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.presentationReduceMotion) private var forcedReduced
    private var reduced:Bool { systemReduced || forcedReduced }
    var body:some View {
        GeometryReader { geometry in
            let width = geometry.size.width/geometry.size.height > 1.5 ? 1920.0 : 1440.0
            let scale = min(geometry.size.width/width,geometry.size.height/1080)
            TimelineView(.animation(minimumInterval:1.0/30,paused:frame.presentations.isEmpty || reduced)) { context in
                content(width:width,date:context.date).frame(width:width,height:1080).scaleEffect(scale,anchor:.center)
                    .frame(width:geometry.size.width,height:geometry.size.height)
            }
        }.background(GameTheme.background).foregroundStyle(GameTheme.ink).preferredColorScheme(.light)
    }
    private func content(width:Double,date:Date) -> some View {
        let arriving = reduced ? nil : frame.presentations.first { $0.opensBattleAfterArrival && date < $0.end }
        let battleVisible = frame.snapshot.round > 0 && arriving == nil
        var camera = frame.camera
        if frame.followsCurrent, let move = arriving?.mapMoves.first, let a = move.points.first, let b = move.points.last {
            camera = MapCamera(x:(a.x+b.x)/2,y:(a.y+b.y)/2,zoom:min(1.35,camera.zoom))
        }
        return VStack(spacing:14) {
            header(arrival:arriving)
            if showingBook {
                Group {
                    if let image { Image(uiImage:image).resizable().scaledToFit() }
                    else { Text("教师正在准备绘本").font(.system(size:36)) }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                PublicPlayerStrip(players:frame.snapshot.units.filter(\.player),fontSize:26).frame(height:244)
            } else {
                HStack(spacing:20) {
                    GamePanel(inset:12) {
                        PVEMapView(nodes:frame.snapshot.nodes,roads:frame.snapshot.roads,units:frame.snapshot.units,
                                   publicDisplay:true,camera:camera,events:frame.presentations,round:frame.snapshot.round)
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                    if battleVisible {
                        battlePanel.frame(width:(width*0.9-20)*0.56).transition(.move(edge:.trailing).combined(with:.opacity))
                    }
                }.frame(maxHeight:.infinity).animation(reduced ? nil : .easeInOut(duration:0.2),value:battleVisible)
                if battleVisible {
                    queue.frame(height:104)
                    if let details = frame.currentDetails,
                       let player = frame.snapshot.units.first(where: { $0.id == details.unitID }), player.player, player.current {
                        turnDetails(details,player:player).frame(height:details.skills.count > 3 ? 382 : 276)
                    }
                } else { explorationFooter(arriving:arriving != nil).frame(height:60) }
            }
        }.padding(.horizontal,width*0.05).padding(.vertical,54)
            .overlay(alignment:.center) { CommittedFeedback(events:frame.presentations).padding(.horizontal,width*0.07) }
    }
    private func header(arrival:CommittedPresentation?) -> some View {
        let arriving = arrival != nil
        let movingName = arrival?.mapMoves.first.flatMap { move in frame.snapshot.units.first { $0.id == move.unitID }?.name }
        return HStack(spacing:18) {
            Text(showingBook ? "课堂绘本" : arriving ? "前往地点" : frame.snapshot.phase.displayName).font(.system(size:30,weight:.bold))
            if !showingBook {
                Text(movingName.map { "移动："+$0 } ?? frame.snapshot.currentName.map { "行动中："+$0 } ??
                     frame.snapshot.units.first(where: { $0.id == frame.cameraFocusID }).map { "查看："+$0.name } ?? "沿道路前进")
                    .font(.system(size:34,weight:.bold)).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
            } else { Spacer() }
            if frame.verification { Text("规则验证").font(.system(size:24)).foregroundStyle(GameTheme.accent) }
            if frame.snapshot.round > 0 && !arriving {
                VStack(alignment:.trailing,spacing:2) {
                    Text("第\(frame.snapshot.round)轮").font(.system(size:24))
                    Text((frame.snapshot.paused ? "已暂停 · " : "")+"\(Int(ceil(frame.snapshot.remainingSeconds)))秒")
                        .font(.system(size:28,weight:.bold)).monospacedDigit()
                }.fixedSize()
            }
        }.padding(.horizontal,24).frame(height:60).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16))
    }
    private func explorationFooter(arriving:Bool) -> some View {
        HStack(spacing:22) {
            Label(arriving ? "到达后展开战斗" : "探索地图",systemImage:arriving ? "figure.walk" : "map").fontWeight(.bold)
            if let unit = frame.snapshot.units.first(where: { $0.id == frame.cameraFocusID }) {
                ResourceValue(id:"health",text:"\(unit.health)/\(unit.maximumHealth)")
                ResourceValue(id:"shield",text:String(unit.shield))
                ResourceValue(id:"coin",text:String(unit.coins))
                ResourceValue(id:"score",text:String(unit.score))
                TeamMark(id:unit.teamID); Text(unit.team)
            } else { Text("角色落点显示于地图 · 边缘箭头表示视野外玩家") }
            Spacer(minLength:0)
            Text("镜头由教师控制").foregroundStyle(GameTheme.muted)
        }.font(.system(size:22)).padding(.horizontal,18).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16))
    }
    private var queue:some View {
        let byID = Dictionary(uniqueKeysWithValues:frame.snapshot.units.map { ($0.id,$0) })
        let ids = frame.snapshot.queueIDs
        let current = ids.firstIndex { byID[$0]?.current == true } ?? 0
        return GeometryReader { geometry in
            let step = geometry.size.width/Double(max(1,ids.count))
            ZStack(alignment:.top) {
                Canvas { context,size in
                    var full = Path(); full.move(to:CGPoint(x:step/2,y:39)); full.addLine(to:CGPoint(x:size.width-step/2,y:39))
                    context.stroke(full,with:.color(GameTheme.primary.opacity(0.18)),style:StrokeStyle(lineWidth:10,lineCap:.round))
                    var done = Path(); done.move(to:CGPoint(x:step/2,y:39)); done.addLine(to:CGPoint(x:step*(Double(current)+0.5),y:39))
                    context.stroke(done,with:.color(GameTheme.primary),style:StrokeStyle(lineWidth:10,lineCap:.round))
                }
                HStack(spacing:0) {
                    ForEach(ids,id:\.self) { id in
                        if let unit = byID[id] {
                            VStack(spacing:4) {
                                ZStack(alignment:.topTrailing) {
                                    UnitPortrait(unit:unit).frame(width:54,height:54)
                                        .background(.white,in:Circle())
                                        .overlay(Circle().stroke(unit.current ? GameTheme.primary : GameTheme.primary.opacity(0.30),lineWidth:unit.current ? 4 : 1))
                                    if unit.health == 0 { Image(systemName:"xmark").font(.system(size:28,weight:.heavy)).foregroundStyle(GameTheme.danger) }
                                    else if unit.canActFromRound > frame.snapshot.round { Image(systemName:"clock.fill").font(.system(size:20)) }
                                    else if unit.acted { Image(systemName:"checkmark.circle.fill").font(.system(size:20)) }
                                    if unit.current { Image(systemName:"arrowtriangle.down.fill").offset(x:-19,y:-15) }
                                }
                                HStack(spacing:3) {
                                    if unit.player { TeamMark(id:unit.teamID).font(.system(size:12)) }
                                    Text(identity(unit)).font(.system(size:16,weight:.bold))
                                }
                            }.frame(maxWidth:.infinity).padding(.top,12)
                        }
                    }
                }
            }
        }.padding(.horizontal,16).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16))
    }
    private func identity(_ unit:PublicGameUnit) -> String {
        let peers = frame.snapshot.units.filter { $0.player == unit.player }.sorted { $0.id < $1.id }
        return unit.host ? "主持" : (unit.player ? "" : "敌")+String((peers.firstIndex { $0.id == unit.id } ?? 0)+1)
    }
    private var battlePanel:some View {
        let current = frame.snapshot.units.first(where:\.current)
        let node = current?.nodeID ?? frame.snapshot.units.first(where:\.player)?.nodeID
        let local = frame.snapshot.units.filter { $0.nodeID == node }
        let allies = local.filter(\.player).sorted {
            if $0.current != $1.current { return $0.current }
            return $0.id < $1.id
        }
        let enemies = local.filter { !$0.player }
        return GamePanel {
            VStack(alignment:.leading,spacing:8) {
                HStack(alignment:.firstTextBaseline) {
                    Text((frame.snapshot.nodes.first { $0.id == node }?.name ?? "已揭示地点")+" · 战斗").font(.system(size:30,weight:.bold))
                    Spacer(minLength:4)
                    Text("横向战场实验").font(.system(size:17,weight:.semibold)).foregroundStyle(GameTheme.muted)
                }
                SideViewBattleStage(allies:allies,enemies:enemies,round:frame.snapshot.round)
                    .frame(maxWidth:.infinity,maxHeight:.infinity).frame(minHeight:260)
                HStack(alignment:.top,spacing:8) {
                    battleRoster("同行",units:allies)
                    Rectangle().fill(GameTheme.primary.opacity(0.18)).frame(width:1)
                    battleRoster("敌方",units:enemies)
                }.frame(height:104)
            }
        }
    }
    private func battleRoster(_ title:String,units:[PublicGameUnit]) -> some View {
        VStack(alignment:.leading,spacing:4) {
            HStack(spacing:5) {
                Text(title).font(.system(size:15,weight:.bold))
                Text("\(units.count)").font(.system(size:13,weight:.semibold)).foregroundStyle(GameTheme.muted)
            }
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:min(4,max(1,units.count))),spacing:4) {
            ForEach(units) { unit in
                VStack(alignment:.leading,spacing:2) {
                    HStack(spacing:3) {
                        if unit.current { Image(systemName:"arrowtriangle.right.fill").foregroundStyle(GameTheme.primary) }
                        Text(identity(unit)).fontWeight(.bold).lineLimit(1)
                        Spacer(minLength:0)
                        if unit.canActFromRound > frame.snapshot.round { Image(systemName:"clock.fill").foregroundStyle(GameTheme.muted) }
                    }
                    HStack(spacing:3) {
                        Image(systemName:"heart.fill").foregroundStyle(GameTheme.danger)
                        Text("\(unit.health)/\(unit.maximumHealth)").monospacedDigit()
                        Image(systemName:"shield.fill").foregroundStyle(GameTheme.shield)
                        Text(String(unit.shield)).monospacedDigit()
                    }.font(.system(size:12,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                }.font(.system(size:13)).padding(.horizontal,5).padding(.vertical,4)
                    .frame(maxWidth:.infinity,minHeight:35,alignment:.leading)
                    .background(unit.current ? GameTheme.primary.opacity(0.10) : Color.white.opacity(0.72),in:RoundedRectangle(cornerRadius:8))
                    .overlay(RoundedRectangle(cornerRadius:8).stroke(GameTheme.primary.opacity(unit.current ? 0.32 : 0.08),lineWidth:1))
            }
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func turnDetails(_ detail:PublicTurnDetails,player:PublicGameUnit) -> some View {
        let pages = max(1,(detail.items.count+3)/4)
        let page = min(max(0,frame.itemPage),pages-1)
        let items = Array(detail.items.dropFirst(page*4).prefix(4))
        return GamePanel(inset:14) {
            VStack(alignment:.leading,spacing:8) {
                HStack(spacing:18) {
                    Text(detail.className).fontWeight(.bold)
                    ResourceValue(id:"health",text:"\(player.health)/\(player.maximumHealth)")
                    ResourceValue(id:"shield",text:String(player.shield))
                    ResourceValue(id:"coin",text:String(player.coins))
                    ResourceValue(id:"score",text:String(player.score))
                    TeamMark(id:player.teamID); Text(player.team)
                }.font(.system(size:24))
                HStack(alignment:.top,spacing:16) {
                    VStack(alignment:.leading,spacing:5) {
                        Text("本回合技能").font(.system(size:22,weight:.bold))
                        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:3),spacing:8) {
                            ForEach(detail.skills) { skill in skillCard(skill) }
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    VStack(alignment:.leading,spacing:6) {
                        HStack {
                            Text("个人物品").bold()
                            Spacer(minLength:0)
                            if pages > 1 { Text("\(page+1)/\(pages)页").foregroundStyle(GameTheme.muted) }
                        }.font(.system(size:22))
                        if items.isEmpty { Text("背包暂无物品").font(.system(size:22)).foregroundStyle(GameTheme.muted) }
                        LazyVGrid(columns:[GridItem(.flexible(),spacing:8),GridItem(.flexible(),spacing:8)],spacing:8) {
                            ForEach(items) { item in itemCard(item) }
                        }
                    }.frame(width:320,alignment:.leading)
                }
            }
        }
    }
    private func skillCard(_ skill:PublicSkillDisplay) -> some View {
        VStack(alignment:.leading,spacing:5) {
            HStack(alignment:.top,spacing:4) {
                Text(skill.name).fontWeight(.bold)
                Spacer(minLength:0)
                Text("\(skill.cost)行动点").font(.system(size:18)).fixedSize()
            }.font(.system(size:22))
            Text(skill.detail).font(.system(size:18)).fixedSize(horizontal:false,vertical:true)
            Label(skill.available == false ? (skill.unavailableReason ?? "暂不可用") : "可选择",systemImage:skill.available == false ? "nosign" : "checkmark.circle")
                .font(.system(size:17,weight:.semibold)).fixedSize(horizontal:false,vertical:true)
                .foregroundStyle(skill.available == false ? GameTheme.muted : GameTheme.primary)
        }.padding(9).frame(maxWidth:.infinity,minHeight:174,alignment:.topLeading)
            .background(GameTheme.primary.opacity(skill.available == false ? 0.03 : 0.08),in:RoundedRectangle(cornerRadius:12))
    }
    private func itemCard(_ item:PublicItemDisplay) -> some View {
        VStack(alignment:.leading,spacing:3) {
            HStack(spacing:4) {
                ArtImage(type:"items",id:item.id).frame(width:24,height:24)
                Text(item.name).fontWeight(.semibold).fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:0)
                Text("×\(item.quantity)").monospacedDigit()
            }.font(.system(size:17))
            Text(item.detail).font(.system(size:15)).fixedSize(horizontal:false,vertical:true)
            Label(item.available == false ? (item.unavailableReason ?? "暂不可用") : "可选择",systemImage:item.available == false ? "nosign" : "checkmark.circle")
                .font(.system(size:14)).foregroundStyle(item.available == false ? GameTheme.muted : GameTheme.primary)
                .lineLimit(2)
        }.padding(6).frame(maxWidth:.infinity,minHeight:79,alignment:.topLeading)
            .background(GameTheme.primary.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
    }
}

private struct SideViewBattleStage:View {
    let allies:[PublicGameUnit]
    let enemies:[PublicGameUnit]
    let round:Int
    private var hero:PublicGameUnit? { allies.first(where:\.current) ?? allies.first(where:{$0.health > 0}) ?? allies.first }
    private var leadEnemy:PublicGameUnit? { enemies.first(where:{$0.health > 0}) ?? enemies.first }
    private var usesContactPose:Bool { hero?.templateID == "adventurer" }
    private let contactPoseName = "heavyStrike-trainingSword-side-contact-v1"
    var body:some View {
        GeometryReader { geometry in
            let width = geometry.size.width, height = geometry.size.height
            ZStack(alignment:.topLeading) {
                BattleSceneBackdrop()
                HStack(alignment:.bottom,spacing:0) {
                    ZStack(alignment:.bottom) {
                        Ellipse().fill(Color(red:0.06,green:0.10,blue:0.12).opacity(0.48))
                            .frame(width:width*0.31,height:height*0.075).offset(y:3)
                        if usesContactPose, let image = GameArt.prototypeImage(contactPoseName) {
                            Image(uiImage:image).resizable().interpolation(.high).scaledToFit()
                        } else if let hero {
                            ArtImage(type:"classes",id:hero.templateID).frame(maxWidth:.infinity,maxHeight:.infinity)
                        }
                    }.frame(width:width*0.40,height:height*0.86,alignment:.bottom)
                    Spacer(minLength:0)
                    HStack(alignment:.bottom,spacing:-width*0.025) {
                        ForEach(Array(enemies.prefix(3))) { enemy in
                            let index = enemies.firstIndex { $0.id == enemy.id } ?? 0
                            ZStack(alignment:.bottom) {
                                Ellipse().fill(Color(red:0.06,green:0.10,blue:0.12).opacity(0.40))
                                    .frame(width:width*0.12,height:height*0.06).offset(y:2)
                                ArtImage(type:"monsters",id:enemy.templateID)
                                    .scaleEffect(x:-1,y:1,anchor:.center)
                                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                                    .opacity(enemy.health == 0 ? 0.52 : 1)
                            }.frame(width:width*(enemies.count > 1 ? 0.16 : 0.24),height:height*(index == 0 ? 0.74 : 0.61),alignment:.bottom)
                        }
                    }
                }.padding(.horizontal,width*0.035).padding(.bottom,height*0.045)
                    .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.bottom)
                HStack(alignment:.top,spacing:8) {
                    Label("横向镜头",systemImage:"rectangle.landscape.fill")
                    Spacer(minLength:4)
                    Text("第\(round)轮")
                }.font(.system(size:14,weight:.semibold)).foregroundStyle(.white)
                    .padding(.horizontal,10).padding(.vertical,6)
                    .background(Color.black.opacity(0.28),in:Capsule()).padding(10)
                VStack {
                    Spacer()
                    HStack(alignment:.bottom,spacing:12) {
                        stageName(hero?.name ?? "队伍",color:GameTheme.primary)
                        Spacer(minLength:0)
                        VStack(alignment:.trailing,spacing:3) {
                            Text(usesContactPose ? "动作姿态样片 · 单帧" : "职业角色立绘 · 静态").font(.system(size:12,weight:.semibold))
                                .padding(.horizontal,8).padding(.vertical,4)
                                .background(.regularMaterial,in:Capsule())
                            if let leadEnemy { stageName(leadEnemy.name,color:GameTheme.danger,trailing:true) }
                        }
                    }.padding(10)
                }
            }.frame(width:width,height:height).clipShape(RoundedRectangle(cornerRadius:13))
                .overlay(RoundedRectangle(cornerRadius:13).stroke(Color.white.opacity(0.56),lineWidth:1))
                .accessibilityElement(children:.combine)
                .accessibilityLabel("横向战斗场景实验。左侧\(hero?.name ?? "队伍")，右侧\(leadEnemy?.name ?? "敌方")。展示的是单帧动作姿态样片，不是完整动画。")
        }
    }
    private func stageName(_ name:String,color:Color,trailing:Bool = false) -> some View {
        Text(name).font(.system(size:14,weight:.bold)).lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(GameTheme.ink).padding(.horizontal,9).padding(.vertical,5)
            .frame(maxWidth:220,alignment:trailing ? .trailing : .leading)
            .background(.regularMaterial,in:Capsule())
            .overlay(Capsule().stroke(color.opacity(0.4),lineWidth:1))
    }
}

private struct BattleSceneBackdrop:View {
    var body:some View {
        GeometryReader { geometry in
            let width = geometry.size.width, height = geometry.size.height
            ZStack {
                LinearGradient(colors:[Color(red:0.10,green:0.17,blue:0.25),Color(red:0.31,green:0.43,blue:0.46),Color(red:0.73,green:0.62,blue:0.43)],startPoint:.top,endPoint:.bottom)
                Circle().fill(RadialGradient(colors:[Color(red:1,green:0.83,blue:0.56).opacity(0.74),Color(red:1,green:0.73,blue:0.44).opacity(0)],center:.center,startRadius:2,endRadius:width*0.18))
                    .frame(width:width*0.44,height:height*0.90).position(x:width*0.70,y:height*0.28)
                BattleRidge(points:[CGPoint(x:0,y:0.59),CGPoint(x:0.17,y:0.40),CGPoint(x:0.34,y:0.52),CGPoint(x:0.54,y:0.35),CGPoint(x:0.75,y:0.50),CGPoint(x:0.90,y:0.37),CGPoint(x:1,y:0.48)])
                    .fill(Color(red:0.24,green:0.34,blue:0.39).opacity(0.62))
                BattleRidge(points:[CGPoint(x:0,y:0.69),CGPoint(x:0.16,y:0.55),CGPoint(x:0.33,y:0.65),CGPoint(x:0.52,y:0.51),CGPoint(x:0.74,y:0.64),CGPoint(x:0.90,y:0.50),CGPoint(x:1,y:0.60)])
                    .fill(Color(red:0.14,green:0.25,blue:0.29).opacity(0.78))
                BattleForest(baseY:0.72,scale:0.80).fill(Color(red:0.10,green:0.20,blue:0.22).opacity(0.82))
                BattleRuins().fill(Color(red:0.28,green:0.34,blue:0.34).opacity(0.78))
                BattleGround().fill(LinearGradient(colors:[Color(red:0.38,green:0.35,blue:0.27),Color(red:0.17,green:0.22,blue:0.21)],startPoint:.top,endPoint:.bottom))
                Path { path in
                    path.move(to:CGPoint(x:0,y:height*0.72)); path.addLine(to:CGPoint(x:width,y:height*0.72))
                }.stroke(Color(red:0.89,green:0.68,blue:0.40).opacity(0.46),lineWidth:2)
                BattleForest(baseY:0.94,scale:0.48).fill(Color(red:0.08,green:0.15,blue:0.16).opacity(0.52))
            }.frame(width:width,height:height).clipped()
        }
    }
}

private struct BattleRidge:Shape {
    let points:[CGPoint]
    func path(in rect:CGRect)->Path {
        var path=Path()
        guard let first=points.first else { return path }
        path.move(to:CGPoint(x:0,y:rect.maxY))
        path.addLine(to:CGPoint(x:first.x*rect.width,y:first.y*rect.height))
        for point in points.dropFirst() { path.addLine(to:CGPoint(x:point.x*rect.width,y:point.y*rect.height)) }
        path.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY)); path.closeSubpath()
        return path
    }
}

private struct BattleForest:Shape {
    let baseY:CGFloat
    let scale:CGFloat
    func path(in rect:CGRect)->Path {
        var path=Path()
        for index in 0..<17 {
            let x=rect.width*(CGFloat(index)/16)
            let jitter=CGFloat((index*7)%5)*0.012
            let top=rect.height*(baseY-(0.11+jitter)*scale)
            let base=rect.height*baseY
            let halfWidth=rect.width*(0.018+CGFloat((index*3)%4)*0.002)*scale
            path.move(to:CGPoint(x:x,y:top)); path.addLine(to:CGPoint(x:x-halfWidth,y:base)); path.addLine(to:CGPoint(x:x+halfWidth,y:base)); path.closeSubpath()
            let lowerTop=top+rect.height*0.045*scale
            path.move(to:CGPoint(x:x,y:lowerTop)); path.addLine(to:CGPoint(x:x-halfWidth*1.28,y:base)); path.addLine(to:CGPoint(x:x+halfWidth*1.28,y:base)); path.closeSubpath()
            path.addRect(CGRect(x:x-halfWidth*0.16,y:base,width:halfWidth*0.32,height:rect.height*0.055*scale))
        }
        return path
    }
}

private struct BattleRuins:Shape {
    func path(in rect:CGRect)->Path {
        var path=Path()
        for x:CGFloat in [0.09,0.84] {
            let left=rect.width*x, width=rect.width*0.045
            path.addRoundedRect(in:CGRect(x:left,y:rect.height*0.31,width:width,height:rect.height*0.40),cornerSize:CGSize(width:width*0.12,height:width*0.12))
            path.addRoundedRect(in:CGRect(x:left-width*0.18,y:rect.height*0.29,width:width*1.36,height:rect.height*0.035),cornerSize:CGSize(width:3,height:3))
            for n in 0..<3 {
                path.addRect(CGRect(x:left+width*0.16+CGFloat(n)*width*0.24,y:rect.height*0.43,width:width*0.07,height:rect.height*0.16))
            }
        }
        path.addRoundedRect(in:CGRect(x:rect.width*0.12,y:rect.height*0.30,width:rect.width*0.20,height:rect.height*0.025),cornerSize:CGSize(width:4,height:4))
        return path
    }
}

private struct BattleGround:Shape {
    func path(in rect:CGRect)->Path {
        var path=Path()
        path.move(to:CGPoint(x:0,y:rect.height*0.70))
        path.addLine(to:CGPoint(x:rect.width,y:rect.height*0.70))
        path.addLine(to:CGPoint(x:rect.width,y:rect.height)); path.addLine(to:CGPoint(x:0,y:rect.height)); path.closeSubpath()
        return path
    }
}
struct PublicPlayerStrip:View {
    let players:[PublicGameUnit]
    let fontSize:Double
    var body:some View {
        GeometryReader { geometry in
            let weights = players.map { player in player.name.count > 8 ? 1.4 : 1.0 }
            let available = geometry.size.width-Double(max(0,players.count-1))*8
            let total = weights.reduce(0,+)
            HStack(alignment:.top,spacing:8) {
                ForEach(Array(players.enumerated()),id:\.element.id) { index,player in
                    VStack(alignment:.leading,spacing:4) {
                        Text(player.name).font(.system(size:28,weight:.bold)).fixedSize(horizontal:false,vertical:true).frame(height:72,alignment:.top)
                        ResourceValue(id:"health",text:"\(player.health)/\(player.maximumHealth)")
                        ResourceValue(id:"shield",text:String(player.shield))
                        HStack(spacing:8) {
                            ResourceValue(id:"coin",text:String(player.coins))
                            ResourceValue(id:"score",text:String(player.score))
                        }
                        HStack(spacing:4) {
                            TeamMark(id:player.teamID).font(.system(size:20)); Text(player.team)
                            if player.health == 0 { ArtImage(type:"uiResource",id:"downed").frame(width:22,height:22).accessibilityLabel("倒地") }
                        }
                    }.font(.system(size:fontSize)).padding(10).frame(width:available*weights[index]/max(1,total),alignment:.leading)
                        .background(.regularMaterial,in:RoundedRectangle(cornerRadius:12))
                }
            }
        }
    }
}
