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
    @State private var bagFilter=BagFilter.owned
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
    private enum BagFilter:String,CaseIterable {case owned="已有",all="全部",weapon="武器",armor="护甲",accessory="饰品",supply="补给"}
    private func matches(_ item:ItemDefinition)->Bool {
        switch bagFilter {
        case .owned:return (Int(inventory[item.id] ?? "0") ?? 0)>0
        case .all:return true
        case .weapon:return item.slot == .weapon
        case .armor:return item.slot == .armor
        case .accessory:return item.slot == .accessory
        case .supply:return item.slot == nil
        }
    }
    private var backpack:some View {
        Section("个人背包 · 点 − / ＋ 立即生效（每次可撤销）") {
            Picker("分类",selection:$bagFilter){ForEach(BagFilter.allCases,id:\.self){Text($0.rawValue).tag($0)}}.pickerStyle(.segmented)
            ClassroomTextField(placeholder:"按物品名称搜索",text:$search)
            let items=(catalog?.items ?? []).filter{(search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) && matches($0)}
            if items.isEmpty {Text(bagFilter == .owned ? "背包是空的，切到“全部”添加物品。":"没有符合的物品。").font(.callout).foregroundStyle(.secondary)}
            ForEach(items){item in
                let count=Int(inventory[item.id] ?? "0") ?? 0
                let rarity=MeadowItemRarity.of(item.id,item:item)
                HStack(spacing:10) {
                    Image(uiImage:MeadowItemIcon.image(item.id,item:item,side:36)).interpolation(.none).resizable().frame(width:36,height:36)
                    VStack(alignment:.leading,spacing:1) {
                        Text(item.name).font(.body.weight(.semibold))
                        Text(rarity.title+(item.slot.map{" · "+["weapon":"武器","armor":"护甲","accessory":"饰品"][$0.rawValue]!} ?? " · 补给")+(current?.equipment.itemIDs.contains(item.id)==true ? " · 穿着中":"")).font(.caption).foregroundStyle(Color(rarity.color))
                    }
                    Spacer()
                    quickButton("minus",enabled:count>0){quickAdjust(item.id,-1)}
                    Text("\(count)").font(.title3.monospacedDigit().weight(.bold)).frame(minWidth:34)
                    quickButton("plus",enabled:true){quickAdjust(item.id,1)}
                    Menu {
                        ForEach([5,10],id:\.self){n in Button("＋\(n)"){quickAdjust(item.id,n)}}
                        Button("清零",role:.destructive){quickAdjust(item.id,-count)}.disabled(count==0)
                    } label: {Image(systemName:"ellipsis.circle").font(.title3)}.menuStyle(.borderlessButton).frame(width:32)
                }
            }
            Text("只调整个人背包：已穿戴的装备、队伍仓库保持原样。最上方“撤销最近一次GM/发放”可撤回。").font(.caption)
        }.glassRow()
    }
    private func quickButton(_ symbol:String,enabled:Bool,action:@escaping ()->Void)->some View {
        Button(action:action){Image(systemName:symbol).font(.body.weight(.bold)).frame(width:34,height:30)}
            .buttonStyle(.bordered).disabled(!enabled || game.busy || game.campaign?.isCompleted==true)
    }
    /// One tap changes this item's count right away (its own GM step), leaving the other fields' unsaved edits as they are.
    private func quickAdjust(_ item:String,_ delta:Int) {
        guard let unit=current,delta != 0 else{return}
        var value=TeacherPlayerEdit(unit:unit),bag=unit.inventory
        let n=max(0,min(999,(bag[item] ?? 0)+delta))
        if n==0 {bag.removeValue(forKey:item)} else {bag[item]=n}
        value.inventory=bag
        if game.saveGM(selected,value:value) {
            inventory[item]=String(n);draft?.inventory=bag
            notice="已改：\((try? catalog?.item(item).name) ?? item) × \(n)"
        } else {notice=game.message}
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
