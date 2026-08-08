import Foundation

/// A post-download step. These report no percentage, so the UI shows an
/// indeterminate bar rather than a fabricated one.
public enum Stage: Equatable, Sendable {
    case merging
    case removingSponsors
    case extractingAudio
    case embeddingSubtitles

    public var label: String {
        switch self {
        case .merging: "Merging…"
        case .removingSponsors: "Removing sponsors…"
        case .extractingAudio: "Extracting audio…"
        case .embeddingSubtitles: "Adding subtitles…"
        }
    }
}

public enum ProgressEvent: Equatable, Sendable {
    case progress(percent: Double, speed: String, eta: String)
    case stage(Stage)
    case retrying
}

/// Turns one line of yt-dlp stdout into an event, or `nil` if it carries nothing
/// the UI needs. Unparseable lines are always `nil` — never a crash, never 0%.
public enum ProgressParser {
    private static let stagePrefixes: [(String, Stage)] = [
        ("[Merger]", .merging),
        ("[ModifyChapters]", .removingSponsors),
        ("[SponsorBlock]", .removingSponsors),
        ("[ExtractAudio]", .extractingAudio),
        ("[EmbedSubtitle]", .embeddingSubtitles),
    ]

    public static func parse(_ line: String) -> ProgressEvent? {
        if line.hasPrefix("dl:") {
            return parseProgress(String(line.dropFirst(3)))
        }
        if line.contains("Retrying") {
            return .retrying
        }
        for (prefix, stage) in stagePrefixes where line.hasPrefix(prefix) {
            return .stage(stage)
        }
        return nil
    }

    private static func parseProgress(_ body: String) -> ProgressEvent? {
        let fields = body.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard fields.count == 3 else { return nil }

        let percentField = fields[0].hasSuffix("%") ? String(fields[0].dropLast()) : fields[0]
        guard let percent = Double(percentField) else { return nil }

        return .progress(percent: percent, speed: fields[1], eta: fields[2])
    }
}
