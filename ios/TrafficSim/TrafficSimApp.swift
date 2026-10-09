import SwiftUI

@main
struct TrafficSimApp: App {
    /// Settings → Classic engine (testing): run the original web version of the game instead.
    @AppStorage("classicEngine") private var classic = false
    @StateObject private var native = NativeGame()
    @StateObject private var bridge = GameBridge()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if classic {
                    WebRoot(bridge: bridge)
                } else {
                    NativeRoot(game: native)
                }
            }
            .background(Color(red: 10/255, green: 16/255, blue: 48/255).ignoresSafeArea())
            .statusBarHidden(false)
            .persistentSystemOverlays(.hidden)
            .onChange(of: scenePhase) { phase in
                if phase != .active { native.pauseIfRunning() }
            }
        }
    }
}

/// The native game: the board and its controls, with the native screens over them.
struct NativeRoot: View {
    @ObservedObject var game: NativeGame

    var body: some View {
        ZStack {
            if game.playing {
                NativeGameView(game: game, session: game.session)
            }
            if let card = game.card, !game.showMenu {
                GameCardView(bridge: game, card: card)
                    .transition(.opacity)
            }
            if game.showMenu {
                MenuView(bridge: game)
                    .transition(.opacity)
            }
        }
        .onAppear {
            LegacyImport.runOnce { strings in game.importLegacy(strings) }
        }
    }
}

/// The original web version of the game, with the native screens over it.
struct WebRoot: View {
    @ObservedObject var bridge: GameBridge

    var body: some View {
        ZStack {
            // The game runs underneath all the time, so progress and a paused shift are always there.
            GameView(bridge: bridge)
                .ignoresSafeArea()
            if let card = bridge.card, !bridge.showMenu {
                GameCardView(bridge: bridge, card: card)
                    .transition(.opacity)
            }
            if bridge.showMenu {
                MenuView(bridge: bridge)
                    .transition(.opacity)
            }
        }
    }
}
