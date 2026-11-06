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
        .testTarget(name: "SoeYakuCoreTests", dependencies: ["SoeYakuCore"]),
        .testTarget(name: "SoeYakuVisionTests", dependencies: ["SoeYakuVision", "SoeYakuCore"]),
        .testTarget(name: "SoeYakuRuntimeTests", dependencies: ["SoeYakuRuntime"])
    ]
)
