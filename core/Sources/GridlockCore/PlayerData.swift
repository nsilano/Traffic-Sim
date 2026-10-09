import Foundation

/// Everything saved about the player: campaign progress, settings, the freeplay setup and
/// freeplay bests. Stored as the same JSON, under the same keys, as the JavaScript game's
/// localStorage, so the app can import an existing player's data unchanged.
public struct PlayerData {
    public static let progressKey = "intersection-progress"
    public static let settingsKey = "intersection-settings"
    public static let freeplayKey = "intersection-freeplay"
    public static let bestsKey = "intersection-freeplay-bests"
    public static let allKeys = [progressKey, settingsKey, freeplayKey, bestsKey]

    // MARK: Settings

    public struct SettingInfo {
        public let key, group, name, hint: String
        public let on: Bool
    }

    /// The switches in Settings, in order (as SETTINGS in game.js).
    public static let settingsList: [SettingInfo] = [
        SettingInfo(key: "signals", group: "Gameplay", name: "Turn signals", hint: "Blinkers on cars that could go more than one way", on: true),
        SettingInfo(key: "counts", group: "Gameplay", name: "Wait timers", hint: "The longest wait at each corner, beside its button", on: true),
        SettingInfo(key: "busiest", group: "Gameplay", name: "Busiest marker", hint: "Star and outline on the corner that needs you most", on: true),
        SettingInfo(key: "emergency", group: "Gameplay", name: "Emergency vehicles", hint: "Ambulances, fire engines and police in shifts", on: true),
        SettingInfo(key: "bigButtons", group: "Display", name: "Big buttons", hint: "Larger signal buttons when the map has room", on: false),
        SettingInfo(key: "colorblind", group: "Display", name: "Colour-blind signals", hint: "A shape on each light: square red, triangle yellow, circle green", on: false),
        SettingInfo(key: "shake", group: "Display", name: "Screen shake", hint: "The map jolts when cars crash", on: true),
        SettingInfo(key: "scanlines", group: "Display", name: "Scanlines", hint: "Old-TV lines over the menu and cards", on: true),
        SettingInfo(key: "sound", group: "Feel", name: "Sound effects", hint: "Chiptune blips, crashes and sirens (follows the silent switch)", on: true),
        SettingInfo(key: "haptics", group: "Feel", name: "Haptics", hint: "A tap you can feel each time you switch a light", on: true),
    ]

    // MARK: Freeplay

    public struct FreeplaySetup: Equatable {
        public var map = 2, density = 5
        public var flow = "lively"
        public var rush = true, peds = true, night = true, emergency = true
        public init() {}
    }

    public struct Best {
        public var score: Double
        public var cpm: Double
        public init(score: Double, cpm: Double) { self.score = score; self.cpm = cpm }
    }

    public static let densityNames = ["Quiet", "Quiet", "Light", "Light", "Normal", "Normal", "Heavy", "Heavy", "Gridlock", "Gridlock"]
    public static func densityName(_ d: Int) -> String { "\(densityNames[max(1, min(10, d)) - 1]) (\(d))" }

    /// The key a freeplay best is filed under.
    public static func bestKey(map: Int, density: Int, flow: String) -> String {
        "\(map)-\(density)\(flow != "lively" ? "-" + flow : "")"
    }

    // MARK: Data

    public var unlocked = 1
    /// Best times, stars and best scores per level index.
    public var bestTimes: [Int: Double] = [:]
    public var stars: [Int: [Bool]] = [:]
    public var scores: [Int: Double] = [:]
    public var settings: [String: Bool] = Dictionary(uniqueKeysWithValues: settingsList.map { ($0.key, $0.on) })
    public var freeplay = FreeplaySetup()
    public var bests: [String: Best] = [:]

    public init() {}

    public func setting(_ key: String) -> Bool { settings[key] ?? Self.settingsList.first { $0.key == key }?.on ?? false }

    public var totalStars: Int { stars.values.reduce(0) { $0 + $1.filter { $0 }.count } }

    // MARK: Reading and writing (same JSON as game.js)

