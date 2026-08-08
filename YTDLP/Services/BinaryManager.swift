import Foundation
import YTDLPCore

/// Owns the locations of the yt-dlp and ffmpeg executables.
///
/// yt-dlp is copied out of the bundle into Application Support on first launch,
/// because `yt-dlp -U` rewrites its own binary and doing that inside the bundle
/// would invalidate the app's code signature. ffmpeg never self-updates and so
/// stays in the bundle.
///
/// Marked `@MainActor`: `@Observable` gives this class mutable, unsynchronized
/// state (`version`), and a `static let shared` of a non-`Sendable` reference
/// type is rejected under Swift 6 strict concurrency ("static property 'shared'
/// is not concurrency-safe"). Isolating the whole type to the main actor makes
/// the singleton and its mutations safe without giving up `@Observable`, and
/// matches how the Settings UI (Task 15) will read `version` from SwiftUI,
/// which is itself main-actor-isolated.
@MainActor
@Observable
final class BinaryManager {
    static let shared = BinaryManager()

    private(set) var version: String = "unknown"

    private let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("YTDLP", isDirectory: true)
    }()

    var ytDlpPath: String { supportDirectory.appendingPathComponent("bin/yt-dlp").path }
    var ffmpegPath: String { Bundle.main.path(forResource: "ffmpeg", ofType: nil) ?? "/opt/homebrew/bin/ffmpeg" }
    var archivePath: String { supportDirectory.appendingPathComponent("archive.txt").path }

    enum BinaryError: LocalizedError {
        case bundledCopyMissing

        var errorDescription: String? {
            "The bundled yt-dlp is missing — rebuild the app."
        }
    }

    /// Seeds or re-seeds the working copy, then records its version.
    /// Safe to call on every launch.
    func prepare() async throws {
        let fileManager = FileManager.default
        let binDirectory = supportDirectory.appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        if !fileManager.isExecutableFile(atPath: ytDlpPath) {
            guard let bundled = Bundle.main.path(forResource: "yt-dlp", ofType: nil) else {
                throw BinaryError.bundledCopyMissing
            }
            if fileManager.fileExists(atPath: ytDlpPath) {
                try fileManager.removeItem(atPath: ytDlpPath)
            }
            try fileManager.copyItem(atPath: bundled, toPath: ytDlpPath)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ytDlpPath)
        }

        version = await capture(arguments: ["--version"]) ?? "unknown"
    }

    /// Runs at most once a day. Failures are silent — a stale yt-dlp still works.
    func checkForUpdates() async {
        let key = "lastUpdateCheck"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86_400 else { return }
        UserDefaults.standard.set(Date(), forKey: key)

        _ = await capture(arguments: ["--update-to", "stable"])
        version = await capture(arguments: ["--version"]) ?? version
    }

    private func capture(arguments: [String]) async -> String? {
        var output: [String] = []
        for await event in SystemProcessRunner().run(executable: ytDlpPath, arguments: arguments) {
            if case .stdout(let line) = event, !line.isEmpty { output.append(line) }
        }
        return output.last
    }
}
