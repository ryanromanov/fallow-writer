// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Fallow",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .executable(name: "Fallow", targets: ["Fallow"]),
        // For builds that add packs of their own on top of Fallow.
        .library(name: "FallowKit", targets: ["FallowKit"]),
        // The scenes, sounds and settings that don't depend on the Mac.
        .library(name: "FallowCore", targets: ["FallowCore"]),
    ],
    targets: [
        // Scenes, sounds, packs and settings: everything that isn't the Mac's own interface.
        .target(name: "FallowCore"),
        // The Mac app: everything but the entry point, so tests can import it.
        .target(name: "FallowKit", dependencies: ["FallowCore"]),
        .executableTarget(name: "Fallow", dependencies: ["FallowKit"]),
        .testTarget(name: "FallowKitTests", dependencies: ["FallowKit", "FallowCore"]),
    ]
)
