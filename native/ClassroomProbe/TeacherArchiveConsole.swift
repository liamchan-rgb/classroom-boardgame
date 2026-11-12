import SwiftUI
import ClassroomGameCore
import MeadowWorldSupport

/// Private teacher-only modal; never attached to the public renderer tree.
struct TeacherArchiveConsole:View {
    @ObservedObject var game:MeadowTeacherCoordinator
    var onClose:()->Void
    @State private var transfer:TeacherSaveTransferRequest?
    @State private var tab=0
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
    @State private var notice="人物档案只含姓名和装扮；行程槽保存整局进度。"
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
    var body:some View {
        NavigationStack {
            VStack(spacing:0) {
                Picker("管理内容",selection:$tab){Text("人物档案").tag(0);Text("行程槽位").tag(1);Text("操作历史").tag(2);Text("老师参战").tag(3)}.pickerStyle(.segmented).padding()
                Text(notice).font(.callout).foregroundStyle(.secondary).padding(.horizontal)
                Form {
                    if tab==0{profileForm}
                    else if tab==1{journeyForm}
                    else if tab==2{historyForm}
                    else{teacherForm}
                }
            }.navigationTitle("教师 · 档案与行程")
                .toolbar{
                    ToolbarItem(placement:.cancellationAction){Button("关闭"){onClose()}}
                    ToolbarItem(placement:.confirmationAction){Menu("导入导出"){
                        Button("批量导出槽位备份"){transfer=TeacherSaveTransferRequest()}
                        Button("从文件导入备份"){transfer=TeacherSaveTransferRequest(importing:true)}
                    }}
                }
                .sheet(item:$transfer,onDismiss:{reload()}){request in TeacherSaveTransferConsole(directory:store.directory,request:request,onClose:{transfer=nil})}
                .onAppear{player=game.campaign?.selectedPlayerID ?? "p1";readPlayer();reload();rebuildHistory();teacherTeam=game.campaign?.engine.state.teams.first?.id ?? "party"}
                .onChange(of:game.campaign?.engine.history.last?.id){_,_ in rebuildHistory()}
                .onChange(of:game.campaign?.engine.state.gameID){_,_ in rebuildHistory()}
                .onChange(of:historyQuery){_,_ in historyLimit=50}
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
            Section("姓名与自定义外观") {
                if !players.isEmpty{Picker("当前角色",selection:$player){ForEach(players){Text($0.name).tag($0.id)}}}
                TextField("人物名（最多40字）",text:$name)
                Picker("外观款式",selection:$bodyStyle){Text("林间绿衣").tag("forester");Text("行旅蓝衣").tag("wayfarer")}
                Picker("衣装装扮",selection:$outfit){Text("跟随实际护甲").tag("follow");Text("基础衣装").tag("blue");Text("皮甲").tag("leatherArmor");Text("符文甲").tag("runeArmor");Text("星辉甲 · 天仪礼甲").tag("starlightArmor");Text("龙纹甲 · 龙翼巡游甲").tag("dragonArmor")}
                Picker("发型（可自由搭配）",selection:$hair){Text("原有发型").tag("original");ForEach(Array(PlayerAppearance.hairOptions.enumerated()),id:\.element){i,id in Text(["男式 · 短碎发","男式 · 偏分发","男式 · 小束发","女式 · 紫色盖耳长发","女式 · 侧马尾","女式 · 盘发"][i]).tag(id)}}
                Picker("五官（可自由搭配）",selection:$face){Text("原有五官").tag("original");ForEach(Array(PlayerAppearance.faceOptions.enumerated()),id:\.element){i,id in Text(["明朗 · 蓝瞳","沉静 · 琥珀瞳","柔和 · 绿瞳","清晰 · 紫瞳"][i]).tag(id)}}
                if let thumbnail{Image(uiImage:thumbnail).interpolation(.none).resizable().scaledToFit().frame(height:130).frame(maxWidth:.infinity).background(Color(red:0.08,green:0.17,blue:0.12))}
                Text("发型与五官自由组合，同步到探索、背包和战斗。保存人物槽后可在新行程复用。衣装不提供装备属性，武器跟随实际装备；沿用原人物体型与动作。").font(.caption)
                Button("应用到当前角色"){let p=profile;ask("将姓名和装扮应用到当前角色，保留职业、数值、装备和行程？"){try game.applyProfile(p,to:player);notice=game.message}}.disabled(game.busy || game.campaign==nil || game.campaign?.isCompleted==true)
                Button("从当前角色重新读取"){readPlayer()}.disabled(players.isEmpty)
            }
            Section("人物槽 · 共\(MeadowSlotStore.profileCount)个，可供新行程复用") {
                ForEach(listedProfileSlots,id:\.self){slot in
                    VStack(alignment:.leading,spacing:6) {
                        Text("人物槽 \(slot) · "+(profiles[slot]?.value.name ?? "空槽")).font(.headline)
                        if let entry=profiles[slot]{Text(entry.savedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption)}
                        if let error=errors["p\(slot)"]{Text("原文件保留："+error).font(.caption).foregroundStyle(.red)}
                        HStack {
                            Button("保存档案"){let p=profile;savePrompt(occupied:profiles[slot] != nil || errors["p\(slot)"] != nil,message:"覆盖人物槽\(slot)？"){try store.saveProfile(p,slot:slot,title:p.name);notice="人物档案已保存。"}}
                            Button("导出"){transfer=TeacherSaveTransferRequest(selection:[.init(.profile,slot)])}.disabled(profiles[slot]==nil)
                            Button("读取到编辑区"){if let p=profiles[slot]?.value{name=p.name;bodyStyle=p.appearance.body;outfit=p.appearance.outfit ?? "follow";hair=p.appearance.hair ?? "original";face=p.appearance.face ?? "original";updateThumbnail();notice="档案已读取到编辑区；尚未改变行程中的角色。"}}.disabled(profiles[slot]==nil)
                        }.buttonStyle(.bordered)
                    }
                }
                Button(showAllProfiles ? "只显示已用槽位和3个空槽":"显示全部\(MeadowSlotStore.profileCount)个人物槽"){showAllProfiles.toggle()}
            }
        }
    }
    private var journeyForm:some View {
        Group {
            Section("完整行程") {
                TextField("存档标题",text:$title)
                Text("保存地图、队伍、背包、战斗队列/骰子状态、各队移动条和镜头。原自动存档继续生效；读取前另存当前进度。读取战斗槽会保持暂停，等待教师继续。").font(.caption)
            }
            Section("查找已保存行程") {
                HStack{Text("搜索");TextField("标题 / 成员 / 队伍 / 种子",text:$journeyQuery.text)}
                Picker("状态",selection:$journeyQuery.state){ForEach(MeadowJourneyState.allCases,id:\.rawValue){Text($0.title).tag($0)}}
                Picker("人数",selection:$journeyQuery.players){Text("全部人数").tag(0);ForEach(1...7,id:\.self){Text("\($0)人").tag($0)}}
                Picker("排序",selection:$journeyQuery.order){ForEach(MeadowArchiveOrder.allCases,id:\.rawValue){Text($0.title).tag($0)}}
                HStack{Text("匹配 \(matchingJourneys.count) / 已保存 \(journeyRows.count)");Spacer();Button("清除筛选"){journeyQuery=MeadowJourneyQuery()}.disabled(journeyQuery==MeadowJourneyQuery())}.font(.caption)
            }
            Section("已保存行程 · 原槽号保持") {
                ForEach(matchingJourneys){row in
                    VStack(alignment:.leading,spacing:6) {
                        Text("行程槽 \(row.slot) · "+row.title).font(.headline)
                        Text("\(row.state.title) · \(row.players)人 · "+row.savedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption)
                        HStack {
                            Button("覆盖保存"){saveJourney(row.slot)}.disabled(game.campaign==nil || game.busy)
                            Button("导出"){transfer=TeacherSaveTransferRequest(selection:[.init(.campaign,row.slot)])}.disabled(game.busy)
                            Button("读取"){if let entry=journeys[row.slot]{ask("读取“\(entry.title)”？当前行程将先自动备份。"){try load(entry.value)}}}.disabled(game.busy)
                        }.buttonStyle(.bordered)
                    }
                }
                if matchingJourneys.isEmpty{Text(journeyRows.isEmpty ? "暂无已保存行程。":"没有匹配的行程，可清除筛选。")}
            }
            if !damagedJourneySlots.isEmpty {
                Section("无法读取 · 不受筛选隐藏") {
                    ForEach(damagedJourneySlots,id:\.self){slot in
                        Text("行程槽\(slot) · 原文件保留："+(errors["j\(slot)"] ?? "未知错误")).font(.caption).foregroundStyle(.red)
                        Button("覆盖保存到行程槽\(slot)"){saveJourney(slot)}.disabled(game.campaign==nil || game.busy)
                    }
                }
            }
            Section("空槽 · 新建保存") {
                ForEach(showAllEmptyJourneys ? emptyJourneySlots:Array(emptyJourneySlots.prefix(4)),id:\.self){slot in Button("保存到行程槽\(slot)"){saveJourney(slot)}.disabled(game.campaign==nil || game.busy)}
                if emptyJourneySlots.count>4{Button(showAllEmptyJourneys ? "收起空槽":"显示全部\(emptyJourneySlots.count)个空槽"){showAllEmptyJourneys.toggle()}}
                if emptyJourneySlots.isEmpty{Text("没有空槽，可在已保存行程中选择覆盖。")}
            }
            Section("读取前自动备份") {
                if recoveries.isEmpty{Text("暂无备份。")}
                ForEach(recoveries.prefix(20),id:\.path){url in
                    Button("恢复 · "+recoveryTitle(url)){ask("恢复这份自动备份？当前进度也会先保留。"){try load(MeadowCampaignSave.decoded(Data(contentsOf:url)))}}
                }
                Text("仅显示最近20份，旧文件保留在本机。人物槽和行程槽不会随新地图被清空。").font(.caption)
            }
        }
    }
    private var historyForm:some View {
        Group {
            Section("查找操作") {
                HStack{Text("搜索");TextField("操作 / 成员姓名 / ID / 序号",text:$historyQuery.text)}
                Picker("类别",selection:$historyQuery.category){ForEach(MeadowHistoryCategory.allCases,id:\.rawValue){Text($0.title).tag($0)}}
                Picker("涉及人物 / 怪物",selection:Binding(get:{historyQuery.participant ?? ""},set:{historyQuery.participant=$0.isEmpty ? nil:$0})){
                    Text("全部对象").tag("")
                    ForEach(historyPeople.keys.sorted(),id:\.self){id in Text((historyPeople[id] ?? id)+" · "+id).tag(id)}
                }
                Toggle("最新操作在前",isOn:$historyQuery.newestFirst)
                HStack{Text("匹配 \(matchingHistory.count) / 全部 \(historyRows.count)");Spacer();Button("清除筛选"){historyQuery=MeadowHistoryQuery()}.disabled(historyQuery==MeadowHistoryQuery())}.font(.caption)
            }
            Section("回退到所选操作之后") {
                Text("筛选只影响列表。回退会保留所选记录，撤回其后所有操作，包括被筛选隐藏的操作；先备份当前行程，再恢复骰子、队列和移动检查点并暂停。").font(.caption)
                if indexingHistory{ProgressView("正在整理历史索引…")}
                ForEach(Array(matchingHistory.prefix(historyLimit))){row in
                    if let history=game.campaign?.engine.history,history.indices.contains(row.sequence-1),history[row.sequence-1].id==row.id {
                        historyRecord(history[row.sequence-1],row:row)
                    }
                }
                if !indexingHistory && matchingHistory.isEmpty{Text(historyRows.isEmpty ? "暂无操作记录。":"没有匹配的记录，可清除筛选。")}
                if matchingHistory.count>historyLimit{Button("再显示50条（已显示\(min(historyLimit,matchingHistory.count)) / \(matchingHistory.count)）"){historyLimit += 50}}
            }
        }
    }
    private func historyRecord(_ entry:OperationReceipt,row:MeadowHistoryIndex)->some View {
        DisclosureGroup("#\(entry.sequence) · "+row.category.title+" · "+row.title) {
            Text(String(describing:entry.command)).font(.caption).textSelection(.enabled)
            ForEach(Array(entry.dice.enumerated()),id:\.offset){_,d in Text("骰子：\(d.values.map(String.init).joined(separator:"、")) → \(d.total)").font(.caption)}
            ForEach(entry.after.players){unit in
                if let before=entry.before.units[unit.id],before != unit{Text("\(unit.name) · HP \(before.health)→\(unit.health) · AP \(before.ap)→\(unit.ap) · 金币 \(before.coins)→\(unit.coins)").font(.caption)}
            }
            Button("回退到此条之后"){let count=(game.campaign?.engine.history.count ?? 0)-entry.sequence;ask("保留原第\(entry.sequence)条，撤回其后全部\(count)条（包括当前未显示的记录）？"){try game.rollback(to:entry.id);notice=game.message}}.disabled(game.busy || indexingHistory)
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
        Section("独立老师席位 P7") {
            if let host=players.first(where:{$0.host}){Text("老师已参战："+host.name)}
            else {
                TextField("老师人物名",text:$teacherName)
                Picker("职业",selection:$teacherClass){ForEach(MeadowPartyConfiguration.classIDs,id:\.self){id in Text((try? game.campaign?.engine.catalog.playerClass(id).name) ?? id).tag(id)}}
                Picker("加入队伍",selection:$teacherTeam){ForEach(game.campaign?.engine.state.teams ?? []){Text($0.name).tag($0.id)}}
                Button("以现有角色动作加入"){ask("老师加入独立P7席位，不占学生名额。使用当前人物编辑区的装扮？"){try game.joinTeacher(name:teacherName,classID:teacherClass,team:teacherTeam,appearance:appearance);notice=game.message}}.disabled(game.campaign==nil || game.busy || game.campaign?.travel != nil || game.campaign?.engine.state.battle != nil || game.campaign?.isCompleted==true)
                Text("最多6名学生+1名老师；仅探索且停止移动时可加入。老师沿用正式战斗/背包/组队与个人行动值，不新建第二套引擎。").font(.caption)
            }
        }
    }
    private func updateThumbnail(){let index=HeroFrames.appearanceIDs.firstIndex(of:bodyStyle) ?? 0;thumbnail=HeroFrames.inventoryImages(appearanceIndex:index,weaponID:nil,armorID:appearance.armor(worn:game.campaign?.engine.state.units[player]?.equipment.armor),hair:appearance.hair,face:appearance.face).first}
    private func readPlayer(){guard let u=game.campaign?.engine.state.units[player] else{updateThumbnail();return};name=u.name;let a=u.appearance ?? .init(body:game.campaign?.snapshot.appearanceID ?? "forester");bodyStyle=a.body;outfit=a.outfit ?? "follow";hair=a.hair ?? "original";face=a.face ?? "original";updateThumbnail()}
    private func ask(_ message:String,action:@escaping ()throws->Void){confirmation=message;pending=action;confirm=true}
    private func executePending(){defer{pending=nil;reload()};do{try pending?()}catch{notice="未完成，原文件保留："+error.localizedDescription}}
    private func savePrompt(occupied:Bool,message:String,action:@escaping ()throws->Void){if occupied{ask(message,action:action)}else{do{try action();reload()}catch{notice=error.localizedDescription}}}
    private func saveJourney(_ slot:Int){guard let c=game.campaign else{return};do{try c.checkpoint();let save=c.snapshot,label=title;savePrompt(occupied:journeys[slot] != nil || errors["j\(slot)"] != nil,message:"覆盖行程槽\(slot)？"){try store.saveCampaign(save,slot:slot,title:label);notice="完整行程已保存。"}}catch{notice=error.localizedDescription}}
    private func load(_ save:MeadowCampaignSave)throws{var value=save;if value.archive.state.battle != nil{value.archive.state.pauseReasons.insert(.manual)};try game.loadJourney(value);notice=game.message;player=game.campaign?.selectedPlayerID ?? "p1";readPlayer()}
    private func recoveryTitle(_ url:URL)->String{let date=(try? url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast;return date.formatted(date:.abbreviated,time:.shortened)}
    private func reload(){defer{journeyRows=journeys.map{MeadowJourneyIndex(slot:$0.key,entry:$0.value)}};profiles=[:];journeys=[:];errors=[:];for s in 1...MeadowSlotStore.profileCount{do{profiles[s]=try store.profile(s)}catch{errors["p\(s)"]=error.localizedDescription}};for s in 1...MeadowSlotStore.campaignCount{do{journeys[s]=try store.campaign(s)}catch{errors["j\(s)"]=error.localizedDescription}};do{recoveries=try store.recoveries()}catch{notice="自动备份目录读取失败："+error.localizedDescription}}
}
