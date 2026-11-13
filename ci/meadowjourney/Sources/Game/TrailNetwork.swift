import Foundation

/// Roads are shared by the renderer and shortest-route planner.
struct TrailNetwork {
    struct Edge {
        let from: Int
        let to: Int
        let trail: Trail
        let width: CGFloat
    }
    struct Projection {
        let edge: Int
        let distance: CGFloat
        let point: CGPoint
        let error: CGFloat
    }
    let edges: [Edge]
    let nodeCount: Int
    let patrol: Trail

    init(roads: [SceneDefinition.Road]) {
        edges = roads.map { Edge(from: $0.from, to: $0.to,
                                trail: Trail.smooth($0.points.map(\.point)), width: $0.width) }
        nodeCount = (edges.flatMap { [$0.from, $0.to] }.max() ?? 0) + 1
        let controls = edges[0].trail.points + Array(edges[1].trail.points.dropFirst())
        patrol = Trail(points: Array(controls))
    }

    func project(_ point: CGPoint) -> Projection {
        edges.indices.map { index in
            let distance = edges[index].trail.distance(nearestTo: point)
            let projected = edges[index].trail.point(at: distance)
            let dx = projected.x - point.x
            let dy = projected.y - point.y
            return Projection(edge: index, distance: distance, point: projected,
                              error: (dx * dx + dy * dy).squareRoot())
        }.min(by: { $0.error < $1.error })!
    }

    /// Add temporary start/end nodes to their road edges, then run Dijkstra.
    func route(from start: CGPoint, to end: CGPoint) -> Trail {
        let source = project(start)
        let target = project(end)
        let startID = nodeCount
        let endID = nodeCount + 1
        struct Link {
            let to: Int
            let points: [CGPoint]
            let cost: CGFloat
        }
        var links = Array(repeating: [Link](), count: nodeCount + 2)
        func connect(_ from: Int, _ to: Int, _ points: [CGPoint]) {
            let cost = Trail(points: points).length
            links[from].append(Link(to: to, points: points, cost: cost))
            links[to].append(Link(to: from, points: Array(points.reversed()), cost: cost))
        }
        for edge in edges { connect(edge.from, edge.to, edge.trail.points) }
        for (id, projection) in [(startID, source), (endID, target)] {
            let edge = edges[projection.edge]
            connect(id, edge.from, edge.trail.subsection(from: projection.distance, to: 0))
            connect(id, edge.to, edge.trail.subsection(from: projection.distance, to: edge.trail.length))
        }
        if source.edge == target.edge {
            connect(startID, endID, edges[source.edge].trail.subsection(from: source.distance, to: target.distance))
        }
        var costs = Array(repeating: CGFloat.greatestFiniteMagnitude, count: links.count)
        var previous: [(Int, [CGPoint])?] = Array(repeating: nil, count: links.count)
        var visited = Set<Int>()
        costs[startID] = 0
        while let current = links.indices.filter({ !visited.contains($0) }).min(by: { costs[$0] < costs[$1] }) {
            if current == endID || costs[current] == .greatestFiniteMagnitude { break }
            visited.insert(current)
            for link in links[current] where costs[current] + link.cost < costs[link.to] {
                costs[link.to] = costs[current] + link.cost
                previous[link.to] = (current, link.points)
            }
        }
        var pieces: [[CGPoint]] = []
        var current = endID
        while current != startID, let item = previous[current] {
            pieces.append(item.1)
            current = item.0
        }
        precondition(current == startID, "Disconnected road network")
        var points = [source.point]
        for piece in pieces.reversed() { points.append(contentsOf: piece.dropFirst()) }
        if points.count < 2 { points.append(target.point) }
        return Trail(points: points)
    }
}
