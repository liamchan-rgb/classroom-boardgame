import Foundation
import MeadowWorldSupport
import ClassroomGameCore

func runExport()throws {
let args=CommandLine.arguments
var c=MeadowMapConfiguration.suggested(total:args.count>1 ? Int(args[1]) ?? 10 : 10,
                                     seed:args.count>2 ? UInt64(args[2]) ?? 31827 : 31827)
if args.count>3 { c.extraRoads=Int(args[3]) ?? 1 }
let result=try MeadowMapGenerator.generate(c)
let encoder=JSONEncoder(); encoder.outputFormatting=[.sortedKeys,.prettyPrinted]
if args.contains("--party") {
    struct Report:Codable {let configuration:MeadowPartyConfiguration;let players:[GameUnit];let skills:[String:[String]];let summaries:[String];let movementCapacity:Double}
    var reports=[Report]()
    for p1 in MeadowPartyConfiguration.classIDs {for p2 in MeadowPartyConfiguration.classIDs {
        let session=try MeadowCampaignSession.new(layout:result,playerClassID:p1,companionClassID:p2)
        let players=session.engine.state.players
        var skills=[String:[String]]()
        for u in players{skills[u.id]=try GameRules.skills(u,catalog:session.engine.catalog)}
        reports.append(Report(configuration:session.partyConfiguration,players:players,skills:skills,summaries:try [p1,p2].map{try MeadowPartyConfiguration.summary(for:$0,catalog:session.engine.catalog)},movementCapacity:session.movementCapacity))
    }}
    FileHandle.standardOutput.write(try encoder.encode(reports))
} else if args.contains("--equipment") {
    struct Report:Codable {let role:String,item:String,comparison:MeadowEquipmentComparison}
    var reports=[Report]()
    for role in ["adventurer","spellblade","dragonKnight"] {
        let initial=try MeadowCampaignSession.new(layout:result,playerClassID:role)
        var save=initial.snapshot
        let equipment=initial.engine.catalog.items.filter{$0.slot != nil}.sorted{$0.id<$1.id}
        for item in equipment{save.archive.state.units["p1"]!.inventory[item.id]=1}
        let session=try MeadowCampaignSession(save:save)
        for item in equipment {reports.append(Report(role:role,item:item.id,comparison:try session.equipmentComparison(actor:"p1",slot:item.slot!,item:item.id)))}
    }
    FileHandle.standardOutput.write(try encoder.encode(reports))
} else if args.contains("--guidance") {
    struct Report:Codable {
        let options:[MeadowRouteOption],resources:String
        let initialRoute:MeadowRouteReadout?,advancedRoute:MeadowRouteReadout?,restoredRoute:MeadowRouteReadout?
    }
    let session=try MeadowCampaignSession.new(layout:result),options=session.routeOptions()
    let resources=session.resourceGuidance
    if let target=options.max(by:{$0.distance<$1.distance}){try session.beginTravel(to:target.nodeID)}
    let initial=session.routeReadout
    try session.advanceTravel(distance:17.25)
    let advanced=session.routeReadout,restored=try MeadowCampaignSession(save:.decoded(session.snapshot.encoded()))
    FileHandle.standardOutput.write(try encoder.encode(Report(options:options,resources:resources,initialRoute:initial,advancedRoute:advanced,restoredRoute:restored.routeReadout)))
} else if args.contains("--balance") {
    struct Report:Codable {let provisions:MeadowProvisionPlan;let previews:[MeadowEncounterReadout]}
    let session=try MeadowCampaignSession.new(layout:result)
    let plan=try MeadowProvisioning.plan(layout:result,players:session.engine.state.players,catalog:session.engine.catalog)
    let previews=try result.map.nodes.sorted{$0.id<$1.id}.compactMap{try session.encounterPreview(node:$0.id)}
    FileHandle.standardOutput.write(try encoder.encode(Report(provisions:plan,previews:previews)))
} else if args.contains("--encounters") {
    FileHandle.standardOutput.write(try encoder.encode(MeadowEncounterPlanner.plan(result)))
} else {
    FileHandle.standardOutput.write(try encoder.encode(result))
}

}
try runExport()
