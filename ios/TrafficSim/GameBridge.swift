import SwiftUI
import UIKit
import WebKit

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

    weak var webView: WKWebView?
    private var ready = false
    private var pending: [String] = []

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let firm = UIImpactFeedbackGenerator(style: .medium)
    private let tick = UISelectionFeedbackGenerator()

    /// A menu choice: play, freeplay, levels, records, settings or help.
    func command(_ name: String) {
        tick.selectionChanged()
        guard ready else { pending.append(name); return }
        run(name)
    }

    private func run(_ name: String) {
        webView?.evaluateJavaScript("window.Gridlock && window.Gridlock.command('\(name)')")
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
            let menu = body["menu"] as? Bool ?? false
            if menu != showMenu {
                withAnimation(.easeOut(duration: 0.2)) { showMenu = menu }
            }
            if !ready {
                ready = true
                for name in pending { run(name) }
                pending.removeAll()
            }
        default:
            break
        }
    }
}
