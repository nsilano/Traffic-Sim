import SwiftUI
import UIKit
import WebKit

/// Shows the bundled game (game/index.html) full screen. Everything is offline:
/// the game files, the fonts and the saved progress all live on the device.
struct GameView: UIViewRepresentable {
    @ObservedObject var bridge: GameBridge

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // a persistent store keeps localStorage (levels, stars, best scores) between launches
        config.websiteDataStore = .default()
        // "haptic": a tap when the player switches a light; "bridge": the menu link (GameBridge)
        config.userContentController.add(bridge, name: "haptic")
        config.userContentController.add(bridge, name: "bridge")
        config.userContentController.add(bridge, name: "sound")

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
        bridge.webView = web

        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "game") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // VoiceOver shouldn't reach the page underneath the native menu or a native card.
        uiView.accessibilityElementsHidden = bridge.showMenu || bridge.card != nil
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "haptic")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "bridge")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "sound")
    }
}
