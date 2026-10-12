import SwiftUI
import UIKit
import ClassroomGameCore

struct PVEPublicView:View {
    let frame:PublicPlayFrame
    let image:UIImage?
    let showingBook:Bool
    var body:some View {
        GeometryReader { geometry in
            let base = min(30.0,max(16.0,Double(geometry.size.width)/52))
            VStack(alignment:.leading,spacing:16) {
                HStack(alignment:.center) {
                    Text(showingBook ? "英语课堂 · 绘本" : "课堂桌游 · \(frame.snapshot.phase.displayName)").font(.system(size:base+8,weight:.bold))
                    if frame.verification { Text("规则验证").font(.system(size:base-2)).padding(8).background(GameTheme.accent.opacity(0.12),in:Capsule()) }
                    Spacer()
                    if frame.snapshot.round > 0 {
                        Text("第\(frame.snapshot.round)轮").font(.system(size:base))
                        Text(frame.snapshot.paused ? "已暂停" : "\(Int(ceil(frame.snapshot.remainingSeconds)))秒")
                            .font(.system(size:base+12,weight:.bold,design:.rounded)).monospacedDigit()
                    }
                }
                if showingBook {
                    if let image { Image(uiImage:image).resizable().scaledToFit().frame(maxWidth:.infinity,maxHeight:.infinity) }
                    else { Text("教师正在准备绘本").font(.largeTitle).frame(maxWidth:.infinity,maxHeight:.infinity) }
                } else {
                    gameContent(base:base)
                }
                PublicPlayerStrip(players:frame.snapshot.units.filter(\.player),showAP:!showingBook,fontSize:max(14,base-3))
            }.padding(max(18,geometry.size.width*0.025))
                .foregroundStyle(GameTheme.ink).frame(maxWidth:.infinity,maxHeight:.infinity).background(GameTheme.background)
        }
    }
    private func gameContent(base:Double) -> some View {
        VStack(alignment:.leading,spacing:12) {
            if frame.snapshot.round > 0 {
                Text("当前：\(frame.snapshot.currentName ?? "等待教师处理")").font(.system(size:base+5,weight:.semibold))
                Text("队列：" + frame.snapshot.queue.joined(separator:" → ")).font(.system(size:base-2)).lineLimit(2)
            } else { Text("探索阶段 · 选择道路前进").font(.system(size:base+4,weight:.semibold)) }
            HStack(alignment:.top,spacing:18) {
                PVEMapView(nodes:frame.snapshot.nodes,roads:frame.snapshot.roads,units:frame.snapshot.units)
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                VStack(alignment:.leading,spacing:12) {
                    ForEach(frame.snapshot.units.filter { !$0.player }) { enemy in
                        VStack(alignment:.leading,spacing:5) {
                            Text(enemy.name).font(.system(size:base,weight:.bold))
                            Text("生命 \(enemy.health)/\(enemy.maximumHealth)")
                            Text("护盾 \(enemy.shield) · AP \(enemy.ap)")
                            if enemy.health == 0 { Text("已击败").foregroundStyle(GameTheme.muted) }
                        }.font(.system(size:base-3)).padding(12).frame(maxWidth:.infinity,alignment:.leading)
                            .background(.white,in:RoundedRectangle(cornerRadius:14))
                    }
                }.frame(width:max(160,min(300,base*10)))
            }.frame(maxHeight:.infinity)
            if !frame.snapshot.dice.isEmpty {
                Text(frame.snapshot.dice.map { dice in
                    (dice.source == "initiative" ? "先攻 " : "") + dice.formula.label + "：" + dice.values.map(String.init).joined(separator:"、") + (dice.naturalTwenty ? " 自然20！" : "")
                }.joined(separator:"  ·  ")).font(.system(size:base,weight:.bold)).lineLimit(2)
            }
            ForEach(Array(frame.log.suffix(3).enumerated()),id:\.offset) { _,line in Text(line).font(.system(size:base-3)).lineLimit(1) }
        }.frame(maxHeight:.infinity)
    }
}
struct PublicPlayerStrip:View {
    let players:[PublicGameUnit]
    let showAP:Bool
    let fontSize:Double
    var body:some View {
        HStack(alignment:.top,spacing:8) {
            ForEach(players) { player in
                VStack(alignment:.leading,spacing:5) {
                    Text(player.name + (player.host ? " · 主持人" : "")).fontWeight(.bold).lineLimit(2)
                    Text("生命\(player.health)/\(player.maximumHealth)")
                    Text("护盾\(player.shield)" + (showAP ? " · AP\(player.ap)" : ""))
                    Text("金币\(player.coins) · 分\(player.score)")
                    Text(player.health == 0 ? player.team + " · 倒地" : player.team)
                }.font(.system(size:fontSize)).minimumScaleFactor(0.8).frame(maxWidth:.infinity,alignment:.leading)
                    .padding(10).background(.white,in:RoundedRectangle(cornerRadius:12))
                    .overlay(RoundedRectangle(cornerRadius:12).stroke(player.current ? GameTheme.accent : .clear,lineWidth:3))
            }
        }
    }
}
