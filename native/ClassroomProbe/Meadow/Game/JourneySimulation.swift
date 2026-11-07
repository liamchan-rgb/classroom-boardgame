import Foundation

struct JourneySimulation {
    static let movementSpeedMultiplier: CGFloat = 3
    static func speed(for index:Int)->CGFloat { (index==0 ? HeroFrames.reviewSpeed:index==1 ? 38:45)*movementSpeedMultiplier }
    enum Mode { case patrol, destination }
    let network: TrailNetwork
    private let spawn: CGPoint?
    private(set) var travelers: [Traveler] = []
    private(set) var routes: [Trail] = []
    private(set) var isPlaying = false
    private(set) var userPaused = false
    private(set) var mode = Mode.patrol
    var selected = 0

    init(network: TrailNetwork, spawn: CGPoint? = nil) {
        self.network = network
        self.spawn = spawn
        reset()
    }

    func point(for index: Int) -> CGPoint { routes[index].point(at: travelers[index].distance) }

    func heading(for index: Int) -> CGPoint {
        let traveler = travelers[index], trail = routes[index]
        let here = point(for: index)
        let ahead = trail.point(at: max(0, min(trail.length, traveler.distance + traveler.direction)))
        return CGPoint(x: ahead.x - here.x, y: ahead.y - here.y)
    }

    mutating func reset() {
        routes = Array(repeating: network.patrol, count: 3)
        travelers = [
            Traveler(distance: network.patrol.distance(nearestTo: CGPoint(x: 440, y: 444)), direction: 1, speed: Self.speed(for:0)),
            Traveler(distance: network.patrol.length, direction: -1, speed: Self.speed(for:1)),
            Traveler(distance: network.patrol.distance(nearestTo: CGPoint(x: 560, y: 441)), direction: 1, speed: Self.speed(for:2))
        ]
        if let spawn {
            let start = network.patrol.distance(nearestTo: spawn)
            for i in travelers.indices { travelers[i].distance = min(network.patrol.length, start + CGFloat(i)*30); travelers[i].direction = 1 }
        }
        isPlaying = false
        userPaused = false
        mode = .patrol
        selected = 0
    }

    mutating func togglePlayback() {
        if isPlaying {
            isPlaying = false
            userPaused = true
        } else {
            // Start a new patrol only when the previous explicit journey has finished.
            if mode == .destination && travelers.allSatisfy(\.isWaiting) {
                let positions = travelers.indices.map { point(for: $0) }
                for index in travelers.indices {
                    let approach = network.route(from: positions[index], to: network.patrol.points.first!)
                    routes[index] = Trail(points: approach.points + Array(network.patrol.points.dropFirst()))
                    travelers[index].distance = 0
                    travelers[index].direction = 1
                    travelers[index].destination = nil
                    travelers[index].isWaiting = false
                }
                mode = .patrol
            }
            isPlaying = true
            userPaused = false
        }
    }

    mutating func orderSelected(to destination: CGPoint) {
        let route = network.route(from: point(for: selected), to: destination)
        for index in travelers.indices { travelers[index].isWaiting = true }
        routes[selected] = route
        travelers[selected].distance = 0
        travelers[selected].direction = 1
        travelers[selected].destination = route.length
        travelers[selected].isWaiting = route.length < 0.5
        mode = .destination
        if !userPaused { isPlaying = !travelers[selected].isWaiting }
    }

    mutating func advance(_ seconds: TimeInterval, p1CanTravel: Bool = true) {
        guard isPlaying else { return }
        for index in travelers.indices {
            if index == 0 && !p1CanTravel { continue }
            let trail = routes[index], traveler = travelers[index]
            let here = trail.point(at: traveler.distance)
            let ahead = trail.point(at: max(0, min(trail.length, traveler.distance + traveler.direction * 1)))
            let projection = WalkCycle.projectedScale(dx: ahead.x - here.x, dy: ahead.y - here.y)
            travelers[index].advance(by: seconds * Double(projection), on: trail)
        }
        if mode == .destination && travelers.allSatisfy(\.isWaiting) { isPlaying = false }
    }
}
