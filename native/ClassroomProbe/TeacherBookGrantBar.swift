import SwiftUI
import ClassroomGameCore

struct TeacherBookGrantBar:View {
    @ObservedObject var game:MeadowTeacherCoordinator
    var prepare:()->Void={}
    @State private var recipients=Set<String>()
    @State private var ap="1"
    @State private var coins="10"
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
            HStack(spacing:4){Image(systemName:"diamond.fill").foregroundStyle(GameTheme.action);ClassroomTextField(placeholder:"1",text:$ap,limit:3,keyboard:.numberPad).frame(width:40,height:36)}
                .padding(.horizontal,10).background(.ultraThinMaterial,in:Capsule())
            HStack(spacing:4){Image(systemName:"bitcoinsign.circle.fill").foregroundStyle(GameTheme.accent);ClassroomTextField(placeholder:"10",text:$coins,limit:5,keyboard:.numberPad).frame(width:54,height:36)}
                .padding(.horizontal,10).background(.ultraThinMaterial,in:Capsule())
            Button{
                prepare();guard let a=Int(ap),let c=Int(coins) else{return}
                game.grantBookPlayers(selected,ap:a,coins:c)
            }label:{Label("发放",systemImage:"gift.fill")}.buttonStyle(GlassIconButtonStyle(tint:GameTheme.accent,prominent:true)).disabled(game.busy)
            Button{prepare();game.grantBookPlayers(selected,ap:1,coins:0)}label:{Label("+1",systemImage:"diamond")}.disabled(selected.isEmpty || game.busy)
            Button{prepare();game.grantBookPlayers(selected,ap:0,coins:10)}label:{Label("+10",systemImage:"bitcoinsign.circle")}.disabled(selected.isEmpty || game.busy)
            Button{prepare();game.undoTeacherAction()}label:{Label("撤销",systemImage:"arrow.uturn.backward")}.disabled(!game.backend.canUndoTeacherAction || game.busy)
            Spacer(minLength:0)
        }.buttonStyle(GlassIconButtonStyle()).menuStyle(.button).padding(.horizontal,10).padding(.vertical,6).glassPanel(radius:20,padding:0)
            .disabled(players.isEmpty || game.campaign?.isCompleted==true)
            .onAppear{if let id=game.campaign?.selectedPlayerID{recipients=[id]}}
    }
}
