import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by ContentView once the view appears. Assigning it flushes any URL
    /// that arrived from a cold-launch dock drop before the view existed.
    static var openURLHandler: ((String) -> Void)? {
        didSet {
            guard let handler = openURLHandler, let buffered = pendingURL else { return }
            pendingURL = nil
            handler(buffered)
        }
    }

    /// Holds the most recent dock-drop URL that arrived before `openURLHandler`
    /// was registered (a cold launch). Only the latest is kept.
    private static var pendingURL: String?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let first = urls.first,
              first.scheme?.hasPrefix("http") == true else { return }

        if let handler = AppDelegate.openURLHandler {
            handler(first.absoluteString)
        } else {
            AppDelegate.pendingURL = first.absoluteString
        }
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
