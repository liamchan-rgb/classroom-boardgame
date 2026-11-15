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
        .overlay{ClassroomTVOverlays(timer:game.classTimer,overlays:game.overlays,game:game)}
    }
}

/// Same read-only page on TV and in the teacher's book preview. The page fills the screen; the players'
/// status floats over its bottom edge as compact frosted cards laid out by party size.
/// Where the teacher dragged the players' cards over the picture book (fractions of the page, shared by TV and preview).
@MainActor final class BookCardsPosition:ObservableObject {
    static let shared=BookCardsPosition()
    @Published var offset=CGSize.zero {didSet{UserDefaults.standard.set([offset.width,offset.height],forKey:"classroom.bookCardsOffset")}}
    init(){if let v=UserDefaults.standard.array(forKey:"classroom.bookCardsOffset") as? [Double],v.count==2{offset=CGSize(width:v[0],height:v[1])}}
}
struct PublicBookPage:View {
    @ObservedObject var model:PublicDisplayModel
    let players:[ClassroomBookPlayerStatus]
    /// The teacher's preview lets the cards be dragged out of the way of the slide (the TV follows).
    var draggable=false
    @ObservedObject private var position=BookCardsPosition.shared
    @State private var dragStart:CGSize?
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
                    .offset(x:position.offset.width*geometry.size.width,y:position.offset.height*geometry.size.height)
                    .contentShape(Rectangle())
                    .allowsHitTesting(draggable)
                    .gesture(DragGesture(minimumDistance:4).onChanged{g in
                        let start=dragStart ?? position.offset;if dragStart==nil{dragStart=start}
                        // Keep the cards on the page (at most the full height up, a little sideways each way).
                        position.offset=CGSize(width:min(0.45,max(-0.45,start.width+g.translation.width/geometry.size.width)),
                                               height:min(0,max(-0.85,start.height+g.translation.height/geometry.size.height)))
                    }.onEnded{_ in dragStart=nil})
                    .onTapGesture(count:2){if draggable{withAnimation(.spring()){position.offset = .zero}}}
                }
            }
            .overlay(alignment:.topTrailing){
                Text("\(model.snapshot.pageCount==0 ? 0:model.snapshot.pageIndex+1) / \(model.snapshot.pageCount)")
                    .font(.system(size:max(11,geometry.size.height*0.022),weight:.bold,design:.rounded)).monospacedDigit()
                    .padding(.horizontal,10).padding(.vertical,5).background(.black.opacity(0.45),in:Capsule()).padding(10)
            }
        }.foregroundStyle(.white).background(.black)
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
    /// 发放后的动画（和战斗掉落同一套像素金币 / 拾取光）：金币或行动点增加时触发一次
    @State private var gain=BookGain()
    /// The old number stays up while the coins fly in; it switches when they land.
    @State private var heldCoins:Int?=nil,heldMovement:Int?=nil
    @State private var holdToken=0
    @State private var coinPop=false
    @State private var apPop=false
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
                // The team's movement bar in steps (what the picture-book bar grants), replacing the old AP diamonds.
                Image(systemName:"figure.walk").foregroundStyle(Color(red:0.45,green:0.85,blue:0.95))
                Text("\(number(heldMovement ?? unit.movement))/\(number(unit.maximumMovement))").monospacedDigit()
                    .scaleEffect(apPop ? 1.4:1,anchor:.leading).foregroundStyle(apPop ? Color(red:0.62,green:0.92,blue:1.0):.white)
                Spacer(minLength:0)
                Image(systemName:"bitcoinsign.circle.fill").foregroundStyle(Color(red:0.98,green:0.80,blue:0.40))
                Text(number(heldCoins ?? unit.coins)).monospacedDigit()
                    .scaleEffect(coinPop ? 1.4:1,anchor:.trailing).foregroundStyle(coinPop ? Color(red:1.0,green:0.86,blue:0.42):.white)
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
        .overlay{BookGainBurst(gain:gain,size:size).frame(width:size.width,height:size.height).allowsHitTesting(false)}
        .onChange(of:unit.coins){old,new in
            guard new>old else{heldCoins=nil;return}
            if heldCoins==nil{heldCoins=old}
            gain=BookGain(serial:gain.serial+1,coins:new-old,ap:0)
            pop(coins:true)
        }
        .onChange(of:unit.movement){old,new in
            guard new>old else{heldMovement=nil;return}
            if heldMovement==nil{heldMovement=old}
            gain=BookGain(serial:gain.serial+1,coins:0,ap:new-old)
            pop(coins:false)
        }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("\(unit.name)，生命\(unit.health)/\(unit.maximumHealth)，移动\(unit.movement)/\(unit.maximumMovement)步，金币\(unit.coins)")
    }
}

extension BookPlayerCard {
    /// 金币飞进来以后数字弹一下
    fileprivate func pop(coins:Bool) {
        holdToken += 1;let token=holdToken
        DispatchQueue.main.asyncAfter(deadline:.now()+0.75){
            // The pieces have landed: now the number changes (the latest grant releases the held value).
            if token==holdToken {heldCoins=nil;heldMovement=nil}
            withAnimation(.spring(response:0.25,dampingFraction:0.45)){ if coins{coinPop=true}else{apPop=true} }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5){ withAnimation(.easeOut(duration:0.35)){ if coins{coinPop=false}else{apPop=false} } }
        }
    }
}

/// 一次发放：序号变了就播一次
struct BookGain:Equatable { var serial=0,coins=0,ap=0 }

