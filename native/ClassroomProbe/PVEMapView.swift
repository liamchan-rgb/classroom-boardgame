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
    var body:some View {
        GeometryReader { geometry in
            let width = Double(geometry.size.width), height = Double(geometry.size.height)
            let marginX = min(64.0,width*0.13), marginY = min(88.0,height*0.20)
            let labelSize = publicDisplay ? 24.0 : 16.0
            let artSize = publicDisplay ? 112.0 : 96.0
            ZStack {
                ArtImage(type:"visualLayer",id:width/height > 1.5 ? "map_ground_1920" : "map_ground_1440").aspectRatio(contentMode:.fill).frame(width:width,height:height).clipped()
                ArtImage(type:"visualLayer",id:width/height > 1.5 ? "map_decoration_1920" : "map_decoration_1440").aspectRatio(contentMode:.fill).frame(width:width,height:height).clipped()
                Canvas { context,size in
                    let byID = Dictionary(uniqueKeysWithValues:nodes.map { ($0.id,$0) })
                    for road in roads {
                        guard let a = byID[road.a], let b = byID[road.b] else { continue }
                        var line = Path(); line.move(to:point(a,size:size,marginX:marginX,marginY:marginY)); line.addLine(to:point(b,size:size,marginX:marginX,marginY:marginY))
                        context.stroke(line,with:.color(GameTheme.primary.opacity(0.28)),style:StrokeStyle(lineWidth:6,lineCap:.round))
                        let selected = path.indices.dropFirst().contains { index in Set([path[index-1],path[index]]) == Set([road.a,road.b]) }
                        if selected {
                            context.stroke(line,with:.color(planAllowed ? GameTheme.accent : GameTheme.danger),style:StrokeStyle(lineWidth:3,lineCap:.round,dash:[8,6]))
                        }
                    }
                }
                ForEach(nodes) { node in
                    let here = units.filter { $0.nodeID == node.id }
                    let current = here.contains { $0.current } || actorNode == node.id
                    Group {
                        if interactive {
                            Button { onNode?(node.id) } label: { nodeContent(node,here:here,current:current,artSize:artSize,labelSize:labelSize) }.buttonStyle(.plain)
                        } else { nodeContent(node,here:here,current:current,artSize:artSize,labelSize:labelSize) }
                    }.frame(width:publicDisplay ? 144 : 126,minHeight:44)
                        .position(point(node,size:geometry.size,marginX:marginX,marginY:marginY))
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius:16))
    }
    private func nodeContent(_ node:PublicGameNode,here:[PublicGameUnit],current:Bool,artSize:Double,labelSize:Double) -> some View {
        VStack(spacing:0) {
            ZStack {
                // Select unknown BEFORE image lookup; hidden kind images never enter this view.
                ArtImage(type:"nodeVisual",id:node.revealed ? (node.kind?.rawValue ?? "unknown") : "unknown")
                if !node.revealed {
                    ArtImage(type:"visualLayer",id:"fog_unknown")
                    Text("?").font(.system(size:30,weight:.bold))
                }
                if current { ArtImage(type:"visualLayer",id:"node_state_current") }
                if path.contains(node.id) { ArtImage(type:"visualLayer",id:"node_state_path") }
                if legalNodes.contains(node.id) { ArtImage(type:"visualLayer",id:"node_state_target") }
                if here.contains(where: { !$0.player && $0.health > 0 }) { ArtImage(type:"visualLayer",id:"node_state_enemy") }
                if node.claimed { ArtImage(type:"visualLayer",id:"node_state_claimed") }
                if here.count > 1 { ArtImage(type:"visualLayer",id:"node_state_crowded") }
                Text(node.revealed ? String(node.id) : "").font(.system(size:labelSize,weight:.bold)).padding(4).background(.white.opacity(0.9),in:Circle()).offset(y:artSize*0.30)
            }.frame(width:artSize,height:artSize)
            Text(node.name).font(.system(size:labelSize,weight:.semibold)).lineLimit(2).multilineTextAlignment(.center)
            if !here.isEmpty {
                Text("角色\(here.filter(\.player).count) · 敌\(here.filter { !$0.player }.count)").font(.system(size:publicDisplay ? 24 : 13)).foregroundStyle(GameTheme.muted)
            }
        }.foregroundStyle(GameTheme.ink).accessibilityElement(children:.combine)
    }
    private func point(_ node:PublicGameNode,size:CGSize,marginX:Double,marginY:Double) -> CGPoint {
        CGPoint(x:marginX + node.x*max(0,Double(size.width)-marginX*2),y:marginY + node.y*max(0,Double(size.height)-marginY*2))
    }
}
