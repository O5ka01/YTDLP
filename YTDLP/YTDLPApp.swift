import SwiftUI

@main
struct YTDLPApp: App {
    var body: some Scene {
        Window("yt-dlp", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}
