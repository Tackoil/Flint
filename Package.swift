// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlintCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "FlintCore", targets: ["FlintCore"])],
    targets: [
        .target(name: "FlintCore"),
        .testTarget(name: "FlintCoreTests", dependencies: ["FlintCore"])
    ]
)
