// swift-tools-version: 5.7
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "ClassroomDisplayProbe",
    platforms: [.iOS("16.0")],
    products: [
        .iOSApplication(
            name: "课堂双画面验证 v0.4",
            targets: ["AppModule"],
            bundleIdentifier: "local.classroom.stage0.displayprobe.v04",
            displayVersion: "0.4",
            bundleVersion: "4",
            appIcon: .placeholder(icon: .star),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [.pad],
            supportedInterfaceOrientations: [.landscapeLeft, .landscapeRight]
        )
    ],
    targets: [.executableTarget(name: "AppModule", path: "Sources/AppModule")],
    swiftLanguageVersions: [.v5]
)
