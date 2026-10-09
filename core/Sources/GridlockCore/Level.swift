import Foundation

/// A campaign level, as described in Resources/levels.json (exported from game.js).
public struct Level: Decodable {
    public struct Group: Decodable {
        public let label: String
        public let dirs: [Direction]
        /// "T" straight and right, "L" left, "A" all.
        public let move: String
    }

    public struct Walk: Decodable {
        public init(label: String, legs: [Direction]) { self.label = label; self.legs = legs }
        public let label: String
        /// Crosswalks, named by the direction of traffic that arrives over them.
        public let legs: [Direction]
    }

    public var name: String
    public var street: String
    public var desc: String
    public var layout: String
    /// Approach lanes, inner lane first, keyed by direction ("N") or by road ("NS").
    public var lanes: [String: [String]]
    /// How many lanes a direction keeps after the box (fewer means a merge).
    public var out: [String: Int]?
    /// Width of a planted median, by road.
    public var median: [String: Double]?
    public var mergeStart: Double?
    public var mergeLen: Double?
    public var groups: [Group]
    public var walks: [Walk]?
    public var peds: Double?
    public var decor: [String]?
    public var night: Bool?
    /// Cars to clear; infinite in freeplay.
    public var goal: Double
    public var rate: [String: [Double]]
    public var left: Double
    public var right: Double
    public var angry: Double
    public var rush: Bool
    public var intro: String
    public var tip: String
    /// Freeplay: pedestrian rate before the density multiplier.
    public var basePeds: Double?

    /// The seven campaign levels.
    public static let all: [Level] = {
        guard let url = Bundle.module.url(forResource: "levels", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let levels = try? JSONDecoder().decode([Level].self, from: data) else {
            fatalError("GridlockCore: Resources/levels.json is missing or invalid")
        }
        return levels
    }()

    /// How much busier than the campaign level a freeplay density is (5 matches it).
    public static func densityFactor(_ d: Int) -> Double { d <= 5 ? Double(d) / 5 : 1 + Double(d - 5) * 0.55 }

    /// A freeplay version of a campaign map: no goal, the chosen density, rush and people.
    public static func freeplay(map: Int, density: Int, rush: Bool, peds: Bool, night: Bool) -> Level {
        let base = all[map]
        var lvl = base
        let k = densityFactor(density)
        lvl.name = "Freeplay"
        lvl.goal = .infinity
        lvl.rate = ["NS": [base.rate["NS"]![1] * k, base.rate["NS"]![1] * k], "EW": [base.rate["EW"]![1] * k, base.rate["EW"]![1] * k]]
        lvl.rush = rush
        lvl.night = night
        if !peds {
            lvl.walks = []
            lvl.peds = 0
        } else if base.walks == nil {
            let parts = base.street.components(separatedBy: " & ")
            lvl.walks = [Walk(label: parts.first ?? "", legs: [.N, .S]), Walk(label: parts.count > 1 ? parts[1] : "", legs: [.E, .W])]
        }
        lvl.basePeds = peds ? (base.peds ?? 0.05) : 0
        lvl.peds = lvl.basePeds! * min(2, densityFactor(density))
        return lvl
    }

    /// Approach lanes for one direction.
    public func lanes(_ k: Direction) -> [String] { lanes[k.rawValue] ?? lanes[k.road] ?? [] }
}
