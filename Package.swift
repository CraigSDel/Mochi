// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mochi",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Mochi", targets: ["Mochi"])],
    targets: [
        .executableTarget(name: "Mochi"),
        .testTarget(name: "MochiTests", dependencies: ["Mochi"])
    ]
)
