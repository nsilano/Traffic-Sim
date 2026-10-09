import Foundation

/// A signal group the player switches: cars (a set of lanes and moves) or a walk signal.
public struct SignalGroup {
    public enum Light { case red, yellow, green }
    public enum Kind { case car, walk }

    public let kind: Kind
    public let label: String
    /// Car groups: the directions it covers and its move ("T", "L" or "A").
    public let dirs: [Direction]
    public let move: String
    /// Walk groups: the crosswalk legs.
    public let legs: [Direction]
    public internal(set) var light: Light
    public internal(set) var timer = 0.0
    /// Goes up each time the group turns yellow, so a driver's yellow-light decision belongs to one cycle.
    public internal(set) var cycle = 0
    /// Cars or people still in the box (or on the crosswalk) for this group.
    public internal(set) var busy = 0
    /// Cars through on the current green, for the Green Wave bonus.
    public internal(set) var passed = 0
}

/// Driver types: top speed range, acceleration, gap when stopped, reaction time,
/// turning pace and extra following time at speed.
public enum DriverType: String, CaseIterable {
    case commuter, speeder, cautious, truck

    struct Profile { let maxV: [Double]; let accel: Double; let gap: Double; let react: [Double]; let turn: [Double]; let headway: [Double] }

    var profile: Profile {
        switch self {
        case .commuter: return Profile(maxV: [92, 115], accel: 150, gap: 8, react: [0.25, 0.6], turn: [0.88, 1.12], headway: [0, 0.04])
        case .speeder: return Profile(maxV: [128, 150], accel: 215, gap: 5, react: [0.15, 0.35], turn: [1.02, 1.22], headway: [0, 0])
        case .cautious: return Profile(maxV: [70, 88], accel: 110, gap: 12, react: [0.5, 0.95], turn: [0.76, 0.95], headway: [0.03, 0.1])
        case .truck: return Profile(maxV: [72, 86], accel: 95, gap: 10, react: [0.4, 0.7], turn: [0.74, 0.9], headway: [0.03, 0.08])
        }
    }

    /// How readily each kind runs a yellow, 0 (never) to 1.
    var nerve: [Double] {
        switch self {
        case .speeder: return [0.55, 1]
        case .commuter: return [0.25, 0.8]
        case .cautious: return [0, 0.3]
        case .truck: return [0.15, 0.55]
        }
    }
}

/// An emergency vehicle's kind.
public struct EmergencyKind: Equatable {
    public let name: String
    public let color: String
    public let stripe: String
    public let len: Double
    public let wid: Double

    public static let all = [
        EmergencyKind(name: "Ambulance", color: "#f4f6f8", stripe: "#e5484d", len: 32, wid: 15),
        EmergencyKind(name: "Fire engine", color: "#d8322e", stripe: "#f4f6f8", len: 42, wid: 16),
        EmergencyKind(name: "Police car", color: "#1b2430", stripe: "#f4f6f8", len: 25, wid: 14),
    ]
}

public final class Car {
    public let id: Int
    public let path: Path
    /// Distance of the car's nose along its path, and its speed.
    public internal(set) var s = 0.0
    public internal(set) var v = 0.0
    public internal(set) var len: Double
    public internal(set) var wid: Double
    public internal(set) var color: String
    public internal(set) var truck: Bool
    public let type: DriverType
    var maxV: Double
    var accel: Double
    var react: Double
    var gapPref: Double
    var headway: Double
    var turnK: Double
    var driftF: Double
    var driftPh: Double
    /// Speeds up to beat a yellow; `racing` while doing it.
    public internal(set) var beater: Bool
    public internal(set) var racing = false
    var nerve: Double
    /// "distracted", "stall" or "tailgate", or nil.
    var habit: String?
    var bumped = false
    var willBump: Bool?
    /// Seconds spent waiting at the line, in total (for the stats).
    public internal(set) var wait = 0.0
    /// Seconds waiting at the front of the line since last moving: what patience runs on.
    public internal(set) var lightWait = 0.0
    /// The yellow cycle this driver committed to going on, and the one they last decided on.
    var commit = -1
    var decided = -1
    /// Seconds before pulling away, and why ("react", "distracted", "stall", "bump", "hit").
    public internal(set) var hold = 0.0
    public internal(set) var holdKind: String?
    var stoppedFor = 0.0
    var starting = false
    var honked = false
    public internal(set) var emergency: EmergencyKind?

    /// The driver's normal top speed (brake lights show below half of it).
    public var topSpeed: Double { maxV }

