import SwiftUI

@main
struct TrafficSimApp: App {
    @StateObject private var bridge = GameBridge()

    var body: some Scene {
        WindowGroup {
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
            .background(Color(red: 10/255, green: 16/255, blue: 48/255).ignoresSafeArea())
            .statusBarHidden(false)
            .persistentSystemOverlays(.hidden)
        }
    }
}
