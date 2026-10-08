import SwiftUI

@main
struct TrafficSimApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
                .ignoresSafeArea()
                .background(Color(red: 10/255, green: 16/255, blue: 48/255))
                .statusBarHidden(false)
                .persistentSystemOverlays(.hidden)
        }
    }
}
