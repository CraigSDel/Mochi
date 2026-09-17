// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalAIController",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LocalAIController", targets: ["LocalAIController"])],
    targets: [
        .executableTarget(name: "LocalAIController"),
        .testTarget(name: "LocalAIControllerTests", dependencies: ["LocalAIController"])
    ]
)
