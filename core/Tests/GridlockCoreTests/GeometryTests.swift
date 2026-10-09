import Foundation
import XCTest
@testable import GridlockCore

/// Checks the Swift geometry against the JavaScript game's own output for every level
/// (Fixtures/geometry.json, made by tools/export-fixtures.js).
final class GeometryTests: XCTestCase {
    struct Fixture: Decodable {
        struct Box: Decodable { let x0, x1, y0, y1: Double }
        struct Crosswalk: Decodable { let leg: String; let group: Int; let uc, road0, road1: Double }
        struct Lamp: Decodable { let dir: String; let lane: Int; let kind: String; let group: Int; let x, y: Double }
        struct Crossing: Decodable { let cw: Int; let s0, s1: Double }
        struct Path: Decodable {
            let dir: String
            let lane: Int
            let move: String
            let group: Int
            let pts: [[Double]]
            let len, A, exitStart, stopS: Double
            let laneKey, exitKey, boxKey: String
            let merges: Bool
            let mergeSide: Int
            let mergeS, mergeAt: Double
            let crossings: [Crossing]
        }
        let box: Box
        let crosswalks: [Crosswalk]
        let lamps: [Lamp]
        let paths: [Path]
        let conflicts: [[Int]]
    }

    static let fixtures: [Fixture] = {
        let url = Bundle.module.url(forResource: "geometry", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
    }()

    let tolerance = 1e-4

    func testLevelsLoad() {
        XCTAssertEqual(Level.all.count, 7)
        XCTAssertEqual(Level.all.first?.name, "First Shift")
        XCTAssertEqual(Level.all.last?.goal, 80)
    }

    func testEveryLevelMatchesTheJavaScriptGame() {
        XCTAssertEqual(Self.fixtures.count, Level.all.count)
        for (index, (level, want)) in zip(Level.all, Self.fixtures).enumerated() {
            let g = Geometry(level: level)
            let at = "level \(index + 1)"

            XCTAssertEqual(g.box.x0, want.box.x0, accuracy: tolerance, at)
            XCTAssertEqual(g.box.x1, want.box.x1, accuracy: tolerance, at)
            XCTAssertEqual(g.box.y0, want.box.y0, accuracy: tolerance, at)
            XCTAssertEqual(g.box.y1, want.box.y1, accuracy: tolerance, at)

            XCTAssertEqual(g.crosswalks.count, want.crosswalks.count, "\(at) crosswalks")
            for (c, w) in zip(g.crosswalks, want.crosswalks) {
                XCTAssertEqual(c.leg.rawValue, w.leg, at)
                XCTAssertEqual(c.group, w.group, at)
                XCTAssertEqual(c.uc, w.uc, accuracy: tolerance, at)
                XCTAssertEqual(c.road0, w.road0, accuracy: tolerance, at)
                XCTAssertEqual(c.road1, w.road1, accuracy: tolerance, at)
            }

            XCTAssertEqual(g.lamps.count, want.lamps.count, "\(at) lamps")
            for (l, w) in zip(g.lamps, want.lamps) {
                XCTAssertEqual(l.dir.rawValue, w.dir, at)
                XCTAssertEqual(l.lane, w.lane, at)
                XCTAssertEqual(l.kind, w.kind, at)
                XCTAssertEqual(l.group, w.group, at)
                XCTAssertEqual(l.position.x, w.x, accuracy: tolerance, at)
                XCTAssertEqual(l.position.y, w.y, accuracy: tolerance, at)
            }

            XCTAssertEqual(g.paths.count, want.paths.count, "\(at) paths")
            for (p, w) in zip(g.paths, want.paths) {
                let path = "\(at) path \(w.laneKey)\(w.move)"
                XCTAssertEqual(p.dir.rawValue, w.dir, path)
                XCTAssertEqual(p.lane, w.lane, path)
                XCTAssertEqual(String(p.move), w.move, path)
                XCTAssertEqual(p.group, w.group, path)
                XCTAssertEqual(p.pts.count, w.pts.count, "\(path) points")
                for (q, wq) in zip(p.pts, w.pts) {
                    XCTAssertEqual(q.x, wq[0], accuracy: tolerance, path)
                    XCTAssertEqual(q.y, wq[1], accuracy: tolerance, path)
                }
                XCTAssertEqual(p.len, w.len, accuracy: tolerance, path)
                XCTAssertEqual(p.A, w.A, accuracy: tolerance, path)
                XCTAssertEqual(p.exitStart, w.exitStart, accuracy: tolerance, path)
                XCTAssertEqual(p.stopS, w.stopS, accuracy: tolerance, path)
                XCTAssertEqual(p.laneKey, w.laneKey, path)
                XCTAssertEqual(p.exitKey, w.exitKey, path)
                XCTAssertEqual(p.boxKey, w.boxKey, path)
                XCTAssertEqual(p.merges, w.merges, path)
                XCTAssertEqual(p.mergeSide, w.mergeSide, path)
                XCTAssertEqual(p.mergeS, w.mergeS, accuracy: tolerance, path)
                XCTAssertEqual(p.mergeAt, w.mergeAt, accuracy: tolerance, path)
                XCTAssertEqual(p.crossings.count, w.crossings.count, "\(path) crossings")
                for (c, wc) in zip(p.crossings, w.crossings) {
                    XCTAssertEqual(c.crosswalk, wc.cw, path)
                    XCTAssertEqual(c.s0, wc.s0, accuracy: tolerance, path)
                    XCTAssertEqual(c.s1, wc.s1, accuracy: tolerance, path)
                }
            }

            XCTAssertEqual(g.conflicts.map { $0.sorted() }, want.conflicts, "\(at) conflicts")
        }
    }

    func testPointAtFollowsThePath() {
        let p = Geometry(level: Level.all[0]).paths[0]
        let start = p.point(at: 0).position
        XCTAssertEqual(start.x, p.pts[0].x, accuracy: tolerance)
        XCTAssertEqual(start.y, p.pts[0].y, accuracy: tolerance)
        let end = p.point(at: p.len).position
        XCTAssertEqual(end.x, p.pts.last!.x, accuracy: tolerance)
        XCTAssertEqual(end.y, p.pts.last!.y, accuracy: tolerance)
    }
}
