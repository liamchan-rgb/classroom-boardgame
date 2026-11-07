// Offline command-line fixture export, never an app or simulator launch.
import Foundation
import ClassroomGameCore

let catalog=try GameCatalog.initial()
var state=try PVEGameFactory.make(players:[PlayerSetup(id:"p1",name:"Student 1",classID:"spellblade"),PlayerSetup(id:"p2",name:"Student 2",classID:"adventurer")],seed:21,catalog:catalog)
state.random.scripted=[20,18,5,3,4]
state.units["p1"]?.health=5
let engine=try GameEngine(catalog:catalog,state:state)
let play=PVEPlaySession(engine:engine)
let exploration=try play.publicFrame()
var ledger=PresentationLedger()
let now=Date(timeIntervalSince1970:1000)
let move=try engine.apply(.move(actors:["p1","p2"],path:[1,2]))
try ledger.submit(move,catalog:catalog,now:now)
var arrival=try play.publicFrame();arrival.presentations=ledger.pending
ledger.clearVisible()
let strike=try engine.apply(.cast(actor:"p1",skill:"runeSlash",target:.unit("m1")))
try ledger.submit(strike,catalog:catalog,now:now.addingTimeInterval(2))
var slash=try play.publicFrame();slash.presentations=ledger.pending
let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
let data=try encoder.encode(["exploration":exploration,"arrival":arrival,"runeSlash":slash])
FileHandle.standardOutput.write(data)
