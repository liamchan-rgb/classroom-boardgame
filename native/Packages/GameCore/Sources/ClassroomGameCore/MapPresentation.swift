import Foundation

/// Coordinates and camera preferences used only by the display, never GameArchive.
public struct MapPoint: Codable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}
public struct MapCamera: Codable, Equatable {
    public var center: MapPoint
    public var zoom: Double
    public init(x: Double = 0.5, y: Double = 0.5, zoom: Double = 1) {
        center = MapPoint(x:x.isFinite ? min(1,max(0,x)) : 0.5,y:y.isFinite ? min(1,max(0,y)) : 0.5)
        self.zoom = zoom.isFinite ? min(3,max(1,zoom)) : 1
    }
    public func screen(_ p: MapPoint, width: Double, height: Double, inset: Double = 70) -> MapPoint {
        MapPoint(x:width/2+(p.x-center.x)*max(1,width-2*inset)*zoom,
                 y:height/2+(p.y-center.y)*max(1,height-2*inset)*zoom)
    }
    public func panned(x: Double, y: Double) -> MapCamera { MapCamera(x:center.x+x,y:center.y+y,zoom:zoom) }
    public func scaled(by factor: Double) -> MapCamera { MapCamera(x:center.x,y:center.y,zoom:zoom*factor) }
}
public enum MapEdge: String, Codable, CaseIterable { case left, right, top, bottom }
public struct MapEdgeMarker: Equatable, Identifiable {
    public var id: String
    public var point: MapPoint
    public var edge: MapEdge
    public var directionDegrees: Double
    public var unitIDs: [String] = []
}
public enum MapDisplayGeometry {
    /// Only call with units from the public snapshot when drawing the public map.
    public static func edgeMarkers(points: [(String,MapPoint)], width: Double, height: Double, size: Double = 52) -> [MapEdgeMarker] {
        guard width > (size+8)*2, height > (size+8)*2 else { return [] }
        let margin = size+8, halfX = width/2-margin, halfY = height/2-margin
        var markers: [MapEdgeMarker] = []
        for (id,p) in points where p.x < margin || p.x > width-margin || p.y < margin || p.y > height-margin {
            let dx = p.x-width/2, dy = p.y-height/2
            let tx = dx == 0 ? Double.infinity : halfX/abs(dx)
            let ty = dy == 0 ? Double.infinity : halfY/abs(dy)
            let t = min(tx,ty)
            let edge: MapEdge = tx < ty ? (dx < 0 ? .left : .right) : (dy < 0 ? .top : .bottom)
            markers.append(MapEdgeMarker(id:id,point:MapPoint(x:width/2+dx*t,y:height/2+dy*t),edge:edge,directionDegrees:atan2(dy,dx)*180/Double.pi,unitIDs:[id]))
        }
        // Keep coincident offscreen players separate, in stable ID order.
        var result: [MapEdgeMarker] = []
        for edge in MapEdge.allCases {
            let vertical = edge == .left || edge == .right
            var group = markers.filter { $0.edge == edge }.sorted {
                let a = vertical ? $0.point.y : $0.point.x, b = vertical ? $1.point.y : $1.point.x
                return a == b ? $0.id < $1.id : a < b
            }
            let low = margin+size*0.8, high = (vertical ? height : width)-margin-size*0.8
            let capacity = max(1,Int(max(0,high-low)/(size+4))+1)
            if group.count > capacity {
                let countPerGroup = Int(ceil(Double(group.count)/Double(capacity)))
                group = stride(from:0,to:group.count,by:countPerGroup).map { start in
                    let subset = Array(group[start..<min(group.count,start+countPerGroup)])
                    var merged = subset[0]
                    merged.unitIDs = subset.flatMap(\.unitIDs); merged.id = merged.unitIDs.joined(separator:"+")
                    merged.point = MapPoint(x:subset.map { $0.point.x }.reduce(0,+)/Double(subset.count),y:subset.map { $0.point.y }.reduce(0,+)/Double(subset.count))
                    return merged
                }
            }
            let gap = min(size+4,max(0,high-low)/Double(max(1,group.count-1)))
            var previous = low-gap
            for i in group.indices {
                let raw = vertical ? group[i].point.y : group[i].point.x
                let value = min(high-Double(group.count-i-1)*gap,max(low,max(raw,previous+gap)))
                if vertical { group[i].point.y = value } else { group[i].point.x = value }
                previous = value
            }
            result += group
        }
        return result
    }
}
public struct PublicMapMove: Codable, Equatable, Identifiable {
    public var id: String { unitID }
    public var unitID: String
    public var points: [MapPoint]
    public init(unitID: String, points: [MapPoint]) { self.unitID = unitID; self.points = points }
    public func position(progress: Double) -> MapPoint? {
        guard let first = points.first, let last = points.last else { return nil }
        guard points.count > 1 else { return first }
        let t = min(1,max(0,progress))
        if t >= 1 { return last }
        let lengths = zip(points,points.dropFirst()).map { hypot($0.1.x-$0.0.x,$0.1.y-$0.0.y) }
        let total = lengths.reduce(0,+)
        guard total > 0 else { return last }
        var distance = total*t
        for i in lengths.indices {
            if distance <= lengths[i], lengths[i] > 0 {
                let f = distance/lengths[i]
                return MapPoint(x:points[i].x+(points[i+1].x-points[i].x)*f,y:points[i].y+(points[i+1].y-points[i].y)*f)
            }
            distance -= lengths[i]
        }
        return last
    }
}
