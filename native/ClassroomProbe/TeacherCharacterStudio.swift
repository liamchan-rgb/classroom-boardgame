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

    static let hairNames=["男式 · 短碎发","男式 · 偏分发","男式 · 小束发","女式 · 紫色盖耳长发","女式 · 侧马尾","女式 · 盘发"]
    static let faceNames=["明朗 · 蓝瞳","沉静 · 琥珀瞳","柔和 · 绿瞳","清晰 · 紫瞳"]
    static let outfits:[(String,String)]=[("follow","跟随实际护甲"),("blue","基础衣装"),("leatherArmor","皮甲"),("runeArmor","符文甲"),("starlightArmor","星辉甲"),("dragonArmor","龙纹甲")]
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
                        choice("外观款式",options:[("forester","林间绿衣"),("wayfarer","行旅蓝衣")],selection:$body_){id in look(body:id)}
                        choice("发型 · 可自由搭配",options:[("original","原有发型")]+zip(PlayerAppearance.hairOptions,Self.hairNames).map{($0,$1)},selection:$hair){id in look(hair:id)}
                        choice("五官 · 可自由搭配",options:[("original","原有五官")]+zip(PlayerAppearance.faceOptions,Self.faceNames).map{($0,$1)},selection:$face,zoomOnFace:true){id in look(face:id)}
                        choice("衣装装扮（不提供装备属性）",options:Self.outfits,selection:$outfit){id in look(outfit:id)}
                        actions
                    }.padding(.trailing,6)
                }
            }.padding(18)
            .background(GameTheme.background)
            .navigationTitle("人物自定义")
            .toolbar{ToolbarItem(placement:.cancellationAction){Button("关闭"){onClose()}}}
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
                    Ellipse().fill(.black.opacity(0.25)).frame(width:110,height:24).offset(y:-44)
                    if let image=cell(facing:facing,column:column,look:appearance){
                        Image(uiImage:image).interpolation(.none).resizable().scaledToFit().frame(width:310,height:310).offset(y:6)
                    }else{Text("预览素材缺失").foregroundStyle(.white)}
                    Text(Self.turnNames[Self.turn.firstIndex(of:facing) ?? 0]).font(.caption.bold()).foregroundStyle(.white.opacity(0.85)).padding(6)
                        .background(.black.opacity(0.3),in:Capsule()).padding(.bottom,10)
                }
                .frame(height:360).clipShape(RoundedRectangle(cornerRadius:16))
                .overlay(RoundedRectangle(cornerRadius:16).stroke(GameTheme.accent,lineWidth:2))
            }
            HStack{
                Button{turning=false;facingIndex=(facingIndex+7)%8}label:{Image(systemName:"arrow.counterclockwise")}
                Button(turning ? "停在当前方向":"自动转身"){if turning{facingIndex=0};turning.toggle()}
                Button{turning=false;facingIndex=(facingIndex+1)%8}label:{Image(systemName:"arrow.clockwise")}
            }.buttonStyle(.bordered)
            // All eight standing poses at once.
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:4),spacing:4){
                ForEach(0..<8,id:\.self){i in
                    Button{turning=false;facingIndex=i}label:{
                        ZStack{
                            RoundedRectangle(cornerRadius:8).fill(Color(red:0.23,green:0.38,blue:0.25))
                            if let image=cell(facing:Self.turn[i],column:0,look:appearance){Image(uiImage:image).interpolation(.none).resizable().scaledToFit()}
                        }.frame(height:76).overlay(RoundedRectangle(cornerRadius:8).stroke(!turning && facingIndex==i ? GameTheme.accent:.clear,lineWidth:2))
                    }.buttonStyle(.plain)
                }
            }
            Text("衣装只是装扮：武器跟随实际装备，职业、数值和装备都不变。").font(.caption).foregroundStyle(GameTheme.muted)
        }
    }

    private var identity:some View {
        VStack(alignment:.leading,spacing:8){
            Text("角色").font(.headline)
            if !players.isEmpty {
                Picker("当前行程中的角色",selection:$player){ForEach(players){Text($0.name).tag($0.id)}}.pickerStyle(.segmented)
            }else{Text("还没有进行中的行程：可以先设计外观并保存到人物槽，开始新行程时读取。").font(.caption).foregroundStyle(GameTheme.muted)}
            TextField("人物名（1-40字）",text:$name).textFieldStyle(.roundedBorder)
        }
    }

    /// A row of picture tiles; `zoomOnFace` crops to the head so faces can be told apart.
    private func choice(_ title:String,options:[(String,String)],selection:Binding<String>,zoomOnFace:Bool=false,look:@escaping (String)->PlayerAppearance)->some View {
        VStack(alignment:.leading,spacing:8){
            Text(title).font(.headline)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:104),spacing:10)],spacing:10){
                ForEach(options,id:\.0){id,label in
                    let selected=selection.wrappedValue==id
                    Button{withAnimation(.spring(response:0.3,dampingFraction:0.7)){selection.wrappedValue=id}}label:{
                        VStack(spacing:4){
                            ZStack{
                                RoundedRectangle(cornerRadius:10).fill(Color(red:0.22,green:0.35,blue:0.24))
                                if let image=tile(key:title+id,look:look(id),zoom:zoomOnFace){Image(uiImage:image).interpolation(.none).resizable().scaledToFit().padding(2)}
                            }.frame(height:96)
                            Text(label).font(.caption.weight(selected ? .bold:.regular)).lineLimit(1).minimumScaleFactor(0.7)
                        }.padding(5)
                        .background(selected ? GameTheme.accent.opacity(0.18):Color.clear,in:RoundedRectangle(cornerRadius:12))
                        .overlay(RoundedRectangle(cornerRadius:12).stroke(selected ? GameTheme.accent:GameTheme.ink.opacity(0.15),lineWidth:selected ? 3:1))
                        .scaleEffect(selected ? 1.03:1)
                    }.buttonStyle(.plain).foregroundStyle(GameTheme.ink)
                }
            }
        }
    }

    private var actions:some View {
        VStack(alignment:.leading,spacing:10){
            Text("保存与应用").font(.headline)
            Text(notice).font(.callout).foregroundStyle(GameTheme.muted)
            HStack{
                Button("应用到当前角色"){
                    let profile=MeadowPlayerProfile(name:name,appearance:appearance),id=player
                    ask("将姓名和装扮应用到该角色？职业、数值、装备和行程保持不变。"){try game.applyProfile(profile,to:id);notice="已应用到 "+profile.name+"。"}
                }.buttonStyle(.borderedProminent).disabled(game.busy || game.campaign==nil || game.campaign?.isCompleted==true || players.isEmpty)
                Button("重新读取该角色"){readPlayer()}.buttonStyle(.bordered).disabled(players.isEmpty)
            }
            HStack{
                Picker("人物槽",selection:$slot){ForEach(1...MeadowSlotStore.profileCount,id:\.self){s in Text("人物槽\(s)"+(used[s].map{" · "+$0} ?? " · 空")).tag(s)}}
                Button("保存到此槽"){
                    let profile=MeadowPlayerProfile(name:name,appearance:appearance),target=slot
                    let save={try store.saveProfile(profile,slot:target,title:profile.name);notice="已保存到人物槽\(target)。";scanSlots()}
                    if used[target] != nil{ask("覆盖人物槽\(target)（\(used[target] ?? "")）？",action:save)}else{do{try save()}catch{notice="未保存："+error.localizedDescription}}
                }.buttonStyle(.borderedProminent)
                Button("从此槽读取"){
                    do{guard let p=try store.profile(slot)?.value else{notice="人物槽\(slot)是空的。";return}
                        name=p.name;body_=p.appearance.body;outfit=p.appearance.outfit ?? "follow";hair=p.appearance.hair ?? "original";face=p.appearance.face ?? "original";notice="已读取人物槽\(slot)到编辑区。"}
                    catch{notice="读取失败，原文件保留："+error.localizedDescription}
                }.buttonStyle(.bordered).disabled(used[slot]==nil)
            }
            Text("人物槽共\(MeadowSlotStore.profileCount)个，只存姓名和装扮；开始新行程时可在“随机地图与新行程”里给每位学生读取。").font(.caption).foregroundStyle(GameTheme.muted)
        }
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
    private func cell(facing:Int,column:Int,look:PlayerAppearance)->UIImage? {
        CustomAppearanceAssets.cell(body:look.body,armor:look.armor(worn:worn),weapon:weapon,hair:look.hair,face:look.face,facing:facing,column:column)
    }
    private func tile(key:String,look:PlayerAppearance,zoom:Bool)->UIImage? {
        let full=key+"|"+look.visualKey
        if let image=tiles[full]{return image}
        guard let image=cell(facing:0,column:0,look:look) else{return nil}
        // Faces: the head only (upper middle of the 256 px cell).
        let result=zoom ? (image.cgImage?.cropping(to:CGRect(x:78,y:28,width:100,height:100)).map{UIImage(cgImage:$0)} ?? image):image
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
