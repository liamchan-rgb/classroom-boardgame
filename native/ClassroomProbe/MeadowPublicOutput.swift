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
                    if teacherPreview && game.externalConnected {MeadowLiveMirror(game:game)}
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

/// Same read-only page on TV and in the teacher's book preview. The page fills the screen; the players'
/// status floats over its bottom edge as compact frosted cards laid out by party size.
struct PublicBookPage:View {
    @ObservedObject var model:PublicDisplayModel
    let players:[ClassroomBookPlayerStatus]
    var body:some View {
        GeometryReader { geometry in
            ZStack(alignment:.bottom){
                Group {
                    if let image=model.image {Image(uiImage:image).resizable().scaledToFit()}
                    else{Label("绘本准备中",systemImage:"book.closed").font(.title)}
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                if let layout=ClassroomBookStatusLayout.cards(in:geometry.size,players:players.count) {
                    VStack(spacing:layout.spacing){
                        ForEach(Array(rowSlices(layout.rows).enumerated()),id:\.offset){_,range in
                            HStack(spacing:layout.spacing){
                                ForEach(range,id:\.self){i in BookPlayerCard(unit:players[i],index:i,size:layout.card)}
                            }
                        }
                    }.padding(.bottom,layout.spacing*1.6)
                }
            }
            .overlay(alignment:.topTrailing){
                Text("\(model.snapshot.pageCount==0 ? 0:model.snapshot.pageIndex+1) / \(model.snapshot.pageCount)")
                    .font(.system(size:max(11,geometry.size.height*0.022),weight:.bold,design:.rounded)).monospacedDigit()
                    .padding(.horizontal,10).padding(.vertical,5).background(.black.opacity(0.45),in:Capsule()).padding(10)
            }
        }.foregroundStyle(.white).background(.black).allowsHitTesting(false)
    }
    private func rowSlices(_ rows:[Int])->[Range<Int>] {
        var start=0;return rows.map{n in defer{start+=n};return start..<start+n}
    }
}
/// One student's frosted card: initial badge, name, a short health bar, action points and coins.
private struct BookPlayerCard:View {
    let unit:ClassroomBookPlayerStatus
    let index:Int
    let size:CGSize
    private static let tints:[Color]=[Color(red:0.36,green:0.72,blue:0.52),Color(red:0.42,green:0.62,blue:0.95),Color(red:0.95,green:0.62,blue:0.36),Color(red:0.78,green:0.52,blue:0.92),Color(red:0.95,green:0.80,blue:0.38),Color(red:0.40,green:0.80,blue:0.85),Color(red:0.92,green:0.50,blue:0.55)]
    private func number(_ value:Int)->String {value.formatted(.number.notation(.compactName).locale(Locale(identifier:"zh_CN")))}
    private var ratio:Double {Double(max(0,unit.health))/Double(max(1,unit.maximumHealth))}
    private var barColor:Color {ratio>0.5 ? Color(red:0.40,green:0.86,blue:0.52):ratio>0.25 ? Color(red:0.98,green:0.80,blue:0.35):Color(red:0.96,green:0.42,blue:0.40)}
    var body:some View {
        let h=size.height,tint=Self.tints[index%Self.tints.count],alive=unit.health>0
        let short=unit.name.components(separatedBy:" · ").first ?? unit.name
        VStack(alignment:.leading,spacing:h*0.07){
            HStack(spacing:h*0.1){
                Text(String(short.prefix(1)).uppercased()).font(.system(size:h*0.2,weight:.heavy,design:.rounded))
                    .frame(width:h*0.32,height:h*0.32).background(tint.opacity(0.85),in:Circle()).foregroundStyle(.white)
                Text(unit.name).font(.system(size:h*0.2,weight:.bold,design:.rounded)).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength:0)
                Image(systemName:alive ? "heart.fill":"heart.slash").font(.system(size:h*0.15,weight:.bold)).foregroundStyle(alive ? barColor:.gray)
                Text("\(number(unit.health))/\(number(unit.maximumHealth))").font(.system(size:h*0.16,weight:.semibold,design:.rounded)).monospacedDigit()
            }
            GeometryReader{g in
                ZStack(alignment:.leading){
                    Capsule().fill(.white.opacity(0.16))
                    Capsule().fill(LinearGradient(colors:[barColor.opacity(0.85),barColor],startPoint:.leading,endPoint:.trailing)).frame(width:g.size.width*ratio)
                }
            }.frame(height:max(4,h*0.085))
            HStack(spacing:h*0.06){
                Image(systemName:"diamond.fill").foregroundStyle(Color(red:0.70,green:0.60,blue:1.0))
                Text("\(number(unit.ap))/\(number(unit.maximumAP))").monospacedDigit()
                Spacer(minLength:0)
                Image(systemName:"bitcoinsign.circle.fill").foregroundStyle(Color(red:0.98,green:0.80,blue:0.40))
                Text(number(unit.coins)).monospacedDigit()
            }.font(.system(size:h*0.16,weight:.semibold,design:.rounded))
        }
        .padding(.horizontal,h*0.14).padding(.vertical,h*0.1)
        .frame(width:size.width,height:size.height)
        .background {
            // Frosted: a real blur is cheap here (the page under it is a still picture) plus a dark tint for legibility.
            ZStack{
                RoundedRectangle(cornerRadius:h*0.2,style:.continuous).fill(.ultraThinMaterial).environment(\.colorScheme,.dark)
                RoundedRectangle(cornerRadius:h*0.2,style:.continuous).fill(LinearGradient(colors:[.black.opacity(0.30),.black.opacity(0.48)],startPoint:.top,endPoint:.bottom))
            }
        }
        .overlay(RoundedRectangle(cornerRadius:h*0.2,style:.continuous).stroke(LinearGradient(colors:[.white.opacity(0.45),.white.opacity(0.1)],startPoint:.top,endPoint:.bottom),lineWidth:1))
        .opacity(alive ? 1:0.6).saturation(alive ? 1:0.2)
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
