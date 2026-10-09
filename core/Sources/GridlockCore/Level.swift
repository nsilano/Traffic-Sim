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
        public let label: String
        /// Crosswalks, named by the direction of traffic that arrives over them.
        public let legs: [Direction]
    }

    public let name: String
    public let street: String
    public let desc: String
    public let layout: String
    /// Approach lanes, inner lane first, keyed by direction ("N") or by road ("NS").
    public let lanes: [String: [String]]
    /// How many lanes a direction keeps after the box (fewer means a merge).
    public let out: [String: Int]?
    /// Width of a planted median, by road.
    public let median: [String: Double]?
    public let mergeStart: Double?
    public let mergeLen: Double?
    public let groups: [Group]
    public let walks: [Walk]?
    public let peds: Double?
    public let decor: [String]?
    public let night: Bool?
    public let goal: Int
    public let rate: [String: [Double]]
    public let left: Double
    public let right: Double
    public let angry: Double
    public let rush: Bool
    public let intro: String
    public let tip: String

    /// The seven campaign levels.
    public static let all: [Level] = {
        guard let url = Bundle.module.url(forResource: "levels", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let levels = try? JSONDecoder().decode([Level].self, from: data) else {
            fatalError("GridlockCore: Resources/levels.json is missing or invalid")
        }
        return levels
    }()

    /// Approach lanes for one direction.
    public func lanes(_ k: Direction) -> [String] { lanes[k.rawValue] ?? lanes[k.road] ?? [] }
}
