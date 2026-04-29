// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PromptMinifierKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "PromptMinifierKit",
            targets: ["PromptMinifierKit"]
        ),
    ],
    targets: [
        .target(
            name: "PromptMinifierKit",
            path: "Sources/PromptMinifierKit"
        ),
        .testTarget(
            name: "PromptMinifierKitTests",
            dependencies: ["PromptMinifierKit"],
            path: "Tests/PromptMinifierKitTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
