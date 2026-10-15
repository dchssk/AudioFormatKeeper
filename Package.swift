// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AudioFormatKeeper",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AudioFormatKeeper", targets: ["AudioFormatKeeper"])
    ],
    targets: [
        .executableTarget(
            name: "AudioFormatKeeper",
            path: "AppSources",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio")
            ]
        ),
        .testTarget(
            name: "AudioFormatKeeperTests",
            dependencies: ["AudioFormatKeeper"],
            path: "Tests"
        )
    ],
    swiftLanguageModes: [.v5]
)
