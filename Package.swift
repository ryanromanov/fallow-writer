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
        // The iPhone and iPad app's interface, for the app in iOS/ and builds that add packs.
        .library(name: "FallowTouch", targets: ["FallowTouch"]),
    ],
    targets: [
        // Scenes, sounds, packs and settings: everything that isn't the Mac's own interface.
        .target(name: "FallowCore"),
        // The Mac app: everything but the entry point, so tests can import it.
        .target(name: "FallowKit", dependencies: ["FallowCore"]),
        .executableTarget(name: "Fallow", dependencies: ["FallowKit"]),
        // The iPhone and iPad interface. Its files are iOS-only, so on the Mac it builds empty.
        .target(name: "FallowTouch", dependencies: ["FallowCore"]),
        .testTarget(name: "FallowKitTests", dependencies: ["FallowKit", "FallowCore"]),
        // The iPhone and iPad interface's tests, run on an iOS simulator (scripts/test-ios.sh).
        .testTarget(name: "FallowTouchTests", dependencies: ["FallowTouch"]),
    ]
)
