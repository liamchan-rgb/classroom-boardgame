import SwiftUI
import UIKit
import ClassroomGameCore
import MeadowWorldSupport
import MeadowClassroomSupport

/// The only external entry point. It contains no configuration/editor surfaces
/// or teacher notes, and embeds the actual existing demo renderer.
struct PublicSurface:View {
    @ObservedObject var model:PublicDisplayModel
    @ObservedObject var game:MeadowTeacherCoordinator
    var teacherPreview=false
    var body:some View {
        Group {
            if game.surface == .book {PublicBookPage(model:model,players:game.backend.bookPlayers)}
            else {
                GeometryReader { geometry in
                    let rect=ClassroomCanvas.fitted(in:geometry.size)
                    ZStack {
                    if teacherPreview && game.externalConnected {MeadowTeacherMirror(mirror:game.frameMirror)}
                    else if game.renderer != nil {MeadowRendererHost(game:game)}
                    else{Color(red:0.07,green:0.12,blue:0.08);Text("林间旅程 · 等待教师开始").font(.largeTitle.bold()).foregroundStyle(.white)}
                    if case .inventory(let id)=game.surface,let c=game.campaign,let unit=c.engine.state.units[id] {
                        PublicInventoryPanel(unit:unit,catalog:c.engine.catalog).padding(40)
                    }
                    if game.surface == .results,let c=game.campaign,let result=c.snapshot.completion {
                        VStack(spacing:20){Text(result.outcome=="victory" ? "行程完成":"本次旅程结束").font(.largeTitle.bold());ForEach(result.players){u in Text("\(u.name) · 积分 \(u.score) · 金币 \(u.coins)").font(.title2)}}
                            .padding(40).foregroundStyle(.white).background(Color(red:0.08,green:0.15,blue:0.1).opacity(0.96),in:RoundedRectangle(cornerRadius:20))
                    }
                    }
                    .frame(width:ClassroomCanvas.size.width,height:ClassroomCanvas.size.height)
                    .scaleEffect(rect.width/ClassroomCanvas.size.width)
                    .position(x:rect.midX,y:rect.midY)
                }.allowsHitTesting(false)
            }
        }.background(.black)
    }
}

/// Same read-only page on TV and in the teacher's book preview.
struct PublicBookPage:View {
    @ObservedObject var model:PublicDisplayModel
    let players:[ClassroomBookPlayerStatus]
    var body:some View {
        GeometryReader { geometry in
            let height=ClassroomBookStatusLayout.height(in:geometry.size,players:players.count)
            VStack(spacing:0){
                ZStack(alignment:.topTrailing){
                    Group {
                        if let image=model.image {Image(uiImage:image).resizable().scaledToFit()}
                        else{Text("教师正在准备绘本").font(.title)}
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                    Text("\(model.snapshot.pageCount==0 ? 0:model.snapshot.pageIndex+1) / \(model.snapshot.pageCount)")
                        .font(.caption.bold()).padding(6).background(.black.opacity(0.45),in:RoundedRectangle(cornerRadius:6)).padding(6)
                }.frame(height:max(0,geometry.size.height-height))
                if height>0 {
                    HStack(spacing:4){
                        ForEach(players){unit in BookPlayerBadge(unit:unit,height:height).frame(maxWidth:.infinity)}
                    }.padding(.horizontal,6).frame(height:height).background(Color(red:0.06,green:0.11,blue:0.08)).clipped()
                }
            }
        }.foregroundStyle(.white).background(.black).allowsHitTesting(false)
    }
}
private struct BookPlayerBadge:View {
    let unit:ClassroomBookPlayerStatus
    let height:CGFloat
    private func number(_ value:Int)->String {value.formatted(.number.notation(.compactName).locale(Locale(identifier:"zh_CN")))}
    var body:some View {
        VStack(alignment:.leading,spacing:1){
            Text(unit.name).font(.system(size:min(16,max(8,height*0.24)),weight:.bold)).foregroundStyle(unit.health>0 ? Color.white:.gray)
            HStack(spacing:3){
                Text("HP \(number(unit.health))/\(number(unit.maximumHealth))")
                ProgressView(value:Double(unit.health),total:Double(max(1,unit.maximumHealth))).tint(.green).frame(maxWidth:.infinity)
            }.font(.system(size:min(14,max(8,height*0.21)),weight:.medium))
            HStack(spacing:3){Text("◆ \(number(unit.ap))/\(number(unit.maximumAP))");Spacer(minLength:0);Text("金币 \(number(unit.coins))")}
                .font(.system(size:min(14,max(8,height*0.21)),weight:.semibold)).foregroundStyle(Color(red:0.94,green:0.81,blue:0.46))
        }.lineLimit(1).minimumScaleFactor(0.45).padding(.horizontal,3)
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("\(unit.name)，生命\(unit.health)/\(unit.maximumHealth)，行动点\(unit.ap)/\(unit.maximumAP)，金币\(unit.coins)")
    }
}

private struct PublicInventoryPanel:View {
    let unit:GameUnit
    let catalog:GameCatalog
    private let gold=Color(red:0.91,green:0.77,blue:0.43)
    var body:some View {
        VStack(alignment:.leading,spacing:18){
            Text(unit.name+" · 行囊与装备").font(.system(size:32,weight:.heavy,design:.serif))
            HStack(spacing:24){
                ForEach(ItemSlot.allCases,id:\.rawValue){slot in
                    let id=unit.equipment[slot]
                    let name=id.flatMap{try? catalog.item($0).name} ?? "未装备"
                    VStack(alignment:.leading,spacing:8){Text(slot.rawValue=="weapon" ? "武器":slot.rawValue=="armor" ? "衣装":"饰品").font(.title3);Text(name).font(.title2.bold())}
                        .frame(maxWidth:.infinity,alignment:.leading).padding().background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:12))
                }
            }
            ScrollView {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:220))],spacing:14){
                    ForEach(unit.inventory.keys.sorted(),id:\.self){id in
                        if let count=unit.inventory[id],count>0,let item=try? catalog.item(id){
                            HStack{Image(systemName:"shippingbox.fill");Text(item.name).bold();Spacer();Text("×\(count)")}.font(.title3).padding(18)
                                .background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:10))
                        }
                    }
                }
            }
            Text("生命 \(unit.health) · 护盾 \(unit.shield) · 金币 \(unit.coins) · 积分 \(unit.score)").font(.title3.bold())
        }.padding(28).foregroundStyle(gold).background(Color(red:0.08,green:0.15,blue:0.1).opacity(0.98),in:RoundedRectangle(cornerRadius:20))
    }
}
