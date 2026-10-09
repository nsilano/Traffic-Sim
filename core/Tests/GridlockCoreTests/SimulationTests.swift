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

/// Saved data, controls and monitors.
final class PlayerDataTests: XCTestCase {
    func testReadsTheJavaScriptGamesSaves() {
        let data = PlayerData(strings: [
            PlayerData.progressKey: #"{"unlocked":3,"best":{"0":61.5},"stars":{"0":[true,false,true],"9":[true,true,true]},"scores":{"0":420,"1":"x"}}"#,
            PlayerData.settingsKey: #"{"sound":false,"bogus":true}"#,
            PlayerData.freeplayKey: #"{"map":4,"density":7,"flow":"wild","rush":false,"peds":true,"night":false,"emergency":true}"#,
            PlayerData.bestsKey: #"{"2-5":{"score":900,"cpm":12.4},"bad":5}"#,
        ])
        XCTAssertEqual(data.unlocked, 3)
        XCTAssertEqual(data.bestTimes[0], 61.5)
        XCTAssertEqual(data.stars[0], [true, false, true])
        XCTAssertNil(data.stars[9], "levels that don't exist are ignored")
        XCTAssertEqual(data.scores[0], 420)
        XCTAssertNil(data.scores[1])
        XCTAssertFalse(data.setting("sound"))
        XCTAssertTrue(data.setting("haptics"))
        XCTAssertEqual(data.freeplay.map, 4)
        XCTAssertEqual(data.freeplay.flow, "wild")
        XCTAssertTrue(data.freeplay.night, "old saves without 'day' start at night")
        XCTAssertEqual(data.bests["2-5"]?.score, 900)
        XCTAssertNil(data.bests["bad"])
        XCTAssertEqual(data.totalStars, 2)

        // And it reads back what it writes.
        let again = PlayerData(strings: data.strings)
        XCTAssertEqual(again.unlocked, 3)
        XCTAssertEqual(again.stars[0], [true, false, true])
        XCTAssertEqual(again.freeplay, data.freeplay)
        XCTAssertEqual(again.bests["2-5"]?.cpm, 12.4)
    }

    func testRecordWin() {
        var data = PlayerData()
        let first = data.recordWin(level: 0, time: 80, stars: [true, false, true], score: 300)
        XCTAssertTrue(first.newBest)
        XCTAssertEqual(data.unlocked, 2)
        let second = data.recordWin(level: 0, time: 70, stars: [true, true, false], score: 200)
        XCTAssertFalse(second.newBest)
        XCTAssertEqual(second.previous, 300)
        XCTAssertEqual(data.stars[0], [true, true, true])
        XCTAssertEqual(data.bestTimes[0], 70)
    }

    func testControlsAndMonitor() {
        for i in 0..<Level.all.count {
            let sim = Simulation(levelIndex: i, rng: Random(seed: 5))
            let layout = ControlLayout(simulation: sim)
            let carGroups = Set(layout.heads.flatMap(\.carGroups))
            let walkGroups = Set(layout.heads.flatMap(\.walkGroups))
            XCTAssertEqual(carGroups.count + walkGroups.count, sim.groups.count, "level \(i + 1): every group has a button")
            sim.mode = .running
            let monitor = CornerMonitor()
            for _ in 0..<(40 * 60) { sim.step(1.0 / 60); monitor.update(sim, layout) }
            XCTAssertFalse(monitor.corners.isEmpty)
            for head in layout.heads {
                let corner = monitor.corners[head.dir]!
                guard let g = corner.longest else { continue }
                XCTAssertTrue((head.carGroups + head.walkGroups).contains(g), "level \(i + 1): the longest wait is one of this corner's buttons")
                XCTAssertEqual(corner.groupOldest[g], corner.oldest, "level \(i + 1): the timer sits on the button waiting longest")
            }
        }
    }

    /// Patience only runs for the driver at the front of the line.
    func testOnlyTheFrontCarWaits() {
        let sim = Simulation(levelIndex: 0, rng: Random(seed: 3))
        sim.mode = .running
        for _ in 0..<(30 * 60) { sim.step(1.0 / 60) }
        var queued = 0
        for c in sim.cars where c.s <= c.path.stopS + 1 && c.v < 1 {
            let ahead = sim.cars.contains { $0 !== c && $0.path.laneKey == c.path.laneKey && $0.s > c.s && $0.s <= $0.path.stopS + 1 }
            if ahead {
                queued += 1
                XCTAssertEqual(c.lightWait, 0, "a car behind another isn't using up patience")
            }
            XCTAssertGreaterThanOrEqual(c.wait, c.lightWait)
        }
        XCTAssertGreaterThan(queued, 0, "the test needs a queue")
    }

    /// People who cross walk on along the sidewalk and off the map, rather than vanishing.
    func testPedestriansWalkOff() {
        let sim = Simulation(levelIndex: 2, rng: Random(seed: 4))
        sim.mode = .running
        let walks = sim.groups.indices.filter { sim.groups[$0].kind == .walk }
        var sawLeaving = false
        for frame in 0..<(90 * 60) {
            if frame % (12 * 60) == 0 { for g in walks { sim.toggle(g) } }
            sim.step(1.0 / 60)
            for ped in sim.peds where ped.state == .leaving {
                sawLeaving = true
                let end = ped.route.pts.last!
                XCTAssertTrue(end.x < 0 || end.y < 0 || end.x > World.width || end.y > World.height, "they leave off the edge of the map")
            }
        }
        XCTAssertTrue(sawLeaving)
    }

    func testLiveDensity() {
        let sim = Simulation(levelIndex: 2, level: Level.freeplay(map: 2, density: 5, rush: true, peds: true, night: true),
                             freeplay: Simulation.Freeplay(map: 2, density: 5, flow: "lively"), rng: Random(seed: 9))
        sim.setDensity(9)
        XCTAssertEqual(sim.freeplay?.density, 9)
        sim.setDensity(3)
        XCTAssertEqual(sim.bestKey, "2-3")
    }
}
