import GridlockCore
import GridlockRender
import SwiftUI
import UIKit

/// What the native game screen draws from, refreshed several times a second (and at once
/// when a light switches) so the HUD and the signal buttons stay current.
final class BoardSession: ObservableObject {
    @Published var frame = 0
}

/// The game run natively: the GridlockCore simulation, drawn by GridlockRender, with the
/// player's progress and settings saved on the device. Drives the same native screens as the
/// web game did (menu, levels, records, settings, freeplay setup, game cards).
final class NativeGame: GameHost {
    private(set) var store: PlayerData
    private(set) var sim: Simulation?
    private(set) var renderer: BoardRenderer?
    private(set) var layout: ControlLayout?
    let monitor = CornerMonitor()
    let session = BoardSession()
    /// On the game screen (false on the menu). A shift left from the pause card stays here, paused.
    @Published private(set) var playing = false
    private var suspended = false
    private var lastPublish = 0.0
    private var lastSave = 0.0
    private let defaults = UserDefaults.standard

    override init() {
        var strings: [String: String] = [:]
        for key in PlayerData.allKeys { if let s = UserDefaults.standard.string(forKey: key) { strings[key] = s } }
        store = PlayerData(strings: strings)
        super.init()
        refresh()
        GameCenter.shared.signIn()
    }

    /// Takes saved data imported from the web game (see LegacyImport) if there's none yet.
    func importLegacy(_ strings: [String: String]) {
        // Only into a fresh start: never over anything already played natively.
        guard !strings.isEmpty, store.unlocked == 1, store.stars.isEmpty, store.scores.isEmpty, store.bests.isEmpty else { return }
        store = PlayerData(strings: strings)
        save()
        refresh()
    }

    private func save() {
        for (key, value) in store.strings { defaults.set(value, forKey: key) }
    }

    func setting(_ key: String) -> Bool { store.setting(key) }

    // MARK: What the menu and screens show

