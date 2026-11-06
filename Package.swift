// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SoeYaku",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SoeYakuCore", targets: ["SoeYakuCore"])
    ],
    targets: [
        .target(name: "SoeYakuCore"),
        .target(name: "SoeYakuRuntime"),
        .testTarget(name: "SoeYakuCoreTests", dependencies: ["SoeYakuCore"]),
        .testTarget(name: "SoeYakuRuntimeTests", dependencies: ["SoeYakuRuntime"])
    ]
)
