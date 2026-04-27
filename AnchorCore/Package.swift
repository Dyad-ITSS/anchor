// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AnchorCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AnchorCore", targets: ["AnchorCore"]),
    ],
    targets: [
        .target(name: "AnchorCore", path: "Sources/AnchorCore"),
        .testTarget(name: "AnchorCoreTests", dependencies: ["AnchorCore"], path: "Tests/AnchorCoreTests"),
    ]
)
