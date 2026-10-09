import Foundation

/// One shift (or freeplay run) at one intersection: signals, traffic, people, emergencies,
/// crashes, score and patience. A line-for-line port of the simulation in game.js; random
/// draws happen in the same order, so the same seed plays out the same way in both.
public final class Simulation {
    // MARK: Tuning (game.js constants)

    static let yellowTime = 2.5
    static let accelDefault = 150.0, brake = 260.0, hardBrake = 520.0, minGap = 8.0
    static let turnSpeed: [Character: Double] = ["L": 62, "R": 38]
    static let minCommitSpeed = 45.0
    static let beaterShare = 0.1
    static let beaterBoost = 1.3
    static let mistakeKinds: Set<String> = ["distracted", "stall", "bump"]
    static let drainPerAngry = 1.1
    static let maxDrain = 6.0
    static let carPoints = 10.0
    static let comboStep = 10
    static let maxCombo = 3.0
    static let waveMin = 4
    static let wavePoints = 5
    static let crashPenalty = 100.0
    static let pedHitPenalty = 150.0
    public static let starPatience = 50.0
    static let drainPerBlocked = 4.0
    static let refillPerCar = 1.6
    static let crashPatience = 12.0
    public static let maxCrashes = 3
    static let wreckTime = 5.0
    static let walkClearTime = 5.0
    static let pedPatience = 1.5
    static let minHitSpeed = 10.0
    static let pedColors = ["#e8c07a", "#c45a4a", "#5a7fb8", "#7a5aa8", "#4f9a6a", "#d0d4d8", "#2e3338", "#d98a3a"]
    static let carColors = ["#e8eef3", "#2c3e57", "#b8372f", "#d6a12b", "#4c7a5a", "#8a96a3", "#1f2328", "#3d6fb0", "#c96b2c"]
    static let truckColors = ["#f0f0ea", "#c9cdd1", "#5a6470"]
    static let rushBoost = 2.4
    public static let flowRamp = 45.0

    public struct FlowStyle {
        public let label: String
        public let desc: String
        let tide, bunch: Double
        let spellEvery: [Double]
        let lull, surge, surgeShare: Double
    }

    public static let flowStyles: [String: FlowStyle] = [
        "calm": FlowStyle(label: "Calm", desc: "Gentle swings", tide: 0.15, bunch: 0.15, spellEvery: [70, 110], lull: 0.45, surge: 1, surgeShare: 0),
        "lively": FlowStyle(label: "Lively", desc: "Waves and lulls", tide: 0.3, bunch: 0.35, spellEvery: [50, 85], lull: 0.4, surge: 1.45, surgeShare: 0.35),
        "wild": FlowStyle(label: "Wild", desc: "Big surges, sudden lulls", tide: 0.45, bunch: 0.55, spellEvery: [30, 55], lull: 0.3, surge: 1.8, surgeShare: 0.55),
    ]

    static let emergencyWarn = 5.0
    static let emergencyHold = 8.0
    static let emergencyPerQueued = 1.4
    static let emergencyFirst: [Double] = [35, 60]
    static let emergencyEvery: [Double] = [55, 95]
    static let emergencyBonus = 50.0
    static let emergencyPenaltyPoints = 120.0
    static let emergencyAgain = 10.0
    static let emergencyPatience = 12.0
    static let from: [Direction: String] = [.N: "south", .S: "north", .E: "west", .W: "east"]

    // MARK: State

    public enum Mode { case intro, running, paused, won, lost }

    public struct Freeplay {
        public var map: Int
        public var density: Int
        public var flow: String
        public init(map: Int, density: Int, flow: String) { self.map = map; self.density = density; self.flow = flow }
    }

    struct Spawner { var timer: Double; var pending: [Character] = []; var blockedFor = 0.0 }
    struct PedSpawner { let crosswalk: Int; let dir: Double; var timer: Double }
    struct Spell { let kind: String; let k: Double; let from: Double; let until: Double }
    struct Flow {
        let style: String
        let p1, p2: Double
        var bunch: [String: (period: Double, offset: Double)]
        var spell: Spell?
        var nextSpell: Double
        let cap: Double
    }

    public struct Emergency {
        public enum Phase { case warn, active }
        public var phase: Phase
        public let dir: Direction
        public let kind: EmergencyKind
        public let spawnAt: Double
        public internal(set) var car: Car?
        var lastT = 0.0
        public internal(set) var held = 0.0
        public internal(set) var limit: Double?
        var nextHit: Double?
        var penalised = false
    }

    public let levelIndex: Int
    public internal(set) var level: Level
    public let geometry: Geometry
    public internal(set) var freeplay: Freeplay?
    /// Freeplay bests are filed under the lightest density a run was played at.
    public internal(set) var bestDensity = 0
    let rng: Random
    /// Settings → Screen shake.
    public var shakeOn: Bool

    public var mode = Mode.intro
    public internal(set) var t = 0.0
    public internal(set) var pulse = 0.0
    public internal(set) var cleared = 0
    public internal(set) var crashes = 0
    public internal(set) var patience = 100.0
    public internal(set) var minPatience = 100.0
    public internal(set) var score = 0.0
    public internal(set) var streak = 0
    public internal(set) var mult = 1.0
    public internal(set) var waitSum = 0.0
    public internal(set) var worstWait = 0.0
    public internal(set) var groups: [SignalGroup]
    var flow: Flow
    var carSeq = 0
    public internal(set) var cars: [Car] = []
    public internal(set) var peds: [Pedestrian] = []
    public internal(set) var wrecks: [Wreck] = []
    public internal(set) var particles: [Particle] = []
    public internal(set) var flashes: [Flash] = []
    public internal(set) var popups: [Popup] = []
    public internal(set) var banners: [Banner] = []
    var spawners: [Direction: Spawner] = [:]
    var pedSpawners: [PedSpawner] = []
    public internal(set) var rush: (dir: Direction, until: Double)?
    var nextRush = 25.0
    public var emergencyOn: Bool
    public internal(set) var emergency: Emergency?
    var nextEmergency = 0.0
    public internal(set) var shake = 0.0
    public internal(set) var failAt: Double?
    public internal(set) var failReason = ""
    /// The freeplay best this run has to beat, for the "New best score!" banner.
    public var bestToBeat = 0.0
    var bestShown = false
    /// What happened this step, for the app to act on (sounds, haptics, the end of the shift).
    public internal(set) var events: [SimEvent] = []

