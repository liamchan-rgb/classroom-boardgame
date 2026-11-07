import Foundation
import MeadowCampaignAuditSupport
import MeadowWorldSupport

func runReview()throws {

    let args=CommandLine.arguments
    func option(_ name:String)throws->String? {
        guard let index=args.firstIndex(of:name) else{return nil}
        guard index+1<args.count,!args[index+1].hasPrefix("--") else{throw NSError(domain:"JourneyAudit",code:1,userInfo:[NSLocalizedDescriptionKey:"Missing value for "+name])}
        return args[index+1]
    }
    guard let size=Int(try option("--size") ?? "10"),let seed=UInt64(try option("--seed") ?? "31827") else{throw NSError(domain:"JourneyAudit",code:2,userInfo:[NSLocalizedDescriptionKey:"Invalid size or seed"])}
    let roles=try option("--role").map{[$0]} ?? ["adventurer","spellblade","dragonKnight"]
    let sizes=args.contains("--matrix") ? [4,10,30]:[size]
    let seeds:[UInt64]=args.contains("--matrix") ? [0,31827,UInt64.max]:[seed]
    if args.contains("--party-matrix") {
        var reports=[MeadowPartyJourneyReport]()
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.prettyPrinted]
        func audit(_ n:Int,_ s:UInt64,_ p1:String,_ p2:String)throws {
            FileHandle.standardError.write(Data("Party \(n)/\(s)/\(p1)/\(p2)\n".utf8))
            let config=MeadowPartyConfiguration(playerClassID:p1,companionClassID:p2)
            reports.append(.init(configuration:config,journey:try MeadowJourneyAudit.run(size:n,seed:s,role:p1,companionRole:p2)))
            if let path=try option("--checkpoint"){try encoder.encode(reports).write(to:URL(fileURLWithPath:path),options:.atomic)}
        }
        for p1 in MeadowPartyConfiguration.classIDs {for p2 in MeadowPartyConfiguration.classIDs {try audit(10,31827,p1,p2)}}
        for n in [4,30] {for (p1,p2) in [("adventurer","adventurer"),("ranger","ranger"),("spellblade","dragonKnight"),("dragonKnight","spellblade")] {try audit(n,0,p1,p2)}}
        FileHandle.standardOutput.write(try encoder.encode(reports));return
    }
    if args.contains("--loadout-matrix") || args.contains("--loadout-smoke") || args.contains("--loadout") {
        let selected=try option("--loadout")
        var kits=selected.map{id in MeadowAuditLoadout.all.filter{$0.id==id}} ?? MeadowAuditLoadout.all
        let smoke=args.contains("--loadout-smoke")
        if smoke {let ids:Set<String>=["trainingSword-plain","huntingBow-leather-badge","greatSword-rune-ring","legendaryStaff-rune-ring","starlight-three","dragon-three","unarmed-rune-ring"];kits=kits.filter{ids.contains($0.id)}}
        guard !kits.isEmpty else{throw NSError(domain:"JourneyAudit",code:3,userInfo:[NSLocalizedDescriptionKey:"Unknown loadout"])}
        var reports=[MeadowLoadoutJourneyReport]()
        let matrix=args.contains("--loadout-matrix")
        for n in matrix ? [10]:[size] {for s:UInt64 in matrix ? [0,31827,UInt64.max]:[seed] {for role in roles {for kit in kits {
            FileHandle.standardError.write(Data("Loadout \(n)/\(s)/\(role)/\(kit.id)\n".utf8))
            reports.append(.init(loadout:kit,journey:try MeadowJourneyAudit.run(size:n,seed:s,role:role,loadout:kit)))
        }}}}
        if matrix || smoke {for n in matrix ? [4,30]:[30] {for s:UInt64 in matrix ? [0,31827]:[0] {for role in roles {for kit in MeadowAuditLoadout.rulesOnly.filter({$0.id.hasSuffix("three")}) {
            FileHandle.standardError.write(Data("Loadout \(n)/\(s)/\(role)/\(kit.id)\n".utf8))
            reports.append(.init(loadout:kit,journey:try MeadowJourneyAudit.run(size:n,seed:s,role:role,loadout:kit)))
        }}}}}
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.prettyPrinted]
        FileHandle.standardOutput.write(try encoder.encode(reports));return
    }
    var reports=[MeadowJourneyAuditReport]()
    for size in sizes {for seed in seeds {for role in roles {
        FileHandle.standardError.write(Data("Audit \(size)/\(seed)/\(role)\n".utf8))
        reports.append(try MeadowJourneyAudit.run(size:size,seed:seed,role:role,allowManualRest: !args.contains("--without-rest"),supplyDetour:args.contains("--supply-detour"),companionRole:try option("--companion-role") ?? "ranger"))
    }}}
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.prettyPrinted]
    FileHandle.standardOutput.write(try encoder.encode(reports))
}
try runReview()