    init(id: Int, path: Path, rng: Random) {
        // The order of draws matches makeCar() in game.js exactly.
        self.id = id
        self.path = path
        let truck = rng.next() < 0.12
        let r = rng.next()
        let type: DriverType = truck ? .truck : r < 0.2 ? .speeder : r < 0.35 ? .cautious : .commuter
        let beater = rng.next() < Simulation.beaterShare
        let prof = type.profile
        let h = rng.next()
        habit = h < 0.08 ? "distracted" : h < 0.08 + 0.03 ? "stall" : h < 0.08 + 0.03 + 0.015 ? "tailgate" : nil
        len = truck ? 38 : 22 + rng.next() * 6
        wid = truck ? 17 : 14
        color = truck ? rng.pick(Simulation.truckColors) : rng.pick(Simulation.carColors)
        self.truck = truck
        self.type = type
        maxV = rng.between(prof.maxV)
        accel = prof.accel * rng.between([0.85, 1.15])
        react = rng.between(prof.react)
        gapPref = prof.gap * rng.between([0.75, 1.5])
        headway = rng.between(prof.headway)
        turnK = rng.between(prof.turn)
        driftF = 0.15 + rng.next() * 0.35
        driftPh = rng.next() * Double.pi * 2
        self.beater = beater
        nerve = beater ? 1 : rng.between(type.nerve)
    }
}

public final class Pedestrian {
    public let crosswalk: Int
    /// +1 crosses from the driver's left to right (road0 to road1), -1 the other way.
    public let dir: Double
    /// Position across the road, and along it (stepping around cars).
    public internal(set) var v: Double
    public internal(set) var du: Double
    let start: Double
    let back: Double
    let speed: Double
    public let color: String
    public enum State { case arriving, waiting, crossing, leaving }
    public internal(set) var state = State.arriving
    public internal(set) var wait = 0.0
    /// Walk-cycle phase, for drawing.
    public internal(set) var phase: Double
    var paused = 0.0
    /// The walk in to the corner, or (once across) the walk off the map.
    public internal(set) var route: Route
    public internal(set) var routeAt = 0.0
    weak var blocker: Car?
    var sideTo: Double?
    var hit = false
    var honked = false
    var gone = false

    /// Where across the road this person stands while waiting at the corner.
    public var waitV: Double { start - dir * back }

    /// A walk along the sidewalk: in from off the board to the corner, or back off it.
    public struct Route {
        public let pts: [Vec]
        public let cum: [Double]
        public let len: Double

        public func point(at distance: Double) -> (position: Vec, angle: Double) {
            let at = distance
            var i = 1
            while i < pts.count - 1 && cum[i] < at { i += 1 }
            let a = pts[i - 1], b = pts[i]
            let span = cum[i] - cum[i - 1]
            let t = min(1, max(0, (at - cum[i - 1]) / (span != 0 ? span : 1)))
            return (Vec(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t), atan2(b.y - a.y, b.x - a.x))
        }
    }

    init(crosswalk: Int, dir: Double, start: Double, waiting: Int, rng: Random, route: (Double, Double, Double) -> Route) {
        // Draws in the same order as game.js.
        let du = (rng.next() - 0.5) * (World.crosswalk - 10)
        let back = Double(waiting) * 5 + rng.next() * 3
        let speed = 26 + rng.next() * 16
        let color = rng.pick(Simulation.pedColors)
        let phase = rng.next() * 6
        self.crosswalk = crosswalk
        self.dir = dir
        v = start
        self.start = start
        self.du = du
        self.back = back
        self.speed = speed
        self.color = color
        self.phase = phase
        self.route = route(du, start, back)
    }
}

public struct Wreck {
    public var x, y, angle: Double
    var vx, vy, spin: Double
    public let len, wid: Double
    public let color: String
    public let truck: Bool
    public var t = 0.0
    var smokeTimer = 0.0
}

public struct Particle {
    public enum Kind { case spark, debris, smoke }
    public let kind: Kind
    public var x, y: Double
    var vx, vy: Double
    public var life = 0.0
    public let max: Double
    public var size = 0.0
    public var color = ""
    public var rot: Double?
    var spin = 0.0

    public var velocity: Vec { Vec(vx, vy) }
}

public struct Flash {
    public let x, y: Double
    public var t = 0.0
    /// nil for a crash, "bump" or "hit".
    public let kind: String?
}

public struct Popup {
    public let x, y: Double
    public let text: String
    public let color: String
    public var t = 0.0
    public let big: Bool
}

public struct Banner {
    public let text: String
    public let color: String
    public var t = 0.0
}

/// What the simulation asks the app to do: play a sound or a haptic, or end the shift.
public enum SimEvent: Equatable {
    case sound(String)
    case haptic(String)
    case won
    case lost(String)
}
