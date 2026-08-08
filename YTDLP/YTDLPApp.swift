import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by ContentView so a dock drop can reach the URL field.
    static var openURLHandler: ((String) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let first = urls.first else { return }
        AppDelegate.openURLHandler?(first.absoluteString)
    }
}

@main
struct YTDLPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
