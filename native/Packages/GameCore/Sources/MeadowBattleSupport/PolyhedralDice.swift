import Foundation

public struct DieVector:Codable,Equatable {
    public var x:Double,y:Double,z:Double
    public init(_ x:Double,_ y:Double,_ z:Double) { self.x=x;self.y=y;self.z=z }
    public static func +(_ a:Self,_ b:Self)->Self { .init(a.x+b.x,a.y+b.y,a.z+b.z) }
    public static func -(_ a:Self,_ b:Self)->Self { .init(a.x-b.x,a.y-b.y,a.z-b.z) }
    public static func *(_ a:Self,_ b:Double)->Self { .init(a.x*b,a.y*b,a.z*b) }
    public func dot(_ b:Self)->Double { x*b.x+y*b.y+z*b.z }
    public func cross(_ b:Self)->Self { .init(y*b.z-z*b.y,z*b.x-x*b.z,x*b.y-y*b.x) }
    public var length:Double { sqrt(dot(self)) }
    public var unit:Self { self*(1/max(1e-12,length)) }
}
public struct DieQuaternion:Codable {
    public var w:Double,x:Double,y:Double,z:Double
    public init(_ w:Double,_ x:Double,_ y:Double,_ z:Double) { self.w=w;self.x=x;self.y=y;self.z=z }
    public static let identity=Self(1,0,0,0)
    public static func axis(_ v:DieVector,_ angle:Double)->Self { let s=sin(angle/2),n=v.unit;return Self(cos(angle/2),n.x*s,n.y*s,n.z*s) }
    public static func *(_ a:Self,_ b:Self)->Self { Self(a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z,a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w) }
    public var unit:Self { let n=sqrt(w*w+x*x+y*y+z*z);return .init(w/n,x/n,y/n,z/n) }
    public func rotate(_ v:DieVector)->DieVector { let q=self*Self(0,v.x,v.y,v.z)*Self(w,-x,-y,-z);return .init(q.x,q.y,q.z) }
    public static func align(_ from:DieVector,_ to:DieVector)->Self {
        let a=from.unit,b=to.unit,d=a.dot(b)
        if d < -0.999999 { return axis(a.cross(abs(a.x)<0.8 ? DieVector(1,0,0):DieVector(0,1,0)),Double.pi) }
        let c=a.cross(b);return Self(1+d,c.x,c.y,c.z).unit
    }
    public static func slerp(_ a:Self,_ value:Self,_ t:Double)->Self {
        var b=value,d=a.w*b.w+a.x*b.x+a.y*b.y+a.z*b.z
        if d<0 { b=Self(-b.w,-b.x,-b.y,-b.z);d = -d }
        if d>0.9995 { return Self(a.w+(b.w-a.w)*t,a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t,a.z+(b.z-a.z)*t).unit }
        let theta=acos(min(1,d)),s=sin(theta),u=sin((1-t)*theta)/s,v=sin(t*theta)/s
        return Self(a.w*u+b.w*v,a.x*u+b.x*v,a.y*u+b.y*v,a.z*u+b.z*v)
    }
}
public struct DieMeshFace {
    public let indices:[Int],value:Int
    public let center:DieVector,normal:DieVector,up:DieVector,right:DieVector
    public let labelRadius:Double
}
public struct DieMesh { public let vertices:[DieVector],faces:[DieMeshFace] }
public struct DieProjectedPoint:Codable { public let x:Double,y:Double }
public struct DieProjectedFace:Codable {
    public let value:Int
    public let points:[DieProjectedPoint]
    public let center:DieProjectedPoint,right:DieProjectedPoint,up:DieProjectedPoint
    public let shade:Double,depth:Double
}
public struct DiePolySample:Codable {
    public let faces:[DieProjectedFace]
    public let alpha:Double,offsetY:Double,radius:Double
    public let resultMix:Double
    public let orientation:DieQuaternion
}
public enum PolyhedralDice {
    public static let supported=[4,6,8,10,12,20]
    public static let settleDuration=0.65
    public static let confirmationDuration=0.32
    private static let meshes=Dictionary(uniqueKeysWithValues:supported.map { ($0,makeMesh($0)) })
    public static func mesh(_ sides:Int)->DieMesh? { meshes[sides] }
    public static func spacing(count:Int)->Double { min(82,200/Double(max(1,count))) }
    public static func radius(count:Int)->Double { min(34,spacing(count:count)*0.44) }
    private static func oriented(_ ids:[Int],_ vertices:[DieVector])->[Int] {
        let c=ids.reduce(DieVector(0,0,0)) { $0+vertices[$1] }*(1/Double(ids.count))
        let n=(vertices[ids[1]]-vertices[ids[0]]).cross(vertices[ids[2]]-vertices[ids[0]])
        return n.dot(c)>0 ? ids:Array(ids.reversed())
    }
    private static func rawIcosa()->([DieVector],[[Int]]) {
        let g=(1+sqrt(5.0))/2
        var v:[DieVector]=[]
        for a in [-1.0,1.0] { for b in [-g,g] { v += [.init(0,a,b),.init(a,b,0),.init(b,0,a)] } }
        v=v.map(\.unit);let edge=2/sqrt(1+g*g);var f:[[Int]]=[]
        for i in 0..<v.count { for j in (i+1)..<v.count where abs((v[i]-v[j]).length-edge)<1e-6 { for k in (j+1)..<v.count where abs((v[i]-v[k]).length-edge)<1e-6 && abs((v[j]-v[k]).length-edge)<1e-6 { f.append(oriented([i,j,k],v)) } } }
        return(v,f)
    }
    private static func dual(_ vertices:[DieVector],_ rawFaces:[[Int]])->([DieVector],[[Int]]) {
        let faces=rawFaces.map { oriented($0,vertices) }
        var v=faces.map { ids -> DieVector in let n=(vertices[ids[1]]-vertices[ids[0]]).cross(vertices[ids[2]]-vertices[ids[0]]).unit;return n*(1/n.dot(vertices[ids[0]])) }
        let maximum=v.map(\.length).max()!;v=v.map { $0*(1/maximum) }
        let f=vertices.indices.map { i -> [Int] in
            let n=vertices[i].unit,up=(abs(n.y)<0.9 ? DieVector(0,1,0):DieVector(1,0,0)).cross(n).unit,right=up.cross(n)
            let ids=faces.indices.filter { faces[$0].contains(i) }.sorted { a,b in atan2(v[a].dot(up),v[a].dot(right))<atan2(v[b].dot(up),v[b].dot(right)) }
            return oriented(ids,v)
        }
        return(v,f)
    }
    private static func makeMesh(_ sides:Int)->DieMesh {
        var v:[DieVector]=[],f:[[Int]]=[]
        switch sides {
        case 4:
            v=[DieVector(1,1,1),DieVector(1,-1,-1),DieVector(-1,1,-1),DieVector(-1,-1,1)].map(\.unit)
            f=[[0,1,2],[0,3,1],[0,2,3],[1,3,2]]
        case 6:
            for z in [-1.0,1.0] { for y in [-1.0,1.0] { for x in [-1.0,1.0] { v.append(DieVector(x,y,z).unit) } } }
            f=[[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]]
        case 8:
            v=[.init(1,0,0),.init(-1,0,0),.init(0,1,0),.init(0,-1,0),.init(0,0,1),.init(0,0,-1)]
            for x in [0,1] { for y in [2,3] { for z in [4,5] { f.append([x,y,z]) } } }
        case 10:
            var source:[DieVector]=[]
            for i in 0..<5 { let a=Double(i)*Double.pi*0.4;source.append(.init(cos(a),sin(a),0.5)) }
            for i in 0..<5 { let a=(Double(i)*0.4+0.2)*Double.pi;source.append(.init(cos(a),sin(a),-0.5)) }
            var fs=[[0,1,2,3,4],[5,9,8,7,6]]
            for i in 0..<5 { let next=(i+1)%5;fs.append([i,5+i,next]);fs.append([5+i,5+next,next]) }
            (v,f)=dual(source,fs)
            v=v.map { DieVector($0.x,$0.y,$0.z*0.65) }
            let scale=1/v.map(\.length).max()!;v=v.map { $0*scale }
        case 12:let ico=rawIcosa();(v,f)=dual(ico.0,ico.1)
        default:(v,f)=rawIcosa()
        }
        f=f.map { oriented($0,v) }
        // Deterministic opposite-face numbering where an opposite face exists.
        var values=[Int](repeating:0,count:f.count),next=1
        let normals=f.map { (v[$0[1]]-v[$0[0]]).cross(v[$0[2]]-v[$0[0]]).unit }
        for i in f.indices where values[i]==0 {
            values[i]=next
            if let j=f.indices.first(where: { $0 != i && values[$0]==0 && normals[i].dot(normals[$0]) < -0.999999 }) { values[j]=sides+1-next }
            next += 1
        }
        let faces=f.enumerated().map { i,ids -> DieMeshFace in
            let c=ids.reduce(DieVector(0,0,0)) { $0+v[$1] }*(1/Double(ids.count)),n=normals[i]
            // Canonical top: triangular/pentagonal faces stand on an edge;
            // square faces have a horizontal top edge. Labels share that basis.
            let top:DieVector
            if ids.count % 2 == 1 { top=v[ids[0]]-c }
            else if sides==10 { top=ids.map { v[$0]-c }.max { $0.length<$1.length }! }
            else { top=(v[ids[0]]+v[ids[1]])*0.5-c }
            let up=(top-n*top.dot(n)).unit,right=up.cross(n)
            let inradius=ids.indices.map { k -> Double in let a=v[ids[k]],b=v[ids[(k+1)%ids.count]];return (a-c).cross(b-a).length/(b-a).length }.min()!
            return DieMeshFace(indices:ids,value:values[i],center:c,normal:n,up:up,right:right,labelRadius:inradius*0.78)
        }
        return DieMesh(vertices:v,faces:faces)
    }
    private static func rolling(_ time:Double,_ index:Int)->DieQuaternion {
        let phase=Double(index)*1.17
        return (DieQuaternion.axis(.init(0,0,1),time*1.18+phase)*DieQuaternion.axis(.init(0,1,0),time*4.1+phase+0.4)*DieQuaternion.axis(.init(1,0,0),time*3.0+0.65)).unit
    }
    public static func orientation(sides:Int,value:Int?,time:Double,index:Int,resolvedAge:Double?,duration:Double=settleDuration)->DieQuaternion {
        guard let mesh=mesh(sides),let age=resolvedAge,let value,let face=mesh.faces.first(where: { $0.value==value }) else { return rolling(time,index) }
        let t=min(1,max(0,age/duration)),impact=time-max(0,age)
        let integrated=impact+duration*(1-pow(1-t,3))/3
        let base=rolling(integrated,index),align=DieQuaternion.align(face.normal,.init(0,0,1)),u=align.rotate(face.up)
        let upright=DieQuaternion.axis(.init(0,0,1),atan2(u.x,u.y))*align
        // The resolved face and its numeral face the screen squarely. Rolling
        // retains all three axes; stopping never leaves a skewed result face.
        let target=upright
        if t>=1 { return target }
        return .slerp(base,target,PartyVisual.smooth(t))
    }
    public static func sample(die:BattleDie,time:Double,index:Int,count:Int,resolvedAge:Double?,visibleAge:Double,exitAge:Double?=nil,locked:Bool=false,confirmationAge:Double?=nil)->DiePolySample {
        let envelope=BattleDice.pose(time:time,index:index,resolvedAge:resolvedAge,visibleAge:visibleAge,exitAge:exitAge)
        let landing=confirmationAge.map { PartyVisual.smooth($0/confirmationDuration) }
        let q=orientation(sides:die.sides,value:die.value,time:time,index:index,resolvedAge:confirmationAge ?? (locked ? settleDuration:resolvedAge),duration:confirmationAge == nil ? settleDuration:confirmationDuration)
        let offset:Double
        if let age=confirmationAge {
            let t=min(1,max(0,age/confirmationDuration)),start=time-max(0,age)
            let travelTime=start+confirmationDuration*(1-pow(1-t,3))/3
            offset=BattleDice.pose(time:travelTime,index:index,resolvedAge:nil,visibleAge:visibleAge).offsetY*(1-(landing ?? 0))
        } else { offset=locked ? 0:envelope.offsetY }
        func project(_ p:DieVector)->DieProjectedPoint { let d=4.2/(4.2-p.z);return .init(x:p.x*d,y:-p.y*d) }
        let faces=(mesh(die.sides)?.faces ?? []).compactMap { face -> DieProjectedFace? in
            let c=q.rotate(face.center),n=q.rotate(face.normal)
            guard n.dot(DieVector(0,0,4.2)-c)>0.001 else { return nil }
            let light=DieVector(-0.4,0.7,1).unit
            return DieProjectedFace(value:face.value,points:face.indices.map { project(q.rotate(mesh(die.sides)!.vertices[$0])) },center:project(c),right:project(c+q.rotate(face.right)*face.labelRadius),up:project(c+q.rotate(face.up)*face.labelRadius),shade:0.45+0.55*max(0,n.dot(light)),depth:c.z)
        }.sorted {
            // Coplanar-depth side faces of a square-on polyhedron must have
            // one draw order on arm64/macOS and Linux despite rounding noise.
            let a=Int64(($0.depth*1e9).rounded()),b=Int64(($1.depth*1e9).rounded())
            return a==b ? $0.value<$1.value:a<b
        }
        return DiePolySample(faces:faces,alpha:envelope.alpha,offsetY:offset,radius:radius(count:count),resultMix:landing ?? (locked ? 1:envelope.resultMix),orientation:q)
    }
}
