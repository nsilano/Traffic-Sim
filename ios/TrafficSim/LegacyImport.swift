import WebKit

/// One-time import of a player's progress from the web version of the game, which kept it in
/// the web view's localStorage: stars, scores, unlocked levels, settings, freeplay setup and
/// bests. Loads the bundled page out of sight, reads the four keys, and hands them over.
final class LegacyImport: NSObject, WKNavigationDelegate {
    static let doneKey = "legacyImported"
    private var web: WKWebView?
    private var completion: (([String: String]) -> Void)?
    private static var current: LegacyImport?

    static func runOnce(_ completion: @escaping ([String: String]) -> Void) {
        guard !UserDefaults.standard.bool(forKey: doneKey), current == nil,
              let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "game") else { return }
        let importer = LegacyImport()
        current = importer
        importer.completion = completion
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10), configuration: config)
        web.navigationDelegate = importer
        importer.web = web
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let keys = ["intersection-progress", "intersection-settings", "intersection-freeplay", "intersection-freeplay-bests"]
        let script = "JSON.stringify({" + keys.map { "'\($0)': localStorage.getItem('\($0)')" }.joined(separator: ",") + "})"
        webView.evaluateJavaScript(script) { result, _ in
            var strings: [String: String] = [:]
            if let text = result as? String, let data = text.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (k, v) in object { if let s = v as? String { strings[k] = s } }
            }
            UserDefaults.standard.set(true, forKey: Self.doneKey)
            self.completion?(strings)
            self.finish()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish() }

    private func finish() {
        web?.navigationDelegate = nil
        web = nil
        completion = nil
        Self.current = nil
    }
}
