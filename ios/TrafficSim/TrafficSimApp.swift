import SwiftUI

@main
struct TrafficSimApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
                .ignoresSafeArea()
                .background(Color(red: 20/255, green: 20/255, blue: 20/255))
                .statusBarHidden(false)
                .persistentSystemOverlays(.hidden)
        }
    }
}
