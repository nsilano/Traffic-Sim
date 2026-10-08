import SwiftUI
import UIKit
import WebKit

/// Shows the bundled game (game/index.html) full screen. Everything is offline:
/// the game files, the fonts and the saved progress all live on the device.
struct GameView: UIViewRepresentable {
    func makeCoordinator() -> Haptics { Haptics() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // a persistent store keeps localStorage (levels, stars, best scores) between launches
        config.websiteDataStore = .default()
        // the game posts "go" or "stop" here when the player switches a light
        config.userContentController.add(context.coordinator, name: "haptic")

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 10/255, green: 16/255, blue: 48/255, alpha: 1)
        web.scrollView.backgroundColor = web.backgroundColor
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsBackForwardNavigationGestures = false
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif

        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "game") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Haptics) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "haptic")
    }

    /// Plays a light tap for a light turning green and a firmer one for a stop.
    final class Haptics: NSObject, WKScriptMessageHandler {
        private let light = UIImpactFeedbackGenerator(style: .light)
        private let firm = UIImpactFeedbackGenerator(style: .medium)

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            let generator = (message.body as? String) == "stop" ? firm : light
            generator.impactOccurred()
            generator.prepare()
        }
    }
}
