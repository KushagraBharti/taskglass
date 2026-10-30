// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Taskglass",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Taskglass", targets: ["Taskglass"])],
    targets: [
        .target(name: "SystemProbe"),
        .executableTarget(name: "Taskglass", dependencies: ["SystemProbe"])
    ]
)
