import Foundation
import YTDLPCore

/// Locates the yt-dlp, ffmpeg and deno executables installed via Homebrew.
///
/// Earlier revisions bundled yt-dlp and ffmpeg inside the app and copied
/// yt-dlp into Application Support so it could self-update with `-U` without
/// invalidating the app's code signature. That approach didn't survive
/// scrutiny: Homebrew's `yt-dlp` is a 192-byte Python launcher script whose
/// shebang hard-codes an absolute path into a specific Homebrew Cellar
/// version, and `ffmpeg` links 18 dylibs from that same Cellar. Copying
/// either one out of `/opt/homebrew` yields something that cannot run.
/// Instead, this type resolves both tools from their well-known Homebrew
/// install locations at runtime and fails with an actionable error if
/// they're missing. Updates now come from `brew upgrade`, not from within
/// the app.
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

    /// Candidate install locations, in lookup order: Apple Silicon Homebrew
    /// prefix first, then the Intel Homebrew prefix.
    private static let ytDlpCandidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
    private static let ffmpegCandidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
    private static let denoCandidates = ["/opt/homebrew/bin/deno", "/usr/local/bin/deno"]

    /// Resolved once in `prepare()`; nil until then (or if the tool wasn't found).
    private(set) var ytDlpPath: String?
    private(set) var ffmpegPath: String?

    /// deno, if installed. Unlike the other two this is *not* required: it is
    /// only needed for sites whose extractor runs JavaScript (in practice,
    /// YouTube), so a missing deno degrades those downloads rather than
    /// stopping the app. yt-dlp would find it on its own via `PATH`, but a
    /// Finder-launched app inherits launchd's bare
    /// `/usr/bin:/bin:/usr/sbin:/sbin`, which excludes both Homebrew prefixes —
    /// so the path is resolved here and passed explicitly, as ffmpeg's is.
    private(set) var jsRuntimePath: String?

    private let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("YTDLP", isDirectory: true)
    }()

    var archivePath: String { supportDirectory.appendingPathComponent("archive.txt").path }

    enum BinaryError: LocalizedError {
        case missing(ytDlp: Bool, ffmpeg: Bool)

        var errorDescription: String? {
            switch self {
            case .missing(true, true):
                return "yt-dlp and ffmpeg weren't found. Install them with:  brew install yt-dlp ffmpeg"
            case .missing(true, false):
                return "yt-dlp wasn't found. Install it with:  brew install yt-dlp"
            case .missing(false, true):
                return "ffmpeg wasn't found. Install it with:  brew install ffmpeg"
            case .missing(false, false):
                return nil
            }
        }
    }

    /// Resolves yt-dlp, ffmpeg and deno from their known Homebrew locations
    /// and records yt-dlp's version. Safe to call on every launch; re-resolves
    /// the paths each time in case Homebrew's install state changed, but
    /// downstream code should read the stored paths rather than re-searching.
    /// Throws only for the two required tools — a missing deno is reported in
    /// Settings and left to degrade the download it affects.
    func prepare() async throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)

        let resolvedYtDlp = Self.resolve(candidates: Self.ytDlpCandidates)
        let resolvedFfmpeg = Self.resolve(candidates: Self.ffmpegCandidates)
        ytDlpPath = resolvedYtDlp
        ffmpegPath = resolvedFfmpeg
        jsRuntimePath = Self.resolve(candidates: Self.denoCandidates)

        guard resolvedYtDlp != nil, resolvedFfmpeg != nil else {
            throw BinaryError.missing(ytDlp: resolvedYtDlp == nil, ffmpeg: resolvedFfmpeg == nil)
        }

        await refreshVersion()
    }

    /// Re-reads `yt-dlp --version`. Call after `prepare()` if the version
    /// display needs to be refreshed (e.g. a Settings screen "Refresh" button).
    func refreshVersion() async {
        version = await capture(arguments: ["--version"]) ?? version
    }

    /// Returns the first candidate path that exists, is a regular file (not a
    /// directory — `isExecutableFile(atPath:)` alone returns true for any
    /// directory with the traversal bit set, e.g. a broken Cellar symlink or
    /// a partial reinstall), and is executable. Otherwise nil.
    private static func resolve(candidates: [String]) -> String? {
        let fileManager = FileManager.default
        return candidates.first { path in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { return false }
            return fileManager.isExecutableFile(atPath: path)
        }
    }

    private func capture(arguments: [String]) async -> String? {
        guard let ytDlpPath else { return nil }
        var output: [String] = []
        for await event in SystemProcessRunner().run(executable: ytDlpPath, arguments: arguments) {
            if case .stdout(let line) = event, !line.isEmpty { output.append(line) }
        }
        return output.last
    }
}
