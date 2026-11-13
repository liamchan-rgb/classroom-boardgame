import SwiftUI
import ClassroomGameCore
import MeadowWorldSupport

/// The character studio: a teacher-only screen to dress a character and keep the look. A large live preview walks the figure round
/// all eight directions; every hair style, face and outfit is a picture tile; the result is applied to a member of the running
/// journey and/or saved to one of the 50 character slots (which new journeys can load). Looks only - class, numbers and gear stay.
struct TeacherCharacterStudio:View {
    @ObservedObject var game:MeadowTeacherCoordinator
    var onClose:()->Void
    @State private var player="p1"
    @State private var name="新角色"
    @State private var body_="forester"
    @State private var outfit="follow"
    @State private var hair="original"
    @State private var face="original"
    @State private var slot=1
    @State private var notice="选好发型、五官和衣装，右侧预览会实时走一圈八个方向。"
    @State private var turning=true
    @State private var facingIndex=0
    @State private var tiles:[String:UIImage]=[:]
    @State private var confirm=false
    @State private var confirmation=""
    @State private var pending:(()throws->Void)?
    @State private var used:[Int:String]=[:]

    static let hairNames=["短碎","偏分","小束","长发","侧马尾","盘发"]
    static let faceNames=["蓝瞳","琥珀","绿瞳","紫瞳"]
    static let outfits:[(String,String)]=[("follow","随护甲"),("blue","基础"),("leatherArmor","皮甲"),("runeArmor","符文"),("starlightArmor","星辉"),("dragonArmor","龙纹")]
    /// Turning order: down, down-left, left, up-left, up, up-right, right, down-right.
    private static let turn=[0,5,1,6,2,7,3,4]
    private static let turnNames=["正面","左前","左侧","左后","背面","右后","右侧","右前"]

    private var players:[GameUnit] {game.campaign?.engine.state.players ?? []}
    private var worn:String? {game.campaign?.engine.state.units[player]?.equipment.armor}
    private var weapon:String? {game.campaign?.engine.state.units[player]?.equipment.weapon ?? "trainingSword"}
    private var appearance:PlayerAppearance {.init(body:body_,outfit:outfit=="follow" ? nil:outfit,hair:hair=="original" ? nil:hair,face:face=="original" ? nil:face)}
    private var store:MeadowSlotStore {MeadowTeacherCoordinator.slotStore}

    var body:some View {
        NavigationStack {
            HStack(alignment:.top,spacing:18){
                preview.frame(width:330)
                ScrollView {
                    VStack(alignment:.leading,spacing:18){
                        identity
                        choice("外观","figure.stand",options:[("forester","林间"),("wayfarer","行旅")],selection:$body_){id in look(body:id)}
                        choice("发型","scissors",options:[("original","原有")]+zip(PlayerAppearance.hairOptions,Self.hairNames).map{($0,$1)},selection:$hair){id in look(hair:id)}
                        choice("五官","face.smiling",options:[("original","原有")]+zip(PlayerAppearance.faceOptions,Self.faceNames).map{($0,$1)},selection:$face,zoomOnFace:true){id in look(face:id)}
                        choice("衣装","tshirt",options:Self.outfits,selection:$outfit){id in look(outfit:id)}
                        actions
                    }.padding(.trailing,6)
                }
            }.padding(18)
            .background(GlassBackdrop())
            .navigationTitle("人物自定义")
            .toolbar{ToolbarItem(placement:.cancellationAction){Button{onClose()}label:{Image(systemName:"xmark.circle.fill").font(.title2)}.accessibilityLabel("关闭")}}
            .alert("确认操作",isPresented:$confirm){Button("取消",role:.cancel){pending=nil};Button("确认"){run()}}message:{Text(confirmation)}
            .onAppear{player=game.campaign?.selectedPlayerID ?? players.first?.id ?? "p1";readPlayer();scanSlots()}
            .onChange(of:player){_,_ in readPlayer()}
            .onChange(of:body_){_,_ in tiles=[:]}
            .onChange(of:outfit){_,_ in tiles=[:]}
            .onChange(of:hair){_,_ in tiles=[:]}
            .onChange(of:face){_,_ in tiles=[:]}
        }
    }

