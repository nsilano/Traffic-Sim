import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
import GridlockCore
@testable import GridlockRender

/// Renders every level mid-shift (same seed and scripted player as the simulation test)
/// to PNGs, for comparing with the JavaScript game by eye. On CI they're uploaded as the
/// "board-snapshots" artifact; locally they go to $SNAPSHOT_DIR or a temp folder.
final class SnapshotTests: XCTestCase {
    static var outDir: URL = {
        let path = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] ?? NSTemporaryDirectory() + "gridlock-snapshots"
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Plays a seeded shift with the scripted player for `seconds`.
    func play(level: Int, seconds: Double) -> Simulation {
        let sim = Simulation(levelIndex: level, rng: Random(seed: UInt32(1000 + level)))
        sim.mode = .running
        let carGroups = sim.groups.filter { $0.kind == .car }.count
        var cur = 0, greenSince = 0.0
        var frame = 0
        while Double(frame) < seconds * 60 && sim.mode == .running {
            if sim.groups[cur].light == .green && sim.t - greenSince >= 7 { sim.toggle(cur) }
            if !sim.groups.enumerated().contains(where: { $0.offset < carGroups && $0.element.light != .red }) {
                let next = (cur + 1) % carGroups
                if !sim.isUnsafe(next) { sim.toggle(next); cur = next; greenSince = sim.t }
            }
            sim.step(1.0 / 60)
            frame += 1
        }
        return sim
    }

    func render(_ sim: Simulation, width: CGFloat, height: CGFloat, name: String) throws {
        let pixelScale: CGFloat = 2
        let pw = Int(width * pixelScale), ph = Int(height * pixelScale)
        let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Points, y down.
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: pixelScale, y: -pixelScale)
        let renderer = BoardRenderer(simulation: sim)
        renderer.render(in: ctx, size: CGSize(width: width, height: height), pixelScale: pixelScale, clock: 10)
        let image = try XCTUnwrap(ctx.makeImage())
        let url = Self.outDir.appendingPathComponent("\(name).png")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    func testEveryLevelRenders() throws {
        for level in 0..<Level.all.count {
            let sim = play(level: level, seconds: 30)
            try render(sim, width: 640, height: 640, name: "level\(level + 1)-square")
            try render(sim, width: 393, height: 600, name: "level\(level + 1)-phone")
        }
        print("Snapshots written to \(Self.outDir.path)")
    }

    func testCanvasColors() {
        let c = Canvas.color("#ff8000").components!
        XCTAssertEqual(c[0], 1, accuracy: 0.01)
        XCTAssertEqual(c[1], 128.0 / 255, accuracy: 0.01)
        XCTAssertEqual(Canvas.color("rgba(10, 20, 30, 0.5)").alpha, 0.5, accuracy: 0.001)
    }
}
