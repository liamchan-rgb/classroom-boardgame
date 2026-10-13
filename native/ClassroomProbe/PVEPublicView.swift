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
        return GamePanel {
            VStack(alignment:.leading,spacing:8) {
                Text((frame.snapshot.nodes.first { $0.id == node }?.name ?? "已揭示地点")+" · 战斗").font(.system(size:30,weight:.bold))
                TimelineView(.animation(minimumInterval:1.0/30,paused:frame.presentations.isEmpty || reduced)) { context in
                    let event = frame.presentations.first { $0.isVisible(at:context.date) }
                    HStack(alignment:.center,spacing:8) {
                        unitGroup(local.filter(\.player),event:event)
                        unitGroup(local.filter { !$0.player },event:event)
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                }
            }
        }
    }
    private func unitGroup(_ units:[PublicGameUnit],event:CommittedPresentation?) -> some View {
        let columns = units.count > 4 ? 3 : units.count > 1 ? 2 : 1
        return LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:6),count:columns),spacing:4) {
            ForEach(units) { unit in
                VStack(spacing:2) {
                    UnitPortrait(unit:unit,event:event,animate:!frame.presentations.isEmpty).frame(height:units.count > 4 ? 60 : units.count > 3 ? 82 : 120)
                        .overlay(alignment:.bottom) {
                            Text(identity(unit)).font(.system(size:14,weight:.bold)).padding(.horizontal,6).background(.white,in:Capsule())
                        }
                        .overlay(alignment:.top) {
                            if unit.current { Image(systemName:"arrowtriangle.down.fill").font(.system(size:14)).foregroundStyle(GameTheme.primary) }
                        }
                    ResourceValue(id:"health",text:"\(unit.health)/\(unit.maximumHealth)")
                    ResourceValue(id:"shield",text:String(unit.shield))
                    if unit.health == 0 { Text(unit.player ? "倒地" : "战败").foregroundStyle(GameTheme.danger) }
                    else if unit.canActFromRound > frame.snapshot.round { Label("下轮",systemImage:"clock") }
                }.font(.system(size:22,weight:.semibold)).padding(3)
            }
        }.frame(maxWidth:.infinity)
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
