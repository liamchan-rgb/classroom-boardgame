import SwiftUI
import UIKit
import ClassroomGameCore

/// What the picture-book grant bar is about to hand out. Kept on the coordinator so the G shortcut grants exactly
/// what the fields show to whoever is ticked.
@MainActor final class BookGrantDraft:ObservableObject {
    @Published var recipients=Set<String>()
    @Published var steps="1"
    @Published var coins="10"
    @Published var score="1"
    /// Digits only (full-width digits from a Chinese keyboard count too); empty means 0.
    static func amount(_ text:String)->Int {
        let digits=text.unicodeScalars.compactMap{s->Character? in
            if ("0"..."9").contains(s) {return Character(s)}
            if (0xFF10...0xFF19).contains(s.value) {return Character(UnicodeScalar(s.value-0xFF10+48)!)}
            return nil
        }
        return min(99999,Int(String(digits)) ?? 0)
    }
}

extension MeadowTeacherCoordinator {
    /// Grant the draft's movement steps and coins to the ticked players (G on the book page, or the 发放 button).
    func grantFromDraft() {
        // Commit whatever a focused field still holds before reading it.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
        DispatchQueue.main.async { [self] in
            let ids=(campaign?.engine.state.players ?? []).map(\.id).filter{grantDraft.recipients.contains($0)}
            grantBookPlayers(ids,movement:BookGrantDraft.amount(grantDraft.steps),coins:BookGrantDraft.amount(grantDraft.coins),score:BookGrantDraft.amount(grantDraft.score))
        }
    }
}

