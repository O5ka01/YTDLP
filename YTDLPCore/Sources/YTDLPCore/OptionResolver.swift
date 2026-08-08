import Foundation

/// A control the resolver switched off, and why. Surfaced in the Options drawer.
public enum OptionNotice: String, Equatable, Sendable, CaseIterable {
    case sponsorBlockDisabledByClip
    case subtitlesUnavailableInAudioMode
    case clipUnavailableForPlaylist

    public var message: String {
        switch self {
        case .sponsorBlockDisabledByClip:
            "Sponsor removal is off while clipping."
        case .subtitlesUnavailableInAudioMode:
            "Audio files can't carry subtitles."
        case .clipUnavailableForPlaylist:
            "A time range doesn't apply to a playlist."
        }
    }
}

public struct ResolvedOptions: Equatable, Sendable {
    public let options: DownloadOptions
    public let notices: [OptionNotice]
}

/// Applies the option conflict rules from the design spec.
///
/// Order matters: the playlist rule drops the clip first, so that a playlist
/// does not lose SponsorBlock to a clip that was itself discarded.
public enum OptionResolver {
    public static func resolve(_ raw: DownloadOptions) -> ResolvedOptions {
        var options = raw
        var notices: [OptionNotice] = []

        if options.isPlaylist, options.clip != nil {
            options.clip = nil
            notices.append(.clipUnavailableForPlaylist)
        }

        if options.clip != nil, !options.sponsorBlockCategories.isEmpty {
            options.sponsorBlockCategories = []
            notices.append(.sponsorBlockDisabledByClip)
        }

        if case .audio = options.mode, options.subtitleLanguages != nil {
            options.subtitleLanguages = nil
            notices.append(.subtitlesUnavailableInAudioMode)
        }

        return ResolvedOptions(options: options, notices: notices)
    }
}