    private static func format(_ n: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: n.rounded())) ?? String(Int(n))
    }

    private func refresh() {
        let levels = Level.all
        let next = min(store.unlocked, levels.count) - 1
        var s = MenuSummary()
        if suspended, let sim = sim {
            s.play = "Resume"
            s.playNote = sim.freeplay != nil ? "Freeplay" : sim.level.name
        } else {
            s.play = store.unlocked > 1 || store.stars[0] != nil ? "Continue" : "Play"
            s.playNote = levels[next].name
        }
        s.shift = "Signal duty · Shift \(next + 1)"
        s.stars = "★ \(store.totalStars)/\(levels.count * 3)"
        let best = store.scores.values.max() ?? 0
        s.best = best > 0 ? "Hi \(Self.format(best))" : ""
        s.scanlines = store.setting("scanlines")
        if s != summary { summary = s }

        var d = GameData()
        d.levels = levels.enumerated().map { i, lvl in
            GameData.Level(name: lvl.name, desc: lvl.desc, layout: lvl.layout, locked: i + 1 > store.unlocked,
                           stars: store.stars[i], score: Int((store.scores[i] ?? 0).rounded()))
        }
        d.bests = store.bests.filter { $0.value.score > 0 }.sorted { $0.value.score > $1.value.score }.prefix(10).map { key, b in
            let parts = key.split(separator: "-").map(String.init)
            let map = Int(parts.first ?? "") ?? 0, density = parts.count > 1 ? Int(parts[1]) ?? 5 : 5
            let flow = parts.count > 2 ? Simulation.flowStyles[parts[2]]?.label : nil
            let name = map < levels.count ? levels[map].name : "Map"
            return GameData.Best(label: "\(name) · \(PlayerData.densityName(density))\(flow.map { " · " + $0 } ?? "")",
                                 score: Int(b.score.rounded()), cpm: (b.cpm * 10).rounded() / 10)
        }
        d.settings = PlayerData.settingsList.map { GameData.Setting(key: $0.key, group: $0.group, name: $0.name, hint: $0.hint, on: store.setting($0.key)) }
        let f = store.freeplay
        d.freeplay = FreeplayConfig(map: f.map, density: f.density, flow: f.flow, rush: f.rush, peds: f.peds, night: f.night, emergency: f.emergency)
        d.flows = ["calm", "lively", "wild"].compactMap { k in Simulation.flowStyles[k].map { GameData.Flow(key: k, label: $0.label, desc: $0.desc) } }
        d.densityNames = PlayerData.densityNames
        if d != data {
            data = d
            GameCenter.shared.report(d)
        }
        let menu = !playing
        if menu != showMenu { withAnimation(.easeOut(duration: 0.2)) { showMenu = menu } }
    }

    private func setCard(_ c: GameCard?) {
        withAnimation(.easeOut(duration: 0.18)) { card = c }
    }

    // MARK: Commands from the native screens

    override func command(_ name: String) {
        feedback()
        switch name {
        case "play":
            if suspended { resume() } else { loadLevel(min(store.unlocked, Level.all.count) - 1) }
        case "reset-bests":
            store.bests = [:]
            save()
        case "reset-all":
            let keep = (store.settings, store.freeplay)
            store = PlayerData()
            store.settings = keep.0
            store.freeplay = keep.1
            suspended = false
            sim = nil
            save()
        default:
            break
        }
        refresh()
    }

    override func command(_ name: String, level: Int) {
        feedback()
        guard name == "pick", level >= 0, level < Level.all.count, level + 1 <= store.unlocked else { return }
        loadLevel(level)
    }

    override func command(_ name: String, key: String) {
        feedback()
        switch name {
        case "setting":
            store.settings[key] = !store.setting(key)
            save()
            applySettings()
            if key == "haptics" && store.setting("haptics") { haptic("go") }
        case "card":
            cardAction(key)
        default:
            break
        }
        refresh()
    }

    override func command(_ name: String, freeplay f: FreeplayConfig) {
        feedback()
        guard name == "freeplay-start" else { return }
        var setup = PlayerData.FreeplaySetup()
        setup.map = max(0, min(Level.all.count - 1, f.map))
        setup.density = max(1, min(10, f.density))
        setup.flow = Simulation.flowStyles[f.flow] != nil ? f.flow : "lively"
        setup.rush = f.rush
        setup.peds = f.peds
        setup.night = f.night
        setup.emergency = f.emergency
        store.freeplay = setup
        save()
        startFreeplay(setup)
    }

    private func applySettings() {
        guard let sim = sim else { return }
        sim.shakeOn = store.setting("shake")
        if sim.freeplay == nil { sim.emergencyOn = sim.levelIndex >= 2 && store.setting("emergency") }
        renderer?.options.turnSignals = store.setting("signals")
        session.frame += 1
    }

    // MARK: Shifts

    private func begin(_ s: Simulation) {
        sim = s
        if let r = renderer { r.setSimulation(s) } else { renderer = BoardRenderer(simulation: s) }
        layout = ControlLayout(simulation: s)
        monitor.update(s, layout!, force: true)
        suspended = false
        playing = true
        applySettings()
    }

    private func loadLevel(_ i: Int) {
        let s = Simulation(levelIndex: i, emergencies: store.setting("emergency"), shake: store.setting("shake"))
        begin(s)
        let lvl = s.level
        setCard(GameCard(
            eyebrow: "Level \(i + 1) · \(lvl.street)", title: lvl.name, stars: nil, score: nil, scoreNote: nil,
            lines: [lvl.intro, lvl.tip, "Clear \(Int(lvl.goal)) cars. \(Simulation.maxCrashes) crashes or an empty patience meter ends the shift."],
            goals: Self.starGoals.enumerated().map { j, g in GameCard.Goal(text: g, on: store.stars[i]?[j] ?? false) },
            actions: [GameCard.Action(id: "start", label: "Start shift", primary: true), GameCard.Action(id: "levels", label: "All levels", primary: nil)]))
        refresh()
    }

    private func startFreeplay(_ f: PlayerData.FreeplaySetup) {
        let level = Level.freeplay(map: f.map, density: f.density, rush: f.rush, peds: f.peds, night: f.night)
        let s = Simulation(levelIndex: f.map, level: level, freeplay: Simulation.Freeplay(map: f.map, density: f.density, flow: f.flow),
                           emergencies: f.emergency, shake: store.setting("shake"))
        s.bestToBeat = store.bests[PlayerData.bestKey(map: f.map, density: f.density, flow: f.flow)]?.score ?? 0
        begin(s)
        s.mode = .running
        setCard(nil)
        refresh()
    }

    private func resume() {
        guard let s = sim else { return }
        suspended = false
        playing = true
        s.mode = .running
        setCard(nil)
        refresh()
    }

    /// Leaves for the menu; a shift in progress stays, paused, for Resume.
    private func toMenu(open screen: String? = nil) {
        if let s = sim, s.mode == .running || s.mode == .paused {
            s.mode = .paused
            suspended = true
        } else {
            suspended = false
        }
        saveFreeplayBest()
        playing = false
        setCard(nil)
        openRequest = screen
        refresh()
    }

    static let starGoals = ["Clear the goal", "No crashes", "Patience never below \(Int(Simulation.starPatience))%"]

    private func statsLine(_ s: Simulation) -> String {
        String(format: "%.1f cars/min · average wait %.1f s · longest wait %.1f s", s.carsPerMinute, s.averageWait, s.worstWait)
    }

    static func time(_ t: Double) -> String { String(format: "%ld:%02ld", Int(t) / 60, Int(t) % 60) }

    /// The HUD's pause button.
    func togglePause() {
        guard let s = sim else { return }
        if s.mode == .running {
            s.mode = .paused
            saveFreeplayBest()
            var actions = [GameCard.Action(id: "resume", label: "Resume", primary: true)]
            if s.freeplay != nil { actions.append(GameCard.Action(id: "freeplay-setup", label: "Change settings", primary: nil)) }
            actions += [GameCard.Action(id: "retry", label: s.freeplay != nil ? "Restart" : "Restart level", primary: nil),
                        GameCard.Action(id: "levels", label: "All levels", primary: nil),
                        GameCard.Action(id: "menu", label: "Main menu", primary: nil)]
            setCard(GameCard(eyebrow: s.freeplay != nil ? "Freeplay" : "Level \(s.levelIndex + 1) · \(s.level.name)", title: "Paused",
                             stars: nil, score: nil, scoreNote: nil,
                             lines: ["Traffic is frozen. \(Self.format(s.score)) points so far.", statsLine(s)], goals: nil, actions: actions))
        } else if s.mode == .paused {
            resume()
        }
        session.frame += 1
    }

    /// The app went to the background: pause a running shift.
    func pauseIfRunning() {
        if sim?.mode == .running && playing { togglePause() }
        saveFreeplayBest()
    }

    private func cardAction(_ id: String) {
        guard let s = sim else { return }
        switch id {
        case "start":
            s.mode = .running
            setCard(nil)
        case "resume":
            resume()
        case "levels":
            toMenu(open: "levels")
        case "freeplay-setup":
            toMenu(open: "freeplay")
        case "menu":
            toMenu()
        case "next":
            loadLevel(min(s.levelIndex + 1, Level.all.count - 1))
        case "retry":
            if let f = s.freeplay {
                var setup = store.freeplay
                setup.map = f.map
                setup.density = f.density
                startFreeplay(setup)
            } else {
                loadLevel(s.levelIndex)
                sim?.mode = .running
                setCard(nil)
            }
        default:
            break
        }
        session.frame += 1
    }

    // MARK: Playing

    /// The player switched a light.
    func toggle(_ group: Int) {
        guard let s = sim else { return }
        s.toggle(group)
        handle(s.drainEvents(), s)
        monitor.update(s, layout!, force: true)
        session.frame += 1
    }

    /// Freeplay: the density slider.
    func setDensity(_ d: Int) {
        guard let s = sim, s.freeplay?.density != d else { return }
        s.setDensity(d)
        store.freeplay.density = d
        save()
        session.frame += 1
    }

    /// One display frame: advances the shift and handles what happened.
    func tick(_ dt: Double, now: Double) {
        guard let s = sim, playing else { return }
        let dt = min(0.05, dt)
        if s.mode == .running {
            s.step(dt)
        } else if s.mode != .paused {
            s.updateEffects(dt)
        }
        handle(s.drainEvents(), s)
        if let layout = layout { monitor.update(s, layout) }
        if s.freeplay != nil && s.mode == .running && now - lastSave > 2 {
            lastSave = now
            saveFreeplayBest()
        }
        if now - lastPublish > 1.0 / 15 {
            lastPublish = now
            session.frame += 1
        }
    }

    private func handle(_ events: [SimEvent], _ s: Simulation) {
        for e in events {
            switch e {
            case .sound(let name):
                if store.setting("sound") { sounds.play(name) }
            case .haptic(let kind):
                if store.setting("haptics") { haptic(kind) }
            case .won:
                won(s)
            case .lost(let reason):
                lost(s, reason)
            }
        }
    }

    private func saveFreeplayBest() {
        guard let s = sim, let key = s.bestKey else { return }
        store.recordFreeplay(key: key, score: s.score, cpm: s.t >= 60 ? s.carsPerMinute : nil)
        save()
    }

    private func won(_ s: Simulation) {
        let i = s.levelIndex
        let stars = s.starsEarned
        let result = store.recordWin(level: i, time: s.t, stars: stars, score: s.score)
        save()
        let hasNext = i + 1 < Level.all.count
        let next = hasNext ? Level.all[i + 1] : nil
        var actions: [GameCard.Action] = []
        if hasNext { actions.append(GameCard.Action(id: "next", label: "Next level", primary: true)) }
        actions += [GameCard.Action(id: "retry", label: "Replay", primary: !hasNext), GameCard.Action(id: "levels", label: "All levels", primary: nil)]
        setCard(GameCard(
            eyebrow: "Level \(i + 1) complete", title: hasNext ? "Intersection cleared" : "You ran every intersection",
            stars: stars, score: "\(Self.format(s.score)) points",
            scoreNote: result.newBest ? "New best!" : "Best \(Self.format(result.previous))",
            lines: ["You moved \(s.cleared) cars in \(Self.time(s.t)) with \(s.crashes) \(s.crashes == 1 ? "crash" : "crashes").",
                    statsLine(s), next.map { "Next: \($0.name). \($0.desc)." } ?? "Every level is unlocked."],
            goals: Self.starGoals.enumerated().map { j, g in GameCard.Goal(text: g, on: stars[j]) },
            actions: actions))
        refresh()
    }

    private func lost(_ s: Simulation, _ reason: String) {
        var actions = [GameCard.Action(id: "retry", label: "Try again", primary: true)]
        if s.freeplay != nil { actions.append(GameCard.Action(id: "freeplay-setup", label: "Change settings", primary: nil)) }
        actions.append(GameCard.Action(id: "levels", label: "All levels", primary: nil))
        let where_ = s.freeplay != nil ? "Freeplay" : "Level \(s.levelIndex + 1)"
        setCard(GameCard(
            eyebrow: "\(where_) · \(s.level.street)", title: "Shift over", stars: nil, score: nil, scoreNote: nil,
            lines: [reason, "You cleared \(s.cleared) of \(Int(s.level.goal)) cars in \(Self.time(s.t)), scoring \(Self.format(s.score)) points.", statsLine(s)],
            goals: nil, actions: actions))
        refresh()
    }
}
