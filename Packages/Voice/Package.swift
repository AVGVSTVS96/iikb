// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "Voice",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "VoiceCapture", targets: ["VoiceCapture"]),
        .library(name: "VoiceModels", targets: ["VoiceModels"]),
    ],
    dependencies: [
        .package(path: "../KeyboardModules"),
        // 0.18.3 wrote more words wrong on his dictations (scripts/voiceloop, Nov 8: 3.39% → 3.45%), mostly filler he
        // never said ("Mm", "Thank you.") put before the first word.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0", traits: []),
    ],
    targets: [
        .target(
            name: "VoiceCapture", dependencies: [.product(name: "KeyboardStore", package: "KeyboardModules")],
            exclude: ["AGENTS.md"], swiftSettings: settings),
        .target(
            name: "VoiceModels",
            dependencies: [
                "VoiceCapture", .product(name: "KeyboardStore", package: "KeyboardModules"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            exclude: ["AGENTS.md"], swiftSettings: settings),
    ]
)
