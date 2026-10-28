// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMeter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexMeterCore", targets: ["CodexMeterCore"]),
        .executable(name: "CodexMeter", targets: ["CodexMeterApp"])
    ],
    targets: [
        .target(name: "CodexMeterCore"),
        .executableTarget(name: "CodexMeterApp", dependencies: ["CodexMeterCore"]),
        .testTarget(name: "CodexMeterCoreTests", dependencies: ["CodexMeterCore"])
    ],
    swiftLanguageModes: [.v5]
)
