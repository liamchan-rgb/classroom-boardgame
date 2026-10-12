import SwiftUI
import ClassroomGameCore

struct PVEMapView:View {
    let nodes:[PublicGameNode]
    let roads:[MapRoad]
    let units:[PublicGameUnit]
    var path:[Int] = []
    var interactive = false
    var onNode:((Int)->Void)?
    var body:some View {
        GeometryReader { geometry in
            let width = Double(geometry.size.width)
            let height = Double(geometry.size.height)
            let marginX = min(84.0,width * 0.15)
            let marginY = min(80.0,height * 0.20)
            let labelSize = min(24.0,max(14.0,width/40))
            ZStack {
                Canvas { context,size in
                    let byID = Dictionary(uniqueKeysWithValues:nodes.map { ($0.id,$0) })
                    for road in roads {
                        guard let a = byID[road.a], let b = byID[road.b] else { continue }
                        var line = Path()
                        line.move(to:point(a,size:size,marginX:marginX,marginY:marginY))
                        line.addLine(to:point(b,size:size,marginX:marginX,marginY:marginY))
                        let selected = path.indices.dropFirst().contains { index in (path[index-1] == road.a && path[index] == road.b) || (path[index-1] == road.b && path[index] == road.a) }
                        context.stroke(line,with:.color(selected ? GameTheme.accent : GameTheme.primary.opacity(0.22)),style:StrokeStyle(lineWidth:selected ? 6 : 4,lineCap:.round))
                    }
                }
                ForEach(nodes) { node in
                    let here = units.filter { $0.nodeID == node.id && $0.health > 0 }
                    let current = here.contains { $0.current }
                    Button { onNode?(node.id) } label: {
                        VStack(spacing:5) {
                            Image(systemName:nodeIcon(node.kind))
                                .font(.system(size:labelSize+6,weight:.semibold))
                                .foregroundStyle(node.revealed ? GameTheme.primary : GameTheme.muted)
                                .frame(width:58,height:58)
                                .background(node.revealed ? Color.white : GameTheme.background,in:Circle())
                                .overlay(Circle().stroke(current || path.contains(node.id) ? GameTheme.accent : GameTheme.primary.opacity(0.3),lineWidth:current || path.contains(node.id) ? 4 : 2))
                            Text(node.name).font(.system(size:labelSize,weight:.semibold)).lineLimit(2).multilineTextAlignment(.center)
                            if !here.isEmpty {
                                Text("玩家\(here.filter(\.player).count) · 敌人\(here.filter { !$0.player }.count)")
                                    .font(.system(size:max(12,labelSize-3))).foregroundStyle(GameTheme.muted)
                            }
                        }.frame(width:min(154,width/3)).foregroundStyle(GameTheme.ink)
                    }.buttonStyle(.plain).disabled(!interactive)
                        .position(point(node,size:geometry.size,marginX:marginX,marginY:marginY))
                }
            }
        }.background(GameTheme.background.opacity(0.65),in:RoundedRectangle(cornerRadius:16))
    }
    private func point(_ node:PublicGameNode,size:CGSize,marginX:Double,marginY:Double) -> CGPoint {
        CGPoint(x:marginX + node.x * max(0,Double(size.width)-marginX*2),y:marginY + node.y * max(0,Double(size.height)-marginY*2))
    }
}
