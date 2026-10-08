import SwiftUI
import UIKit
import WebKit

/// Everything the native screens show, sent by the game as JSON with each menu update.
struct GameData: Decodable, Equatable {
    struct Level: Decodable, Equatable {
        let name: String
        let desc: String
        let layout: String
        let locked: Bool
        let stars: [Bool]?
        let score: Int
    }
    struct Best: Decodable, Equatable {
        let label: String
        let score: Int
        let cpm: Double
    }
    struct Setting: Decodable, Equatable {
        let key: String
        let group: String
        let name: String
        let hint: String
        let on: Bool
    }
    struct Flow: Decodable, Equatable {
        let key: String
        let label: String
        let desc: String
    }
    var levels: [Level] = []
    var bests: [Best] = []
    var settings: [Setting] = []
    var freeplay = FreeplayConfig()
    var flows: [Flow] = []
    var densityNames: [String] = []

    var totalStars: Int { levels.reduce(0) { $0 + ($1.stars ?? []).filter { $0 }.count } }
}

/// A game card (level intro, pause, results) for the app to draw over the board.
struct GameCard: Decodable, Equatable {
    struct Goal: Decodable, Equatable {
        let text: String
        let on: Bool
    }
    struct Action: Decodable, Equatable {
        let id: String
        let label: String
        let primary: Bool?
    }
    let eyebrow: String
    let title: String
    let stars: [Bool]?
    let score: String?
    let scoreNote: String?
    let lines: [String]?
    let goals: [Goal]?
    let actions: [Action]
}

/// A freeplay setup, as the game stores it.
struct FreeplayConfig: Codable, Equatable {
    var map = 2
    var density = 5
    var flow = "lively"
    var rush = true
    var peds = true
    var night = true
    var emergency = true
}

/// What the native main menu shows. The game sends it whenever the menu comes back.
struct MenuSummary: Equatable {
    var play = "Play"
    var playNote = ""
    var shift = "Signal duty · Shift 1"
    var stars = "★ 0/21"
    var best = ""
    var scanlines = true
}

/// The two-way link between the native app and the game running in the web view.
///
/// The game posts `{type: "screen", menu: Bool, ...}` on the "bridge" channel whenever
/// the menu appears or something covers it, and "go"/"stop" on the "haptic" channel when
/// the player switches a light. The app sends menu choices in with `Gridlock.command(...)`.
final class GameBridge: NSObject, ObservableObject, WKScriptMessageHandler {
    @Published var showMenu = true
    @Published var summary = MenuSummary()
    @Published var data = GameData()
    /// The game card showing over the board, if any.
    @Published var card: GameCard?
    /// A native screen the game asked to open over the menu (levels or freeplay).
    @Published var openRequest: String?

    weak var webView: WKWebView?
    private var ready = false
    private var pending: [String] = []

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let firm = UIImpactFeedbackGenerator(style: .medium)
    private let tick = UISelectionFeedbackGenerator()

    /// A command for the game: play, levels, records, settings, help, or with a value:
    /// pick (a level index), freeplay-start (a FreeplayConfig), setting (a key),
    /// reset-bests, reset-all.
    func command(_ name: String) { send(name, argument: "null") }
    func command(_ name: String, level: Int) { send(name, argument: String(level)) }
    func command(_ name: String, key: String) { send(name, argument: Self.json(key)) }
    func command(_ name: String, freeplay: FreeplayConfig) { send(name, argument: Self.json(freeplay)) }

    private func send(_ name: String, argument: String) {
        tick.selectionChanged()
        let script = "window.Gridlock && window.Gridlock.command(\(Self.json(name)), \(argument))"
        guard ready else { pending.append(script); return }
        run(script)
    }

    private func run(_ script: String) {
        webView?.evaluateJavaScript(script)
    }

    private static func json<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) else { return "null" }
        return text
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "haptic":
            let generator = (message.body as? String) == "stop" ? firm : light
            generator.impactOccurred()
            generator.prepare()
        case "bridge":
            guard let body = message.body as? [String: Any], body["type"] as? String == "screen" else { return }
            var s = summary
            s.play = body["play"] as? String ?? s.play
            s.playNote = body["playNote"] as? String ?? s.playNote
            s.shift = body["shift"] as? String ?? s.shift
            s.stars = body["stars"] as? String ?? s.stars
            s.best = body["best"] as? String ?? s.best
            s.scanlines = body["scanlines"] as? Bool ?? s.scanlines
            if s != summary { summary = s }
            if let json = body["data"] as? String, let bytes = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(GameData.self, from: bytes), decoded != data {
                data = decoded
            }
            var newCard: GameCard?
            if let raw = body["card"], !(raw is NSNull),
               let json = try? JSONSerialization.data(withJSONObject: raw) {
                newCard = try? JSONDecoder().decode(GameCard.self, from: json)
            }
            if newCard != card {
                withAnimation(.easeOut(duration: 0.18)) { card = newCard }
            }
            if let open = body["open"] as? String { openRequest = open }
            let menu = body["menu"] as? Bool ?? false
            if menu != showMenu {
                withAnimation(.easeOut(duration: 0.2)) { showMenu = menu }
            }
            if !ready {
                ready = true
                for script in pending { run(script) }
                pending.removeAll()
            }
        default:
            break
        }
    }
}
