// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "DebugSwiftAndroid",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DebugSwiftAndroid",
            type: .dynamic,
            targets: ["DebugSwiftAndroid"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.11"),
        .package(url: "https://github.com/skiptools/skip-ui.git", from: "1.60.0"),
        .package(name: "DebugSwift", path: "..")
    ],
    targets: [
        .target(
            name: "DebugSwiftAndroid",
            dependencies: [
                .product(name: "SkipUI", package: "skip-ui"),
                .product(name: "DebugSwift", package: "DebugSwift", condition: .when(platforms: [.iOS]))
            ],
            path: "Sources/DebugSwiftAndroid",
            plugins: [
                .plugin(name: "skipstone", package: "skip")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
