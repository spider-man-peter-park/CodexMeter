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
        .executableTarget(name: "CodexMeterApp", dependencies: ["CodexMeterCore"],
                          resources: [.process("Resources")]),
        .testTarget(name: "CodexMeterCoreTests", dependencies: ["CodexMeterCore"]),
        .testTarget(name: "CodexMeterAppTests", dependencies: ["CodexMeterApp", "CodexMeterCore"])
    ],
    swiftLanguageModes: [.v5]
)
