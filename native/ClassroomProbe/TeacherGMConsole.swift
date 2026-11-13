import SwiftUI
import ClassroomGameCore

struct TeacherGMConsole:View {
    @ObservedObject var game:MeadowTeacherCoordinator
    var onClose:()->Void
    @State private var selected="p1"
    @State private var name=""
    @State private var values:[String:String]=[:]
    @State private var inventory:[String:String]=[:]
    @State private var skillUses:[String:String]=[:]
    @State private var buffEnabled=false
    @State private var buffAmount="0"
    @State private var buffRounds="1"
    @State private var draft:TeacherPlayerEdit?
    @State private var search=""
    @State private var notice="改动仅在点击保存后生效。"
    private var players:[GameUnit] {game.campaign?.engine.state.players ?? []}
    private var current:GameUnit? {game.campaign?.engine.state.units[selected]}
    private var catalog:GameCatalog? {game.campaign?.engine.catalog}
    private let resourceFields=[("health","当前生命"),("shield","当前护盾"),("ap","当前行动点"),("coins","金币"),("score","个人积分")]
    private let attributeFields=[("maximumHealth","基础最大生命"),("baseAP","基础行动点"),("maximumAP","基础行动点上限"),("damage","基础伤害加成"),("range","基础射程加成")]
    var body:some View {
        NavigationStack {
            Form {
                Section("编辑对象 · 仅教师可见") {
                    Picker("玩家",selection:$selected){ForEach(players){Text($0.name+($0.host ? " · 老师":"")).tag($0.id)}}
                    ClassroomTextField(placeholder:"姓名",text:$name)
                    Text(notice).font(.callout).foregroundStyle(.secondary)
                }.glassRow()
                resources
                attributes
                buffsAndSkills
                backpack
            }.glassSheet().navigationTitle("GM · 玩家数值与背包")
                .toolbar {
                    ToolbarItem(placement:.cancellationAction){Button("关闭"){onClose()}}
                    ToolbarItem(placement:.bottomBar){Button("撤销最近一次GM/发放"){if game.undoTeacherAction(){reload();notice=game.message}else{notice=game.message}}.disabled(game.busy || !game.backend.canUndoTeacherAction)}
                    ToolbarItem(placement:.confirmationAction){Button("保存修改"){save()}.disabled(game.busy || current==nil || game.campaign?.isCompleted==true)}
                }
                .onAppear{selected=game.campaign?.selectedPlayerID ?? players.first?.id ?? "p1";reload()}
                .onChange(of:selected){_,_ in reload()}
        }
    }
    private var resources:some View {
        Section("当前资源 · 绝对设置") {
            ForEach(resourceFields,id:\.0){field in numeric(field.1,key:field.0)}
            Text("生命不能超过含装备加成的最大生命，行动点不能超过个人上限。设为倒地会清除护盾和增伤；复活沿用下一轮可行动规则。").font(.caption)
            if let c=game.campaign,c.travel?.actors.contains(selected)==true{Text("该成员仍在道路上；设为倒地需先抵达建筑节点。").font(.caption)}
        }.glassRow()
    }
    private var attributes:some View {
        Section("基础属性 · 装备加成另计") {
            ForEach(attributeFields,id:\.0){field in numeric(field.1,key:field.0)}
            if let unit=current,let catalog,let result=try? GameRules.attributes(unit,catalog:catalog){
                Text("当前最终值：生命上限 \(result.maximumHealth) · 伤害加成 \(result.damage) · 基础行动 \(result.baseAP) · 行动上限 \(result.maximumAP) · 射程加成 \(result.range)").font(.caption)
            }
            Text("提高上限不会自动回满生命、行动点或地图移动条。降低上限时，请同时将当前资源改到合法范围。").font(.caption)
        }.glassRow()
    }
    private var buffsAndSkills:some View {
        Section("临时增伤与技能次数") {
            Toggle("启用临时增伤",isOn:$buffEnabled)
            if buffEnabled {
                HStack{Text("增伤数值");ClassroomTextField(placeholder:"0",text:$buffAmount,limit:12,keyboard:.numbersAndPunctuation,alignment:.right)}
                HStack{Text("剩余轮数");ClassroomTextField(placeholder:"1",text:$buffRounds,limit:12,keyboard:.numberPad,alignment:.right)}
            }
            ForEach(skillUses.keys.sorted(),id:\.self){id in
                HStack {
                    Text((try? catalog?.skill(id).name) ?? id)
                    Spacer()
                    Text("已用")
                    ClassroomTextField(placeholder:"0",text:Binding(get:{skillUses[id] ?? "0"},set:{skillUses[id]=$0}),limit:12,keyboard:.numberPad,alignment:.right).frame(width:70)
                    if let c=catalog,let definition=try? c.skill(id),let limit=definition.uses{Text("/\(limit)").foregroundStyle(.secondary)}
                }
            }
            Button("将这些技能的已用次数设为0"){for id in skillUses.keys{skillUses[id]="0"}}
        }.glassRow()
    }
    private var backpack:some View {
        Section("个人背包 · 数量0表示移除") {
            ClassroomTextField(placeholder:"按物品名称搜索",text:$search)
            ForEach((catalog?.items ?? []).filter{search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)}){item in
                HStack {
                    Text(item.name)
                    Spacer()
                    ClassroomTextField(placeholder:"0",text:Binding(get:{inventory[item.id] ?? "0"},set:{inventory[item.id]=$0}),limit:12,keyboard:.numberPad,alignment:.right).frame(width:100)
                }
            }
            Text("这里只调整个人背包。已穿戴物品、队伍仓库和物品定义保持原样；允许教师直接增加或移除数量。").font(.caption)
        }.glassRow()
    }
    private func numeric(_ title:String,key:String)->some View {
        HStack{Text(title);Spacer();ClassroomTextField(placeholder:"0",text:Binding(get:{values[key] ?? "0"},set:{values[key]=$0}),limit:12,keyboard:.numbersAndPunctuation,alignment:.right).frame(width:140)}
    }
    private func reload(){
        guard let unit=current else{return}
        draft=TeacherPlayerEdit(unit:unit);name=unit.name
        values=["health":String(unit.health),"shield":String(unit.shield),"ap":String(unit.ap),"coins":String(unit.coins),"score":String(unit.score),"maximumHealth":String(unit.baseAttributes.maximumHealth),"baseAP":String(unit.baseAttributes.baseAP),"maximumAP":String(unit.baseAttributes.maximumAP),"damage":String(unit.baseAttributes.damage),"range":String(unit.baseAttributes.range)]
        inventory=unit.inventory.mapValues{String($0)}
        let learned=catalog.flatMap{try? GameRules.skills(unit,catalog:$0)} ?? []
        let ids=Set(learned+Array(unit.skillUses.keys))
        skillUses=Dictionary(uniqueKeysWithValues:ids.map{($0,String(unit.skillUses[$0] ?? 0))})
        buffEnabled=unit.damageBuff != nil;buffAmount=String(unit.damageBuff?.amount ?? 0);buffRounds=String(unit.damageBuff?.roundsLeft ?? 1)
        search="";notice="改动仅在点击保存后生效。"
    }
    private func save(){
        guard var value=draft else{return}
        let numbers=values.compactMapValues{Int($0)},bag=inventory.compactMapValues{Int($0)},uses=skillUses.compactMapValues{Int($0)}
        guard numbers.count==values.count,bag.count==inventory.count,uses.count==skillUses.count else{notice="请输入可保存的整数，空白或超范围数字不会保存。";return}
        value.name=name;value.attributes=Attributes(maximumHealth:numbers["maximumHealth"]!,damage:numbers["damage"]!,baseAP:numbers["baseAP"]!,maximumAP:numbers["maximumAP"]!,range:numbers["range"]!)
        value.health=numbers["health"]!;value.shield=numbers["shield"]!;value.ap=numbers["ap"]!;value.coins=numbers["coins"]!;value.score=numbers["score"]!
        value.inventory=bag;value.skillUses=uses
        if buffEnabled {
            guard let amount=Int(buffAmount),let rounds=Int(buffRounds) else{notice="请输入有效的增伤数值与轮数。";return}
            value.damageBuff=DamageBuff(amount:amount,roundsLeft:rounds,appliedRound:value.damageBuff?.appliedRound ?? game.campaign?.engine.state.battle?.round ?? 0)
        }else{value.damageBuff=nil}
        if game.saveGM(selected,value:value){reload();notice="已保存，可继续调整或关闭窗口。"}else{notice=game.message}
    }
}
