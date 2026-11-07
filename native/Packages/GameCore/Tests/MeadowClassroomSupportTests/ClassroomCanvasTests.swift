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
}
