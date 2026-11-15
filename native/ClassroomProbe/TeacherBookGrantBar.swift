import SwiftUI
import UIKit
import ClassroomGameCore

struct TeacherBookGrantBar:View {
    @ObservedObject var game:MeadowTeacherCoordinator
    var prepare:()->Void={}
    @State private var recipients=Set<String>()
    @State private var steps="1"
    @State private var coins="10"
    /// Digits only (full-width digits from a Chinese keyboard count too); empty means 0.
    private static func amount(_ text:String)->Int {
        let digits=text.unicodeScalars.compactMap{s->Character? in
            if ("0"..."9").contains(s) {return Character(s)}
            if (0xFF10...0xFF19).contains(s.value) {return Character(UnicodeScalar(s.value-0xFF10+48)!)}
            return nil
        }
        return min(99999,Int(String(digits)) ?? 0)
    }
    private func grant(movement:Int,coins:Int) {
        prepare()
        // Commit whatever the focused field still holds before reading it.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
        game.grantBookPlayers(selected,movement:movement,coins:coins)
    }
    private var players:[GameUnit] {game.campaign?.engine.state.players ?? []}
    private var selected:[String] {players.map(\.id).filter{recipients.contains($0)}}
    var body:some View {
        HStack(spacing:8){
            Menu {
                Button{recipients=Set(players.map(\.id))}label:{Label("全选",systemImage:"checkmark.circle")}
                Button{recipients=[]}label:{Label("清空",systemImage:"circle")}
                ForEach(players){unit in
                    Button{if recipients.contains(unit.id){recipients.remove(unit.id)}else{recipients.insert(unit.id)}}label:{Label(unit.name,systemImage:recipients.contains(unit.id) ? "checkmark.circle.fill":"circle")}
                }
            }label:{Label("\(selected.count)",systemImage:"person.2.fill")}
            HStack(spacing:4){Image(systemName:"figure.walk").foregroundStyle(GameTheme.primary);ClassroomTextField(placeholder:"0",text:$steps,limit:3,keyboard:.numberPad).frame(width:40,height:36)}
                .padding(.horizontal,10).background(GlassFill.field,in:Capsule())
            HStack(spacing:4){Image(systemName:"bitcoinsign.circle.fill").foregroundStyle(GameTheme.accent);ClassroomTextField(placeholder:"0",text:$coins,limit:5,keyboard:.numberPad).frame(width:54,height:36)}
                .padding(.horizontal,10).background(GlassFill.field,in:Capsule())
            Button{
                // Read on the next turn so a field that is still being edited has handed over its text.
                DispatchQueue.main.async{grant(movement:Self.amount(steps),coins:Self.amount(coins))}
            }label:{Label("发放",systemImage:"gift.fill")}.buttonStyle(GlassIconButtonStyle(tint:GameTheme.accent,prominent:true)).disabled(selected.isEmpty || game.busy)
            Button{grant(movement:1,coins:0)}label:{Label("移动+1",systemImage:"figure.walk")}.disabled(selected.isEmpty || game.busy)
            Button{grant(movement:0,coins:10)}label:{Label("+10",systemImage:"bitcoinsign.circle")}.disabled(selected.isEmpty || game.busy)
            Button{prepare();game.undoTeacherAction()}label:{Label("撤销",systemImage:"arrow.uturn.backward")}.disabled(!game.backend.canUndoTeacherAction || game.busy)
            Spacer(minLength:0)
        }.buttonStyle(GlassIconButtonStyle()).menuStyle(.button).padding(.horizontal,10).padding(.vertical,6).glassPanel(radius:20,padding:0)
            .disabled(players.isEmpty || game.campaign?.isCompleted==true)
            .onAppear{if let id=game.campaign?.selectedPlayerID{recipients=[id]}}
    }
}
