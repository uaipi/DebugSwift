// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DebugSwift",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DebugSwift",
            targets: ["DebugSwift"]
        ),
        .library(
            name: "DebugSwiftCore",
            targets: ["DebugSwiftCore"]
        ),
        .library(
            name: "DebugSwiftUI",
            type: .dynamic,
            targets: ["DebugSwiftUI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.11"),
        .package(url: "https://source.skip.tools/skip-fuse.git", from: "1.0.0"),
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0")
    ],
    targets: [
        // Foundation-only, no UIKit: compiles natively for iOS and Android (Skip Fuse).
        .target(
            name: "DebugSwiftCore",
            path: "DebugSwiftCore/Sources/DebugSwiftCore"
        ),
        // Native Skip Fuse SwiftUI: one debug panel for iOS and Android.
        .target(
            name: "DebugSwiftUI",
            dependencies: [
                "DebugSwiftCore",
                .product(name: "SkipFuse", package: "skip-fuse"),
                .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
                .target(name: "DebugSwift", condition: .when(platforms: [.iOS]))
            ],
            path: "DebugSwiftUI/Sources/DebugSwiftUI",
            plugins: [
                .plugin(name: "skipstone", package: "skip")
            ]
        ),
        .testTarget(
            name: "DebugSwiftCoreTests",
            dependencies: ["DebugSwiftCore"],
            path: "DebugSwiftCore/Tests/DebugSwiftCoreTests"
        ),
        .target(
            name: "DebugSwift",
            dependencies: ["DebugSwiftCore"],
            path: "DebugSwift",
            resources: [
                .process("Resources")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