struct TeacherBookGrantBar:View {
    @ObservedObject var game:MeadowTeacherCoordinator
    @ObservedObject var draft:BookGrantDraft
    var prepare:()->Void={}
    @State private var picking=false
    enum Box {case steps,coins,score}
    /// A box's amount dropped on one player's card: only that player gets it (ticked recipients are left alone).
    private func dropGrant(_ id:String,_ box:Box) {
        prepare()
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
        // Read the box after the field has committed what it still holds.
        DispatchQueue.main.async {
            let amount=BookGrantDraft.amount(box == .steps ? draft.steps:box == .coins ? draft.coins:draft.score)
            game.grantBookPlayers([id],movement:box == .steps ? amount:0,coins:box == .coins ? amount:0,score:box == .score ? amount:0)
        }
    }
    private var players:[GameUnit] {game.campaign?.engine.state.players ?? []}
    private var teams:[GameTeam] {game.campaign?.engine.state.teams.filter{t in players.contains{$0.teamID==t.id}} ?? []}
    private var selected:[String] {players.map(\.id).filter{draft.recipients.contains($0)}}
    var body:some View {
        HStack(spacing:8){
            // A popover (not a menu) so several people / a whole group can be ticked before it is closed.
            // One dot per player in seat order (the numbers the keys use); lit = will receive.
            Button{prepare();picking=true}label:{
                Label{
                    HStack(spacing:3){
                        ForEach(players.sorted{game.seatNumber($0.id)<game.seatNumber($1.id)},id:\.id){u in
                            let on=draft.recipients.contains(u.id)
                            Circle().fill(on ? GameTheme.primary:GameTheme.muted.opacity(0.22)).frame(width:7.5,height:7.5)
                                .overlay(Circle().stroke(GameTheme.primary.opacity(on ? 0:0.35),lineWidth:0.8))
                        }
                    }.frame(height:11)
                }icon:{Image(systemName:"person.2.fill")}
            }
            .accessibilityLabel("发放对象：已选 \(selected.count) 人")
                #if targetEnvironment(macCatalyst)
                // A popover here shows up empty on the Mac (as the word card did): a sheet there instead.
                .sheet(isPresented:$picking){
                    recipientPicker.padding(.top,8).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top).background(GlassBackdrop())
                        .presentationDetents([.medium])
                }
                #else
                .popover(isPresented:$picking,arrowEdge:.bottom){recipientPicker}
                #endif
            // Drag the icon onto a player's card in the preview to give that player the amount in the box.
            HStack(spacing:4){
                GrantDragHandle(systemImage:"figure.walk",tint:GameTheme.primary,amount:$draft.steps){id in dropGrant(id,.steps)}
                ClassroomTextField(placeholder:"0",text:$draft.steps,limit:3,keyboard:.numberPad).frame(width:40,height:36)
            }.padding(.horizontal,10).background(GlassFill.field,in:Capsule()).zIndex(1)
            HStack(spacing:4){
                GrantDragHandle(systemImage:"bitcoinsign.circle.fill",tint:GameTheme.accent,amount:$draft.coins){id in dropGrant(id,.coins)}
                ClassroomTextField(placeholder:"0",text:$draft.coins,limit:5,keyboard:.numberPad).frame(width:54,height:36)
            }.padding(.horizontal,10).background(GlassFill.field,in:Capsule()).zIndex(1)
            // Points (积分), like the coins: the box, or drag the star onto one card.
            HStack(spacing:4){
                GrantDragHandle(systemImage:"star.fill",tint:Color(red:0.85,green:0.6,blue:0.12),amount:$draft.score){id in dropGrant(id,.score)}
                ClassroomTextField(placeholder:"0",text:$draft.score,limit:4,keyboard:.numberPad).frame(width:44,height:36)
            }.padding(.horizontal,10).background(GlassFill.field,in:Capsule()).zIndex(1)
            Button{prepare();game.grantFromDraft()}label:{Label("发放 G",systemImage:"gift.fill")}
                .buttonStyle(GlassIconButtonStyle(tint:GameTheme.accent,prominent:true)).disabled(selected.isEmpty || game.busy)
            Button{prepare();game.undoTeacherAction()}label:{Label("撤销",systemImage:"arrow.uturn.backward")}.disabled(!game.backend.canUndoTeacherAction || game.busy)
            Spacer(minLength:0)
        }.buttonStyle(GlassIconButtonStyle()).padding(.horizontal,10).padding(.vertical,6).glassPanel(radius:20,padding:0)
            .disabled(players.isEmpty || game.campaign?.isCompleted==true)
            .onAppear{if draft.recipients.isEmpty,let id=game.campaign?.selectedPlayerID{draft.recipients=[id]}}
    }
    /// Tick any number of players; whole groups in one tap. Stays open until tapped outside or 完成.
    private var recipientPicker:some View {
        VStack(alignment:.leading,spacing:12){
            HStack{
                VStack(alignment:.leading,spacing:2){
                    Label("发放对象 · 已选 \(selected.count)",systemImage:"person.2.fill").font(.headline)
                    Text("数字键按编号勾选 · 长按成员改编号 · G发金币 M发体力（输数字回车；连按两下按输入框）").font(.caption).foregroundStyle(GameTheme.muted)
                }
                Spacer()
                Button("完成"){picking=false}.bold()
            }
            HStack(spacing:8){
                chip("全员",systemImage:"person.3.fill",on:selected.count==players.count && !players.isEmpty){draft.recipients=Set(players.map(\.id))}
                chip("清空",systemImage:"xmark.circle",on:false){draft.recipients=[]}
                ForEach(teams){team in
                    let members=Set(players.filter{$0.teamID==team.id}.map(\.id))
                    chip(team.name,systemImage:"flag.fill",on:!members.isEmpty && members.isSubset(of:draft.recipients)){
                        // Tap a group: tick all of it; tap again (all ticked): untick it.
                        if members.isSubset(of:draft.recipients){draft.recipients.subtract(members)}else{draft.recipients.formUnion(members)}
                    }
                }
            }
            LazyVGrid(columns:[GridItem(.adaptive(minimum:150),spacing:8)],spacing:8){
                ForEach(players.sorted{game.seatNumber($0.id)<game.seatNumber($1.id)}){unit in
                    let on=draft.recipients.contains(unit.id)
                    Button{if on{draft.recipients.remove(unit.id)}else{draft.recipients.insert(unit.id)}}label:{
                        HStack(spacing:8){
                            Image(systemName:on ? "checkmark.circle.fill":"circle").foregroundStyle(on ? GameTheme.primary:GameTheme.muted)
                            // The number key that ticks this player (long-press to change it).
                            Text("\(game.seatNumber(unit.id))").font(.system(size:13,weight:.heavy,design:.rounded)).foregroundStyle(.white)
                                .frame(width:22,height:22).background(GameTheme.primary.opacity(0.85),in:Circle())
                            Text(unit.name).lineLimit(1).minimumScaleFactor(0.7)
                            Spacer(minLength:0)
                        }.padding(.horizontal,12).frame(height:44)
                        .background(on ? GameTheme.primary.opacity(0.14):Color.white.opacity(0.55),in:RoundedRectangle(cornerRadius:12,style:.continuous))
                    }.buttonStyle(.plain)
                    .contextMenu{
                        Section("长按改编号（数字键按编号勾选）"){
                            ForEach(1...max(1,players.count),id:\.self){n in
                                Button{game.setSeatNumber(unit.id,n)}label:{
                                    let holder=game.player(forSeat:n).flatMap{game.campaign?.engine.state.units[$0]?.shortName}
                                    Label("编号 \(n)"+(holder.map{" · 现为"+$0} ?? ""),systemImage:game.seatNumber(unit.id)==n ? "checkmark":"number")
                                }
                            }
                        }
                    }
                }
            }
        }.padding(16).frame(width:520).foregroundStyle(GameTheme.ink)
    }
    private func chip(_ title:String,systemImage:String,on:Bool,action:@escaping ()->Void)->some View {
        Button(action:action){Label(title,systemImage:systemImage).font(.subheadline.bold()).padding(.horizontal,12).frame(height:36)
            .background(on ? GameTheme.primary:Color.white.opacity(0.6),in:Capsule()).foregroundStyle(on ? Color.white:GameTheme.ink)}.buttonStyle(.plain)
    }
}

