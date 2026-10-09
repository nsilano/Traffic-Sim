import Foundation
import XCTest
@testable import GridlockCore

/// Runs the Swift simulation with the same seed and the same scripted player as the
/// JavaScript game (Fixtures/simulation.json, from tools/export-fixtures.js) and checks
/// they play out the same, second by second.
final class SimulationTests: XCTestCase {
    struct Run: Decodable {
        struct Frame: Decodable {
            let t: Double
            let cars, peds, cleared, crashes, wrecks, lastId: Int
            let score, patience, sumS, sumV: Double
            let emergency: String?
        }
        let level: Int
        let seed: UInt32
        let seconds: Int
        let mode: String
        let frames: [Frame]
    }

    static let runs: [Run] = {
        let url = Bundle.module.url(forResource: "simulation", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONDecoder().decode([Run].self, from: Data(contentsOf: url))
    }()

    func testRandomMatchesJavaScript() {
        // First draws of mulberry32(1) in JavaScript.
        let rng = Random(seed: 1)
        XCTAssertEqual(rng.next(), 0.6270739405881613, accuracy: 1e-15)
        XCTAssertEqual(rng.next(), 0.002735721180215478, accuracy: 1e-15)
    }

    func testShiftsPlayOutLikeTheJavaScriptGame() {
        for run in Self.runs {
            let sim = Simulation(levelIndex: run.level, rng: Random(seed: run.seed))
            sim.mode = .running
            let carGroups = sim.groups.filter { $0.kind == .car }.count
            var cur = 0, greenSince = 0.0
            var frames: [Run.Frame] = []
            var frame = 1
            while frame <= run.seconds * 60 {
                if sim.mode != .running { break }
                if sim.groups[cur].light == .green && sim.t - greenSince >= 7 { sim.toggle(cur) }
                if !sim.groups.enumerated().contains(where: { $0.offset < carGroups && $0.element.light != .red }) {
                    let next = (cur + 1) % carGroups
                    if !sim.isUnsafe(next) { sim.toggle(next); cur = next; greenSince = sim.t }
                }
                sim.step(1.0 / 60)
                if frame % 60 == 0 {
                    frames.append(Run.Frame(t: sim.t, cars: sim.cars.count, peds: sim.peds.count, cleared: sim.cleared,
                                            crashes: sim.crashes, wrecks: sim.wrecks.count, lastId: sim.carSeq,
                                            score: sim.score, patience: sim.patience,
                                            sumS: sim.cars.reduce(0) { $0 + $1.s }, sumV: sim.cars.reduce(0) { $0 + $1.v },
                                            emergency: sim.emergency.map { $0.phase == .warn ? "warn" : "active" }))
                }
                frame += 1
            }
            let at = "level \(run.level + 1)"
            XCTAssertEqual(frames.count, run.frames.count, "\(at): seconds played")
            for (i, (got, want)) in zip(frames, run.frames).enumerated() {
                let when = "\(at) at \(i + 1)s"
                let same = got.cars == want.cars && got.peds == want.peds && got.cleared == want.cleared
                    && got.crashes == want.crashes && got.wrecks == want.wrecks && got.lastId == want.lastId
                    && got.emergency == want.emergency
                    && abs(got.score - want.score) < 1e-6 && abs(got.patience - want.patience) < 1e-4
                    && abs(got.sumS - want.sumS) < 1e-3 && abs(got.sumV - want.sumV) < 1e-3
                if !same {
                    XCTFail("\(when): Swift \(got) vs JavaScript \(want)")
                    break
                }
            }
            let mode: String
            switch sim.mode {
            case .won: mode = "won"
            case .lost: mode = "lost"
            default: mode = "running"
            }
            XCTAssertEqual(mode, run.mode, "\(at): how the shift ended")
        }
    }
}
