// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClassroomGameCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "ClassroomGameCore", targets: ["ClassroomGameCore"])],
    targets: [
        .target(name: "ClassroomGameCore", resources: [.process("Resources")]),
        .testTarget(name: "ClassroomGameCoreTests", dependencies: ["ClassroomGameCore"])
    ]
)
