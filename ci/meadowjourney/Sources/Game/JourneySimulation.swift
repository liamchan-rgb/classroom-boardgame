import Foundation

struct JourneySimulation {
    enum Mode { case patrol, destination }
    let network: TrailNetwork
    private(set) var travelers: [Traveler] = []
    private(set) var routes: [Trail] = []
    private(set) var isPlaying = false
    private(set) var userPaused = false
    private(set) var mode = Mode.patrol
    var selected = 0

    init(network: TrailNetwork) {
        self.network = network
        reset()
    }

    func point(for index: Int) -> CGPoint { routes[index].point(at: travelers[index].distance) }

    mutating func reset() {
        routes = Array(repeating: network.patrol, count: 3)
        travelers = [
            Traveler(distance: network.patrol.distance(nearestTo: CGPoint(x: 440, y: 444)), direction: 1, speed: 42),
            Traveler(distance: network.patrol.length, direction: -1, speed: 38),
            Traveler(distance: network.patrol.distance(nearestTo: CGPoint(x: 560, y: 441)), direction: 1, speed: 45)
        ]
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

    mutating func advance(_ seconds: TimeInterval) {
        guard isPlaying else { return }
        for index in travelers.indices { travelers[index].advance(by: seconds, on: routes[index]) }
        if mode == .destination && travelers.allSatisfy(\.isWaiting) { isPlaying = false }
    }
}
