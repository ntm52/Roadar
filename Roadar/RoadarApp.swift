import SwiftUI

@main
struct RoadarApp: App {
    @State private var session = AppSession.shared

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
                .preferredColorScheme(.dark)
                .tint(RoadarTheme.accent)
        }
    }
}