    // MARK: preview

    private var preview:some View {
        VStack(spacing:10){
            TimelineView(.periodic(from:.now,by:0.11)){context in
                let tick=Int(context.date.timeIntervalSinceReferenceDate/0.11)
                let facing=Self.turn[turning ? (tick/16)%8:facingIndex]
                let column=1+tick%8
                ZStack(alignment:.bottom){
                    LinearGradient(colors:[Color(red:0.36,green:0.55,blue:0.38),Color(red:0.20,green:0.36,blue:0.22)],startPoint:.top,endPoint:.bottom)
                    Ellipse().fill(.black.opacity(0.25)).frame(width:120,height:26).offset(y:-30)
                    if let image=cell(facing:facing,column:column,look:appearance){
                        Image(uiImage:image).interpolation(.none).resizable().scaledToFit().frame(width:300,height:330).padding(.bottom,14)
                    }else{Text("预览素材缺失").foregroundStyle(.white)}
                    Text(Self.turnNames[Self.turn.firstIndex(of:facing) ?? 0]).font(.caption.bold()).foregroundStyle(.white.opacity(0.85)).padding(6)
                        .background(.black.opacity(0.3),in:Capsule()).padding(.bottom,10)
                }
                .frame(height:360).clipShape(RoundedRectangle(cornerRadius:20,style:.continuous))
                .overlay(RoundedRectangle(cornerRadius:20,style:.continuous).stroke(.white.opacity(0.6),lineWidth:1.5))
            }
            HStack(spacing:10){
                Button{turning=false;facingIndex=(facingIndex+7)%8}label:{Image(systemName:"arrow.counterclockwise")}.accessibilityLabel("向左转")
                Button{if turning{facingIndex=0};turning.toggle()}label:{Image(systemName:turning ? "pause.fill":"play.fill")}.accessibilityLabel(turning ? "停在当前方向":"自动转身")
                Button{turning=false;facingIndex=(facingIndex+1)%8}label:{Image(systemName:"arrow.clockwise")}.accessibilityLabel("向右转")
            }.buttonStyle(GlassIconButtonStyle())
            // All eight standing poses at once.
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:4),spacing:4){
                ForEach(0..<8,id:\.self){i in
                    Button{turning=false;facingIndex=i}label:{
                        ZStack{
                            RoundedRectangle(cornerRadius:10,style:.continuous).fill(GlassFill.button)
                            if let image=cell(facing:Self.turn[i],column:0,look:appearance){Image(uiImage:image).interpolation(.none).resizable().scaledToFit()}
                        }.frame(height:76).overlay(RoundedRectangle(cornerRadius:8).stroke(!turning && facingIndex==i ? GameTheme.accent:.clear,lineWidth:2))
                    }.buttonStyle(.plain)
                }
            }
            Label("仅外观 · 数值不变",systemImage:"info.circle").font(.caption).foregroundStyle(GameTheme.muted)
        }.glassPanel(radius:22,padding:12)
    }

    private var identity:some View {
        VStack(alignment:.leading,spacing:10){
            GlassHeader(icon:"person.crop.circle",title:"角色")
            if !players.isEmpty {
                Picker("角色",selection:$player){ForEach(players){Text($0.name).tag($0.id)}}.pickerStyle(.segmented)
            }else{Label("无进行中行程 · 可先存到人物槽",systemImage:"tray").font(.caption).foregroundStyle(GameTheme.muted)}
            HStack(spacing:8){
                GlassField(icon:"character.cursor.ibeam",placeholder:"人物名",text:$name,limit:40)
                Button{renameWithAlert()}label:{Image(systemName:"pencil")}.buttonStyle(GlassIconButtonStyle()).accessibilityLabel("弹窗输入名字")
            }
        }.glassPanel()
    }
    /// Fallback name entry through a system alert (always accepts typing, including the Chinese keyboard).
    private func renameWithAlert(){
        guard let host=game.privatePresenter else{return}
        var top=host;while let next=top.presentedViewController{top=next}
        let alert=UIAlertController(title:"人物名",message:nil,preferredStyle:.alert)
        alert.addTextField{$0.text=name;$0.placeholder="1-40字";$0.clearButtonMode = .whileEditing}
        alert.addAction(UIAlertAction(title:"取消",style:.cancel))
        alert.addAction(UIAlertAction(title:"确定",style:.default){_ in
            let value=(alert.textFields?.first?.text ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
            if !value.isEmpty{name=String(value.prefix(40))}
        })
        top.present(alert,animated:true)
    }

    /// A row of picture tiles; `zoomOnFace` crops to the head so faces can be told apart.
    private func choice(_ title:String,_ icon:String,options:[(String,String)],selection:Binding<String>,zoomOnFace:Bool=false,look:@escaping (String)->PlayerAppearance)->some View {
        VStack(alignment:.leading,spacing:8){
            GlassHeader(icon:icon,title:title)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:96),spacing:10)],spacing:10){
                ForEach(options,id:\.0){id,label in
                    let selected=selection.wrappedValue==id
                    Button{withAnimation(.spring(response:0.3,dampingFraction:0.7)){selection.wrappedValue=id}}label:{
                        VStack(spacing:4){
                            ZStack{
                                RoundedRectangle(cornerRadius:12,style:.continuous).fill(LinearGradient(colors:[Color(red:0.42,green:0.62,blue:0.45).opacity(0.55),Color(red:0.20,green:0.36,blue:0.24).opacity(0.65)],startPoint:.top,endPoint:.bottom))
                                if let image=tile(key:title+id,look:look(id),zoom:zoomOnFace){Image(uiImage:image).interpolation(.none).resizable().scaledToFit().padding(2)}
                            }.frame(height:96)
                            Text(label).font(.caption.weight(selected ? .bold:.regular)).lineLimit(1).minimumScaleFactor(0.7)
                        }.padding(5)
                        .background(GlassFill.button,in:RoundedRectangle(cornerRadius:14,style:.continuous))
                        .overlay(RoundedRectangle(cornerRadius:14,style:.continuous).stroke(selected ? GameTheme.accent:.white.opacity(0.5),lineWidth:selected ? 3:1))
                        .overlay(alignment:.topTrailing){if selected{Image(systemName:"checkmark.circle.fill").foregroundStyle(.white,GameTheme.accent).font(.system(size:18)).padding(6)}}
                        .scaleEffect(selected ? 1.03:1)
                    }.buttonStyle(.plain).foregroundStyle(GameTheme.ink)
                }
            }
        }.glassPanel()
    }

    private var actions:some View {
        VStack(alignment:.leading,spacing:12){
            GlassHeader(icon:"square.and.arrow.down.on.square",title:"保存")
            Text(notice).font(.footnote).foregroundStyle(GameTheme.muted).lineLimit(2)
            HStack(spacing:10){
                Button{
                    let profile=MeadowPlayerProfile(name:name.trimmingCharacters(in:.whitespacesAndNewlines),appearance:appearance),id=player
                    ask("将姓名和装扮应用到该角色？职业、数值、装备和行程保持不变。"){try game.applyProfile(profile,to:id);notice="已应用到 "+profile.name+"。"}
                }label:{Label("应用",systemImage:"person.fill.checkmark")}
                .buttonStyle(GlassIconButtonStyle(prominent:true)).disabled(game.busy || game.campaign==nil || game.campaign?.isCompleted==true || players.isEmpty)
                Button{readPlayer()}label:{Label("还原",systemImage:"arrow.uturn.backward")}.buttonStyle(GlassIconButtonStyle()).disabled(players.isEmpty)
                Divider().frame(height:40)
                Picker("人物槽",selection:$slot){ForEach(1...MeadowSlotStore.profileCount,id:\.self){s in Text("\(s)"+(used[s].map{" · "+$0} ?? " · 空")).tag(s)}}
                    .pickerStyle(.menu).padding(.horizontal,6).frame(minHeight:48).background(GlassFill.button,in:RoundedRectangle(cornerRadius:14,style:.continuous))
                Button{
                    let profile=MeadowPlayerProfile(name:name.trimmingCharacters(in:.whitespacesAndNewlines),appearance:appearance),target=slot
                    let save={try store.saveProfile(profile,slot:target,title:profile.name);notice="已保存到人物槽\(target)。";scanSlots()}
                    if used[target] != nil{ask("覆盖人物槽\(target)（\(used[target] ?? "")）？",action:save)}else{do{try save()}catch{notice="未保存："+error.localizedDescription}}
                }label:{Label("存入",systemImage:"tray.and.arrow.down.fill")}.buttonStyle(GlassIconButtonStyle(tint:GameTheme.accent,prominent:true))
                Button{
                    do{guard let p=try store.profile(slot)?.value else{notice="人物槽\(slot)是空的。";return}
                        name=p.name;body_=p.appearance.body;outfit=p.appearance.outfit ?? "follow";hair=p.appearance.hair ?? "original";face=p.appearance.face ?? "original";notice="已读取人物槽\(slot)到编辑区。"}
                    catch{notice="读取失败，原文件保留："+error.localizedDescription}
                }label:{Label("读取",systemImage:"tray.and.arrow.up")}.buttonStyle(GlassIconButtonStyle()).disabled(used[slot]==nil)
            }
            Label("\(MeadowSlotStore.profileCount) 个人物槽 · 新行程可读取",systemImage:"square.grid.3x3").font(.caption).foregroundStyle(GameTheme.muted)
        }.glassPanel()
    }

    // MARK: pictures

    private func look(body:String?=nil,outfit:String?=nil,hair:String?=nil,face:String?=nil)->PlayerAppearance {
        var a=appearance
        if let body{a.body=body}
        if let outfit{a.outfit=outfit=="follow" ? nil:outfit}
        if let hair{a.hair=hair=="original" ? nil:hair}
        if let face{a.face=face=="original" ? nil:face}
        return a
    }
    /// The figure stands about x 88-157, y 79-213 in its 256 px cell: crops keep it large in the frame.
    private static let bodyCrop=CGRect(x:52,y:56,width:152,height:168),headCrop=CGRect(x:94,y:72,width:66,height:66)
    private func cell(facing:Int,column:Int,look:PlayerAppearance,crop:CGRect=Self.bodyCrop)->UIImage? {
        guard let full=CustomAppearanceAssets.cell(body:look.body,armor:look.armor(worn:worn),weapon:weapon,hair:look.hair,face:look.face,facing:facing,column:column) else{return nil}
        return full.cgImage?.cropping(to:crop).map{UIImage(cgImage:$0)} ?? full
    }
    private func tile(key:String,look:PlayerAppearance,zoom:Bool)->UIImage? {
        let full=key+"|"+look.visualKey
        if let image=tiles[full]{return image}
        // Faces: the head only.
        guard let result=cell(facing:0,column:0,look:look,crop:zoom ? Self.headCrop:Self.bodyCrop) else{return nil}
        DispatchQueue.main.async{tiles[full]=result}
        return result
    }

    private func readPlayer(){
        guard let u=game.campaign?.engine.state.units[player] else{return}
        name=u.name
        let a=u.appearance ?? .init(body:game.campaign?.snapshot.appearanceID ?? "forester")
        body_=a.body;outfit=a.outfit ?? "follow";hair=a.hair ?? "original";face=a.face ?? "original"
    }
    private func scanSlots(){
        var found=[Int:String]()
        for s in 1...MeadowSlotStore.profileCount{if let p=try? store.profile(s){found[s]=p.value.name}}
        used=found
        if used[slot] != nil,let free=(1...MeadowSlotStore.profileCount).first(where:{used[$0]==nil}){slot=free}
    }
    private func ask(_ message:String,action:@escaping ()throws->Void){confirmation=message;pending=action;confirm=true}
    private func run(){defer{pending=nil};do{try pending?()}catch{notice="未完成："+error.localizedDescription}}
}
