import SwiftUI
import UIKit
import ClassroomGameCore

/// What the picture-book grant bar is about to hand out. Kept on the coordinator so the G shortcut grants exactly
/// what the fields show to whoever is ticked.
@MainActor final class BookGrantDraft:ObservableObject {
    @Published var recipients=Set<String>()
    @Published var steps="1"
    @Published var coins="10"
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
            grantBookPlayers(ids,movement:BookGrantDraft.amount(grantDraft.steps),coins:BookGrantDraft.amount(grantDraft.coins))
        }
    }
}

struct TeacherBookGrantBar:View {
    @ObservedObject var game:MeadowTeacherCoordinator
    @ObservedObject var draft:BookGrantDraft
    var prepare:()->Void={}
    @State private var picking=false
    private func grant(movement:Int,coins:Int) {
        prepare()
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
        game.grantBookPlayers(selected,movement:movement,coins:coins)
    }
    private var players:[GameUnit] {game.campaign?.engine.state.players ?? []}
    private var teams:[GameTeam] {game.campaign?.engine.state.teams.filter{t in players.contains{$0.teamID==t.id}} ?? []}
    private var selected:[String] {players.map(\.id).filter{draft.recipients.contains($0)}}
    var body:some View {
        HStack(spacing:8){
            // A popover (not a menu) so several people / a whole group can be ticked before it is closed.
            Button{prepare();picking=true}label:{Label("\(selected.count)",systemImage:"person.2.fill")}
                .popover(isPresented:$picking,arrowEdge:.bottom){recipientPicker}
            HStack(spacing:4){Image(systemName:"figure.walk").foregroundStyle(GameTheme.primary);ClassroomTextField(placeholder:"0",text:$draft.steps,limit:3,keyboard:.numberPad).frame(width:40,height:36)}
                .padding(.horizontal,10).background(GlassFill.field,in:Capsule())
            HStack(spacing:4){Image(systemName:"bitcoinsign.circle.fill").foregroundStyle(GameTheme.accent);ClassroomTextField(placeholder:"0",text:$draft.coins,limit:5,keyboard:.numberPad).frame(width:54,height:36)}
                .padding(.horizontal,10).background(GlassFill.field,in:Capsule())
            Button{prepare();game.grantFromDraft()}label:{Label("发放 G",systemImage:"gift.fill")}
                .buttonStyle(GlassIconButtonStyle(tint:GameTheme.accent,prominent:true)).disabled(selected.isEmpty || game.busy)
            Button{grant(movement:1,coins:0)}label:{Label("移动+1",systemImage:"figure.walk")}.disabled(selected.isEmpty || game.busy)
            Button{grant(movement:0,coins:10)}label:{Label("+10",systemImage:"bitcoinsign.circle")}.disabled(selected.isEmpty || game.busy)
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
                Label("发放对象 · 已选 \(selected.count)",systemImage:"person.2.fill").font(.headline)
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
                ForEach(players){unit in
                    let on=draft.recipients.contains(unit.id)
                    Button{if on{draft.recipients.remove(unit.id)}else{draft.recipients.insert(unit.id)}}label:{
                        HStack(spacing:8){
                            Image(systemName:on ? "checkmark.circle.fill":"circle").foregroundStyle(on ? GameTheme.primary:GameTheme.muted)
                            Text(unit.name).lineLimit(1).minimumScaleFactor(0.7)
                            Spacer(minLength:0)
                        }.padding(.horizontal,12).frame(height:44)
                        .background(on ? GameTheme.primary.opacity(0.14):Color.white.opacity(0.55),in:RoundedRectangle(cornerRadius:12,style:.continuous))
                    }.buttonStyle(.plain)
                }
            }
        }.padding(16).frame(width:520).foregroundStyle(GameTheme.ink)
    }
    private func chip(_ title:String,systemImage:String,on:Bool,action:@escaping ()->Void)->some View {
        Button(action:action){Label(title,systemImage:systemImage).font(.subheadline.bold()).padding(.horizontal,12).frame(height:36)
            .background(on ? GameTheme.primary:Color.white.opacity(0.6),in:Capsule()).foregroundStyle(on ? Color.white:GameTheme.ink)}.buttonStyle(.plain)
    }
}