/// 绘本状态卡上的发放动画：像素金币（或行动点菱形）从卡片上方抛出、落进金币数字，落点炸开拾取光，飘起「+10」。
/// 和战斗里的掉落动画用同一套像素片段（coinSpin / collectGold / collectEpic）。
struct BookGainBurst:UIViewRepresentable {
    let gain:BookGain
    let size:CGSize
    final class Coordinator { var serial=0 }
    func makeCoordinator()->Coordinator { Coordinator() }
    func makeUIView(context:Context)->UIView { let v=UIView();v.clipsToBounds=false;v.isUserInteractionEnabled=false;return v }
    func updateUIView(_ view:UIView,context:Context) {
        guard gain.serial != context.coordinator.serial else{return}
        let first=context.coordinator.serial==0 && gain.serial==0
        context.coordinator.serial=gain.serial
        guard !first,gain.coins>0 || gain.ap>0 else{return}
        DispatchQueue.main.async { play(in:view) }
    }

    private static func frames(_ id:String)->[UIImage] {
        guard let clip=MeadowPixelFX.clips[id] else{return []}
        let images=MeadowPixelFX.images(clip),start=clip.back && clip.front ? clip.n:0
        return (start..<min(images.count,start+clip.n)).map{UIImage(cgImage:images[$0])}
    }

    private func play(in view:UIView) {
        let h=size.height,w=size.width,coins=gain.coins>0
        // 落点：金币图标（右下）/ 行动点菱形（左下）
        let target=coins ? CGPoint(x:w*0.80,y:h*0.80):CGPoint(x:h*0.24,y:h*0.80)
        let amount=coins ? gain.coins:gain.ap
        let count=coins ? min(10,max(4,amount/3)):min(5,max(2,amount))
        let spin=coins ? Self.frames("coinSpin"):[]
        let side=h*0.42
        for i in 0..<count {
            let piece=UIImageView(frame:CGRect(x:0,y:0,width:side,height:side))
            piece.layer.magnificationFilter = .nearest
            if coins,!spin.isEmpty { piece.animationImages=spin;piece.animationDuration=Double(spin.count)/20;piece.startAnimating() }
            else {
                piece.image=UIImage(systemName:"figure.walk")?.withTintColor(UIColor(red:0.45,green:0.85,blue:0.95,alpha:1),renderingMode:.alwaysOriginal)
                piece.bounds=CGRect(x:0,y:0,width:side*0.55,height:side*0.55)
            }
            // 从卡片上方中间一带抛起来，划弧落进数字
            let start=CGPoint(x:w*0.5+CGFloat(i-count/2)*h*0.16,y:-h*0.15)
            let control=CGPoint(x:(start.x+target.x)/2+CGFloat((i%3)-1)*h*0.3,y:-h*(1.1+CGFloat(i%2)*0.35))
            piece.layer.position=start;piece.alpha=0
            view.addSubview(piece)
            let path=UIBezierPath();path.move(to:start);path.addQuadCurve(to:target,controlPoint:control)
            let move=CAKeyframeAnimation(keyPath:"position");move.path=path.cgPath
            move.timingFunction=CAMediaTimingFunction(name:.easeIn)
            let shrink=CABasicAnimation(keyPath:"transform.scale");shrink.fromValue=1.15;shrink.toValue=0.55
            let fade=CAKeyframeAnimation(keyPath:"opacity");fade.values=[0,1,1,0.9];fade.keyTimes=[0,0.12,0.85,1]
            let group=CAAnimationGroup();group.animations=[move,shrink,fade];group.duration=0.62
            group.beginTime=CACurrentMediaTime()+Double(i)*0.07;group.fillMode = .both;group.isRemovedOnCompletion=false
            piece.layer.add(group,forKey:"fly")
            DispatchQueue.main.asyncAfter(deadline:.now()+Double(i)*0.07+0.64){ piece.removeFromSuperview() }
        }
        // 落点的拾取光 + 飘起的「+N」
        let land=Double(count-1)*0.07+0.6
        DispatchQueue.main.asyncAfter(deadline:.now()+land){
            let burstFrames=Self.frames(coins ? "collectGold":"collectEpic")
            if !burstFrames.isEmpty {
                let b=UIImageView(frame:CGRect(x:0,y:0,width:h*1.1,height:h*1.2))
                b.center=CGPoint(x:target.x,y:target.y-h*0.3);b.layer.magnificationFilter = .nearest
                b.animationImages=burstFrames;b.animationDuration=Double(burstFrames.count)/20;b.animationRepeatCount=1
                view.addSubview(b);b.startAnimating()
                DispatchQueue.main.asyncAfter(deadline:.now()+b.animationDuration){ b.removeFromSuperview() }
            }
            let label=UILabel()
            label.text="+\(amount)";label.font = .systemFont(ofSize:h*0.3,weight:.black)
            label.textColor=coins ? UIColor(red:1.0,green:0.84,blue:0.36,alpha:1):UIColor(red:0.80,green:0.70,blue:1.0,alpha:1)
            label.layer.shadowColor=UIColor.black.cgColor;label.layer.shadowOpacity=0.8;label.layer.shadowRadius=3;label.layer.shadowOffset = .zero
            label.sizeToFit();label.center=CGPoint(x:target.x,y:target.y-h*0.35);label.transform=CGAffineTransform(scaleX:0.4,y:0.4)
            view.addSubview(label)
            UIView.animate(withDuration:0.3,delay:0,usingSpringWithDamping:0.5,initialSpringVelocity:0.8){ label.transform = .identity }
            UIView.animate(withDuration:0.9,delay:0.5,options:.curveEaseOut,animations:{ label.center.y -= h*0.55;label.alpha=0 }){ _ in label.removeFromSuperview() }
        }
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
