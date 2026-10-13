#if DEBUG
import SwiftUI
import UIKit
import ClassroomGameCore

/// Cloud simulator-only fixture export. Excluded from the Release installation.
@MainActor
enum NativeVisualValidation {
    static func run(in window:UIWindow) async throws {
        let catalog = try GameCatalog.initial()
        let classes = ["adventurer","ranger","spellblade","dragonKnight","adventurer","ranger","dragonKnight"]
        let names = ["晨曦森林守护者小队长安然","AlexandriaWinterbrookJoy","小禾","星星","阿乐","小满","林老师"]
        let players = classes.enumerated().map { PlayerSetup(id:"p\($0.offset+1)",name:names[$0.offset],classID:$0.element,host:$0.offset == 6) }
        var state = try PVEGameFactory.make(players:players,scenario:.playerTwenty,seed:117,catalog:catalog)
        for id in state.units.keys { state.units[id]?.nodeID = 2 }
        state.map.revealed = [1,2,3]
        let queue = ["p1","m1","p2","p3","m2","p4","p5","p6","m3","p7"]
        state.battle = BattleState(kind:.pve,queue:queue,current:"p1")
        state.phase = .pve; state.pauseReasons = [.manual]; state.remainingSeconds = 17
        for id in ["m1","m2","m3"] { state.units[id]?.active = true }
        state.units["p1"]?.inventory = ["smallPotion":2,"largePotion":1,"shieldPotion":1,"revivalStone":1]
        state.units["p5"]?.health = 0; state.units["p5"]?.shield = 0
        state.units["p6"]?.canActFromRound = 2
        let engine = try GameEngine(catalog:catalog,state:state)
        let play = PVEPlaySession(engine:engine)
        let output = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("visual-validation")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func capture<V:View>(_ name:String,_ view:V,_ size:CGSize) async throws {
            let host = UIHostingController(rootView:view.preferredColorScheme(.light))
            window.rootViewController = host; window.makeKeyAndVisible()
            host.view.frame = CGRect(origin:.zero,size:size); host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds:500_000_000)
            host.view.frame = CGRect(origin:.zero,size:size); host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size:size,format:format).image { _ in
                host.view.drawHierarchy(in:CGRect(origin:.zero,size:size),afterScreenUpdates:true)
            }
            try image.pngData()!.write(to:output.appendingPathComponent(name+".png"))
        }
        let page = UIGraphicsImageRenderer(size:CGSize(width:1200,height:900)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x:0,y:0,width:1200,height:900))
            UIColor.systemBlue.setStroke(); context.cgContext.setLineWidth(8); context.stroke(CGRect(x:10,y:10,width:1180,height:880))
            ("离线绘本比例检查 · 四边完整" as NSString).draw(at:CGPoint(x:80,y:400),withAttributes:[.font:UIFont.systemFont(ofSize:40),.foregroundColor:UIColor.black])
        }
        for (ratio,size) in [("16x9",CGSize(width:1920,height:1080)),("4x3",CGSize(width:1440,height:1080))] {
            let frame = try play.publicFrame()
            try await capture("public-player-"+ratio,PVEPublicView(frame:frame,image:nil,showingBook:false),size)
            try await capture("public-book-"+ratio,PVEPublicView(frame:frame,image:page,showingBook:true),size)
            var monster = frame
            monster.currentDetails = nil; monster.snapshot.currentName = state.units["m1"]!.name
            for i in monster.snapshot.units.indices { monster.snapshot.units[i].current = monster.snapshot.units[i].id == "m1" }
            try await capture("public-monster-"+ratio,PVEPublicView(frame:monster,image:nil,showingBook:false),size)
        }
        try await capture("public-reduced-motion-4x3",PVEPublicView(frame:try play.publicFrame(),image:nil,showingBook:false).environment(\.presentationReduceMotion,true),CGSize(width:1440,height:1080))
        var ledger = PresentationLedger()
        let reward = try play.reward(ResourceReward(coins:10,score:2))
        try ledger.submit(reward,catalog:catalog,now:Date().addingTimeInterval(-0.2))
        var feedback = try play.publicFrame(); feedback.presentations = ledger.pending
        try await capture("public-feedback-4x3",PVEPublicView(frame:feedback,image:nil,showingBook:false),CGSize(width:1440,height:1080))
        var boss = state; boss.map.nodes[4].kind = .boss; boss.map.nodes[4].name = "隐藏Boss"
        var hiddenReward = boss; hiddenReward.map.nodes[4].kind = .reward; hiddenReward.map.nodes[4].name = "隐藏奖励"
        for (name,source) in [("boss",boss),("reward",hiddenReward)] {
            let publicMap = try source.publicSnapshot(catalog:catalog)
            try await capture("public-unknown-"+name,PVEMapView(nodes:publicMap.nodes,roads:publicMap.roads,units:publicMap.units,publicDisplay:true),CGSize(width:596,height:622))
        }
        var exploration = state
        exploration.battle = nil; exploration.phase = .exploration
        exploration.map.revealed = [1,2,3,4]
        for (index,id) in exploration.players.map(\.id).enumerated() {
            exploration.units[id]?.nodeID = [1,3,4,5,2,1,2][index]
        }
        for id in ["m1","m2","m3"] { exploration.units[id]?.active = false }
        let exploring = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:exploration))
        for (ratio,size) in [("16x9",CGSize(width:1920,height:1080)),("4x3",CGSize(width:1440,height:1080))] {
            var view = try exploring.publicFrame(); view.camera = MapCamera()
            try await capture("public-exploration-"+ratio,PVEPublicView(frame:view,image:nil,showingBook:false),size)
            view.camera = MapCamera(x:0.1,y:0.55,zoom:2.7); view.cameraFocusID = "p1"; view.followsCurrent = false
            try await capture("public-offscreen-"+ratio,PVEPublicView(frame:view,image:nil,showingBook:false),size)
        }
        var inventory = state
        inventory.units["p1"]?.inventory = Dictionary(uniqueKeysWithValues:catalog.items.map { ($0.id,2) })
        let inventoryPlay = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:inventory))
        var inventoryFrame = try inventoryPlay.publicFrame()
        try await capture("public-many-items-page1-4x3",PVEPublicView(frame:inventoryFrame,image:nil,showingBook:false),CGSize(width:1440,height:1080))
        inventoryFrame.itemPage = 4
        try await capture("public-many-items-page5-4x3",PVEPublicView(frame:inventoryFrame,image:nil,showingBook:false),CGSize(width:1440,height:1080))
        let travelingState = try PVEGameFactory.make(players:players,seed:22,catalog:catalog)
        let traveling = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:travelingState))
        let moveReceipt = try traveling.apply(.move(actors:players.map(\.id),path:[1,2,4]))
        var moveLedger = PresentationLedger()
        try moveLedger.submit(moveReceipt,catalog:catalog,now:Date().addingTimeInterval(0.2))
        var moveFrame = try traveling.publicFrame(); moveFrame.presentations = moveLedger.pending
        try await capture("public-arriving-4x3",PVEPublicView(frame:moveFrame,image:nil,showingBook:false),CGSize(width:1440,height:1080))
        moveFrame.presentations = []
        try await capture("public-arrived-4x3",PVEPublicView(frame:moveFrame,image:nil,showingBook:false),CGSize(width:1440,height:1080))
        let teacher = TeacherSession.shared
        let model = PVEAppSession(display:teacher.display)
        model.installVisualFixture(play)
        try await capture("teacher-1366x1024",PVEPlayView(model:model,teacher:teacher),CGSize(width:1366,height:1024))
        try await capture("teacher-1180x820",PVEPlayView(model:model,teacher:teacher),CGSize(width:1180,height:820))
        // Every manifest PNG must decode using Bundle.main while the simulator has no asset server.
        var missing:[String] = []
        for key in GameArt.bindings.keys.sorted() {
            let pair = key.split(separator:":",maxSplits:1).map(String.init)
            if GameArt.image(pair[0],pair[1]) == nil { missing.append(key) }
        }
        let report:[String:Any] = ["screenshots":20,"assetCount":GameArt.bindings.count,"missingAssets":missing,"names":names,"deviceVerified":false,"note":"Actual native SwiftUI simulator rendering; not physical iPad/TV feedback"]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("report.json"))
        guard missing.isEmpty else { throw GameError("离线资产无法解码") }
        try Data("success".utf8).write(to:output.appendingPathComponent("complete.txt"))
    }
}
#endif
