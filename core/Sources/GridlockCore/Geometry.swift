import Foundation

/// One crosswalk: the road leg traffic heading `leg` arrives over.
public struct Crosswalk {
    public let leg: Direction
    /// Its walk signal's group index (after the car groups).
    public let group: Int
    /// Centre of the crosswalk, along the leg's heading from the box centre.
    public let uc: Double
    /// How far it reaches across the road: from road0 (driver's left) to road1 (right).
    public let road0: Double
    public let road1: Double

    /// The point at distance v across the road and du along it.
    public func point(_ v: Double, _ du: Double = 0) -> Vec { leg.point(uc + du, v) }
}

/// The stretch of a path that runs over a crosswalk.
public struct Crossing {
    public let crosswalk: Int
    public let s0: Double
    public let s1: Double
}

/// A signal lamp at a stop line.
public struct Lamp {
    public let dir: Direction
    public let lane: Int
    public let u: Double
    public let v: Double
    /// "L" for a left-turn lane, "T" otherwise.
    public let kind: String
    public let position: Vec
    public let group: Int
}

/// The route one kind of move takes from one approach lane, from off the board on the
/// way in to off the board on the way out.
public final class Path {
    public let dir: Direction
    public let lane: Int
    /// "T" straight, "L" left or "R" right.
    public let move: Character
    public internal(set) var group = -1
    public let pts: [Vec]
    /// Distance along the path at each point.
    public let cum: [Double]
    public let len: Double
    /// Where the path enters the box.
    public let A: Double
    /// Where it leaves the box.
    public let exitStart: Double
    public let stopS: Double
    public let laneKey: String
    /// The lane the car ends up in, and the lane it is in right after the box.
    public let exitKey: String
    public let boxKey: String
    public let merges: Bool
    /// +1 moves over to the driver's right, -1 to the left.
    public let mergeSide: Int
    public let mergeS: Double
    /// Where a merging car's body starts to cross into the next lane.
    public let mergeAt: Double
    public internal(set) var crossings: [Crossing] = []

    init(dir: Direction, lane: Int, move: Character, pts: [Vec], jEnd: Int, exitKey: String, boxKey: String,
         shift: Double, mergeStart: Double, mergeLength: Double) {
        self.dir = dir
        self.lane = lane
        self.move = move
        self.pts = pts
        var cum = [0.0]
        for j in 1..<pts.count { cum.append(cum[j - 1] + pts[j].distance(to: pts[j - 1])) }
        self.cum = cum
        len = cum[cum.count - 1]
        A = cum[1]
        exitStart = cum[jEnd]
        stopS = cum[1] - World.crosswalk - World.stopGap
        laneKey = dir.rawValue + String(lane)
        self.exitKey = exitKey
        self.boxKey = boxKey
        merges = shift != 0
        mergeSide = shift > 0 ? 1 : shift < 0 ? -1 : 0
        mergeS = cum[jEnd] + mergeStart
        mergeAt = cum[jEnd] + mergeStart + mergeLength * 0.4
    }

    /// The point at distance s along the path, and the heading there (radians).
    public func point(at s: Double) -> (position: Vec, angle: Double) {
        let n = pts.count
        var lo = 0
        if s >= cum[n - 2] {
            lo = n - 2
        } else if s > 0 {
            var hi = n - 2
            while lo < hi {
                let mid = (lo + hi + 1) >> 1
                if cum[mid] <= s { lo = mid } else { hi = mid - 1 }
            }
        }
        let a = pts[lo], b = pts[lo + 1]
        let t = (s - cum[lo]) / (cum[lo + 1] - cum[lo])
        return (Vec(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t), atan2(b.y - a.y, b.x - a.x))
    }
}

/// Everything about a level's roads: lanes, the box, crosswalks, the paths cars take,
/// the lamps, and which signal groups conflict.
public struct Geometry {
    public struct Box { public let x0, x1, y0, y1: Double }

    /// How far the box reaches, seen from an approach: the edge it enters (near), the
    /// edge it leaves by (far), and to the driver's right and left.
    public struct Extent { public let near, far, right, left: Double }

    public let level: Level
    public let lanes: [Direction: [String]]
    public let out: [Direction: Int]
    public let mergeStart: Double
    public let mergeLength: Double
    public private(set) var box = Box(x0: 0, x1: 0, y0: 0, y1: 0)
    public private(set) var crosswalks: [Crosswalk] = []
    public private(set) var paths: [Path] = []
    public private(set) var lamps: [Lamp] = []
    /// For each signal group (cars first, then walks), the groups it can't run with.
    public private(set) var conflicts: [Set<Int>] = []

