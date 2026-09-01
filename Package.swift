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
        // 直接远程依赖官方 KSPlayer 稳定版本，零源码侵入，免维护享受官方更新
        .package(url: "https://github.com/kingslay/KSPlayer.git", from: "2.5.0"),
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
