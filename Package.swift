// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MediaPlayerKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
        .tvOS(.v14),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "MediaPlayerKit",
            targets: ["MediaPlayerKit"]
        ),
    ],
    dependencies: [
        // 依赖 KSPlayer 稳定版本 (tag 2.3.4 或更高)
        .package(url: "https://github.com/kingslay/KSPlayer.git", from: "2.3.4"),
    ],
    targets: [
        .target(
            name: "MediaPlayerKit",
            dependencies: [
                .product(name: "KSPlayer", package: "KSPlayer"),
            ],
            path: "Sources/MediaPlayerKit",
            resources: [
                .process("Rendering/Shaders.metal")
            ],
            swiftSettings: [
                .define("ENABLE_METAL_RENDER"),
                .define("ENABLE_HARDWARE_ACCELERATION")
            ]
        ),
        .testTarget(
            name: "MediaPlayerKitTests",
            dependencies: ["MediaPlayerKit"],
            path: "Tests/MediaPlayerKitTests"
        ),
    ]
)