    /// A campaign shift (levelIndex 0–6) or, with `freeplay`, a freeplay run on that map.
    public init(levelIndex: Int, level: Level? = nil, freeplay: Freeplay? = nil,
                emergencies: Bool = true, shake: Bool = true, rng: Random = Random()) {
        let level = level ?? Level.all[levelIndex]
        let geo = Geometry(level: level)
        let flowStyle = freeplay.map { Self.flowStyles[$0.flow] != nil ? $0.flow : "lively" } ?? (levelIndex < 2 ? "calm" : "lively")
        // Draw order matches newState() in game.js.
        var spawners: [Direction: Spawner] = [:]
        for k in Direction.allCases { spawners[k] = Spawner(timer: rng.next() * 2) }
        var pedSpawners: [PedSpawner] = []
        for index in geo.crosswalks.indices {
            for dir in [1.0, -1.0] { pedSpawners.append(PedSpawner(crosswalk: index, dir: dir, timer: rng.next() * 6)) }
        }
        self.levelIndex = levelIndex
        self.level = level
        self.freeplay = freeplay
        self.rng = rng
        shakeOn = shake
        geometry = geo
        self.spawners = spawners
        self.pedSpawners = pedSpawners
        groups = level.groups.enumerated().map { i, g in
            SignalGroup(kind: .car, label: g.label, dirs: g.dirs, move: g.move, legs: [], light: i == 0 ? .green : .red)
        } + (level.walks ?? []).map { w in
            SignalGroup(kind: .walk, label: w.label, dirs: [], move: "", legs: w.legs, light: .red)
        }
        let st = Self.flowStyles[flowStyle]!
        let p1 = rng.next() * Double.pi * 2
        let p2 = rng.next() * Double.pi * 2
        let ns = (period: 22 + rng.next() * 14, offset: rng.next() * 40)
        let ew = (period: 22 + rng.next() * 14, offset: rng.next() * 40)
        flow = Flow(style: flowStyle, p1: p1, p2: p2, bunch: ["NS": ns, "EW": ew], spell: nil,
                    nextSpell: Self.flowRamp + st.spellEvery[0] * (0.5 + rng.next() * 0.5),
                    cap: (1 + st.tide) * (1 + st.bunch) * Swift.max(1, st.surge))
        emergencyOn = freeplay != nil ? emergencies : levelIndex >= 2 && emergencies
        nextEmergency = rng.between(Self.emergencyFirst)
        bestDensity = freeplay?.density ?? 0
    }

    var hasLimits: Bool { freeplay == nil }

    /// Freeplay: change the traffic density mid-run (the slider under the map).
    public func setDensity(_ density: Int) {
        guard var f = freeplay else { return }
        f.density = density
        freeplay = f
        let fresh = Level.freeplay(map: f.map, density: density, rush: level.rush, peds: (level.basePeds ?? 0) > 0, night: level.night ?? false)
        level.rate = fresh.rate
        level.peds = (level.basePeds ?? 0) * Swift.min(2, Level.densityFactor(density))
        // New arrival timers so the new rate takes effect straight away.
        for k in Direction.allCases where !geometry.lanes[k]!.isEmpty { spawners[k]?.timer = rng.exponential(mean: 1 / laneRateCap(k)) }
        for i in pedSpawners.indices {
            pedSpawners[i].timer = (level.peds ?? 0) > 0 ? rng.exponential(mean: 1 / ((level.peds ?? 0) * flow.cap)) : 6
        }
        bestDensity = Swift.min(bestDensity, density)
    }

    /// The freeplay best this run is filed under.
    public var bestKey: String? {
        freeplay.map { PlayerData.bestKey(map: $0.map, density: bestDensity, flow: $0.flow) }
    }

    // MARK: Signals

    /// The player switches a group: green goes to yellow, red goes to green.
    public func toggle(_ i: Int) {
        guard mode == .running, failAt == nil, groups.indices.contains(i) else { return }
        if groups[i].light == .green {
            greenWave(i)
            groups[i].light = .yellow
            groups[i].timer = 0
            groups[i].cycle += 1
            events.append(.haptic("stop"))
            sound("stop")
        } else if groups[i].light == .red {
            groups[i].light = .green
            groups[i].passed = 0
            events.append(.haptic("go"))
            sound("go")
        }
    }

    func updateGroups(_ dt: Double) {
        for i in groups.indices where groups[i].light == .yellow {
            groups[i].timer += dt
            if groups[i].timer >= (groups[i].kind == .walk ? Self.walkClearTime : Self.yellowTime) { groups[i].light = .red }
        }
    }

    /// Would turning group i green now cross moving traffic?
    public func isUnsafe(_ i: Int) -> Bool {
        for j in geometry.conflicts[i] where groups[j].light != .red || groups[j].busy > 0 { return true }
        return false
    }

    // MARK: Step

    /// Takes the sounds, haptics and end-of-shift events since the last call.
    public func drainEvents() -> [SimEvent] {
        defer { events.removeAll() }
        return events
    }

    /// Advances the world by dt seconds. Collect what happened with drainEvents().
    public func step(_ dt: Double, quiet: Bool = false) {
        t += dt
        pulse += dt
        updateGroups(dt)
        var tails = laneTails()
        updateSpawns(dt, &tails)
        updateCars(dt)
        updatePeds(dt)
        if !quiet {
            var tails2 = laneTails()
            updateEmergency(&tails2)
            detectCrashes()
            detectPedHits()
            updateEffects(dt)
            updateStatus(dt)
        }
    }

    // MARK: Messages to the player

    func banner(_ text: String, _ color: String) {
        banners.append(Banner(text: text, color: color))
        if banners.count > 3 { banners.removeFirst() }
    }

    func sound(_ name: String) {
        if mode != .running && name != "win" && name != "lose" { return }
        events.append(.sound(name))
    }

    func addPoints(_ n: Double, _ at: Vec?, _ color: String) {
        score = Swift.max(0, score + n)
        if let at = at {
            popups.append(Popup(x: at.x, y: at.y, text: (n > 0 ? "+" : "") + Self.format(n), color: color, big: abs(n) >= 40))
        }
        checkBest()
    }

