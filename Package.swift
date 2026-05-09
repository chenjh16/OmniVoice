// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OmniVoice",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OmniVoice", targets: ["OmniVoiceApp"]),
        .executable(name: "OmniVoiceE2E", targets: ["OmniVoiceE2EApp"]),
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
                .linkedFramework("Security"),
                .linkedFramework("Speech")
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
                "OmniVoiceCore"
            ]
        ),
        .executableTarget(
            name: "OmniVoiceE2EApp",
            dependencies: [
                "OmniVoiceCore",
                "OmniVoiceE2ESupport"
            ]
        ),
        .testTarget(
            name: "OmniVoiceCoreTests",
            dependencies: [
                "OmniVoiceCore"
            ]
        ),
        .testTarget(
            name: "OmniVoiceE2ESupportTests",
            dependencies: [
                "OmniVoiceCore",
                "OmniVoiceE2ESupport"
            ]
        )
    ]
)
