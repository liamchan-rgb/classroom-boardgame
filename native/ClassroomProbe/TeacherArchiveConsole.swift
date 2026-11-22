import SwiftUI
import ClassroomGameCore
import MeadowWorldSupport

/// Private teacher-only modal; never attached to the public renderer tree.
struct TeacherArchiveConsole:View {
    @ObservedObject var game:MeadowTeacherCoordinator
    var onClose:()->Void
    @State private var transfer:TeacherSaveTransferRequest?
    @State private var tab=1
    @State private var journeyQuery=MeadowJourneyQuery()
    @State private var journeyRows:[MeadowJourneyIndex]=[]
    @State private var historyQuery=MeadowHistoryQuery()
    @State private var historyRows:[MeadowHistoryIndex]=[]
    @State private var historyPeople:[String:String]=[:]
    @State private var historyLimit=50
    @State private var historyIndexToken=UUID()
    @State private var indexingHistory=false
    private var matchingJourneys:[MeadowJourneyIndex]{journeyQuery.apply(journeyRows)}
    private var matchingHistory:[MeadowHistoryIndex]{historyQuery.apply(historyRows)}
    private var emptyJourneySlots:[Int]{(1...MeadowSlotStore.campaignCount).filter{journeys[$0]==nil && errors["j\($0)"]==nil}}
    private var damagedJourneySlots:[Int]{(1...MeadowSlotStore.campaignCount).filter{errors["j\($0)"] != nil}}
    @State private var player="p1"
    @State private var name=""
    @State private var bodyStyle="forester"
    @State private var outfit="follow"
    @State private var hair="original"
    @State private var face="original"
    @State private var title="课堂行程"
    @State private var notice=""
    @State private var profiles:[Int:MeadowSaveSlot<MeadowPlayerProfile>]=[:]
    @State private var journeys:[Int:MeadowSaveSlot<MeadowCampaignSave>]=[:]
    @State private var errors:[String:String]=[:]
    @State private var recoveries:[URL]=[]
    @State private var thumbnail:UIImage?
    @State private var teacherName="老师"
    @State private var teacherClass="adventurer"
    @State private var teacherTeam="party"
    @State private var confirm=false
    @State private var confirmation=""
    @State private var pending:(()throws->Void)?
    /// 50 slots each: by default only used slots and a few empty ones are listed.
    @State private var showAllProfiles=false
    @State private var showAllEmptyJourneys=false
    private var listedProfileSlots:[Int] {
        let all=Array(1...MeadowSlotStore.profileCount)
        if showAllProfiles{return all}
        let used=all.filter{profiles[$0] != nil || errors["p\($0)"] != nil}
        return (used+all.filter{!used.contains($0)}.prefix(3)).sorted()
    }
    private var store:MeadowSlotStore {MeadowTeacherCoordinator.slotStore}
    private var players:[GameUnit] {game.campaign?.engine.state.players ?? []}
    private var appearance:PlayerAppearance {.init(body:bodyStyle,outfit:outfit=="follow" ? nil:outfit,hair:hair=="original" ? nil:hair,face:face=="original" ? nil:face)}
    private var profile:MeadowPlayerProfile {.init(name:name,appearance:appearance)}
    private var tabCaption:String {
        switch tab {
        case 1:return "每个行程槽保存整局进度（地图、队伍、背包、战斗）。读取前会自动备份当前行程。"
        case 0:return "人物档案只存姓名和装扮，新行程时可以给学生复用。"
        case 2:return "每一步操作都有记录；可以回退到某一条之后，回退前自动备份。"
        default:return "老师可以作为第7名成员加入，不占学生名额。"
        }
    }
    var body:some View {
        NavigationStack {
            VStack(alignment:.leading,spacing:8) {
                Picker("管理内容",selection:$tab){Label("行程",systemImage:"map").tag(1);Label("人物",systemImage:"person.crop.square").tag(0);Label("历史",systemImage:"clock.arrow.circlepath").tag(2);Label("老师",systemImage:"graduationcap").tag(3)}.pickerStyle(.segmented)
                Text(tabCaption).font(.callout).foregroundStyle(.secondary)
                if !notice.isEmpty{Label(notice,systemImage:notice.hasPrefix("未完成") ? "exclamationmark.triangle.fill":"checkmark.circle.fill").font(.callout.bold()).foregroundStyle(notice.hasPrefix("未完成") ? Color.red:GameTheme.primary)}
                Form {
                    if tab==0{profileForm}
                    else if tab==1{journeyForm}
                    else if tab==2{historyForm}
                    else{teacherForm}
                }.scrollContentBackground(.hidden)
            }.padding(.horizontal).padding(.top,8).background(GlassBackdrop()).navigationTitle("存档与历史")
                .toolbar{
                    ToolbarItem(placement:.cancellationAction){Button("完成"){onClose()}}
                    ToolbarItem(placement:.confirmationAction){Menu{
                        Button{transfer=TeacherSaveTransferRequest()}label:{Label("导出槽位备份…",systemImage:"square.and.arrow.up")}
                        Button{transfer=TeacherSaveTransferRequest(importing:true)}label:{Label("从文件导入…",systemImage:"square.and.arrow.down")}
                    }label:{Label("导入导出",systemImage:"arrow.up.arrow.down.circle").labelStyle(.titleAndIcon)}}
                }
                .sheet(item:$transfer,onDismiss:{reload()}){request in TeacherSaveTransferConsole(directory:store.directory,request:request,onClose:{transfer=nil})}
                .onAppear{player=game.campaign?.selectedPlayerID ?? "p1";readPlayer();reload();rebuildHistory();teacherTeam=game.campaign?.engine.state.teams.first?.id ?? "party"}
                .onChange(of:game.campaign?.engine.history.last?.id){_,_ in rebuildHistory()}
                .onChange(of:game.campaign?.engine.state.gameID){_,_ in rebuildHistory()}
                .onChange(of:historyQuery){_,_ in historyLimit=50}
                .onChange(of:tab){_,_ in notice=""}
                .onChange(of:player){_,_ in readPlayer()}
                .onChange(of:bodyStyle){_,_ in updateThumbnail()}
                .onChange(of:outfit){_,_ in updateThumbnail()}
                .onChange(of:hair){_,_ in updateThumbnail()}
                .onChange(of:face){_,_ in updateThumbnail()}
                .alert("确认操作",isPresented:$confirm){Button("取消",role:.cancel){pending=nil};Button("确认",role:.destructive){executePending()}}message:{Text(confirmation)}
        }
    }
    private var profileForm:some View {
        Group {
            Section("编辑姓名与装扮") {
                if !players.isEmpty{Picker("角色",selection:$player){ForEach(players){Text($0.name).tag($0.id)}}}
                HStack{Text("姓名");ClassroomTextField(placeholder:"人物名（最多40字）",text:$name)}
                Picker("款式",selection:$bodyStyle){Text("林间绿衣").tag("forester");Text("行旅蓝衣").tag("wayfarer")}
                Picker("衣装",selection:$outfit){Text("跟随实际护甲").tag("follow");Text("基础衣装").tag("blue");Text("皮甲").tag("leatherArmor");Text("符文甲").tag("runeArmor");Text("星辉甲 · 天仪礼甲").tag("starlightArmor");Text("龙纹甲 · 龙翼巡游甲").tag("dragonArmor")}
                Picker("发型",selection:$hair){Text("原有发型").tag("original");ForEach(Array(PlayerAppearance.hairOptions.enumerated()),id:\.element){i,id in Text(["男式 · 短碎发","男式 · 偏分发","男式 · 小束发","女式 · 紫色盖耳长发","女式 · 侧马尾","女式 · 盘发"][i]).tag(id)}}
                Picker("五官",selection:$face){Text("原有五官").tag("original");ForEach(Array(PlayerAppearance.faceOptions.enumerated()),id:\.element){i,id in Text(["明朗 · 蓝瞳","沉静 · 琥珀瞳","柔和 · 绿瞳","清晰 · 紫瞳"][i]).tag(id)}}
                if let thumbnail{Image(uiImage:thumbnail).interpolation(.none).resizable().scaledToFit().frame(height:130).frame(maxWidth:.infinity).background(Color(red:0.08,green:0.17,blue:0.12))}
                Text("只换样子，不改职业、数值和装备；武器跟随实际装备。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("应用到这个角色"){let p=profile;ask("把姓名和装扮应用到这个角色？职业、数值、装备和行程不变。"){try game.applyProfile(p,to:player);notice=game.message}}.buttonStyle(.borderedProminent).disabled(game.busy || game.campaign==nil || game.campaign?.isCompleted==true)
                    Button("重新读取"){readPlayer()}.buttonStyle(.bordered).disabled(players.isEmpty)
                }
            }.glassRow()
            Section("人物槽（共\(MeadowSlotStore.profileCount)个）") {
                ForEach(listedProfileSlots,id:\.self){slot in
                    HStack(spacing:10) {
                        VStack(alignment:.leading,spacing:2) {
                            Text("\(slot) · "+(profiles[slot]?.value.name ?? "空槽")).font(.headline).foregroundStyle(profiles[slot]==nil ? .secondary:.primary)
                            if let entry=profiles[slot]{Text(entry.savedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)}
                            if let error=errors["p\(slot)"]{Text("无法读取，原文件保留："+error).font(.caption).foregroundStyle(.red)}
                        }
                        Spacer()
                        if let p=profiles[slot]?.value {
                            Button("读到编辑区"){name=p.name;bodyStyle=p.appearance.body;outfit=p.appearance.outfit ?? "follow";hair=p.appearance.hair ?? "original";face=p.appearance.face ?? "original";updateThumbnail();notice="已读到编辑区，还没有应用到角色。"}.buttonStyle(.bordered)
                        }
                        Menu{
                            Button{let p=profile;savePrompt(occupied:profiles[slot] != nil || errors["p\(slot)"] != nil,message:"覆盖人物槽\(slot)？"){try store.saveProfile(p,slot:slot,title:p.name);notice="人物档案已保存到槽\(slot)。"}}label:{Label(profiles[slot]==nil ? "把编辑区存到这里":"用编辑区覆盖",systemImage:"square.and.arrow.down")}
                            Button{transfer=TeacherSaveTransferRequest(selection:[.init(.profile,slot)])}label:{Label("导出…",systemImage:"square.and.arrow.up")}.disabled(profiles[slot]==nil)
                        }label:{Image(systemName:"ellipsis.circle").font(.title3)}.menuStyle(.button).buttonStyle(.borderless).frame(width:36)
                    }
                }
                Button(showAllProfiles ? "只显示已用和3个空槽":"显示全部\(MeadowSlotStore.profileCount)个"){showAllProfiles.toggle()}.font(.callout)
            }.glassRow()
        }
    }
    private var journeyForm:some View {
        Group {
            Section("保存当前行程") {
                HStack {
                    ClassroomTextField(placeholder:"存档标题",text:$title)
                    if let slot=emptyJourneySlots.first {
                        Button("保存到新槽（\(slot)）"){saveJourney(slot)}.buttonStyle(.borderedProminent).disabled(game.campaign==nil || game.busy)
                        if emptyJourneySlots.count>1 {
                            Menu{ForEach(emptyJourneySlots,id:\.self){s in Button("行程槽 \(s)"){saveJourney(s)}}}label:{Text("选空槽")}.menuStyle(.button).buttonStyle(.bordered).fixedSize().disabled(game.campaign==nil || game.busy)
                        }
                    } else {Text("没有空槽，在下面选一个覆盖").font(.caption).foregroundStyle(.secondary)}
                }
            }.glassRow()
            Section {
                HStack{Image(systemName:"magnifyingglass").foregroundStyle(.secondary);ClassroomTextField(placeholder:"搜索标题 / 成员 / 队伍 / 种子",text:$journeyQuery.text)}
                DisclosureGroup("筛选与排序") {
                    Picker("状态",selection:$journeyQuery.state){ForEach(MeadowJourneyState.allCases,id:\.rawValue){Text($0.title).tag($0)}}
                    Picker("人数",selection:$journeyQuery.players){Text("全部人数").tag(0);ForEach(1...7,id:\.self){Text("\($0)人").tag($0)}}
                    Picker("排序",selection:$journeyQuery.order){ForEach(MeadowArchiveOrder.allCases,id:\.rawValue){Text($0.title).tag($0)}}
                    Button("清除筛选"){journeyQuery=MeadowJourneyQuery()}.disabled(journeyQuery==MeadowJourneyQuery())
                }
                ForEach(matchingJourneys){row in
                    HStack(spacing:10) {
                        VStack(alignment:.leading,spacing:2) {
                            Text("\(row.slot) · "+row.title).font(.headline)
                            Text("\(row.state.title) · \(row.players)人 · "+row.savedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("读取"){if let entry=journeys[row.slot]{ask("读取“\(entry.title)”？当前行程会先自动备份。"){try load(entry.value)}}}.buttonStyle(.borderedProminent).disabled(game.busy)
                        Menu{
                            Button{saveJourney(row.slot)}label:{Label("用当前行程覆盖",systemImage:"square.and.arrow.down")}.disabled(game.campaign==nil || game.busy)
                            Button{transfer=TeacherSaveTransferRequest(selection:[.init(.campaign,row.slot)])}label:{Label("导出…",systemImage:"square.and.arrow.up")}.disabled(game.busy)
                        }label:{Image(systemName:"ellipsis.circle").font(.title3)}.menuStyle(.button).buttonStyle(.borderless).frame(width:36)
                    }
                }
                if matchingJourneys.isEmpty{Text(journeyRows.isEmpty ? "还没有保存过行程。":"没有匹配的行程。").foregroundStyle(.secondary)}
            } header:{Text("已保存的行程（\(matchingJourneys.count) / \(journeyRows.count)）")}.glassRow()
            if !damagedJourneySlots.isEmpty {
                Section("无法读取的槽（原文件保留）") {
                    ForEach(damagedJourneySlots,id:\.self){slot in
                        HStack {
                            Text("行程槽\(slot) · "+(errors["j\(slot)"] ?? "未知错误")).font(.caption).foregroundStyle(.red)
                            Spacer()
                            Button("用当前行程覆盖"){saveJourney(slot)}.buttonStyle(.bordered).disabled(game.campaign==nil || game.busy)
                        }
                    }
                }.glassRow()
            }
            Section {
                DisclosureGroup("读取前的自动备份（\(min(recoveries.count,20))）") {
                    if recoveries.isEmpty{Text("暂无备份。").foregroundStyle(.secondary)}
                    ForEach(recoveries.prefix(20),id:\.path){url in
                        HStack{Text(recoveryTitle(url));Spacer();Button("恢复"){ask("恢复这份自动备份？当前进度也会先备份。"){try load(MeadowCampaignSave.decoded(Data(contentsOf:url)))}}.buttonStyle(.bordered)}
                    }
                    Text("只列最近20份，旧文件仍留在本机。").font(.caption).foregroundStyle(.secondary)
                }
            }.glassRow()
        }
    }
    private var historyForm:some View {
        Group {
            Section {
                HStack{Image(systemName:"magnifyingglass").foregroundStyle(.secondary);ClassroomTextField(placeholder:"搜索操作 / 姓名 / 序号",text:$historyQuery.text)}
                DisclosureGroup("筛选与排序") {
                    Picker("类别",selection:$historyQuery.category){ForEach(MeadowHistoryCategory.allCases,id:\.rawValue){Text($0.title).tag($0)}}
                    Picker("涉及",selection:Binding(get:{historyQuery.participant ?? ""},set:{historyQuery.participant=$0.isEmpty ? nil:$0})){
                        Text("全部对象").tag("")
                        ForEach(historyPeople.keys.sorted(),id:\.self){id in Text((historyPeople[id] ?? id)+" · "+id).tag(id)}
                    }
                    Toggle("最新的在前",isOn:$historyQuery.newestFirst)
                    Button("清除筛选"){historyQuery=MeadowHistoryQuery()}.disabled(historyQuery==MeadowHistoryQuery())
                }
                if indexingHistory{ProgressView("正在整理历史…")}
                ForEach(Array(matchingHistory.prefix(historyLimit))){row in
                    if let history=game.campaign?.engine.history,history.indices.contains(row.sequence-1),history[row.sequence-1].id==row.id {
                        historyRecord(history[row.sequence-1],row:row)
                    }
                }
                if !indexingHistory && matchingHistory.isEmpty{Text(historyRows.isEmpty ? "还没有操作记录。":"没有匹配的记录。").foregroundStyle(.secondary)}
                if matchingHistory.count>historyLimit{Button("再显示50条（\(min(historyLimit,matchingHistory.count)) / \(matchingHistory.count)）"){historyLimit += 50}}
            } header:{Text("操作记录（\(matchingHistory.count) / \(historyRows.count)）")} footer:{Text("回退会保留所选记录、撤回它之后的全部操作（包括被筛选隐藏的）。")}.glassRow()
        }
    }
    private func historyRecord(_ entry:OperationReceipt,row:MeadowHistoryIndex)->some View {
        DisclosureGroup("#\(entry.sequence) · "+row.category.title+" · "+row.title) {
            Text(String(describing:entry.command)).font(.caption).textSelection(.enabled)
            ForEach(Array(entry.dice.enumerated()),id:\.offset){_,d in Text("骰子：\(d.values.map(String.init).joined(separator:"、")) → \(d.total)").font(.caption)}
            ForEach(entry.after.players){unit in
                if let before=entry.before.units[unit.id],before != unit{Text("\(unit.name) · HP \(before.health)→\(unit.health) · AP \(before.ap)→\(unit.ap) · 金币 \(before.coins)→\(unit.coins)").font(.caption)}
            }
            Button("回退到这条之后"){let count=(game.campaign?.engine.history.count ?? 0)-entry.sequence;ask("保留第\(entry.sequence)条，撤回它之后的全部\(count)条（包括当前没显示的）？"){try game.rollback(to:entry.id);notice=game.message}}.buttonStyle(.bordered).disabled(game.busy || indexingHistory)
        }
    }
    private func rebuildHistory(){
        let token=UUID();historyIndexToken=token;historyLimit=50;historyRows=[];historyPeople=[:]
        guard let archive=game.campaign?.engine.archive else{indexingHistory=false;return}
        indexingHistory=true
        Task {
            let result=await Task.detached(priority:.userInitiated){()->([MeadowHistoryIndex],[String:String]) in
                let rows=archive.history.map{MeadowHistoryIndex(entry:$0,catalog:archive.catalog)}
                var names=[String:String]()
                for entry in archive.history {for id in Set(entry.before.units.keys).union(entry.after.units.keys){names[id]=entry.after.units[id]?.name ?? entry.before.units[id]?.name}}
                let used=Set(rows.flatMap(\.participants));return (rows,names.filter{used.contains($0.key)})
            }.value
            guard historyIndexToken==token else{return}
            historyRows=result.0;historyPeople=result.1;indexingHistory=false
            if let id=historyQuery.participant,historyPeople[id]==nil{historyQuery.participant=nil}
        }
    }
    private var teacherForm:some View {
        Section("老师参战（第7名成员）") {
            if let host=players.first(where:{$0.host}){Label("老师已参战："+host.name,systemImage:"checkmark.circle.fill")}
            else {
                ClassroomTextField(placeholder:"老师人物名",text:$teacherName)
                Picker("职业",selection:$teacherClass){ForEach(MeadowPartyConfiguration.classIDs,id:\.self){id in Text((try? game.campaign?.engine.catalog.playerClass(id).name) ?? id).tag(id)}}
                Picker("加入队伍",selection:$teacherTeam){ForEach(game.campaign?.engine.state.teams ?? []){Text($0.name).tag($0.id)}}
                Button("加入行程"){ask("老师加入行程（不占学生名额），使用“人物”里编辑区的装扮？"){try game.joinTeacher(name:teacherName,classID:teacherClass,team:teacherTeam,appearance:appearance);notice=game.message}}.buttonStyle(.borderedProminent).disabled(game.campaign==nil || game.busy || game.campaign?.travel != nil || game.campaign?.engine.state.battle != nil || game.campaign?.isCompleted==true)
                Text("只能在探索中、队伍没有在走路时加入。").font(.caption).foregroundStyle(.secondary)
            }
        }.glassRow()
    }
    private func updateThumbnail(){let index=HeroFrames.appearanceIDs.firstIndex(of:bodyStyle) ?? 0;thumbnail=HeroFrames.inventoryImages(appearanceIndex:index,weaponID:nil,armorID:appearance.armor(worn:game.campaign?.engine.state.units[player]?.equipment.armor),hair:appearance.hair,face:appearance.face).first}
    private func readPlayer(){guard let u=game.campaign?.engine.state.units[player] else{updateThumbnail();return};name=u.name;let a=u.appearance ?? .init(body:game.campaign?.snapshot.appearanceID ?? "forester");bodyStyle=a.body;outfit=a.outfit ?? "follow";hair=a.hair ?? "original";face=a.face ?? "original";updateThumbnail()}
    private func ask(_ message:String,action:@escaping ()throws->Void){confirmation=message;pending=action;confirm=true}
    private func executePending(){defer{pending=nil;reload()};do{try pending?()}catch{notice="未完成，原文件保留："+error.localizedDescription}}
    private func savePrompt(occupied:Bool,message:String,action:@escaping ()throws->Void){if occupied{ask(message,action:action)}else{do{try action();reload()}catch{notice="未完成："+error.localizedDescription}}}
    private func saveJourney(_ slot:Int){guard let c=game.campaign else{return};do{try c.checkpoint();let save=c.snapshot,label=title;savePrompt(occupied:journeys[slot] != nil || errors["j\(slot)"] != nil,message:"覆盖行程槽\(slot)？"){try store.saveCampaign(save,slot:slot,title:label);notice="完整行程已保存。"}}catch{notice="未完成："+error.localizedDescription}}
    private func load(_ save:MeadowCampaignSave)throws{var value=save;if value.archive.state.battle != nil{value.archive.state.pauseReasons.insert(.manual)};try game.loadJourney(value);notice=game.message;player=game.campaign?.selectedPlayerID ?? "p1";readPlayer()}
    private func recoveryTitle(_ url:URL)->String{let date=(try? url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast;return date.formatted(date:.abbreviated,time:.shortened)}
    private func reload(){defer{journeyRows=journeys.map{MeadowJourneyIndex(slot:$0.key,entry:$0.value)}};profiles=[:];journeys=[:];errors=[:];for s in 1...MeadowSlotStore.profileCount{do{profiles[s]=try store.profile(s)}catch{errors["p\(s)"]=error.localizedDescription}};for s in 1...MeadowSlotStore.campaignCount{do{journeys[s]=try store.campaign(s)}catch{errors["j\(s)"]=error.localizedDescription}};do{recoveries=try store.recoveries()}catch{notice="未完成：自动备份目录读取失败，"+error.localizedDescription}}
}
