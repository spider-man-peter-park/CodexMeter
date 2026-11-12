// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMeter",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexMeterCore", targets: ["CodexMeterCore"]),
        .executable(name: "CodexMeter", targets: ["CodexMeterApp"]),
        .library(name: "OrbMotionKit", targets: ["OrbMotionKit"]),
        .library(name: "ProjectionMotionKit", targets: ["ProjectionMotionKit"]),
        .executable(name: "OrbMotionPlayground", targets: ["OrbMotionPlayground"])
    ],
    targets: [
        .target(name: "CodexMeterCore", resources: [.process("Resources")]),
        .executableTarget(name: "CodexMeterApp", dependencies: ["CodexMeterCore", "ProjectionMotionKit", "OrbMotionKit", "PlaygroundLocalization"],
                          resources: [.process("Resources")]),
        .target(name: "PlaygroundLocalization"),
        .target(name: "OrbMotionKit", dependencies: ["PlaygroundLocalization"]),
        .target(name: "ProjectionMotionKit", dependencies: ["OrbMotionKit", "PlaygroundLocalization"]),
        .executableTarget(name: "OrbMotionPlayground", dependencies: ["OrbMotionKit", "ProjectionMotionKit", "PlaygroundLocalization"]),
        .testTarget(name: "PlaygroundLocalizationTests", dependencies: ["PlaygroundLocalization"]),
        .testTarget(name: "PlaygroundAppTests", dependencies: ["OrbMotionPlayground", "PlaygroundLocalization", "OrbMotionKit", "ProjectionMotionKit"]),
        .testTarget(name: "OrbMotionKitTests", dependencies: ["OrbMotionKit"]),
        .testTarget(name: "ProjectionMotionKitTests", dependencies: ["ProjectionMotionKit", "OrbMotionKit"]),
        .testTarget(name: "CodexMeterCoreTests", dependencies: ["CodexMeterCore"]),
        .testTarget(name: "CodexMeterAppTests", dependencies: ["CodexMeterApp", "CodexMeterCore"])
    ],
    swiftLanguageModes: [.v5]
)
