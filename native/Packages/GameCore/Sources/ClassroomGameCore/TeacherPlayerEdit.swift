import Foundation

/// Absolute, per-player GM draft. Identity, class, team, position and equipped
/// slots are preserved; inventory quantities never modify catalog definitions.
public struct TeacherPlayerEdit:Codable,Equatable {
    public var name:String
    public var attributes:Attributes
    public var health:Int,shield:Int,ap:Int,coins:Int,score:Int
    public var inventory:[String:Int]
    public var skillUses:[String:Int]
    public var damageBuff:DamageBuff?
    public init(unit:GameUnit){
        name=unit.name;attributes=unit.baseAttributes
        health=unit.health;shield=unit.shield;ap=unit.ap;coins=unit.coins;score=unit.score
        inventory=unit.inventory;skillUses=unit.skillUses;damageBuff=unit.damageBuff
    }
}
extension Evaluation {
    mutating func editPlayer(_ id:String,value:TeacherPlayerEdit)throws {
        var player=try unit(id)
        guard player.kind == .player,!value.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              value.shield>=0,value.ap>=0,value.coins>=0,value.inventory.values.allSatisfy({$0>=0}) else{throw GameError("玩家名称、护盾、行动点、金币或背包数量无效。")}
        try GameCatalog.validateBase(value.attributes)
        for item in value.inventory.keys{_=try catalog.item(item)}
        player.name=value.name.trimmingCharacters(in:.whitespacesAndNewlines);player.baseAttributes=value.attributes
        player.shield=value.shield;player.ap=value.ap;player.coins=value.coins;player.score=value.score
        player.inventory=value.inventory.filter{$0.value>0};player.skillUses=value.skillUses;player.damageBuff=value.damageBuff
        state.units[id]=player
        // Preserve normal death/revival, including next-round eligibility and
        // clearing shield/buff on defeat. Never award a teacher kill to a player.
        try setHealth(id,value:value.health,killer:nil)
        events.append(GameEvent("teacherPlayerEdited",target:id,detail:"个人数值与背包绝对设置；身份/队伍/装备/仓库保留"))
    }
    mutating func grantPlayerResources(_ ids:[String],ap:Int,coins:Int)throws {
        guard !ids.isEmpty,Set(ids).count==ids.count,ap>=0,coins>=0,ap>0 || coins>0 else{throw GameError("请选择奖励对象和非负发放数量。")}
        for id in ids {
            var player=try unit(id);guard player.kind == .player else{throw GameError("只能向玩家发放资源。")}
            let maximum=try GameRules.attributes(player,catalog:catalog).maximumAP
            player.ap=try checkedAdd(player.ap,min(ap,max(0,maximum-player.ap)))
            player.coins=try checkedAdd(player.coins,coins);state.units[id]=player
            events.append(GameEvent("teacherPlayerGrant",target:id,amount:coins,detail:"行动点+\(ap)，按个人上限封顶"))
        }
    }
}
