import SwiftUI
import ClassroomGameCore

struct PVEMapView:View {
    let nodes:[PublicGameNode]
    let roads:[MapRoad]
    let units:[PublicGameUnit]
    var path:[Int] = []
    var interactive = false
    var onNode:((Int)->Void)?
    var actorNode:Int? = nil
    var legalNodes:Set<Int> = []
    var planAllowed = true
    var publicDisplay = false
    var camera = MapCamera()
    var events:[CommittedPresentation] = []
    var onFocusUnit:((String)->Void)? = nil
    var round = 0
    var onPan:((Double,Double)->Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.presentationReduceMotion) private var forcedReduced
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/30,paused:events.isEmpty || systemReduced || forcedReduced)) { context in
            GeometryReader { geometry in
                let width = Double(geometry.size.width), height = Double(geometry.size.height)
                let portraitSize = publicDisplay ? 46.0 : 34.0
                let event = events.first { context.date < $0.end && !$0.mapMoves.isEmpty }
                let positions = Dictionary(uniqueKeysWithValues:units.compactMap { unit -> (String,CGPoint)? in
                    guard let node = nodes.first(where: { $0.id == unit.nodeID }) else { return nil }
                    var location = MapPoint(x:node.x,y:node.y)
                    if !systemReduced && !forcedReduced, let event, let move = event.mapMoves.first(where: { $0.unitID == unit.id }),
                       let point = move.position(progress:context.date.timeIntervalSince(event.start)/1.3) { location = point }
                    let base = camera.screen(location,width:width,height:height)
                    let offset = slot(unit,size:portraitSize)
                    return (unit.id,CGPoint(x:base.x+offset.x,y:base.y+offset.y))
                })
                let markers = MapDisplayGeometry.edgeMarkers(points:units.filter(\.player).compactMap { unit in
                    positions[unit.id].map { (unit.id,MapPoint(x:Double($0.x),y:Double($0.y))) }
                },width:width,height:height,size:publicDisplay ? 52 : 44)
                ZStack {
                    ArtImage(type:"visualLayer",id:width/height > 1.5 ? "map_ground_1920" : "map_ground_1440")
                        .aspectRatio(contentMode:.fill).frame(width:width,height:height).clipped()
                    ArtImage(type:"visualLayer",id:width/height > 1.5 ? "map_decoration_1920" : "map_decoration_1440")
                        .aspectRatio(contentMode:.fill).frame(width:width,height:height).clipped()
                    Canvas { drawing,size in
                        let byID = Dictionary(uniqueKeysWithValues:nodes.map { ($0.id,$0) })
                        for road in roads {
                            guard let a = byID[road.a], let b = byID[road.b] else { continue }
                            var line = Path(); line.move(to:point(a,size:size)); line.addLine(to:point(b,size:size))
                            drawing.stroke(line,with:.color(GameTheme.primary.opacity(0.30)),style:StrokeStyle(lineWidth:6,lineCap:.round))
                            if path.indices.dropFirst().contains(where: { Set([path[$0-1],path[$0]]) == Set([road.a,road.b]) }) {
                                drawing.stroke(line,with:.color(planAllowed ? GameTheme.accent : GameTheme.danger),style:StrokeStyle(lineWidth:3,lineCap:.round,dash:[8,6]))
                            }
                        }
                    }
                    ForEach(nodes) { node in
                        let here = units.filter { $0.nodeID == node.id }
                        let current = here.contains { $0.current } || actorNode == node.id
                        Group {
                            if interactive {
                                Button { onNode?(node.id) } label: { nodeContent(node,here:here,current:current) }.buttonStyle(.plain)
                            } else { nodeContent(node,here:here,current:current) }
                        }.frame(width:publicDisplay ? 94 : 68,height:publicDisplay ? 94 : 68).position(point(node,size:geometry.size))
                    }
                    ForEach(units) { unit in
                        if let position = positions[unit.id], position.x >= 24, position.x <= width-24, position.y >= 24, position.y <= height-24 {
                            unitButton(unit,size:portraitSize).position(position)
                        }
                    }
                    ForEach(markers) { marker in
                        if let unit = units.first(where: { $0.id == marker.id }) {
                            ZStack(alignment:.topTrailing) {
                                unitButton(unit,size:publicDisplay ? 48 : 36)
                                Image(systemName:"arrow.right.circle.fill").font(.system(size:publicDisplay ? 24 : 18,weight:.bold))
                                    .rotationEffect(.degrees(marker.directionDegrees)).foregroundStyle(GameTheme.primary)
                                    .background(.white,in:Circle()).offset(x:8,y:-6).allowsHitTesting(false)
                            }.position(x:marker.point.x,y:marker.point.y)
                        }
                    }
                }.frame(width:width,height:height).clipped()
                    .highPriorityGesture(DragGesture(minimumDistance:12).onEnded { value in
                        onPan?(-Double(value.translation.width)/max(1,width-140)/camera.zoom,
                               -Double(value.translation.height)/max(1,height-140)/camera.zoom)
                    })
            }
        }.clipShape(RoundedRectangle(cornerRadius:16))
    }
    private func slot(_ unit:PublicGameUnit,size:Double) -> MapPoint {
        let peers = units.filter { $0.nodeID == unit.nodeID && $0.player == unit.player }.sorted { $0.id < $1.id }
        let index = peers.firstIndex { $0.id == unit.id } ?? 0
        let columns = min(4,peers.count), rowCount = min(columns,peers.count-(index/4)*4)
        return MapPoint(x:(Double(index%4)-Double(rowCount-1)/2)*(size+6),y:unit.player ? 36+Double(index/4)*(size+10) : -42-Double(index/4)*(size+10))
    }
    @ViewBuilder private func unitButton(_ unit:PublicGameUnit,size:Double) -> some View {
        if unit.player, let onFocusUnit {
            Button { onFocusUnit(unit.id) } label: { pin(unit,size:size) }.buttonStyle(.plain)
                .accessibilityLabel("查看\(unit.name)所在地图位置")
        } else { pin(unit,size:size) }
    }
    private func pin(_ unit:PublicGameUnit,size:Double) -> some View {
        ZStack(alignment:.bottom) {
            Ellipse().fill(GameTheme.ink.opacity(0.16)).frame(width:size*0.75,height:8).offset(y:4)
            ArtImage(type:unit.player ? "classes" : "monsters",id:unit.templateID).frame(width:size,height:size)
                .opacity(unit.health == 0 ? 0.65 : 1)
            Text(identity(unit)).font(.system(size:publicDisplay ? 14 : 11,weight:.bold)).padding(.horizontal,5)
                .background(.white,in:Capsule()).offset(y:10)
            if unit.health == 0 { Image(systemName:"xmark").font(.system(size:22,weight:.heavy)).foregroundStyle(GameTheme.danger) }
            else if unit.canActFromRound > round && round > 0 { Image(systemName:"clock.fill").offset(x:size/3,y:-size/2) }
            if unit.current { Image(systemName:"arrowtriangle.down.fill").foregroundStyle(GameTheme.primary).offset(y:-size-2) }
        }.frame(width:max(44,size),height:max(44,size)).contentShape(Rectangle())
    }
    private func identity(_ unit:PublicGameUnit) -> String {
        if unit.host { return "主持" }
        let peers = units.filter { $0.player == unit.player }.sorted { $0.id < $1.id }
        return (unit.player ? "" : "敌")+String((peers.firstIndex { $0.id == unit.id } ?? 0)+1)
    }
    private func nodeContent(_ node:PublicGameNode,here:[PublicGameUnit],current:Bool) -> some View {
        ZStack {
            // Unknown selection precedes lookup: no hidden kind image is loaded.
            ArtImage(type:"nodeVisual",id:node.revealed ? (node.kind?.rawValue ?? "unknown") : "unknown")
            if !node.revealed { ArtImage(type:"visualLayer",id:"fog_unknown"); Text("?").font(.system(size:28,weight:.bold)) }
            if current { ArtImage(type:"visualLayer",id:"node_state_current") }
            if path.contains(node.id) { ArtImage(type:"visualLayer",id:"node_state_path") }
            if legalNodes.contains(node.id) { ArtImage(type:"visualLayer",id:"node_state_target") }
            if here.contains(where: { !$0.player && $0.health > 0 }) { ArtImage(type:"visualLayer",id:"node_state_enemy") }
            if node.claimed { ArtImage(type:"visualLayer",id:"node_state_claimed") }
            if here.count > 1 { ArtImage(type:"visualLayer",id:"node_state_crowded") }
        }.overlay(alignment:.top) {
            Text(node.name).font(.system(size:publicDisplay ? 22 : 13,weight:.semibold)).lineLimit(2)
                .multilineTextAlignment(.center).padding(3).background(.white.opacity(0.90),in:RoundedRectangle(cornerRadius:5))
                .frame(width:publicDisplay ? 154 : 110).offset(y:-36)
        }.accessibilityLabel(node.name)
    }
    private func point(_ node:PublicGameNode,size:CGSize) -> CGPoint {
        let p = camera.screen(MapPoint(x:node.x,y:node.y),width:Double(size.width),height:Double(size.height))
        return CGPoint(x:p.x,y:p.y)
    }
}