    public init(level: Level) {
        self.level = level
        var lanes: [Direction: [String]] = [:]
        var out: [Direction: Int] = [:]
        for k in Direction.allCases {
            lanes[k] = level.lanes(k)
            out[k] = level.out?[k.rawValue] ?? lanes[k]!.count
        }
        self.lanes = lanes
        self.out = out
        mergeStart = level.mergeStart ?? World.mergeStart
        mergeLength = level.mergeLen ?? World.mergeLength
        box = Box(x0: World.cx - halfOf(.S), x1: World.cx + halfOf(.N), y0: World.cy - halfOf(.W), y1: World.cy + halfOf(.E))

        let carGroups = level.groups
        func groupFor(_ k: Direction, _ move: Character) -> Int {
            carGroups.firstIndex { g in g.dirs.contains(k) && (g.move == "A" || (g.move == "L") == (move == "L")) } ?? -1
        }

        for (wi, w) in (level.walks ?? []).enumerated() {
            for k in w.legs where hasLeg(k) {
                crosswalks.append(Crosswalk(leg: k, group: carGroups.count + wi,
                                            uc: -ext(k).near - World.crosswalk / 2,
                                            road0: -legLeft(k), road1: legRight(k)))
            }
        }

        for k in Direction.allCases {
            for (i, laneSpec) in lanes[k]!.enumerated() {
                for move in laneSpec {
                    guard let p = buildPath(k, i, move) else { continue }
                    p.group = groupFor(k, move)
                    paths.append(p)
                }
                let u = -ext(k).near - World.crosswalk - World.stopGap + 9, v = laneOff(k, i)
                lamps.append(Lamp(dir: k, lane: i, u: u, v: v, kind: laneSpec == "L" ? "L" : "T",
                                  position: k.point(u, v), group: groupFor(k, laneSpec.first!)))
            }
        }
        for p in paths { p.crossings = crossings(of: p) }
        conflicts = computeConflicts()
    }

    // MARK: Road widths

    /// Half the width of a planted median on a divided road (0 on most roads).
    public func mh(_ k: Direction) -> Double {
        let o = k.opposite
        guard lanes[k]!.count + out[k]! > 0, lanes[o]!.count + out[o]! > 0 else { return 0 }
        return (level.median?[k.road] ?? 0) / 2
    }

    /// Distance of lane i (inner lane 0) from the road's centre line.
    public func laneOff(_ k: Direction, _ i: Int) -> Double { mh(k) + World.laneWidth * (Double(i) + 0.5) }

    /// Width of the half of a road that carries direction k (its lanes in the box).
    public func halfOf(_ k: Direction) -> Double {
        let n = max(lanes[k]!.count, out[k]!)
        return n > 0 ? mh(k) + Double(n) * World.laneWidth : 0
    }

    public func ext(_ k: Direction) -> Extent {
        Extent(near: halfOf(k.rightTurn), far: halfOf(k.leftTurn), right: halfOf(k), left: halfOf(k.opposite))
    }

    /// The road leg that traffic heading k arrives over: its width to the right and left.
    public func legRight(_ k: Direction) -> Double {
        lanes[k]!.isEmpty ? 0 : mh(k) + Double(lanes[k]!.count) * World.laneWidth
    }

    public func legLeft(_ k: Direction) -> Double { out[k.opposite]! > 0 ? halfOf(k.opposite) : 0 }

    public func hasLeg(_ k: Direction) -> Bool { legRight(k) > 0 || legLeft(k) > 0 }

    /// The outline of the road leg that traffic heading k arrives over, in k's frame
    /// (+u along the heading, +v to the driver's right), as game.js legDims().
    public struct Leg { public let far, near, R, L0, L1, mh, m0, m1: Double }

    public func legDims(_ k: Direction) -> Leg {
        let near = -ext(k).near
        let o = k.opposite
        return Leg(far: -(World.half + World.pad), near: near, R: legRight(k), L0: legLeft(k),
                   L1: out[o]! > 0 ? mh(k) + Double(out[o]!) * World.laneWidth : 0, mh: mh(k),
                   m0: near - mergeStart, m1: near - mergeStart - mergeLength)
    }

    /// Approach lanes shared by more than one move (say straight and right): only there
    /// does a turn signal tell the player anything.
    public var sharedLanes: Set<String> {
        var moves: [String: Set<Character>] = [:]
        for p in paths { moves[p.laneKey, default: []].insert(p.move) }
        return Set(moves.filter { $0.value.count > 1 }.keys)
    }

    // MARK: Paths

