// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnapLater",
    platforms: [.macOS("15.2"), .iOS(.v18)],
    products: [.library(name: "SnapLaterCore", targets: ["SnapLaterCore"])],
    targets: [
        .target(name: "SnapLaterCore"),
        .testTarget(name: "SnapLaterCoreTests", dependencies: ["SnapLaterCore"])
    ]
)
