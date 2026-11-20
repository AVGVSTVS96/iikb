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
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.3", traits: []),
    ],
    targets: [
        .target(
            name: "VoiceCapture",
            dependencies: [.product(name: "KeyboardStore", package: "KeyboardModules")],
            exclude: ["AGENTS.md"], swiftSettings: settings),
        .target(
            name: "VoiceModels",
            dependencies: [
                "VoiceCapture", "VoiceEditor", .product(name: "KeyboardStore", package: "KeyboardModules"),
                .product(name: "VoiceCore", package: "KeyboardModules"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            exclude: ["AGENTS.md"], swiftSettings: settings),
        .target(
            name: "VoiceEditor", dependencies: ["llama"], exclude: ["AGENTS.md"],
            swiftSettings: [.treatAllWarnings(as: .error)]),
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b10400/llama-b10400-xcframework.zip",
            checksum: "ba83d0e9893c76bac0d001aa3e67bb4ca0aedf1e3dec53a1afa97291818bc69b"),
    ]
)
