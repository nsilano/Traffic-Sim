// swift-tools-version:5.9
// GridlockCore: the game's rules and traffic simulation in plain Swift, with no UI,
// so it builds and tests anywhere (GitHub runs `swift test` on every change to core/).
import PackageDescription

let package = Package(
    name: "GridlockCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "GridlockCore", targets: ["GridlockCore"]),
        .library(name: "GridlockRender", targets: ["GridlockRender"]),
    ],
    targets: [
        .target(name: "GridlockCore", resources: [.copy("Resources/levels.json")]),
        // Drawing the board with Core Graphics (Apple platforms).
        .target(name: "GridlockRender", dependencies: ["GridlockCore"], resources: [.copy("Resources/Fonts")]),
        .testTarget(name: "GridlockCoreTests", dependencies: ["GridlockCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "GridlockRenderTests", dependencies: ["GridlockCore", "GridlockRender"]),
    ]
)
