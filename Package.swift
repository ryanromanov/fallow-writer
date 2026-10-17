// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Fallow",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Fallow", targets: ["Fallow"]),
        // For builds that add packs of their own on top of Fallow.
        .library(name: "FallowKit", targets: ["FallowKit"]),
    ],
    targets: [
        // Everything but the entry point lives in FallowKit so tests can import it.
        .target(name: "FallowKit"),
        .executableTarget(name: "Fallow", dependencies: ["FallowKit"]),
        .testTarget(name: "FallowKitTests", dependencies: ["FallowKit"]),
    ]
)