/// Where the players' cards sit in the teacher's book preview, so a grant icon dragged from the bar knows
/// which card it was let go over.
@MainActor final class BookDropTargets:ObservableObject {
    static let shared=BookDropTargets()
    var frames:[String:CGRect]=[:]
    /// The card under the dragged icon (highlighted).
    @Published var hover:String?
    func target(at point:CGPoint)->String? {frames.first{$0.value.contains(point)}?.key}
    /// The box whose icon is being dragged: digits typed meanwhile set its amount (the first digit replaces it).
    var dragging:Binding<String>?
    private var typedDuringDrag=false
    func beginDrag(_ amount:Binding<String>) {dragging=amount;typedDuringDrag=false}
    func endDrag() {dragging=nil}
    /// Digits / Backspace while a grant icon is held; true when the key was used.
    func dragKey(_ key:UIKey)->Bool {
        guard let box=dragging else{return false}
        if key.keyCode == .keyboardDeleteOrBackspace {box.wrappedValue=String(box.wrappedValue.dropLast());typedDuringDrag=true;return true}
        let c=key.charactersIgnoringModifiers
        guard c.count==1,let d=c.first,d.isASCII,d.isNumber else{return false}
        let next=(typedDuringDrag ? box.wrappedValue:"")+String(d)
        box.wrappedValue=String(next.prefix(5));typedDuringDrag=true;return true
    }
}

/// The step / coin icon of a grant box. Drag it onto a player's card: that player gets the box's amount.
struct GrantDragHandle:View {
    let systemImage:String
    let tint:Color
    @Binding var amount:String
    let onDrop:(String)->Void
    @ObservedObject private var targets=BookDropTargets.shared
    @State private var drag:CGSize?
    var body:some View {
        Image(systemName:systemImage).foregroundStyle(tint)
            .frame(width:22,height:36).contentShape(Rectangle())
            .overlay{
                if let drag {
                    // The amount follows the pointer so it is clear what lands on the card.
                    Label(String(BookGrantDraft.amount(amount)),systemImage:systemImage)
                        .font(.system(size:20,weight:.heavy,design:.rounded)).monospacedDigit()
                        .padding(.horizontal,14).frame(height:40)
                        .background(tint,in:Capsule()).foregroundStyle(.white)
                        .shadow(color:.black.opacity(0.3),radius:6,y:3)
                        .fixedSize().offset(drag).allowsHitTesting(false)
                }
            }
            .gesture(DragGesture(minimumDistance:3,coordinateSpace:.global)
                .onChanged{g in
                    if drag == nil {
                        // Hand the keyboard back to the window so digits typed while holding reach the box.
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
                        targets.beginDrag($amount)
                    }
                    drag=g.translation
                    let id=targets.target(at:g.location)
                    if id != targets.hover {targets.hover=id}
                }
                .onEnded{g in
                    targets.endDrag()
                    if let id=targets.target(at:g.location) {onDrop(id)}
                    drag=nil;targets.hover=nil
                })
            .help("拖到玩家卡片上发放；拖着时可直接敲数字改数量")
            .accessibilityHint("拖到玩家卡片上发放")
    }
}
