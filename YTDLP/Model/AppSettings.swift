import Foundation
import SwiftUI
import YTDLPCore

/// Persisted preferences, and the single place a `DownloadOptions` is assembled
/// from settings plus the drawer's per-download choices.
///
/// Marked `@MainActor` for the same reason as `BinaryManager`: `@Observable`
/// gives this class mutable, unsynchronized state, and a `static let shared`
/// of a non-`Sendable` reference type is rejected under Swift 6 strict
/// concurrency ("static property 'shared' is not concurrency-safe").
/// Isolating the whole type to the main actor makes the singleton safe, and
/// `makeOptions` also reads the `@MainActor`-isolated `BinaryManager.shared`,
/// so this isolation is needed regardless. Every expected caller (a SwiftUI
/// view action) is already on the main actor.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var downloadFolder: String {
        didSet { UserDefaults.standard.set(downloadFolder, forKey: "downloadFolder") }
    }
    var sponsorBlockCategories: [String] {
        didSet { UserDefaults.standard.set(sponsorBlockCategories, forKey: "sponsorBlockCategories") }
    }
    var preferAppleCodecs: Bool {
        didSet { UserDefaults.standard.set(preferAppleCodecs, forKey: "preferAppleCodecs") }
    }
    var concurrentFragments: Int {
        didSet { UserDefaults.standard.set(concurrentFragments, forKey: "concurrentFragments") }
    }
    var defaultAudioFormat: AudioFormat {
        didSet { UserDefaults.standard.set(defaultAudioFormat.rawValue, forKey: "defaultAudioFormat") }
    }
    var subtitleLanguages: String {
        didSet { UserDefaults.standard.set(subtitleLanguages, forKey: "subtitleLanguages") }
    }
    var cookieBrowser: String {
        didSet { UserDefaults.standard.set(cookieBrowser, forKey: "cookieBrowser") }
    }

    static let availableSponsorBlockCategories = ["sponsor", "selfpromo", "intro", "outro", "interaction", "music_offtopic"]
    static let availableCookieBrowsers = ["safari", "chrome", "firefox", "edge", "brave"]

    private init() {
        let defaults = UserDefaults.standard
        downloadFolder = defaults.string(forKey: "downloadFolder")
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].path
        sponsorBlockCategories = defaults.stringArray(forKey: "sponsorBlockCategories") ?? ["sponsor"]
        preferAppleCodecs = defaults.object(forKey: "preferAppleCodecs") as? Bool ?? true
        concurrentFragments = defaults.object(forKey: "concurrentFragments") as? Int ?? 4
        defaultAudioFormat = AudioFormat(rawValue: defaults.string(forKey: "defaultAudioFormat") ?? "") ?? .m4a
        subtitleLanguages = defaults.string(forKey: "subtitleLanguages") ?? "en"
        cookieBrowser = defaults.string(forKey: "cookieBrowser") ?? "safari"
    }

    /// Assembles a `DownloadOptions` from these settings plus the drawer's
    /// per-download choices.
    ///
    /// `BinaryManager.ffmpegPath` is `String?` — it resolves Homebrew's install
    /// location at runtime and can be nil if ffmpeg isn't installed — while
    /// `DownloadOptions.ffmpegPath` is a plain, non-optional `String`. Rather
    /// than force-unwrap here, the resolved path is a required parameter: the
    /// caller (a SwiftUI view action, already on the main actor alongside
    /// `BinaryManager`) unwraps the optional once, decides what to do if it's
    /// nil (e.g. refuse to start the download and surface the same install
    /// hint `BinaryManager.BinaryError` produces), and only calls this method
    /// with a concrete path. This mirrors how `MediaProbe` already takes
    /// resolved `ytDlpPath`/`ffmpegPath` strings instead of a `BinaryManager`
    /// reference.
    func makeOptions(
        mode: MediaMode,
        isPlaylist: Bool,
        clip: TimeRange?,
        subtitlesEnabled: Bool,
        cookiesEnabled: Bool,
        ffmpegPath: String
    ) -> DownloadOptions {
        let languages = subtitleLanguages
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return DownloadOptions(
            mode: mode,
            isPlaylist: isPlaylist,
            clip: clip,
            subtitleLanguages: subtitlesEnabled ? (languages.isEmpty ? nil : languages) : nil,
            cookieBrowser: cookiesEnabled ? cookieBrowser : nil,
            sponsorBlockCategories: sponsorBlockCategories,
            preferAppleCodecs: preferAppleCodecs,
            concurrentFragments: concurrentFragments,
            downloadFolder: downloadFolder,
            ffmpegPath: ffmpegPath,
            archivePath: BinaryManager.shared.archivePath
        )
    }
}
