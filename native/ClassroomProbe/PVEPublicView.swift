import SwiftUI
import UIKit
import ClassroomGameCore

struct PVEPublicView:View {
    let frame:PublicPlayFrame
    let image:UIImage?
    let showingBook:Bool
    var body:some View {
        GeometryReader { geometry in
            let width = geometry.size.width/geometry.size.height > 1.5 ? 1920.0 : 1440.0
            let scale = min(geometry.size.width/width,geometry.size.height/1080)
            content(width:width).frame(width:width,height:1080).scaleEffect(scale,anchor:.center)
                .frame(width:geometry.size.width,height:geometry.size.height)
        }.background(GameTheme.background).foregroundStyle(GameTheme.ink).preferredColorScheme(.light)
    }
    private func content(width:Double) -> some View {
        VStack(spacing:16) {
            header
            if showingBook {
                Group {
                    if let image { Image(uiImage:image).resizable().scaledToFit() }
                    else { Text("教师正在准备绘本").font(.system(size:36)) }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                PublicPlayerStrip(players:frame.snapshot.units.filter(\.player),fontSize:26).frame(height:244)
            } else {
                HStack(spacing:24) {
                    GamePanel {
                        VStack(alignment:.leading,spacing:8) {
                            Text("当前地图").font(.system(size:30,weight:.bold))
                            PVEMapView(nodes:frame.snapshot.nodes,roads:frame.snapshot.roads,units:frame.snapshot.units,publicDisplay:true)
                        }
                    }.frame(width:(width*0.90-24)*0.44)
                    battlePanel
                }.frame(maxHeight:.infinity)
                queue.frame(height:80)
                if let details = frame.currentDetails,
                   let player = frame.snapshot.units.first(where: { $0.id == details.unitID }), player.player,
                   player.current {
                    turnDetails(details,player:player).frame(height:(details.skills.count > 3 ? 250.0 : 224.0)+Double(max(0,(details.items.count+4)/5-1))*38)
                }
            }
        }.padding(.horizontal,width*0.05).padding(.vertical,54)
            .overlay(alignment:.center) { CommittedFeedback(events:frame.presentations).padding(.horizontal,width*0.07) }
    }
    private var header:some View {
        HStack(spacing:20) {
            Text(showingBook ? "课堂绘本" : frame.snapshot.phase.displayName).font(.system(size:30,weight:.bold))
            if !showingBook {
                Text(frame.snapshot.currentName.map { "行动中："+$0 } ?? "探索 · 选择道路前进")
                    .font(.system(size:34,weight:.bold)).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
            } else { Spacer() }
            if frame.verification { Text("规则验证").font(.system(size:24)).foregroundStyle(GameTheme.accent) }
            if frame.snapshot.round > 0 {
                VStack(alignment:.trailing,spacing:2) {
                    Text("第\(frame.snapshot.round)轮").font(.system(size:24))
                    Text((frame.snapshot.paused ? "已暂停 · " : "")+"\(Int(ceil(frame.snapshot.remainingSeconds)))秒")
                        .font(.system(size:28,weight:.bold)).monospacedDigit()
                }.fixedSize()
            }
        }.padding(.horizontal,24).frame(height:60).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16))
    }
    private var queue:some View {
        let byID = Dictionary(uniqueKeysWithValues:frame.snapshot.units.map { ($0.id,$0) })
        let ids = frame.snapshot.queueIDs.isEmpty ? frame.snapshot.units.map(\.id) : frame.snapshot.queueIDs
        return TimelineView(.animation(minimumInterval:1.0/30,paused:frame.presentations.isEmpty)) { context in
        HStack(spacing:12) {
            ForEach(ids,id:\.self) { id in
                if let unit = byID[id] {
                    ZStack(alignment:.top) {
                        UnitPortrait(unit:unit,event:frame.presentations.first { $0.isVisible(at:context.date) },animate:!frame.presentations.isEmpty).frame(width:64,height:64)
                            .background(.white,in:Circle()).overlay(Circle().stroke(unit.current ? GameTheme.primary : GameTheme.primary.opacity(0.3),lineWidth:unit.current ? 4 : 1))
                        if unit.current { Image(systemName:"arrowtriangle.down.fill").offset(y:-8) }
                        if unit.health == 0 { Image(systemName:"xmark").font(.system(size:28,weight:.heavy)).foregroundStyle(GameTheme.danger) }
                        else if unit.canActFromRound > frame.snapshot.round && frame.snapshot.round > 0 { Image(systemName:"clock.fill").offset(x:22,y:0) }
                        else if unit.acted { Image(systemName:"checkmark.circle.fill").offset(x:22,y:0) }
                        HStack(spacing:2) {
                            if unit.player { TeamMark(id:unit.teamID).font(.system(size:12)) }
                            Text(identity(unit)).font(.system(size:16,weight:.bold))
                        }.padding(2).background(.white,in:Capsule()).offset(y:49)
                    }.frame(maxWidth:.infinity)
                }
            }
        }.padding(8).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16))
        }
    }
    private func identity(_ unit:PublicGameUnit) -> String {
        let peers = frame.snapshot.units.filter { $0.player == unit.player }.sorted { $0.id < $1.id }
        return unit.host ? "主持" : (unit.player ? "" : "敌")+String((peers.firstIndex { $0.id == unit.id } ?? 0)+1)
    }
    private var battlePanel:some View {
        let current = frame.snapshot.units.first(where: \.current)
        let node = current?.nodeID ?? frame.snapshot.units.first(where: \.player)?.nodeID
        let local = frame.snapshot.units.filter { $0.nodeID == node }
        return GamePanel {
            VStack(alignment:.leading,spacing:8) {
                Text((frame.snapshot.nodes.first { $0.id == node }?.name ?? "已揭示地点") + (frame.snapshot.round > 0 ? " · 战斗" : " · 探索"))
                    .font(.system(size:30,weight:.bold))
                TimelineView(.animation(minimumInterval:1.0/30,paused:frame.presentations.isEmpty)) { context in
                    let event = frame.presentations.first { $0.isVisible(at:context.date) }
                    HStack(alignment:.center,spacing:8) {
                        unitGroup(local.filter(\.player),event:event)
                        unitGroup(local.filter { !$0.player },event:event)
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    private func unitGroup(_ units:[PublicGameUnit],event:CommittedPresentation?) -> some View {
        let columns = units.count > 4 ? 3 : units.count > 1 ? 2 : 1
        return LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:6),count:columns),spacing:4) {
            ForEach(units) { unit in
                VStack(spacing:2) {
                    UnitPortrait(unit:unit,event:event,animate:true).frame(height:units.count > 4 ? 64 : units.count > 3 ? 90 : 140)
                    ResourceValue(id:"health",text:"\(unit.health)/\(unit.maximumHealth)")
                    ResourceValue(id:"shield",text:String(unit.shield))
                    if unit.health == 0 { Text(unit.player ? "倒地" : "战败").foregroundStyle(GameTheme.danger) }
                    else if unit.canActFromRound > frame.snapshot.round && frame.snapshot.round > 0 { Label("下轮",systemImage:"clock") }
                }.font(.system(size:24,weight:.semibold)).padding(4)
            }
        }.frame(maxWidth:.infinity)
    }
    private func turnDetails(_ detail:PublicTurnDetails,player:PublicGameUnit) -> some View {
        GamePanel {
            VStack(alignment:.leading,spacing:8) {
                HStack(spacing:24) {
                    Text(detail.className).fontWeight(.bold)
                    ResourceValue(id:"health",text:"\(player.health)/\(player.maximumHealth)")
                    ResourceValue(id:"shield",text:String(player.shield))
                    ResourceValue(id:"coin",text:String(player.coins))
                    ResourceValue(id:"score",text:String(player.score))
                    TeamMark(id:player.teamID); Text(player.team)
                }.font(.system(size:26))
                HStack(alignment:.top,spacing:10) {
                    ForEach(detail.skills) { skill in
                        VStack(alignment:.leading,spacing:4) {
                            HStack { Text(skill.name).bold(); Spacer(minLength:0); Text("\(skill.cost)行动点") }
                            Text(skill.detail).fixedSize(horizontal:false,vertical:true)
                        }.font(.system(size:24)).padding(8).frame(maxWidth:.infinity,alignment:.leading)
                            .background(GameTheme.primary.opacity(0.06),in:RoundedRectangle(cornerRadius:12))
                    }
                }
                InlineFlow(spacing:8) {
                    Text("个人道具").bold()
                    if detail.items.isEmpty { Text("暂无") }
                    ForEach(detail.items) { item in
                        HStack(spacing:4) {
                            ArtImage(type:"items",id:item.id).frame(width:28,height:28)
                            Text("\(item.name)×\(item.quantity)")
                        }
                    }
                }.font(.system(size:24)).fixedSize(horizontal:false,vertical:true)
            }
        }
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
