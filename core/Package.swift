// swift-tools-version:5.9
// GridlockCore: the game's rules and traffic simulation in plain Swift, with no UI,
// so it builds and tests anywhere (GitHub runs `swift test` on every change to core/).
import PackageDescription

let package = Package(
    name: "GridlockCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "GridlockCore", targets: ["GridlockCore"])],
    targets: [
        .target(name: "GridlockCore", resources: [.copy("Resources/levels.json")]),
        .testTarget(name: "GridlockCoreTests", dependencies: ["GridlockCore"], resources: [.copy("Fixtures")]),
    ]
)
