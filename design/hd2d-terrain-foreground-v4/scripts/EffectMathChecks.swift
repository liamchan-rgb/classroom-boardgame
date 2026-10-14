import Foundation
import CoreGraphics

@main struct EffectMathChecks {
    static func main() {
        var count = 0
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            guard condition() else { fatalError("FAIL: \(name)") }
            count += 1; print("PASS: \(name)")
        }
        let geometry = WorldGeometry(), graph = DisplayGraph.sample()
        let points = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id,geometry.point($0.point)) })
        let roads = graph.publicEdges.map { RoadCurve(a: points[$0.a]!,b: points[$0.b]!,bend: $0.a == 1 ? -28 : 20) }
        let field = MeadowField(seed: 17,roads: roads,landmarks: graph.nodes.filter(\.revealed).map { geometry.point($0.point) })
        let duplicate = MeadowField(seed: 17,roads: roads,landmarks: field.landmarks)
        let changedSeed = MeadowField(seed: 19,roads: roads,landmarks: field.landmarks)
        var bounded = true, repeats = true, nonuniform = Set<Int>()
        for y in stride(from: -750,through: 2300,by: 61) { for x in stride(from: -750,through: 2300,by: 53) {
            let p = CGPoint(x:x,y:y), a = field.channels(p), b = duplicate.channels(p)
            bounded = bounded && [a.detail,a.forest,a.sunlight].allSatisfy { $0.isFinite && (0...1).contains($0) }
            repeats = repeats && a.detail == b.detail && a.forest == b.forest && a.sunlight == b.sunlight
            nonuniform.insert(Int(a.detail*100))
        } }
        check("field channels finite and bounded across world",bounded)
        check("seeded world field deterministic",repeats)
        check("natural patches have multiple density levels",nonuniform.count>25)
        check("decoration seed changes field",field.community(CGPoint(x:300,y:600)) != changedSeed.community(CGPoint(x:300,y:600)))
        check("road center has no dense detail",(0...30).allSatisfy { field.clearance(roads[0].point(Double($0)/30))<0.05 })
        check("camp center has no dense detail",field.clearance(points[1]!)==0)
        check("clearance recovers away from paths",field.clearance(CGPoint(x:1500,y:1400))>0.95)
        let p = CGPoint(x:418.21,y:981.57)
        check("noise continuous at small camera-independent displacement",abs(field.community(p)-field.community(CGPoint(x:p.x+0.001,y:p.y)))<0.0001)
        let projection=SunProjection(), foot=CGPoint(x:231,y:451), projectedFoot=projection.projectedFoot(anchorTop:foot)
        check("shadow foot fixed",abs(projectedFoot.x-foot.x)<0.0001 && abs(projectedFoot.y)<0.0001)
        let top=CGPoint(x:foot.x,y:0).applying(projection.transform(anchorTop:foot))
        check("upper-left sun casts lower-right",top.x>projectedFoot.x && top.y>projectedFoot.y)
        var extreme=HD2DSettings();extreme.shadowStrength = -3;extreme.vegetationContrast = 20;extreme.bloomStrength = .nan;extreme.depthRadius = .infinity;extreme.motionStrength = 20
        let safe=extreme.bounded()
        check("finite bounded effects",safe.shadowStrength==0 && safe.vegetationContrast==1 && safe.bloomStrength==0 && safe.depthRadius==0 && safe.motionStrength==1)
        check("default settings already bounded",HD2DSettings()==HD2DSettings().bounded())
        check("pixel character excluded from environment kind",SurfaceKind.asset("hero-7")==SurfaceKind.actor && SurfaceKind.asset("ranger")==SurfaceKind.actor)
        check("only public edges rendered",graph.publicEdges==[DisplayEdge(a:1,b:2),DisplayEdge(a:2,b:3)])
        check("original five nodes unchanged",graph.nodes.count==5 && hypot(points[1]!.x-160,points[1]!.y-720)<0.001 && hypot(points[3]!.x-992,points[3]!.y-1184)<0.001)
        check("road/movement endpoints unchanged",roads[0].point(0)==points[1] && roads[0].point(1)==points[2])
        let event=DemoPresentation(id:"one",start:Date(),duration:1.8,curve:roads[0]);var gate=PresentationGate()
        check("duplicate display event not replayed",gate.accept(event,now:event.start) && !gate.accept(event,now:event.start))
        check("16:9 and 4:3 fits positive",geometry.fitScale(view:CGSize(width:1600,height:900))>0 && geometry.fitScale(view:CGSize(width:1200,height:900))>0)
        check("projection shorter than v3 while preserving direction",projection.dx<0.55 && projection.dy<0.28)
        let n=field.normal(p)
        check("geometric ground normals normalized",abs(n.x*n.x+n.y*n.y+n.z*n.z-1)<0.000001 && n.z>0)
        check("ground height deterministic and bounded",field.height(p)==duplicate.height(p) && (0...56).contains(field.height(p)))
        let recipe=SceneryRecipe(field:field).candidates(),again=SceneryRecipe(field:duplicate).candidates()
        check("same decoration candidate budget",recipe.count==85)
        check("modular grove recipe deterministic",zip(recipe,again).allSatisfy { a,b in a.point==b.point && a.id==b.id && a.width==b.width })
        check("tree recipes use standalone assets",recipe.filter { $0.id.contains("single") }.count>40 && !recipe.contains { $0.id.contains("grove") })
        check("terrain facets receive terrain material",SurfaceKind.asset("terrace")==SurfaceKind.terrain && SurfaceKind.asset("bank")==SurfaceKind.terrain)
        let views=[CGSize(width:1280,height:960),CGSize(width:1280,height:720)]
        var remainsVisible=true,continuous=true,fixedFoot=true
        for view in views { for corner in 0...1 {
            let foot=ForegroundGeometry.foot(index:corner,view:view),width=ForegroundGeometry.width(view:view)
            let rect=CGRect(x:foot.x-width/2,y:foot.y,width:width,height:ForegroundGeometry.height(view:view))
            var previous:CGFloat?
            for step in 0...140 {
                let zoom=1+CGFloat(step)*0.01,scale=geometry.fitScale(view:view)/zoom
                let screen=ForegroundGeometry.screen(points[1]!,camera:CGPoint(x:800,y:768),scale:scale)
                let opacity=ForegroundGeometry.opacity(rect:rect,protected:[screen])
                remainsVisible = remainsVisible && opacity>=ForegroundGeometry.minimumOpacity && opacity<=ForegroundGeometry.maximumOpacity
                if let previous { continuous = continuous && abs(opacity-previous)<0.10 }
                previous=opacity
                fixedFoot = fixedFoot && foot==ForegroundGeometry.foot(index:corner,view:view)
            }
        } }
        check("both corner trees remain nonzero through 1 to 2.4 zoom in both ratios",remainsVisible)
        check("foreground avoidance continuous during zoom",continuous)
        check("viewport foreground does not relocate with camera zoom",fixedFoot)
        let rect=CGRect(x:0,y:0,width:100,height:120)
        let a=ForegroundGeometry.opacity(rect:rect,protected:[CGPoint(x:120,y:80)])
        let b=ForegroundGeometry.opacity(rect:rect,protected:[CGPoint(x:120.001,y:80)])
        check("no hard overlap opacity threshold",abs(a-b)<0.0001)
        check("overlap retains foreground silhouette",ForegroundGeometry.opacity(rect:rect,protected:[CGPoint(x:40,y:60)])==ForegroundGeometry.minimumOpacity)
        print("PASS: \(count) effect/geometry checks; no screenshots, simulator or visual review.")
    }
}
