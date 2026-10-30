// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Taskglass",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Taskglass", targets: ["Taskglass"])],
    targets: [
        .target(name: "SystemProbe", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .executableTarget(name: "Taskglass", dependencies: ["SystemProbe"])
    ]
)