    static func format(_ n: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: n.rounded())) ?? String(Int(n.rounded()))
    }

    func checkBest() {
        guard freeplay != nil, mode == .running else { return }
        if score > bestToBeat && bestToBeat > 0 && !bestShown {
            bestShown = true
            banner("New best score!", "#f2a91f")
        }
    }

    public var carsPerMinute: Double { t > 0 ? Double(cleared) / t * 60 : 0 }
    public var averageWait: Double { cleared > 0 ? waitSum / Double(cleared) : 0 }

    /// Stars: clear the goal, no crashes, patience never below 50%.
    public var starsEarned: [Bool] { [Double(cleared) >= level.goal, crashes == 0, minPatience >= Self.starPatience] }

    // MARK: Traffic flow

    func flowGlobal() -> Double {
        let st = Self.flowStyles[flow.style]!
        let x = Swift.min(1, t / Self.flowRamp)
        let ramp = 0.12 + 0.88 * x * x * (3 - 2 * x)
        let tide = 1 + st.tide * (0.65 * sin((2 * Double.pi * t) / 80 + flow.p1) + 0.35 * sin((2 * Double.pi * t) / 33 + flow.p2))
        var spell = 1.0
        if let s = flow.spell {
            let env = Swift.max(0, Swift.min(1, (t - s.from) / 3, (s.until - t) / 3))
            spell = 1 + (s.k - 1) * env
        }
        return ramp * tide * spell
    }

    func flowBunch(_ road: String) -> Double {
        let b = flow.bunch[road]!
        let phase = (t + b.offset).truncatingRemainder(dividingBy: b.period) / b.period
        return 1 + Self.flowStyles[flow.style]!.bunch * cos(2 * Double.pi * phase)
    }

    func updateFlow() {
        let st = Self.flowStyles[flow.style]!
        if let s = flow.spell, t >= s.until {
            flow.spell = nil
            flow.nextSpell = t + rng.between(st.spellEvery)
        } else if flow.spell == nil && t >= flow.nextSpell {
            let surge = rng.next() < st.surgeShare
            let heavy = freeplay.map { Level.densityFactor($0.density) } ?? 1
            if surge {
                flow.spell = Spell(kind: "surge", k: st.surge, from: t, until: t + 10 + rng.next() * 8)
            } else {
                flow.spell = Spell(kind: "lull", k: Swift.min(st.lull, 0.75 / heavy), from: t, until: t + 12 + rng.next() * 8 + 4 * (heavy - 1))
            }
            if mode == .running { banner(surge ? "Wave of traffic coming" : "Traffic easing off", surge ? "#f2a91f" : "#7fb2e5") }
        }
    }

    /// What the traffic is doing right now, for the freeplay readout.
    public var flowLabel: String {
        if t < Self.flowRamp { return "Building up" }
        if let s = flow.spell { return s.kind == "surge" ? "Surge" : "Quiet spell" }
        let d = 0.65 * cos((2 * Double.pi * t) / 80 + flow.p1) / 80 + 0.35 * cos((2 * Double.pi * t) / 33 + flow.p2) / 33
        return d > 0.002 ? "Picking up" : d < -0.002 ? "Easing off" : "Steady"
    }

    func baseLaneRate(_ k: Direction) -> Double {
        let r = level.rate[k.road]!
        let prog = Swift.min(1, Double(cleared) / level.goal)
        return r[0] + (r[1] - r[0]) * prog
    }

    func laneRate(_ k: Direction) -> Double {
        let boost = rush?.dir == k ? Self.rushBoost : 1
        return baseLaneRate(k) * boost * flowGlobal() * flowBunch(k.road)
    }

    func laneRateCap(_ k: Direction) -> Double { baseLaneRate(k) * Self.rushBoost * flow.cap }

    func pickMove(_ k: Direction) -> Character {
        func has(_ m: Character) -> Bool { geometry.paths.contains { $0.dir == k && $0.move == m } }
        if !has("T") { return has("L") && (!has("R") || rng.next() < 0.5) ? "L" : "R" }
        if has("L") && rng.next() < level.left { return "L" }
        return has("R") && rng.next() < level.right ? "R" : "T"
    }

    // MARK: Spawning

    func laneTails() -> [String: Double] {
        var tails: [String: Double] = [:]
        for c in cars {
            let rear = c.s - c.len
            let k = c.path.laneKey
            if rear < c.path.A && (tails[k] == nil || rear < tails[k]!) { tails[k] = rear }
        }
        return tails
    }

    func makeCar(_ path: Path) -> Car {
        carSeq += 1
        return Car(id: carSeq, path: path, rng: rng)
    }

    func updateSpawns(_ dt: Double, _ tails: inout [String: Double]) {
        for k in Direction.allCases {
            guard !geometry.lanes[k]!.isEmpty, var sp = spawners[k] else { continue }
            sp.timer -= dt
            if sp.timer <= 0 {
                let cap = laneRateCap(k)
                if sp.pending.count < 20 && rng.next() * cap < laneRate(k) { sp.pending.append(pickMove(k)) }
                sp.timer = rng.exponential(mean: 1 / cap)
            }
            // Drivers stuck in a long queue off the map take another way.
            if sp.pending.count > 6 && rng.next() < dt * 0.04 * Double(sp.pending.count - 6) { sp.pending.removeLast() }
            if sp.pending.isEmpty {
                sp.blockedFor = 0
                spawners[k] = sp
                continue
            }
            var best: Path?
            var bestRoom = 4.0
            var at = -1
            var i = 0
            while i < sp.pending.count && best == nil {
                for p in geometry.paths where p.dir == k && p.move == sp.pending[i] {
                    let room = tails[p.laneKey].map { $0 - Self.minGap } ?? .infinity
                    if room > bestRoom { best = p; bestRoom = room; at = i }
                }
                i += 1
            }
            if let best = best {
                let car = makeCar(best)
                car.v = Swift.min(car.maxV, (2 * Self.brake * Swift.max(0, bestRoom)).squareRoot())
                cars.append(car)
                tails[best.laneKey] = -car.len
                sp.pending.remove(at: at)
                sp.blockedFor = 0
            } else {
                sp.blockedFor += dt
            }
            spawners[k] = sp
        }

        updateFlow()
        guard level.rush else { return }
        if let r = rush, t >= r.until { rush = nil }
        if rush == nil && t >= nextRush {
            rush = (dir: rng.pick(Direction.allCases.filter { !geometry.lanes[$0]!.isEmpty }), until: t + 12)
            nextRush = t + 22 + rng.next() * 10
        }
    }

    /// Approaches backed up off the map for more than a second, for the warning badges.
    public func backlog(_ k: Direction) -> (blocked: Bool, waiting: Int) {
        let sp = spawners[k]
        return (sp.map { $0.blockedFor > 1 } ?? false, sp?.pending.count ?? 0)
    }

    // MARK: Driving

    func goesOnYellow(_ c: Car, _ d: Double, _ left: Double) -> Bool {
        if !wrecks.isEmpty && wreckOnPath(c) { return false }
        if d > 40 + 170 * c.nerve { return false }
        if c.v < 20 && c.nerve < 0.6 { return false }
        let top = c.beater ? c.maxV * Self.beaterBoost : c.maxV
        let accel = c.beater ? c.accel * 1.6 : c.accel
        let tTop = (top - c.v) / accel, dTop = (c.v + top) / 2 * tTop
        let time = d <= dTop ? (-c.v + (c.v * c.v + 2 * accel * d).squareRoot()) / accel : tTop + (d - dTop) / top
        return time <= left * (0.45 + 0.9 * c.nerve)
    }

    func updateCars(_ dt: Double) {
        var byLane: [String: [Car]] = [:], byExit: [String: [Car]] = [:], byBox: [String: [Car]] = [:]
        for c in cars {
            byLane[c.path.laneKey, default: []].append(c)
            byExit[c.path.exitKey, default: []].append(c)
            byBox[c.path.boxKey, default: []].append(c)
        }
        // Crosswalks with someone on the road right now.
        var pedsOnRoad: [Int: [Pedestrian]] = [:]
        for ped in peds {
            let cw = geometry.crosswalks[ped.crosswalk]
            if ped.state != .crossing || ped.v <= cw.road0 - 4 || ped.v >= cw.road1 + 4 { continue }
            pedsOnRoad[ped.crosswalk, default: []].append(ped)
        }
        func crossingFor(_ cw: Int, _ c: Car) -> Bool { pedsOnRoad[cw]?.contains { $0.blocker !== c } ?? false }

        // Lanes held up by a driver's own mistake: nobody there loses patience.
        var mistakeLanes = Set<String>()
        for c in cars where c.hold > 0 && c.holdKind.map({ Self.mistakeKinds.contains($0) }) == true { mistakeLanes.insert(c.path.laneKey) }

        for c in cars {
            let p = c.path
            if c.racing && c.s > p.exitStart { c.racing = false }
            var vMax = c.racing ? c.maxV * Self.beaterBoost : c.maxV * (1 + 0.05 * sin(t * c.driftF + c.driftPh))

            // Slow down for the turn, each driver at their own pace.
            if let base = Self.turnSpeed[p.move] {
                let tv = base * c.turnK
                if c.s < p.exitStart + World.crosswalk + c.len {
                    vMax = Swift.min(vMax, (tv * tv + 2 * Self.brake * Swift.max(0, p.A - c.s)).squareRoot())
                }
            }

            // Gap to whoever is ahead in the same approach lane or exit lane.
            var gap = Double.infinity
            var lead: Car?
            for o in byLane[p.laneKey]! {
                if o === c || o.s <= c.s { continue }
                if o.path !== p && o.s - o.len >= p.A + 2 && !inTheWay(c, o) { continue }
                let gl = o.s - o.len - c.s
                if gl < gap { gap = gl; lead = o }
            }
            let ec = c.s - p.exitStart
            let cWaitingToMerge = p.merges && c.s < p.mergeAt
            var mergeCap = Double.infinity
            for o in byExit[p.exitKey]! {
                if o === c { continue }
                let eo = o.s - o.path.exitStart
                let oWaitingToMerge = o.path.merges && o.s < o.path.mergeAt
                if o.path !== p {
                    // Zipper merge, decided the same way from both sides.
                    if cWaitingToMerge && !oWaitingToMerge {
                        if eo <= 0 || mergesAhead(c, ec, o, eo) { continue }
                        let behind = eo - o.len - ec
                        if behind >= 0 {
                            gap = Swift.min(gap, behind)
                        } else {
                            gap = Swift.min(gap, Swift.max(0, p.mergeAt - c.s))
                            mergeCap = Swift.min(mergeCap, o.v * 0.75)
                        }
                        continue
                    }
                    if oWaitingToMerge && !cWaitingToMerge {
                        if eo > 0 && mergesAhead(o, eo, c, ec) && o.s > o.path.mergeAt - 90 { gap = Swift.min(gap, eo - o.len - ec) }
                        continue
                    }
                }
                if eo <= ec || (o.path !== p && eo <= 0) { continue }
                gap = Swift.min(gap, eo - o.len - ec)
            }
            // Turning drivers stop short of a crosswalk while anyone is crossing it.
            if p.move != "T" && !pedsOnRoad.isEmpty {
                for x in p.crossings {
                    if !crossingFor(x.crosswalk, c) || c.s >= x.s0 - 6 || x.s0 - c.s > 90 { continue }
                    if (c.v * c.v) / (2 * Self.hardBrake) <= x.s0 - c.s - 7 { gap = Swift.min(gap, x.s0 - 7 - c.s + c.gapPref) }
                }
            }
            if !pedsOnRoad.isEmpty && (p.move != "T" || c.v < 25) && pedNear(c) { gap = Swift.min(gap, c.gapPref) }
            // Stop short of wrecks on the road ahead.
            if !wrecks.isEmpty && c.s < p.len {
                for w in wrecks {
                    var q = 6.0
                    while q <= 72 {
                        if p.point(at: c.s + q).position.distance(to: Vec(w.x, w.y)) < 16 { gap = Swift.min(gap, q - 10); break }
                        q += 6
                    }
                }
            }
            // Mistake: a tailgater comes up on a stopped queue too fast and taps it.
            var tailgating = false
            if c.habit == "tailgate", !c.bumped, let lead = lead, lead.v < 3, lead.s <= lead.path.stopS,
               gap < 70, c.v > 25, c.s < p.stopS - 4 {
                if c.willBump == nil { c.willBump = rng.next() < 0.35 }
                tailgating = c.willBump! && c.v < 45
                if tailgating && gap <= 1 { bump(c, lead); continue }
            }
            if !tailgating { vMax = Swift.min(vMax, (2 * Self.brake * Swift.max(0, gap - c.gapPref - c.v * c.headway)).squareRoot()) }
            if mergeCap < vMax { vMax = Swift.min(vMax, Swift.max(mergeCap, c.v - Self.brake * dt)) }

            // Obey the signal while still before the stop line.
            var mustStop = false
            let gi = p.group
            if c.s <= p.stopS {
                let d = p.stopS - c.s
                var hold = false
                let g = groups[gi]
                if g.light == .red {
                    hold = c.commit != g.cycle
                    if !hold && c.v < 2 { hold = true; c.commit = -1; c.racing = false }
                    if !hold && c.racing && (c.v * c.v) / (2 * Self.hardBrake) <= d { hold = true; c.racing = false }
                } else if g.light == .yellow && c.commit != g.cycle {
                    let tooClose = (c.v * c.v) / (2 * Self.hardBrake) > d
                    if tooClose && c.v >= Self.minCommitSpeed {
                        c.commit = g.cycle
                    } else if c.decided != g.cycle {
                        c.decided = g.cycle
                        if goesOnYellow(c, d, Self.yellowTime - g.timer) {
                            c.commit = g.cycle
                            c.racing = c.beater
                        } else {
                            hold = true
                        }
                    } else {
                        hold = true
                    }
                }
                if !hold && !wrecks.isEmpty && wreckOnPath(c) { hold = true }
                if !hold && c.commit != groups[gi].cycle && exitBlocked(c, byBox[p.boxKey] ?? []) { hold = true }
                if hold {
                    mustStop = true
                    vMax = Swift.min(vMax, (2 * Self.brake * d).squareRoot())
                }
            }

            // A driver stranded in the box doesn't pull out across another car there.
            if c.v < 3 && c.s > p.stopS && c.s < p.exitStart && vMax > 0 {
                let cross = geometry.conflicts[gi]
                for o in cars {
                    if o === c || o.s <= o.path.stopS || o.s - o.len >= o.path.exitStart || !cross.contains(o.path.group) { continue }
                    if o.v >= 3 || o.id < c.id { vMax = 0; break }
                }
            }

            // Pulling away from a stop takes a moment; some drivers take longer.
            if c.v < 1 { c.stoppedFor += dt } else if c.v > 5 { c.stoppedFor = 0; c.starting = false }
            if c.v < 1 && c.stoppedFor > 0.3 && vMax > 5 && c.hold <= 0 && !c.starting {
                c.starting = true
                c.hold = c.react
                c.holdKind = "react"
                if c.habit == "distracted" && rng.next() < 0.6 {
                    c.hold += 1.2 + rng.next() * 1.5
                    c.holdKind = "distracted"
                } else if c.habit == "stall" && rng.next() < 0.5 {
                    c.hold += 2 + rng.next() * 1.5
                    c.holdKind = "stall"
                }
            }
            if c.hold > 0 {
                c.hold -= dt
                vMax = 0
                if c.hold <= 0 { c.holdKind = nil }
            }

            let accel = c.racing ? c.accel * 1.6 : c.accel
            if c.v < vMax { c.v = Swift.min(vMax, c.v + accel * dt) } else { c.v = Swift.max(vMax, c.v - Self.hardBrake * 1.5 * dt) }
            let before = c.s
            c.s += c.v * dt
            if mustStop && before <= p.stopS && c.s > p.stopS { c.s = p.stopS; c.v = 0 }
            if before <= p.stopS && c.s > p.stopS && groups[gi].light == .green { groups[gi].passed += 1 }

            if c.v < 4 && c.s <= p.stopS + 1 && !mistakeLanes.contains(p.laneKey) { c.wait += dt }
        }

        // Cars that left the map count as cleared.
        var keep: [Car] = []
        for c in cars {
            if c.s - c.len > c.path.len { carCleared(c) } else { keep.append(c) }
        }
        cars = keep
    }

    func mergesAhead(_ m: Car, _ em: Double, _ t: Car, _ et: Double) -> Bool {
        let room = em - m.len - et
        return room >= 2 && (t.v * t.v) / (2 * Self.brake) <= room + 20
    }

    /// Three circles along a car's body, for collisions.
    public func bodyCircles(_ c: Car) -> [(Vec, Double)] {
        let r = c.wid / 2 - 1
        return [0.18, 0.5, 0.82].map { f in (c.path.point(at: c.s - c.len * f).position, r) }
    }

    func pedPosition(_ ped: Pedestrian, v: Double? = nil, du: Double? = nil) -> Vec {
        geometry.crosswalks[ped.crosswalk].point(v ?? ped.v, du ?? ped.du)
    }

    func pedNear(_ c: Car) -> Bool {
        let mid = c.path.point(at: c.s - c.len / 2).position
        var body: [(Vec, Double)]?
        for ped in peds where ped.state == .crossing {
            let at = pedPosition(ped)
            if at.distance(to: mid) > c.len / 2 + 30 { continue }
            if body == nil { body = bodyCircles(c) }
            if ped.blocker !== c && body!.contains(where: { at.distance(to: $0.0) < $0.1 + 8 }) { return true }
            var q = 0.0
            while q <= 18 {
                if c.path.point(at: c.s + q).position.distance(to: at) < c.wid / 2 + 7 { return true }
                q += 6
            }
        }
        return false
    }

    func inTheWay(_ c: Car, _ o: Car) -> Bool {
        let oc = bodyCircles(o)
        var q = 2.0
        while q <= 20 {
            let pt = c.path.point(at: c.s + q).position
            if oc.contains(where: { pt.distance(to: $0.0) < $0.1 + c.wid / 2 }) { return true }
            q += 6
        }
        return false
    }

    func bump(_ c: Car, _ lead: Car) {
        c.s = lead.s - lead.len - 3
        c.v = 0
        c.bumped = true
        for car in [c, lead] {
            car.hold = Swift.max(car.hold, 2.5)
            car.holdKind = "bump"
            car.starting = true
        }
        let at = c.path.point(at: c.s).position
        for _ in 0..<3 {
            let ang = rng.next() * Double.pi * 2, sp = 30 + rng.next() * 40
            particles.append(Particle(kind: .spark, x: at.x, y: at.y, vx: cos(ang) * sp, vy: sin(ang) * sp, max: 0.2 + rng.next() * 0.25))
        }
        flashes.append(Flash(x: at.x, y: at.y, kind: "bump"))
    }

    func exitBlocked(_ c: Car, _ others: [Car]) -> Bool {
        for o in others where o !== c {
            let eo = o.s - o.path.exitStart
            if eo > 0 && eo - o.len < c.len + 6 && o.v < 15 { return true }
        }
        return false
    }

    func wreckOnPath(_ c: Car) -> Bool {
        let p = c.path
        var s = p.stopS
        while s <= p.exitStart + 30 {
            let pt = p.point(at: s).position
            for w in wrecks where pt.distance(to: Vec(w.x, w.y)) < 18 { return true }
            s += 8
        }
        return false
    }

    // MARK: Scoring

    func carCleared(_ c: Car) {
        guard failAt == nil else { return }
        cleared += 1
        patience = Swift.min(100, patience + Self.refillPerCar)
        waitSum += c.wait
        worstWait = Swift.max(worstWait, c.wait)
        streak += 1
        let newMult = Swift.min(Self.maxCombo, 1 + 0.5 * floor(Double(streak) / Double(Self.comboStep)))
        if newMult > mult {
            banner("\(streak) in a row · ×\(Self.trim(newMult))", "#f2a91f")
            sound("combo")
        }
        mult = newMult
        addPoints((Self.carPoints * mult).rounded(), c.path.point(at: c.path.len - World.pad - 22).position, "#f2f6f3")
    }

    /// 1.5 → "1.5", 2.0 → "2", like JavaScript prints numbers.
    static func trim(_ x: Double) -> String { x == x.rounded() ? String(Int(x)) : String(x) }

    func breakStreak(_ why: String, _ at: Vec? = nil) {
        if streak >= Self.comboStep {
            banner("Streak lost · \(why)", "#ff8a8d")
            sound("streak")
            if let at = at { popups.append(Popup(x: at.x, y: at.y - 14, text: "HONK!", color: "#ff8a8d", big: false)) }
        }
        streak = 0
        mult = 1
    }

    func greenWave(_ i: Int) {
        let g = groups[i]
        guard g.kind == .car, g.passed >= Self.waveMin, mode == .running else { return }
        if cars.contains(where: { $0.path.group == i && $0.s <= $0.path.stopS && $0.s > $0.path.stopS - 140 }) { return }
        let bonus = Double(g.passed * Self.wavePoints)
        let lamp = geometry.lamps.first { $0.group == i }
        addPoints(bonus, lamp.map { Vec($0.position.x, $0.position.y - 12) }, "#30c070")
        banner("Green wave · \(g.passed) cars · +\(Int(bonus))", "#30c070")
        sound("wave")
    }

    // MARK: Emergency vehicles

    func updateEmergency(_ tails: inout [String: Double]) {
        if !emergencyOn { emergency = nil; return }
        guard var em = emergency else {
            if t < nextEmergency { return }
            let dirs = Direction.allCases.filter { k in geometry.paths.contains { $0.dir == k && $0.move == "T" } }
            if dirs.isEmpty { return }
            let k = rng.pick(dirs), kind = rng.pick(EmergencyKind.all)
            emergency = Emergency(phase: .warn, dir: k, kind: kind, spawnAt: t + Self.emergencyWarn)
            banner("\(kind.name) from the \(Self.from[k]!) · clear \(k.name)!", "#ff5a5f")
            sound("siren")
            return
        }
        if em.phase == .warn {
            if t < em.spawnAt { return }
            var best: Path?
            var room = -Double.infinity
            for p in geometry.paths where p.dir == em.dir && p.move == "T" {
                let r = tails[p.laneKey].map { $0 - Self.minGap } ?? .infinity
                if r > room { room = r; best = p }
            }
            guard let path = best, room >= em.kind.len + 4 else { return }
            let c = makeCar(path)
            c.color = em.kind.color
            c.len = em.kind.len
            c.wid = em.kind.wid
            c.truck = false
            c.emergency = em.kind
            c.maxV = 135; c.accel = 230; c.gapPref = 6; c.headway = 0.1; c.turnK = 1; c.react = 0.1
            c.habit = nil; c.beater = false; c.nerve = 1
            c.v = Swift.min(c.maxV, (2 * Self.brake * Swift.max(0, room)).squareRoot())
            tails[path.laneKey] = -c.len
            cars.append(c)
            em.phase = .active
            em.car = c
            em.lastT = t
            em.held = 0
            em.limit = nil
            em.nextHit = nil
            em.penalised = false
            emergency = em
            return
        }
        guard let c = em.car, cars.contains(where: { $0 === c }) else {
            emergencyPenalty(nil, "\(em.kind.name) wrecked")
            endEmergency()
            return
        }
        let at = c.path.point(at: c.s - c.len / 2).position
        let dt = t - em.lastT
        em.lastT = t
        if c.s > c.path.stopS {
            if !em.penalised {
                addPoints(Self.emergencyBonus, Vec(at.x, at.y - 16), "#30c070")
                banner("Clear path for the \(em.kind.name.lowercased()) · +\(Int(Self.emergencyBonus))", "#30c070")
                sound("clear")
            }
            emergency = em
            endEmergency()
            return
        }
        // Only time spent stopped counts.
        if c.v > 6 { emergency = em; return }
        if em.limit == nil {
            let ahead = cars.filter { $0 !== c && $0.path.laneKey == c.path.laneKey && $0.s > c.s && $0.s <= $0.path.stopS + 1 }.count
            em.limit = Self.emergencyHold + Double(ahead) * Self.emergencyPerQueued
        }
        em.held += dt
        if em.held >= (em.nextHit ?? em.limit!) {
            em.nextHit = em.held + Self.emergencyAgain
            em.penalised = true
            emergency = em
            emergencyPenalty(Vec(at.x, at.y - 16), "\(em.kind.name) held up")
        }
        emergency = em
    }

    func emergencyPenalty(_ at: Vec?, _ text: String) {
        sound("held")
        breakStreak(text.lowercased())
        addPoints(-Self.emergencyPenaltyPoints, at, "#ff8a8d")
        banner("\(text) · −\(Int(Self.emergencyPenaltyPoints))", "#ff5a5f")
        if hasLimits { patience = Swift.max(0, patience - Self.emergencyPatience) }
    }

    func endEmergency() {
        emergency = nil
        nextEmergency = t + rng.between(Self.emergencyEvery)
    }

    /// The emergency still waiting on the player: announced, or on its way to the stop line.
    public var pendingEmergency: Emergency? {
        guard let em = emergency else { return nil }
        if em.phase == .warn { return em }
        if let c = em.car, c.s <= c.path.stopS { return em }
        return nil
    }

    // MARK: Pedestrians

    func legDims(_ k: Direction) -> (far: Double, R: Double, L0: Double, L1: Double, m0: Double, m1: Double) {
        let l = geometry.legDims(k)
        return (l.far, l.R, l.L0, l.L1, l.m0, l.m1)
    }

    func arrivalRoute(crosswalk: Int, dir: Double, du: Double, start: Double, back: Double) -> Pedestrian.Route {
        let cw = geometry.crosswalks[crosswalk]
        let k = cw.leg
        let dims = legDims(k)
        let half = World.sidewalk / 2
        let wait = (u: cw.uc + du * 0.7, v: start - dir * back)
        let pts: [Vec] = dir > 0
            ? [k.point(dims.far - 10, -dims.L1 - half), k.point(dims.m1, -dims.L1 - half), k.point(dims.m0, -dims.L0 - half),
               k.point(wait.u - 10, -dims.L0 - half), k.point(wait.u, wait.v)]
            : [k.point(dims.far - 10, dims.R + half), k.point(wait.u - 10, dims.R + half), k.point(wait.u, wait.v)]
        var cum = [0.0]
        for i in 1..<pts.count { cum.append(cum[i - 1] + pts[i].distance(to: pts[i - 1])) }
        return Pedestrian.Route(pts: pts, cum: cum, len: cum[cum.count - 1])
    }

    func updatePeds(_ dt: Double) {
        let rate = level.peds ?? 0
        if rate != 0 {
            let cap = rate * flow.cap, now = rate * flowGlobal()
            for i in pedSpawners.indices {
                pedSpawners[i].timer -= dt
                if pedSpawners[i].timer > 0 { continue }
                pedSpawners[i].timer = rng.exponential(mean: 1 / cap)
                if rng.next() * cap >= now { continue }
                let sp = pedSpawners[i]
                let waiting = peds.filter { $0.crosswalk == sp.crosswalk && $0.dir == sp.dir && $0.state != .crossing }.count
                if waiting >= 6 { continue }
                let cw = geometry.crosswalks[sp.crosswalk]
                let start = sp.dir > 0 ? cw.road0 - 9 : cw.road1 + 9
                let ped = Pedestrian(crosswalk: sp.crosswalk, dir: sp.dir, start: start, waiting: waiting, rng: rng) { du, start, back in
                    self.arrivalRoute(crosswalk: sp.crosswalk, dir: sp.dir, du: du, start: start, back: back)
                }
                peds.append(ped)
            }
        }
        for ped in peds {
            let gi = geometry.crosswalks[ped.crosswalk].group
            if ped.state == .arriving {
                ped.routeAt += ped.speed * 1.1 * dt
                ped.phase += dt * 10
                if ped.routeAt >= ped.route.len { ped.state = .waiting }
                continue
            }
            if ped.state == .waiting {
                if groups[gi].light == .green && !carsInTheWay(ped) { ped.state = .crossing } else { ped.wait += dt }
            } else {
                let blocker = carAhead(ped)
                ped.blocker = blocker
                if blocker != nil && ped.paused < Self.pedPatience {
                    ped.paused += dt
                } else if ped.paused >= Self.pedPatience && blocker != nil && sidestep(ped, dt) {
                    ped.phase += dt * 10
                } else {
                    if ped.paused < Self.pedPatience && blocker == nil { ped.paused = 0 }
                    ped.sideTo = nil
                    ped.v += ped.dir * ped.speed * (groups[gi].light == .green ? 1 : 1.5) * dt
                    ped.phase += dt * 10
                }
            }
        }
        peds = peds.filter { p in
            let cw = geometry.crosswalks[p.crosswalk]
            return !(p.state == .crossing && (p.dir > 0 ? p.v > cw.road1 + 10 : p.v < cw.road0 - 10))
        }
    }

    func onCrosswalk(_ cw: Crosswalk, _ pt: Vec, _ pad: Double) -> Bool {
        let d = cw.leg.heading, r = cw.leg.right
        let u = (pt.x - World.cx) * d.x + (pt.y - World.cy) * d.y, v = (pt.x - World.cx) * r.x + (pt.y - World.cy) * r.y
        return abs(u - cw.uc) <= World.crosswalk / 2 + pad && v >= cw.road0 - pad && v <= cw.road1 + pad
    }

    func carsInTheWay(_ ped: Pedestrian) -> Bool {
        let cw = geometry.crosswalks[ped.crosswalk]
        for c in cars {
            if c.v < 3 || abs(c.s - c.path.A) > 160 { continue }
            for lookAhead in [0, 0.35, 0.7, 1.0] {
                let ahead = c.s + c.v * lookAhead
                for f in [0, 0.5, 1.0] where onCrosswalk(cw, c.path.point(at: ahead - c.len * f).position, 3) { return true }
            }
        }
        return false
    }

    func sidestep(_ ped: Pedestrian, _ dt: Double) -> Bool {
        var target = ped.sideTo
        if let tg = target, carAhead(ped, du: tg) != nil { target = nil }
        var k = 3.0
        while k <= 30 && target == nil {
            for du in [ped.du - k, ped.du + k] where carAhead(ped, du: du) == nil {
                target = du
                break
            }
            k += 3
        }
        guard let goal = target else { return false }
        ped.sideTo = goal
        let stepLen = ped.speed * dt
        ped.du += Swift.max(-stepLen, Swift.min(stepLen, goal - ped.du))
        return true
    }

    func carAhead(_ ped: Pedestrian, du: Double? = nil) -> Car? {
        let next = pedPosition(ped, v: ped.v + ped.dir * 7, du: du ?? ped.du)
        for c in cars {
            if next.distance(to: c.path.point(at: c.s - c.len / 2).position) > 30 { continue }
            if bodyCircles(c).contains(where: { next.distance(to: $0.0) < $0.1 + 4 }) { return c }
        }
        return nil
    }

    func detectPedHits() {
        for ped in peds {
            let cw = geometry.crosswalks[ped.crosswalk]
            if ped.state != .crossing || ped.v < cw.road0 - 2 || ped.v > cw.road1 + 2 { continue }
            let at = pedPosition(ped)
            for c in cars {
                if ped.blocker === c { continue }
                if c.v < Self.minHitSpeed || at.distance(to: c.path.point(at: c.s - c.len / 2).position) > 30 { continue }
                if bodyCircles(c).contains(where: { at.distance(to: $0.0) < $0.1 + 3.5 }) { pedHit(ped, c, at); break }
            }
        }
        peds = peds.filter { !$0.hit }
    }

    func pedHit(_ ped: Pedestrian, _ car: Car, _ at: Vec) {
        ped.hit = true
        car.v = 0
        car.hold = 3
        car.holdKind = "hit"
        car.starting = true
        for _ in 0..<12 {
            let ang = rng.next() * Double.pi * 2, sp = 40 + rng.next() * 90
            particles.append(Particle(kind: .spark, x: at.x, y: at.y, vx: cos(ang) * sp, vy: sin(ang) * sp, max: 0.3 + rng.next() * 0.3))
        }
        flashes.append(Flash(x: at.x, y: at.y, kind: "hit"))
        registerCrash("Someone was hit in a crosswalk.", at, Self.pedHitPenalty)
    }

    // MARK: Crashes

    func detectCrashes() {
        let zone = cars.filter { $0.s > $0.path.A - 6 && $0.s - $0.len < $0.path.exitStart + 6 }
        let circles = zone.map { self.bodyCircles($0) }
        var hit = Set<ObjectIdentifier>()
        for i in zone.indices {
            for j in (i + 1)..<Swift.max(i + 1, zone.count) {
                let a = zone[i], b = zone[j]
                if a.path === b.path || a.path.laneKey == b.path.laneKey { continue }
                if hit.contains(ObjectIdentifier(a)) || hit.contains(ObjectIdentifier(b)) { continue }
                var touch = false
                outer: for ca in circles[i] {
                    for cb in circles[j] where ca.0.distance(to: cb.0) < ca.1 + cb.1 {
                        touch = true
                        break outer
                    }
                }
                if touch {
                    hit.insert(ObjectIdentifier(a))
                    hit.insert(ObjectIdentifier(b))
                    crash(a, b)
                }
            }
        }
        if !hit.isEmpty { cars = cars.filter { !hit.contains(ObjectIdentifier($0)) } }
    }

    func crash(_ a: Car, _ b: Car) {
        let poses = [a, b].map { c in (c, c.path.point(at: c.s - c.len / 2)) }
        let mid = Vec((poses[0].1.position.x + poses[1].1.position.x) / 2, (poses[0].1.position.y + poses[1].1.position.y) / 2)
        for (c, pose) in poses {
            let push = c.v * 0.55
            let spin = (rng.next() < 0.5 ? -1.0 : 1.0) * (2 + rng.next() * 4)
            wrecks.append(Wreck(x: pose.position.x, y: pose.position.y, angle: pose.angle,
                                vx: cos(pose.angle) * push, vy: sin(pose.angle) * push, spin: spin,
                                len: c.len, wid: c.wid, color: c.color, truck: c.truck))
        }
        for _ in 0..<26 {
            let ang = rng.next() * Double.pi * 2, sp = 90 + rng.next() * 220
            particles.append(Particle(kind: .spark, x: mid.x, y: mid.y, vx: cos(ang) * sp, vy: sin(ang) * sp, max: 0.3 + rng.next() * 0.5))
        }
        for _ in 0..<12 {
            let ang = rng.next() * Double.pi * 2, sp = 40 + rng.next() * 110
            let mx = 1.6 + rng.next()
            let size = 2 + rng.next() * 3
            let color = rng.pick([a.color, b.color, "#cfd6dc", "#1c2126"])
            let rot = rng.next() * 6
            let spin = (rng.next() - 0.5) * 12
            particles.append(Particle(kind: .debris, x: mid.x, y: mid.y, vx: cos(ang) * sp, vy: sin(ang) * sp,
                                      max: mx, size: size, color: color, rot: rot, spin: spin))
        }
        flashes.append(Flash(x: mid.x, y: mid.y, kind: nil))
        registerCrash("", mid, Self.crashPenalty)
    }

    func registerCrash(_ note: String, _ at: Vec?, _ penalty: Double) {
        if failAt != nil || (hasLimits && Double(cleared) >= level.goal) { return }
        sound("crash")
        breakStreak("crash")
        addPoints(-penalty, at.map { Vec($0.x, $0.y - 18) }, "#ff8a8d")
        shake = shakeOn ? 0.5 : 0
        crashes += 1
        patience = Swift.max(0, patience - Self.crashPatience)
        if hasLimits && crashes >= Self.maxCrashes && failAt == nil {
            failAt = t + 1.8
            failReason = "\(Self.maxCrashes) crashes. \(note.isEmpty ? "" : note + " ")The city pulled you off signal duty."
        }
    }

    /// Wrecks drift and smoke, particles fly, popups and banners fade.
    public func updateEffects(_ dt: Double) {
        for i in wrecks.indices {
            wrecks[i].t += dt
            wrecks[i].x += wrecks[i].vx * dt
            wrecks[i].y += wrecks[i].vy * dt
            let f = exp(-4 * dt)
            wrecks[i].vx *= f
            wrecks[i].vy *= f
            wrecks[i].angle += wrecks[i].spin * dt
            wrecks[i].spin *= exp(-3 * dt)
            wrecks[i].smokeTimer -= dt
            if wrecks[i].t < 3.5 && wrecks[i].smokeTimer <= 0 {
                wrecks[i].smokeTimer = 0.14
                let x = wrecks[i].x + (rng.next() - 0.5) * 8
                let y = wrecks[i].y + (rng.next() - 0.5) * 8
                let vx = 6 + rng.next() * 8
                let vy = -8 - rng.next() * 8
                let mx = 1.4 + rng.next() * 0.6
                particles.append(Particle(kind: .smoke, x: x, y: y, vx: vx, vy: vy, max: mx))
            }
        }
        wrecks = wrecks.filter { $0.t < Self.wreckTime }

        for i in particles.indices {
            particles[i].life += dt
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt
            let drag = particles[i].kind == .spark ? 3.0 : particles[i].kind == .debris ? 4.0 : 0.6
            let f = exp(-drag * dt)
            particles[i].vx *= f
            particles[i].vy *= f
            if let rot = particles[i].rot {
                particles[i].rot = rot + particles[i].spin * dt
                particles[i].spin *= f
            }
        }
        particles = particles.filter { $0.life < $0.max }
        for i in flashes.indices { flashes[i].t += dt }
        flashes = flashes.filter { $0.t < 1.4 }
        for i in popups.indices { popups[i].t += dt }
        popups = popups.filter { $0.t < ($0.big ? 1.4 : 0.9) }
        if !banners.isEmpty {
            banners[0].t += dt
            if banners[0].t > 1.8 { banners.removeFirst() }
        }
        shake = Swift.max(0, shake - dt)
    }

    // MARK: Patience, busy groups, win and lose

    func isAngry(_ c: Car) -> Bool { c.wait > level.angry && c.s <= c.path.stopS + 1 }

    func updateStatus(_ dt: Double) {
        for i in groups.indices { groups[i].busy = 0 }
        var angry = 0
        for c in cars {
            let p = c.path
            let grp = groups[p.group]
            let committed = c.commit == grp.cycle && grp.light != .green
            if (c.s > p.stopS + 0.5 || c.racing || committed) && c.s - c.len < p.exitStart { groups[p.group].busy += 1 }
            if isAngry(c) {
                angry += 1
                if !c.honked {
                    c.honked = true
                    breakStreak("a driver waited too long", p.point(at: c.s - c.len / 2).position)
                }
            }
        }
        for ped in peds {
            let cw = geometry.crosswalks[ped.crosswalk]
            if ped.state == .crossing && ped.v > cw.road0 - 4 && ped.v < cw.road1 + 4 { groups[cw.group].busy += 1 }
            if ped.state == .waiting && ped.wait > level.angry {
                angry += 1
                if !ped.honked {
                    ped.honked = true
                    breakStreak("someone waited too long to cross")
                }
            }
        }
        var blocked = 0
        for k in Direction.allCases where (spawners[k]?.blockedFor ?? 0) > 1 { blocked += 1 }
        let drain = Swift.min(Self.maxDrain, Double(angry) * Self.drainPerAngry + Double(blocked) * Self.drainPerBlocked)
        patience = Swift.max(0, patience - drain * dt)
        minPatience = Swift.min(minPatience, patience)
        guard hasLimits else { return }

        if failAt == nil {
            if Double(cleared) >= level.goal {
                win()
                return
            }
            if patience <= 0 {
                patience = 0
                failAt = t + 0.3
                failReason = "Drivers waited too long and the city ran out of patience."
            }
        }
        if let at = failAt, t >= at { lose() }
    }

    func win() {
        sound("win")
        mode = .won
        events.append(.won)
    }

    func lose() {
        sound("lose")
        mode = .lost
        events.append(.lost(failReason))
    }
}
