// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Snipstep",
    platforms: [.macOS("15.2"), .iOS(.v18)],
    products: [.library(name: "SnipstepCore", targets: ["SnipstepCore"])],
    targets: [
        .target(name: "SnipstepCore"),
        .testTarget(name: "SnipstepCoreTests", dependencies: ["SnipstepCore"])
    ]
)
