import XCTest
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import MeadowWorldSupport
@testable import MeadowClassroomSupport

final class ClassroomPreviewTests:XCTestCase {
    func testOpeningMonsterPreviewStillAllowsTeacherRoadNavigation()throws {
        let b=ClassroomGameBackend(),layout=try MeadowMapGenerator.generate(.suggested(total:10,seed:31827)),c=try MeadowCampaignSession.new(layout:layout)
        try b.install(c,role:.teacher)
        let node=try XCTUnwrap(c.engine.state.map.nodes.first{$0.kind == .combat})
        try b.project(.encounter(node.id),role:.teacher)
        XCTAssertTrue(b.surface.acceptsMapInput)
        let random=c.engine.state.random
        try b.travel(to:c.point(at:node.id),role:.teacher)
        XCTAssertEqual(b.surface,.exploration);XCTAssertNotNil(c.travel);XCTAssertEqual(c.engine.state.random,random)
        for panel:ClassroomPublicSurface in [.book,.inventory("p1"),.battle,.waiting,.results]{XCTAssertFalse(panel.acceptsMapInput)}
    }
    func testPreviewPayloadStaysWithinBudgetWithoutChangingGameCanvas(){
        let size=ClassroomPreviewPolicy.size(for:ClassroomCanvas.size)
        let bytesPerSecond=Double(size.width*size.height*4)*ClassroomPreviewPolicy.framesPerSecond
        XCTAssertLessThanOrEqual(bytesPerSecond,16_000_000)
        XCTAssertEqual(ClassroomCanvas.size,CGSize(width:1280,height:720))
        XCTAssertEqual(size.width/size.height,16/9,accuracy:0.000001)
        XCTAssertEqual(ClassroomPreviewPolicy.size(for:CGSize(width:1,height:1)),CGSize(width:1,height:1))
    }
    func testPreviewIsOffWhenHiddenLocalBookBackgroundOrPrivateModal(){
        func allowed(_ external:Bool=true,_ visible:Bool=true,_ foreground:Bool=true,_ modal:Bool=false,_ surface:ClassroomPublicSurface = .exploration)->Bool {
            ClassroomPreviewPolicy.enabled(external:external,visible:visible,foreground:foreground,privateModal:modal,surface:surface)
        }
        XCTAssertTrue(allowed());XCTAssertTrue(allowed(true,true,true,false,.encounter(1)))
        XCTAssertFalse(allowed(false));XCTAssertFalse(allowed(true,false));XCTAssertFalse(allowed(true,true,false));XCTAssertFalse(allowed(true,true,true,true))
        XCTAssertFalse(allowed(true,true,true,false,.book));XCTAssertFalse(allowed(true,true,true,false,.waiting))
    }
}
