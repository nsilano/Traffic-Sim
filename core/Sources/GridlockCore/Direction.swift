/// A direction of travel. `heading` is where the traffic goes; `right` points to the driver's right.
public enum Direction: String, CaseIterable, Codable {
    // Same order as game.js (DIR_KEYS), which the order of paths and lamps depends on.
    case N, S, E, W

    public var name: String {
        switch self {
        case .N: return "Northbound"
        case .S: return "Southbound"
        case .E: return "Eastbound"
        case .W: return "Westbound"
        }
    }

    /// The road this direction runs on: "NS" or "EW".
    public var road: String { self == .N || self == .S ? "NS" : "EW" }

    public var heading: Vec {
        switch self {
        case .N: return Vec(0, -1)
        case .S: return Vec(0, 1)
        case .E: return Vec(1, 0)
        case .W: return Vec(-1, 0)
        }
    }

    public var right: Vec { Vec(-heading.y, heading.x) }

    public var opposite: Direction {
        switch self {
        case .N: return .S
        case .S: return .N
        case .E: return .W
        case .W: return .E
        }
    }

    /// The direction a driver heading this way ends up in after turning left.
    public var leftTurn: Direction {
        switch self {
        case .N: return .W
        case .W: return .S
        case .S: return .E
        case .E: return .N
        }
    }

    /// The direction a driver heading this way ends up in after turning right.
    public var rightTurn: Direction {
        switch self {
        case .N: return .E
        case .E: return .S
        case .S: return .W
        case .W: return .N
        }
    }

    /// The board point at distance u along this heading and v to its right, from the centre.
    public func point(_ u: Double, _ v: Double) -> Vec {
        Vec(World.cx + heading.x * u + right.x * v, World.cy + heading.y * u + right.y * v)
    }
}
