// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TreadUpdater",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TreadUpdater", targets: ["TreadUpdater"]),
    ],
    targets: [
        .executableTarget(name: "TreadUpdater"),
        .testTarget(
            name: "TreadUpdaterTests",
            dependencies: ["TreadUpdater"],
            path: "tests/TreadUpdaterTests",
            resources: [.process("Fixtures")]
        ),
    ]
)