    private func buildPath(_ k: Direction, _ i: Int, _ move: Character) -> Path? {
        let e = ext(k)
        let off = laneOff(k, i)
        var pts = [k.point(-(World.half + World.pad), off), k.point(-e.near, off)]
        let steps = 24
        let exitDir: Direction
        let boxLane: Int
        if move == "T" {
            exitDir = k
            boxLane = i
            if out[k]! == 0 { return nil }
            pts.append(k.point(e.far, off))
        } else if move == "L" {
            exitDir = k.leftTurn
            boxLane = 0
            if out[exitDir]! == 0 { return nil }
            // Quarter ellipse around the far-left corner of the box.
            let a = off + e.left, b = laneOff(k.leftTurn, 0) + e.near
            for j in 1...steps {
                let t = Double(j) / Double(steps) * Double.pi / 2
                pts.append(k.point(-e.near + b * sin(t), -e.left + a * cos(t)))
            }
        } else {
            exitDir = k.rightTurn
            if out[exitDir]! == 0 { return nil }
            boxLane = out[exitDir]! - 1
            // Curve around the near-right corner into the outer lane.
            let offX = laneOff(exitDir, boxLane)
            let a = e.right - off, b = e.near - offX
            for j in 1...steps {
                let t = Double(j) / Double(steps) * Double.pi / 2
                pts.append(k.point(-e.near + b * sin(t), e.right - a * cos(t)))
            }
        }
        let jEnd = pts.count - 1
        let exitLane = min(boxLane, out[exitDir]! - 1)
        let ed = exitDir.heading, er = exitDir.right
        let remain = World.half + World.pad - ext(exitDir).far
        let x = pts[jEnd]
        let shift = World.laneWidth * Double(exitLane - boxLane)
        if shift != 0 {
            // Lane ends after the box: taper across into the next lane.
            pts.append(Vec(x.x + ed.x * mergeStart, x.y + ed.y * mergeStart))
            for m in 1...12 {
                let t = Double(m) / 12, sm = t * t * (3 - 2 * t)
                let along = mergeStart + mergeLength * t
                pts.append(Vec(x.x + ed.x * along + er.x * shift * sm, x.y + ed.y * along + er.y * shift * sm))
            }
        }
        pts.append(Vec(x.x + ed.x * remain + er.x * shift, x.y + ed.y * remain + er.y * shift))
        return Path(dir: k, lane: i, move: move, pts: pts, jEnd: jEnd,
                    exitKey: exitDir.rawValue + String(exitLane), boxKey: exitDir.rawValue + String(boxLane),
                    shift: shift, mergeStart: mergeStart, mergeLength: mergeLength)
    }

    /// The stretches of a path that run over each crosswalk.
    private func crossings(of p: Path) -> [Crossing] {
        var result: [Crossing] = []
        for (index, cw) in crosswalks.enumerated() {
            let d = cw.leg.heading, r = cw.leg.right
            var s0: Double?, s1: Double?
            var s = p.stopS
            while s <= p.exitStart + World.crosswalk + 30 {
                let pt = p.point(at: s).position
                let u = (pt.x - World.cx) * d.x + (pt.y - World.cy) * d.y
                let v = (pt.x - World.cx) * r.x + (pt.y - World.cy) * r.y
                if abs(u - cw.uc) <= World.crosswalk / 2 + 1 && v >= cw.road0 - 2 && v <= cw.road1 + 2 {
                    if s0 == nil { s0 = s }
                    s1 = s
                }
                s += 2
            }
            if let s0 = s0, let s1 = s1 { result.append(Crossing(crosswalk: index, s0: s0, s1: s1)) }
        }
        return result
    }

    // MARK: Conflicts

    /// Two signal groups conflict if their paths come close inside the box. A walk signal
    /// conflicts with straight-through traffic over its crosswalk; turning drivers stop
    /// for people, so they are not a conflict.
    private func computeConflicts() -> [Set<Int>] {
        let count = level.groups.count + (level.walks ?? []).count
        var conflicts = Array(repeating: Set<Int>(), count: count)
        func link(_ a: Int, _ b: Int) { conflicts[a].insert(b); conflicts[b].insert(a) }
        let samples: [[Vec]] = paths.map { p in
            var pts: [Vec] = []
            var s = p.A - 2
            while s <= p.exitStart + 12 {
                pts.append(p.point(at: s).position)
                s += 3
            }
            return pts
        }
        for i in 0..<paths.count {
            for j in (i + 1)..<max(i + 1, paths.count) {
                let p = paths[i], q = paths[j]
                if p.group == q.group || p.laneKey == q.laneKey || conflicts[p.group].contains(q.group) { continue }
                var hit = p.exitKey == q.exitKey && p.boxKey == q.boxKey
                outer: for a in samples[i] where !hit {
                    for b in samples[j] where a.distance(to: b) < World.conflictDistance {
                        hit = true
                        break outer
                    }
                }
                if hit { link(p.group, q.group) }
            }
        }
        for p in paths where p.move == "T" {
            for c in p.crossings { link(p.group, crosswalks[c.crosswalk].group) }
        }
        return conflicts
    }
}