    /// Reads the four stored JSON strings; anything missing or malformed falls back to defaults,
    /// with the same checks as game.js.
    public init(strings: [String: String]) {
        let levels = Level.all.count
        func json(_ key: String) -> Any? {
            strings[key].flatMap { $0.data(using: .utf8) }.flatMap { try? JSONSerialization.jsonObject(with: $0) }
        }
        if let p = json(Self.progressKey) as? [String: Any], let u = p["unlocked"] as? Int {
            unlocked = min(levels, max(1, u))
            for (k, v) in p["best"] as? [String: Any] ?? [:] {
                if let i = Int(k), let t = (v as? NSNumber)?.doubleValue, t.isFinite, t >= 0 { bestTimes[i] = t }
            }
            for (k, v) in p["stars"] as? [String: Any] ?? [:] {
                if let i = Int(k), i >= 0, i < levels, let a = v as? [Any], a.count == 3 {
                    stars[i] = a.map { ($0 as? Bool) ?? (($0 as? NSNumber)?.boolValue ?? false) }
                }
            }
            for (k, v) in p["scores"] as? [String: Any] ?? [:] {
                if let i = Int(k), i >= 0, i < levels, let s = (v as? NSNumber)?.doubleValue, s.isFinite, s >= 0 { scores[i] = s }
            }
        }
        if let s = json(Self.settingsKey) as? [String: Any] {
            for info in Self.settingsList { if let b = s[info.key] as? Bool { settings[info.key] = b } }
        }
        if let f = json(Self.freeplayKey) as? [String: Any], let map = f["map"] as? Int, map >= 0, map < levels,
           let density = f["density"] as? Int, density >= 1, density <= 10 {
            var setup = FreeplaySetup()
            setup.map = map
            setup.density = density
            if let flow = f["flow"] as? String, Simulation.flowStyles[flow] != nil { setup.flow = flow }
            setup.rush = f["rush"] as? Bool ?? false
            setup.peds = f["peds"] as? Bool ?? true
            // Saves store "day"; older ones (with only "night") start at night.
            setup.night = (f["day"] as? Bool).map { !$0 } ?? true
            setup.emergency = f["emergency"] as? Bool ?? true
            freeplay = setup
        }
        if let b = json(Self.bestsKey) as? [String: Any] {
            for (k, v) in b {
                guard let entry = v as? [String: Any] else { continue }
                let score = (entry["score"] as? NSNumber)?.doubleValue ?? 0
                let cpm = (entry["cpm"] as? NSNumber)?.doubleValue ?? 0
                bests[k] = Best(score: score.isFinite ? score : 0, cpm: cpm.isFinite ? cpm : 0)
            }
        }
    }

    /// The four JSON strings to store.
    public var strings: [String: String] {
        func text(_ object: Any) -> String {
            (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        }
        let progress: [String: Any] = [
            "unlocked": unlocked,
            "best": Dictionary(uniqueKeysWithValues: bestTimes.map { (String($0.key), $0.value) }),
            "stars": Dictionary(uniqueKeysWithValues: stars.map { (String($0.key), $0.value) }),
            "scores": Dictionary(uniqueKeysWithValues: scores.map { (String($0.key), $0.value) }),
        ]
        let f: [String: Any] = ["map": freeplay.map, "density": freeplay.density, "flow": freeplay.flow, "rush": freeplay.rush,
                                "peds": freeplay.peds, "night": freeplay.night, "day": !freeplay.night, "emergency": freeplay.emergency]
        let b = Dictionary(uniqueKeysWithValues: bests.map { ($0.key, ["score": $0.value.score, "cpm": $0.value.cpm]) })
        return [Self.progressKey: text(progress), Self.settingsKey: text(settings), Self.freeplayKey: text(f), Self.bestsKey: text(b)]
    }

    // MARK: Results

    /// Records a won shift: best time, unlocks the next level, merges stars, keeps the best score.
    /// Returns whether the score is a new best, and the previous best.
    public mutating func recordWin(level i: Int, time: Double, stars earned: [Bool], score: Double) -> (newBest: Bool, previous: Double) {
        if bestTimes[i] == nil || time < bestTimes[i]! { bestTimes[i] = time }
        unlocked = max(unlocked, min(Level.all.count, i + 2))
        let had = stars[i] ?? [false, false, false]
        stars[i] = zip(had, earned).map { $0 || $1 }
        let previous = scores[i] ?? 0
        let newBest = score > previous
        if newBest { scores[i] = score }
        return (newBest, previous)
    }

    /// Updates the freeplay best for a run's key with its score and (after a minute) cars per minute.
    public mutating func recordFreeplay(key: String, score: Double, cpm: Double?) {
        var entry = bests[key] ?? Best(score: 0, cpm: 0)
        if score > entry.score { entry.score = score }
        if let cpm = cpm, cpm > entry.cpm { entry.cpm = (cpm * 10).rounded() / 10 }
        bests[key] = entry
    }
}
