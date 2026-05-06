// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OmniVoice",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OmniVoice", targets: ["OmniVoiceApp"]),
        .library(name: "OmniVoiceCore", targets: ["OmniVoiceCore"])
    ],
    targets: [
        .target(
            name: "OmniVoiceCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Security")
            ]
        ),
        .target(
            name: "OmniVoiceE2ESupport",
            dependencies: ["OmniVoiceCore"],
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "OmniVoiceApp",
            dependencies: [
                "OmniVoiceCore",
                "OmniVoiceE2ESupport"
            ]
        ),
        .testTarget(
            name: "OmniVoiceCoreTests",
            dependencies: [
                "OmniVoiceCore",
                "OmniVoiceE2ESupport"
            ]
        )
    ]
)
