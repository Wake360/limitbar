// swift-tools-version: 6.0
import PackageDescription

let testingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"

let package = Package(
    name: "limitbar",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "limitbar", path: "Sources/limitbar", resources: [.copy("Resources")]),
        .testTarget(
            name: "limitbarTests",
            dependencies: ["limitbar"],
            path: "Tests/limitbarTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.unsafeFlags(["-plugin-path", testingPlugins])]
        ),
    ]
)
