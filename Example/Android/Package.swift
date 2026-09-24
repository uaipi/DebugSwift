// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import PackageDescription

let package = Package(
    name: "debugswift-android",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "DebugSwiftAndroidSample", type: .dynamic, targets: ["DebugSwiftAndroidSample"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.11"),
        .package(url: "https://github.com/skiptools/skip-ui.git", from: "1.60.0"),
        .package(name: "DebugSwiftAndroid", path: "../../DebugSwiftAndroid")
    ],
    targets: [
        .target(name: "DebugSwiftAndroidSample", dependencies: [
            .product(name: "DebugSwiftAndroid", package: "DebugSwiftAndroid"),
            .product(name: "SkipUI", package: "skip-ui")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
