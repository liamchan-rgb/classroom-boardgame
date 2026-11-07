import SwiftUI
import ClassroomGameCore
import MeadowWorldSupport

/// Private teacher-only modal; never attached to the public renderer tree.
struct TeacherArchiveConsole:View {
    @ObservedObject var game:MeadowTeacherCoordinator
    var onClose:()->Void
    @State private var transfer:TeacherSaveTransferRequest?
    @State private var tab=0
    @State private var player="p1"
    @State private var name=""
    @State private var bodyStyle="forester"
    @State private var outfit="follow"
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
    private var store:MeadowSlotStore {MeadowTeacherCoordinator.slotStore}
    private var players:[GameUnit] {game.campaign?.engine.state.players ?? []}
    private var appearance:PlayerAppearance {.init(body:bodyStyle,outfit:outfit=="follow" ? nil:outfit)}
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
                .onAppear{player=game.campaign?.selectedPlayerID ?? "p1";readPlayer();reload();teacherTeam=game.campaign?.engine.state.teams.first?.id ?? "party"}
                .onChange(of:player){_,_ in readPlayer()}
                .onChange(of:bodyStyle){_,_ in updateThumbnail()}
                .onChange(of:outfit){_,_ in updateThumbnail()}
                .alert("确认操作",isPresented:$confirm){Button("取消",role:.cancel){pending=nil};Button("确认",role:.destructive){executePending()}}message:{Text(confirmation)}
        }
    }
    private var profileForm:some View {
        Group {
            Section("姓名与自定义外观") {
                if !players.isEmpty{Picker("当前角色",selection:$player){ForEach(players){Text($0.name).tag($0.id)}}}
                TextField("人物名（最多40字）",text:$name)
                Picker("外观款式",selection:$bodyStyle){Text("林间绿衣").tag("forester");Text("行旅蓝衣").tag("wayfarer")}
                Picker("衣装装扮",selection:$outfit){Text("跟随实际护甲").tag("follow");Text("基础衣装").tag("blue");Text("皮甲").tag("leatherArmor");Text("符文甲").tag("runeArmor")}
                if let thumbnail{Image(uiImage:thumbnail).interpolation(.none).resizable().scaledToFit().frame(height:130).frame(maxWidth:.infinity).background(Color(red:0.08,green:0.17,blue:0.12))}
                Text("仅使用已有美术。装扮不提供装备属性；武器仍跟随实际装备。战斗沿用现有挂载骨架，尚缺独立体型美术。").font(.caption)
                Button("应用到当前角色"){let p=profile;ask("将姓名和装扮应用到当前角色，保留职业、数值、装备和行程？"){try game.applyProfile(p,to:player);notice=game.message}}.disabled(game.busy || game.campaign==nil || game.campaign?.isCompleted==true)
                Button("从当前角色重新读取"){readPlayer()}.disabled(players.isEmpty)
            }
            Section("人物槽 · 可供新行程复用") {
                ForEach(1...MeadowSlotStore.profileCount,id:\.self){slot in
                    VStack(alignment:.leading,spacing:6) {
                        Text("人物槽 \(slot) · "+(profiles[slot]?.value.name ?? "空槽")).font(.headline)
                        if let entry=profiles[slot]{Text(entry.savedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption)}
                        if let error=errors["p\(slot)"]{Text("原文件保留："+error).font(.caption).foregroundStyle(.red)}
                        HStack {
                            Button("保存档案"){let p=profile;savePrompt(occupied:profiles[slot] != nil || errors["p\(slot)"] != nil,message:"覆盖人物槽\(slot)？"){try store.saveProfile(p,slot:slot,title:p.name);notice="人物档案已保存。"}}
                            Button("导出"){transfer=TeacherSaveTransferRequest(selection:[.init(.profile,slot)])}.disabled(profiles[slot]==nil)
                            Button("读取到编辑区"){if let p=profiles[slot]?.value{name=p.name;bodyStyle=p.appearance.body;outfit=p.appearance.outfit ?? "follow";updateThumbnail();notice="档案已读取到编辑区；尚未改变行程中的角色。"}}.disabled(profiles[slot]==nil)
                        }.buttonStyle(.bordered)
                    }
                }
            }
        }
    }
    private var journeyForm:some View {
        Group {
            Section("完整行程") {
                TextField("存档标题",text:$title)
                Text("保存地图、队伍、背包、战斗队列/骰子状态、各队移动条和镜头。原自动存档继续生效；读取前另存当前进度。读取战斗槽会保持暂停，等待教师继续。").font(.caption)
            }
            Section("行程槽") {
                ForEach(1...MeadowSlotStore.campaignCount,id:\.self){slot in
                    VStack(alignment:.leading,spacing:6) {
                        Text("行程槽 \(slot) · "+(journeys[slot]?.title ?? "空槽")).font(.headline)
                        if let e=journeys[slot]{Text("\(e.value.archive.state.players.count)人 · \(e.value.layout.map.nodes.count)节点 · "+e.savedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption)}
                        if let error=errors["j\(slot)"]{Text("原文件保留："+error).font(.caption).foregroundStyle(.red)}
                        HStack {
                            Button("保存到此槽"){saveJourney(slot)}.disabled(game.campaign==nil || game.busy)
                            Button("导出"){transfer=TeacherSaveTransferRequest(selection:[.init(.campaign,slot)])}.disabled(journeys[slot]==nil || game.busy)
                            Button("读取"){if let entry=journeys[slot]{ask("读取“\(entry.title)”？当前行程将先自动备份。"){try load(entry.value)}}}.disabled(journeys[slot]==nil || game.busy)
                        }.buttonStyle(.bordered)
                    }
                }
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
        Section("回退到所选操作之后") {
            Text("保留选中这一条，撤回后续操作；骰子状态与战斗队列一并恢复。回退后暂停，当前行程自动备份。旧记录若没有道路快照，会停止移动游标。").font(.caption)
            ForEach(Array((game.campaign?.engine.history ?? []).reversed())){entry in
                DisclosureGroup("#\(entry.sequence) · "+historyTitle(entry)) {
                    Text(String(describing:entry.command)).font(.caption).textSelection(.enabled)
                    ForEach(Array(entry.dice.enumerated()),id:\.offset){_,d in Text("骰子：\(d.values.map(String.init).joined(separator:"、")) → \(d.total)").font(.caption)}
                    ForEach(entry.after.players){unit in
                        if let before=entry.before.units[unit.id],before != unit{Text("\(unit.name) · HP \(before.health)→\(unit.health) · AP \(before.ap)→\(unit.ap) · 金币 \(before.coins)→\(unit.coins)").font(.caption)}
                    }
                    Button("回退到此条之后"){let count=(game.campaign?.engine.history.count ?? 0)-entry.sequence;ask("保留第\(entry.sequence)条，撤回其后\(count)条操作？"){try game.rollback(to:entry.id);notice=game.message}}.disabled(game.busy)
                }
            }
            if game.campaign?.engine.history.isEmpty != false{Text("暂无操作记录。")}
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
    private func historyTitle(_ entry:OperationReceipt)->String {
        switch entry.command {
        case .applyPlayerProfile:return "更新人物档案"
        case .addHost:return "老师加入"
        case .grantPlayerResources:return "发放行动点 / 金币"
        case .editPlayer,.editResources:return "GM修改玩家"
        case .configureTeams,.mergeTeams,.changeTeam:return "调整队伍"
        case .transferTeamResource,.teacherTransferTeamResource:return "转移队伍资源"
        case .campaignMove,.move:return "抵达地图节点"
        case .refillCampaignMovement:return "补充地图移动条"
        case .startBattle:return "开始战斗"
        case .attack:return "普通攻击"
        case .cast(_,let skill,_):return (try? game.campaign?.engine.catalog.skill(skill).name) ?? "释放技能"
        case .monsterStep:return "怪物行动"
        case .useItem:return "使用物品"
        case .equip:return "更换装备"
        case .endTurn:return "结束行动"
        case .reward:return "发放奖励"
        case .finishBattle:return "结束战斗"
        default:return "游戏操作"
        }
    }
    private func updateThumbnail(){let index=HeroFrames.appearanceIDs.firstIndex(of:bodyStyle) ?? 0;thumbnail=HeroFrames.inventoryImages(appearanceIndex:index,weaponID:nil,armorID:appearance.armor(worn:game.campaign?.engine.state.units[player]?.equipment.armor)).first}
    private func readPlayer(){guard let u=game.campaign?.engine.state.units[player] else{updateThumbnail();return};name=u.name;let a=u.appearance ?? .init(body:game.campaign?.snapshot.appearanceID ?? "forester");bodyStyle=a.body;outfit=a.outfit ?? "follow";updateThumbnail()}
    private func ask(_ message:String,action:@escaping ()throws->Void){confirmation=message;pending=action;confirm=true}
    private func executePending(){defer{pending=nil;reload()};do{try pending?()}catch{notice="未完成，原文件保留："+error.localizedDescription}}
    private func savePrompt(occupied:Bool,message:String,action:@escaping ()throws->Void){if occupied{ask(message,action:action)}else{do{try action();reload()}catch{notice=error.localizedDescription}}}
    private func saveJourney(_ slot:Int){guard let c=game.campaign else{return};do{try c.checkpoint();let save=c.snapshot,label=title;savePrompt(occupied:journeys[slot] != nil || errors["j\(slot)"] != nil,message:"覆盖行程槽\(slot)？"){try store.saveCampaign(save,slot:slot,title:label);notice="完整行程已保存。"}}catch{notice=error.localizedDescription}}
    private func load(_ save:MeadowCampaignSave)throws{var value=save;if value.archive.state.battle != nil{value.archive.state.pauseReasons.insert(.manual)};try game.loadJourney(value);notice=game.message;player=game.campaign?.selectedPlayerID ?? "p1";readPlayer()}
    private func recoveryTitle(_ url:URL)->String{let date=(try? url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast;return date.formatted(date:.abbreviated,time:.shortened)}
    private func reload(){profiles=[:];journeys=[:];errors=[:];for s in 1...MeadowSlotStore.profileCount{do{profiles[s]=try store.profile(s)}catch{errors["p\(s)"]=error.localizedDescription}};for s in 1...MeadowSlotStore.campaignCount{do{journeys[s]=try store.campaign(s)}catch{errors["j\(s)"]=error.localizedDescription}};do{recoveries=try store.recoveries()}catch{notice="自动备份目录读取失败："+error.localizedDescription}}
}
