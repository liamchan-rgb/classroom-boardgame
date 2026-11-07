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
    var body:some View {
        Group {
            if game.surface == .book {PublicBookPage(model:model)}
            else {
                ZStack {
                    if game.renderer != nil {MeadowRendererHost(game:game)}
                    else{Color(red:0.07,green:0.12,blue:0.08);Text("林间旅程 · 等待教师开始").font(.largeTitle.bold()).foregroundStyle(.white)}
                    if case .inventory(let id)=game.surface,let c=game.campaign,let unit=c.engine.state.units[id] {
                        PublicInventoryPanel(unit:unit,catalog:c.engine.catalog).padding(40)
                    }
                    if game.surface == .results,let c=game.campaign,let result=c.snapshot.completion {
                        VStack(spacing:20){Text(result.outcome=="victory" ? "行程完成":"本次旅程结束").font(.largeTitle.bold());ForEach(result.players){u in Text("\(u.name) · 积分 \(u.score) · 金币 \(u.coins)").font(.title2)}}
                            .padding(40).foregroundStyle(.white).background(Color(red:0.08,green:0.15,blue:0.1).opacity(0.96),in:RoundedRectangle(cornerRadius:20))
                    }
                }.allowsHitTesting(false)
            }
        }.background(.black)
    }
}

private struct PublicBookPage:View {
    @ObservedObject var model:PublicDisplayModel
    var body:some View {
        VStack(spacing:12){
            HStack{Text("课堂绘本").bold();Spacer();Text("\(model.snapshot.pageCount==0 ? 0:model.snapshot.pageIndex+1) / \(model.snapshot.pageCount)")}.font(.title2).padding()
            if let image=model.image {Image(uiImage:image).resizable().scaledToFit().frame(maxWidth:.infinity,maxHeight:.infinity)}
            else{Text("教师正在准备绘本").font(.largeTitle).frame(maxWidth:.infinity,maxHeight:.infinity)}
        }.foregroundStyle(.white).background(Color(red:0.06,green:0.11,blue:0.08))
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
