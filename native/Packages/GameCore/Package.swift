// swift-tools-version: 5.9
import PackageDescription
let package = Package(name:"ClassroomGameCore",platforms:[.iOS(.v15),.macOS(.v13)],products:[
    .library(name:"ClassroomGameCore",targets:["ClassroomGameCore"]),
    .library(name:"MeadowBattleSupport",targets:["MeadowBattleSupport"]),
    .library(name:"MeadowWorldSupport",targets:["MeadowWorldSupport"]),
    .library(name:"MeadowClassroomSupport",targets:["MeadowClassroomSupport"]),
    .executable(name:"MeadowMapExport",targets:["MeadowMapExport"]),
    .executable(name:"MeadowSupportReviewExport",targets:["MeadowSupportReviewExport"]),
    .executable(name:"MeadowCampaignReview",targets:["MeadowCampaignReview"])
],targets:[
    .target(name:"ClassroomGameCore",resources:[.process("Resources")]),
    .target(name:"MeadowWorldSupport",dependencies:["ClassroomGameCore"]),
    .target(name:"MeadowClassroomSupport",dependencies:["MeadowWorldSupport","MeadowBattleSupport","ClassroomGameCore"]),
    .testTarget(name:"MeadowClassroomSupportTests",dependencies:["MeadowClassroomSupport","MeadowWorldSupport","ClassroomGameCore"]),
    .executableTarget(name:"MeadowMapExport",dependencies:["MeadowWorldSupport"],path:"MapTools"),
    .testTarget(name:"MeadowWorldSupportTests",dependencies:["MeadowWorldSupport","MeadowBattleSupport","ClassroomGameCore","MeadowCampaignAuditSupport"]),
    .target(name:"MeadowCampaignAuditSupport",dependencies:["MeadowWorldSupport","MeadowBattleSupport","ClassroomGameCore"],path:"AuditSupport"),
    .executableTarget(name:"MeadowCampaignReview",dependencies:["MeadowCampaignAuditSupport"],path:"CampaignTools"),
    .target(name:"MeadowBattleSupport",dependencies:["ClassroomGameCore"],resources:[.process("Resources")]),
    .executableTarget(name:"MeadowSupportReviewExport",dependencies:["MeadowBattleSupport","ClassroomGameCore"],path:"Tools"),
    .testTarget(name:"ClassroomGameCoreTests",dependencies:["ClassroomGameCore"]),
    .testTarget(name:"MeadowBattleSupportTests",dependencies:["MeadowBattleSupport","ClassroomGameCore"])
])
