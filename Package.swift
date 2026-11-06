// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SoeYaku",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SoeYakuCore", targets: ["SoeYakuCore"]),
        .executable(name: "SoeYaku", targets: ["SoeYakuApp"]),
        .executable(name: "soeyaku-cli", targets: ["SoeYakuCLI"])
    ],
    targets: [
        .target(name: "SoeYakuCore"),
        .target(name: "SoeYakuVision", dependencies: ["SoeYakuCore"]),
        .target(name: "SoeYakuRuntime"),
        .target(name: "SoeYakuCLIKit", dependencies: ["SoeYakuCore", "SoeYakuVision"]),
        .executableTarget(name: "SoeYakuCLI", dependencies: ["SoeYakuCLIKit"]),
        .executableTarget(name: "SoeYakuApp", dependencies: ["SoeYakuCore", "SoeYakuVision", "SoeYakuRuntime"]),
        .target(name: "SoeYakuTestSupport", path: "Tests/SoeYakuTestSupport"),
        .testTarget(name: "SoeYakuCoreTests", dependencies: ["SoeYakuCore", "SoeYakuTestSupport"]),
        .testTarget(name: "SoeYakuVisionTests", dependencies: ["SoeYakuVision", "SoeYakuCore", "SoeYakuTestSupport"]),
        .testTarget(name: "SoeYakuCLIKitTests", dependencies: ["SoeYakuCLIKit", "SoeYakuCore", "SoeYakuTestSupport"]),
        .testTarget(name: "SoeYakuRuntimeTests", dependencies: ["SoeYakuRuntime"]),
        .testTarget(name: "SoeYakuAppTests", dependencies: ["SoeYakuApp", "SoeYakuCore"])
    ]
)
