import XCTest
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import MeadowWorldSupport
@testable import MeadowClassroomSupport

final class ClassroomCanvasTests:XCTestCase {
    let hosts=[CGSize(width:1234,height:694),CGSize(width:1024,height:768),CGSize(width:1920,height:1080),CGSize(width:3840,height:2160),CGSize(width:768,height:1024)]
    func testAllHostsUseOneCanvasAndFitWithoutCroppingOrStretching(){
        for host in hosts {
            let frame=ClassroomCanvas.fitted(in:host)
            XCTAssertEqual(frame.width/frame.height,16/9,accuracy:0.000001)
            XCTAssertGreaterThanOrEqual(frame.minX,0);XCTAssertGreaterThanOrEqual(frame.minY,0)
            XCTAssertLessThanOrEqual(frame.maxX,host.width+0.000001);XCTAssertLessThanOrEqual(frame.maxY,host.height+0.000001)
            XCTAssertEqual(ClassroomCanvas.point(CGPoint(x:host.width/2,y:host.height/2),in:host),CGPoint(x:640,y:360))
            XCTAssertEqual(ClassroomCanvas.size,CGSize(width:1280,height:720))
        }
    }
    func testInputRoundTripAndLetterboxReject(){
        for host in hosts {
            let frame=ClassroomCanvas.fitted(in:host)
            for p in [CGPoint(x:4,y:4),CGPoint(x:640,y:360),CGPoint(x:1270,y:710)] {
                let displayed=CGPoint(x:frame.minX+p.x/1280*frame.width,y:frame.minY+p.y/720*frame.height)
                let restored=ClassroomCanvas.point(displayed,in:host)!
                XCTAssertEqual(restored.x,p.x,accuracy:0.000001);XCTAssertEqual(restored.y,p.y,accuracy:0.000001)
            }
        }
        XCTAssertNil(ClassroomCanvas.point(CGPoint(x:10,y:10),in:CGSize(width:1024,height:768)))
        XCTAssertNil(ClassroomCanvas.point(.zero,in:.zero))
    }
    func testDragVectorsHaveTheSameCanonicalDistanceAcrossHosts(){
        let delta=CGPoint(x:120,y:-48)
        for host in hosts {
            let rect=ClassroomCanvas.fitted(in:host),scale=rect.width/1280
            let actual=ClassroomCanvas.translation(CGPoint(x:delta.x*scale,y:delta.y*scale),in:host)!
            XCTAssertEqual(actual.x,delta.x,accuracy:0.000001);XCTAssertEqual(actual.y,delta.y,accuracy:0.000001)
            let back=ClassroomCanvas.translation(CGPoint(x:-delta.x*scale,y:-delta.y*scale),in:host)!
            XCTAssertEqual(actual.x+back.x,0,accuracy:0.000001);XCTAssertEqual(actual.y+back.y,0,accuracy:0.000001)
        }
    }
    func testInvalidDragVectorsAreRejected(){
        XCTAssertNil(ClassroomCanvas.translation(CGPoint(x:1,y:1),in:.zero))
        XCTAssertNil(ClassroomCanvas.translation(CGPoint(x:Double.nan,y:1),in:CGSize(width:1280,height:720)))
    }
    func testActualProjectionInverseIncludesZoomPanAndNonUniformAxes(){
        for zoom in [0.7,1.0,1.6,2.2] {
            let origin=CGPoint(x:-145,y:81),xAxis=CGPoint(x:zoom,y:0.1*zoom),yAxis=CGPoint(x:0.03*zoom,y:zoom)
            let world=CGPoint(x:713,y:452)
            let screen=CGPoint(x:origin.x+world.x*xAxis.x+world.y*yAxis.x,y:origin.y+world.x*xAxis.y+world.y*yAxis.y)
            let restored=ClassroomCanvas.unproject(screen,origin:origin,xAxis:xAxis,yAxis:yAxis)!
            XCTAssertEqual(restored.x,world.x,accuracy:0.000001);XCTAssertEqual(restored.y,world.y,accuracy:0.000001)
        }
        XCTAssertNil(ClassroomCanvas.unproject(.zero,origin:.zero,xAxis:.zero,yAxis:.zero))
    }
    func testRepeatedIPadTVDisconnectFitsDoNotChangeCampaignCameraMapOrRandom()throws {
        let layout=try MeadowMapGenerator.generate(.suggested(total:10,seed:31827)),c=try MeadowCampaignSession.new(layout:layout),before=c.snapshot
        for _ in 0..<20 {
            for host in hosts+hosts.reversed() {
                let f=ClassroomCanvas.fitted(in:host)
                for node in layout.map.nodes {
                    let p=CGPoint(x:node.x*1280,y:node.y*720)
                    let q=CGPoint(x:f.minX+p.x/1280*f.width,y:f.minY+p.y/720*f.height)
                    let restored=ClassroomCanvas.point(q,in:host)!
                    XCTAssertEqual(restored.x,p.x,accuracy:0.000001);XCTAssertEqual(restored.y,p.y,accuracy:0.000001)
                }
            }
        }
        XCTAssertEqual(c.snapshot,before)
    }

