import Foundation
import CoreGraphics

// Geometry shared by runtime and CPU checks: no Boolean overlap threshold and no zoom culling.
struct ForegroundGeometry {
    static let minimumOpacity: CGFloat = 0.34
    static let maximumOpacity: CGFloat = 0.90
    static func height(view: CGSize) -> CGFloat { min(160,max(112,view.height*0.16)) }
    static func width(view: CGSize) -> CGFloat { height(view:view)*0.80 }
    static func foot(index: Int, view: CGSize) -> CGPoint {
        let x = view.width/2-width(view:view)*0.22
        return CGPoint(x: index==0 ? -x : x,y:-view.height/2-12)
    }
    static func screen(_ point: CGPoint,camera: CGPoint,scale: CGFloat) -> CGPoint {
        CGPoint(x:(point.x-camera.x)/max(0.01,scale),y:(point.y-camera.y)/max(0.01,scale))
    }
    static func opacity(rect: CGRect, protected points: [CGPoint]) -> CGFloat {
        var coverage: CGFloat = 0
        for point in points {
            let dx = max(0,max(rect.minX-point.x,point.x-rect.maxX))
            let dy = max(0,max(rect.minY-point.y,point.y-rect.maxY))
            let distance = hypot(dx,dy)
            let value = 1-CGFloat(MeadowField.smooth(0,64,Double(distance)))
            coverage = max(coverage,value)
        }
        return max(minimumOpacity,min(maximumOpacity,maximumOpacity-(maximumOpacity-minimumOpacity)*coverage))
    }
}

// Display-only tree placement. Trees share atlas units but differ in size and foot position.
struct SceneryCandidate {
    let id: String
    let point: CGPoint
    let width: CGFloat
    let terrain: Bool
}
struct SceneryRecipe {
    let field: MeadowField
    func candidates() -> [SceneryCandidate] {
        var rng=DisplayRandom(seed:field.seed)
        var result:[SceneryCandidate]=[]
        for i in 0..<85 {
            let point:CGPoint
            if i%4 != 3 {
                let center=field.forestCenters[i%field.forestCenters.count]
                point=CGPoint(x:center.x+(rng.next()-0.5)*390,y:center.y+(rng.next()-0.5)*310)
            } else { point=CGPoint(x:-100+rng.next()*1850,y:40+rng.next()*1450) }
            let id:String,width:CGFloat,isTerrain:Bool
            if i%11==7 { id="terrace";width=210+rng.next()*75;isTerrain=true }
            else if i%13==8 { id="bank";width=165+rng.next()*65;isTerrain=true }
            else if i%7==5 { id="rock_outcrop";width=96+rng.next()*46;isTerrain=false }
            else if i%9==6 { id="ground_tuft";width=48+rng.next()*23;isTerrain=false }
            else { id=i%3==0 ? "fir_single":"oak_single";width=(id=="fir_single" ? 65:112)+rng.next()*28;isTerrain=false }
            result.append(SceneryCandidate(id:id,point:point,width:width,terrain:isTerrain))
        }
        return result
    }
}
