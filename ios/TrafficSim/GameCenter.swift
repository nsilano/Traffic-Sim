import GameKit
import UIKit

/// Game Center: signs the player in, posts leaderboard scores and unlocks achievements
/// from the progress the game reports. The leaderboards and achievements below must exist
/// in App Store Connect with exactly these IDs (see ios/README.md); until they do, Game
/// Center just ignores the reports and the game carries on as normal.
final class GameCenter {
    static let shared = GameCenter()

    enum Leaderboard {
        static let campaign = "com.nicsilano.gridlock.campaign"   // sum of best scores across the levels
        static let stars = "com.nicsilano.gridlock.stars"         // stars earned, out of 21
        static let freeplay = "com.nicsilano.gridlock.freeplay"   // best freeplay score
    }

    enum Achievement {
        static let firstShift = "com.nicsilano.gridlock.first-shift"       // finish level 1
        static let perfectShift = "com.nicsilano.gridlock.perfect-shift"   // three stars on any level
        static let everyShift = "com.nicsilano.gridlock.every-shift"       // finish all seven levels
        static let allStars = "com.nicsilano.gridlock.all-stars"           // all 21 stars
        static let freeplay5k = "com.nicsilano.gridlock.freeplay-5000"     // 5,000 points in one freeplay run
    }

    private var signedIn = false
    private var waiting: GameData?
    private var posted: [String: Int] = [:]
    private var unlocked = Set(UserDefaults.standard.stringArray(forKey: "gameCenterUnlocked") ?? [])

    /// Shows Game Center's sign-in once if needed; after that it signs in quietly.
    func signIn() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] controller, _ in
            guard let self = self else { return }
            if let controller = controller {
                Self.topController()?.present(controller, animated: true)
                return
            }
            self.signedIn = GKLocalPlayer.local.isAuthenticated
            if self.signedIn, let data = self.waiting {
                self.waiting = nil
                self.report(data)
            }
        }
    }

    var isSignedIn: Bool { signedIn }

    /// Opens Game Center's own leaderboards and achievements screen.
    func showDashboard() {
        guard signedIn else { signIn(); return }
        GKAccessPoint.shared.trigger(state: .dashboard) {}
    }

    /// Posts anything that has improved since the last report.
    func report(_ data: GameData) {
        guard signedIn else { waiting = data; return }
        let campaign = data.levels.reduce(0) { $0 + $1.score }
        let stars = data.totalStars
        let freeplay = data.bests.map(\.score).max() ?? 0
        post(campaign, to: Leaderboard.campaign)
        post(stars, to: Leaderboard.stars)
        post(freeplay, to: Leaderboard.freeplay)

        let finished = data.levels.filter { $0.stars != nil }
        var earned: [String] = []
        if data.levels.first?.stars != nil { earned.append(Achievement.firstShift) }
        if finished.contains(where: { ($0.stars ?? []).allSatisfy { $0 } && ($0.stars ?? []).count == 3 }) { earned.append(Achievement.perfectShift) }
        if !data.levels.isEmpty && finished.count == data.levels.count { earned.append(Achievement.everyShift) }
        if !data.levels.isEmpty && stars >= data.levels.count * 3 { earned.append(Achievement.allStars) }
        if freeplay >= 5000 { earned.append(Achievement.freeplay5k) }
        unlock(earned.filter { !unlocked.contains($0) })
    }

    private func post(_ score: Int, to leaderboard: String) {
        guard score > 0, score > posted[leaderboard, default: 0] else { return }
        posted[leaderboard] = score
        GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [leaderboard]) { _ in }
    }

    private func unlock(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let achievements = ids.map { id -> GKAchievement in
            let a = GKAchievement(identifier: id)
            a.percentComplete = 100
            a.showsCompletionBanner = true
            return a
        }
        GKAchievement.report(achievements) { [weak self] error in
            guard error == nil, let self = self else { return }
            DispatchQueue.main.async {
                self.unlocked.formUnion(ids)
                UserDefaults.standard.set(Array(self.unlocked), forKey: "gameCenterUnlocked")
            }
        }
    }

    private static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
