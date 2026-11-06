// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SoeYaku",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SoeYakuCore", targets: ["SoeYakuCore"]),
        .executable(name: "SoeYaku", targets: ["SoeYakuApp"])
    ],
    targets: [
        .target(name: "SoeYakuCore"),
        .target(name: "SoeYakuVision", dependencies: ["SoeYakuCore"]),
        .target(name: "SoeYakuRuntime"),
        .executableTarget(name: "SoeYakuApp", dependencies: ["SoeYakuCore", "SoeYakuVision", "SoeYakuRuntime"]),
        .target(name: "SoeYakuTestSupport", path: "Tests/SoeYakuTestSupport"),
        .testTarget(name: "SoeYakuCoreTests", dependencies: ["SoeYakuCore", "SoeYakuTestSupport"]),
        .testTarget(name: "SoeYakuVisionTests", dependencies: ["SoeYakuVision", "SoeYakuCore", "SoeYakuTestSupport"]),
        .testTarget(name: "SoeYakuRuntimeTests", dependencies: ["SoeYakuRuntime"])
    ]
)
