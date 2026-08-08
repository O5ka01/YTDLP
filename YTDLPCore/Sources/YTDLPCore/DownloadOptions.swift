import Foundation

public enum AudioFormat: String, Equatable, Sendable, CaseIterable {
    case m4a, mp3, opus
}

public enum MediaMode: Equatable, Sendable {
    /// `maxHeight == nil` means "Best available".
    case video(maxHeight: Int?)
    case audio(format: AudioFormat)
}

public struct TimeRange: Equatable, Sendable {
    public let start: String    // "HH:MM:SS"
    public let end: String      // "HH:MM:SS"

    public init(start: String, end: String) {
        self.start = start
        self.end = end
    }

    /// The value passed to `--download-sections`.
    public var sectionArgument: String { "*\(start)-\(end)" }
}

/// Everything that determines the argv for one download.
///
/// Fields above the divider come from the Options drawer and reset after each
/// download; fields below come from Settings and persist.
public struct DownloadOptions: Equatable, Sendable {
    public var mode: MediaMode
    public var isPlaylist: Bool
    public var clip: TimeRange?
    /// `nil` means subtitles are off.
    public var subtitleLanguages: [String]?
    /// `nil` means cookies are off. Otherwise a yt-dlp browser name, e.g. "safari".
    public var cookieBrowser: String?

    public var sponsorBlockCategories: [String]
    public var preferAppleCodecs: Bool
    public var concurrentFragments: Int
    public var downloadFolder: String
    public var ffmpegPath: String
    public var archivePath: String

    public init(
        mode: MediaMode = .video(maxHeight: nil),
        isPlaylist: Bool = false,
        clip: TimeRange? = nil,
        subtitleLanguages: [String]? = nil,
        cookieBrowser: String? = nil,
        sponsorBlockCategories: [String] = [],
        preferAppleCodecs: Bool = true,
        concurrentFragments: Int = 4,
        downloadFolder: String,
        ffmpegPath: String,
        archivePath: String
    ) {
        self.mode = mode
        self.isPlaylist = isPlaylist
        self.clip = clip
        self.subtitleLanguages = subtitleLanguages
        self.cookieBrowser = cookieBrowser
        self.sponsorBlockCategories = sponsorBlockCategories
        self.preferAppleCodecs = preferAppleCodecs
        self.concurrentFragments = concurrentFragments
        self.downloadFolder = downloadFolder
        self.ffmpegPath = ffmpegPath
        self.archivePath = archivePath
    }

    /// Fixed values used by tests and SwiftUI previews so assertions stay readable.
    public static let preview = DownloadOptions(
        downloadFolder: "/Users/me/Downloads",
        ffmpegPath: "/App/ffmpeg",
        archivePath: "/App/archive.txt"
    )
}
