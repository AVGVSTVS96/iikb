// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KeyboardAndroid",
    products: [.library(name: "iikb", type: .dynamic, targets: ["KeyboardAndroid"])],
    dependencies: [.package(path: "../Packages/KeyboardModules")],
    targets: [
        .systemLibrary(name: "CJNI"),
        .target(
            name: "KeyboardAndroid",
            dependencies: ["CJNI", .product(name: "KeyboardCore", package: "KeyboardModules")],
            swiftSettings: [.treatAllWarnings(as: .error)],
            // The static Swift runtime calls into libdispatch, which --static-swift-stdlib doesn't link by itself.
            linkerSettings: [.linkedLibrary("dispatch"), .linkedLibrary("BlocksRuntime")]
        ),
    ]
)
