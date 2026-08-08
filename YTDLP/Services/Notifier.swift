import AppKit
import Foundation
import UserNotifications

/// Completion notifications, plus revealing the finished file in Finder.
///
/// Notification actions are deliberately omitted: wiring "Reveal in Finder"
/// into a notification button requires a `UNUserNotificationCenterDelegate`
/// and knowledge of the final filename, which yt-dlp only reports in its
/// `[download] Destination:` line. The queue row's own controls cover the
/// same need. If you later want the button, parse `Destination:` in
/// `ProgressParser` first.
final class Notifier: @unchecked Sendable {
    static let shared = Notifier()

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyFinished(title: String, folder: String) {
        let content = UNMutableNotificationContent()
        content.title = "Download finished"
        content.body = title
        content.sound = .default

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    func reveal(folder: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder)
    }
}
