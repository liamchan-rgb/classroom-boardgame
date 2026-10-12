// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClassroomProbeCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "ClassroomProbeCore", targets: ["ClassroomProbeCore"])],
    dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
    targets: [
        .target(name: "ClassroomProbeCore", dependencies: ["ZIPFoundation"]),
        .testTarget(name: "ClassroomProbeCoreTests", dependencies: ["ClassroomProbeCore"],
                    resources: [.copy("Fixtures")])
    ]
)