    func testCompactQuizCardStaysInsideAllAspectRatiosAndMapsEdgesConsistently(){
        let canvases=[CGSize(width:840,height:720),CGSize(width:960,height:720),CGSize(width:1280,height:720),CGSize(width:1800,height:720)]
        let cards=[CGSize(width:380,height:144),CGSize(width:720,height:185),CGSize(width:920,height:240)]
        let anchors=[ClassroomQuizCardLayout.defaultAnchor,CGPoint(x:0,y:0),CGPoint(x:1,y:0),CGPoint(x:0,y:1),CGPoint(x:1,y:1),CGPoint(x:0.25,y:0.75)]
        for canvas in canvases {
            for card in cards {
                let effectiveCard=CGSize(width:min(card.width,canvas.width-36),height:card.height)
                for anchor in anchors {
                    let frame=ClassroomQuizCardLayout.compactFrame(cardSize:effectiveCard,in:canvas,anchor:anchor)
                    XCTAssertGreaterThanOrEqual(frame.minX,0)
                    XCTAssertGreaterThanOrEqual(frame.minY,0)
                    XCTAssertLessThanOrEqual(frame.maxX,canvas.width+0.001)
                    XCTAssertLessThanOrEqual(frame.maxY,canvas.height+0.001)
                    XCTAssertEqual(frame.size,effectiveCard)
                }
                let defaultFrame=ClassroomQuizCardLayout.compactFrame(cardSize:effectiveCard,in:canvas,anchor:ClassroomQuizCardLayout.defaultAnchor)
                XCTAssertEqual(defaultFrame.midX,canvas.width/2,accuracy:0.5)
                XCTAssertEqual(defaultFrame.minY,ClassroomQuizCardLayout.edgeMargin,accuracy:0.5)
            }
        }
    }

    func testCompactQuizCardDragClampsAndPreservesHorizontalAnchorWhenFullWidth(){
        let canvas=CGSize(width:1280,height:720),card=CGSize(width:420,height:150)
        let moved=ClassroomQuizCardLayout.draggedAnchor(from:ClassroomQuizCardLayout.defaultAnchor,delta:CGPoint(x:9999,y:9999),cardSize:card,in:canvas)
        XCTAssertEqual(moved,CGPoint(x:1,y:1))
        let backTopLeft=ClassroomQuizCardLayout.draggedAnchor(from:moved,delta:CGPoint(x:-9999,y:-9999),cardSize:card,in:canvas)
        XCTAssertEqual(backTopLeft,CGPoint(x:0,y:0))
        let invalid=ClassroomQuizCardLayout.draggedAnchor(from:CGPoint(x:0.4,y:0.6),delta:CGPoint(x:Double.nan,y:20),cardSize:card,in:canvas)
        XCTAssertEqual(invalid,CGPoint(x:0.4,y:0.6))

        // Narrow preview where card fills full width (travel.width == 0): vertical drag keeps horizontal anchor intact.
        let narrowCanvas=CGSize(width:900,height:720),wideCard=CGSize(width:864,height:180)
        let verticalOnly=ClassroomQuizCardLayout.draggedAnchor(from:CGPoint(x:0.25,y:0.0),delta:CGPoint(x:120,y:252),cardSize:wideCard,in:narrowCanvas)
        XCTAssertEqual(verticalOnly.x,0.25,accuracy:0.0001)
        XCTAssertGreaterThan(verticalOnly.y,0.45)

        // Challenge & top-center timer clear their respective top banners.
        XCTAssertEqual(ClassroomQuizCardLayout.topInset(challengeActive:false,timerTopCenter:false),ClassroomQuizCardLayout.edgeMargin)
        XCTAssertEqual(ClassroomQuizCardLayout.topInset(challengeActive:true,timerTopCenter:false),ClassroomQuizCardLayout.challengeTopInset)
        XCTAssertEqual(ClassroomQuizCardLayout.topInset(challengeActive:false,timerTopCenter:true),ClassroomQuizCardLayout.timerTopInset)
        let challengeFrame=ClassroomQuizCardLayout.compactFrame(cardSize:card,in:canvas,anchor:ClassroomQuizCardLayout.defaultAnchor,topInset:ClassroomQuizCardLayout.topInset(challengeActive:true,timerTopCenter:false))
        XCTAssertEqual(challengeFrame.minY,ClassroomQuizCardLayout.challengeTopInset,accuracy:0.5)
    }
}
