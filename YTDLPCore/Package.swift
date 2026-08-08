// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YTDLPCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "YTDLPCore", targets: ["YTDLPCore"])],
    targets: [
        .target(name: "YTDLPCore"),
        .testTarget(
            name: "YTDLPCoreTests",
            dependencies: ["YTDLPCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
