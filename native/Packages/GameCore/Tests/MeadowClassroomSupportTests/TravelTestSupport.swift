import XCTest
import MeadowWorldSupport

extension MeadowCampaignSession {
    /// Walks the selected member's team to `node`. A move ends wherever the bar runs out (a node or a spot on the
    /// road), so the walk refills (free, teacher refill) and sets off again from there until it arrives.
    func walkAll(to node:Int,actor:String?=nil,file:StaticString=#filePath,line:UInt=#line)throws {
        let who=actor ?? selectedPlayerID
        lastTravelCut=nil
        for _ in 0..<60 {
            if travel==nil || !hasPendingTravel {
                if travel==nil,engine.state.units[who]?.nodeID==node || engine.state.battle != nil {return}
                do{try beginTravel(to:node,actor:who)}
                catch{try refillMovement(usingCoins:false);try beginTravel(to:node,actor:who)}
            }
            if !isMoving {try refillMovement(usingCoins:false);try setPaused(false)}
            try advanceTravel(distance:100000)
        }
        XCTFail("walk to \(node) did not arrive",file:file,line:line)
    }
}
