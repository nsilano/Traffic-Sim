import Foundation

/// Where the signal buttons go: one set per approach, on the block at the driver's right
/// just before the junction, with the walk buttons whose crosswalk is at that corner.
/// A port of buildControls() in game.js.
public struct ControlLayout {
    public struct Head {
        public let dir: Direction
        /// Car groups at this corner, left turns first.
        public let carGroups: [Int]
        public let walkGroups: [Int]
        /// Board point the set hangs from, and which way it extends from there.
        public let anchor: Vec
        public let extendsRight: Bool
        public let extendsDown: Bool
    }

    public let heads: [Head]
    /// For each crosswalk leg, the approach whose set holds its walk button.
    public let walkBlock: [Direction: Direction]

    static let dockOrder: [Direction] = [.S, .W, .E, .N]

    public init(simulation sim: Simulation) {
        let geo = sim.geometry
        let approaches = Self.dockOrder.filter { !geo.lanes[$0]!.isEmpty }
        var walksAt: [Direction: [Int]] = [:]
        for k in approaches { walksAt[k] = [] }
        var walkBlock: [Direction: Direction] = [:]
        for cw in geo.crosswalks where walksAt[cw.leg] != nil {
            if !walksAt[cw.leg]!.contains(cw.group) { walksAt[cw.leg]!.append(cw.group) }
            walkBlock[cw.leg] = cw.leg
        }
        for (i, g) in sim.groups.enumerated() where g.kind == .walk && !approaches.isEmpty {
            if approaches.contains(where: { walksAt[$0]!.contains(i) }) { continue }
            walksAt[approaches[0]]!.append(i)
            for cw in geo.crosswalks where cw.group == i { walkBlock[cw.leg] = approaches[0] }
        }
        for cw in geo.crosswalks where walkBlock[cw.leg] == nil {
            if let first = approaches.first { walkBlock[cw.leg] = first }
        }
        heads = approaches.map { k in
            var groups: [Int] = []
            for lamp in geo.lamps where lamp.dir == k && !groups.contains(lamp.group) { groups.append(lamp.group) }
            // Left turns first, keeping the original order otherwise (a stable sort, like the JS one).
            let ordered = groups.filter { sim.groups[$0].move == "L" } + groups.filter { sim.groups[$0].move != "L" }
            let d = k.heading, r = k.right
            let u = -geo.ext(k).near - World.sidewalk, v = geo.legRight(k) + World.sidewalk
            return Head(dir: k, carGroups: ordered, walkGroups: walksAt[k] ?? [],
                        anchor: k.point(u, v), extendsRight: (-d.x + r.x) > 0, extendsDown: (-d.y + r.y) > 0)
        }
        self.walkBlock = walkBlock
    }
}

/// What each corner's monitor shows: how many are waiting there (including cars backed up
/// off the map) and the longest wait, per-button counts, the busiest corner (calm on purpose)
/// and the emergency flags. A port of updateMonitor() in game.js.
public final class CornerMonitor {
    public struct Corner {
        public var total = 0
        public var oldest = 0.0
        public var groups: [Int: Int] = [:]
        /// The longest wait at each button, and the button waiting longest (if anyone is).
        public var groupOldest: [Int: Double] = [:]
        public var longest: Int?
        /// "ok", "warn" (half the patience used) or "bad".
        public var level = "ok"
        public var busiest = false
        public var emergency = false
        public init() {}
    }

    public private(set) var corners: [Direction: Corner] = [:]
    /// Buttons that would give the waiting emergency vehicle its green.
    public private(set) var emergencyGroups: Set<Int> = []

    private var monitorAt = -1.0
    private var queued = Set<Int>()
    private var busiest: Direction?
    private var busiestAt = -Double.infinity
    private var challenger: Direction?
    private var challengerAt = 0.0

    public init() {}

    /// Recounts at most four times a second, like the game.
    public func update(_ sim: Simulation, _ layout: ControlLayout, force: Bool = false) {
        if !force && monitorAt >= 0 && sim.t - monitorAt < 0.25 { return }
        monitorAt = sim.t
        var by: [Direction: Corner] = [:]
        for k in Direction.allCases { by[k] = Corner() }
        var live = Set<Int>()
        for c in sim.cars {
            live.insert(c.id)
            let p = c.path
            if c.s > p.stopS + 1 || c.s <= p.stopS - 420 { continue }
            if c.v < 4 { queued.insert(c.id) }
            if !queued.contains(c.id) && c.v >= 12 { continue }
            by[p.dir]!.total += 1
            by[p.dir]!.groups[p.group, default: 0] += 1
            by[p.dir]!.oldest = max(by[p.dir]!.oldest, c.lightWait)
            by[p.dir]!.groupOldest[p.group] = max(by[p.dir]!.groupOldest[p.group] ?? 0, c.lightWait)
        }
        queued.formIntersection(live)
        for k in Direction.allCases {
            let b = sim.backlog(k)
            if b.blocked { by[k]!.total += b.waiting }
        }
        for ped in sim.peds where ped.state == .waiting {
            let cw = sim.geometry.crosswalks[ped.crosswalk]
            let k = layout.walkBlock[cw.leg] ?? cw.leg
            by[k]!.total += 1
            by[k]!.groups[cw.group, default: 0] += 1
            by[k]!.oldest = max(by[k]!.oldest, ped.wait)
            by[k]!.groupOldest[cw.group] = max(by[k]!.groupOldest[cw.group] ?? 0, ped.wait)
        }

        // The busiest marker stays at least 8 seconds, never leaves a corner that has a
        // green, and only moves when another corner has been clearly busier (40% more,
        // plus two) for 3 seconds straight. It does leave a corner that empties.
        func weight(_ k: Direction) -> Double { by[k]!.total > 0 ? Double(by[k]!.total) + by[k]!.oldest * 0.25 : 0 }
        var leader: Direction?
        var top = 0.0
        for head in layout.heads {
            let w = weight(head.dir)
            if w > top { top = w; leader = head.dir }
        }
        let cur = busiest.flatMap { weight($0) > 0 ? $0 : nil }
        func served(_ k: Direction) -> Bool {
            layout.heads.first { $0.dir == k }.map { h in (h.carGroups + h.walkGroups).contains { sim.groups[$0].light == .green } } ?? false
        }
        if let cur = cur {
            if leader != cur && top > weight(cur) * 1.4 + 2 && sim.t - busiestAt >= 8 && !served(cur) {
                if challenger != leader {
                    challenger = leader
                    challengerAt = sim.t
                } else if sim.t - challengerAt >= 3 {
                    busiest = leader
                    busiestAt = sim.t
                    challenger = nil
                }
            } else {
                challenger = nil
            }
        } else {
            if leader != busiest { busiestAt = sim.t }
            busiest = leader
            challenger = nil
        }

        let angry = sim.level.angry
        let em = sim.pendingEmergency
        emergencyGroups = em.map { e in Set(sim.geometry.paths.filter { $0.dir == e.dir && $0.move == "T" }.map(\.group)) } ?? []
        for head in layout.heads {
            var m = by[head.dir]!
            m.level = m.oldest > angry ? "bad" : m.oldest > angry * 0.5 ? "warn" : "ok"
            m.busiest = head.dir == busiest && sim.mode == .running
            m.emergency = em?.dir == head.dir
            m.longest = (head.carGroups + head.walkGroups)
                .filter { (m.groupOldest[$0] ?? 0) >= 1 }
                .max { (m.groupOldest[$0] ?? 0) < (m.groupOldest[$1] ?? 0) }
            by[head.dir] = m
        }
        corners = by
    }
}
