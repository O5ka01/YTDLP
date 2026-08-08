import Foundation

public struct RawFormat: Equatable, Sendable, Decodable {
    public let formatID: String
    public let ext: String
    public let height: Int?
    public let vcodec: String?
    public let acodec: String?
    public let filesize: Int?

    private enum CodingKeys: String, CodingKey {
        case formatID = "format_id"
        case ext, height, vcodec, acodec, filesize
    }

    /// yt-dlp writes the string "none" rather than omitting the codec.
    public var hasVideo: Bool { vcodec != nil && vcodec != "none" }
}

public struct PlaylistEntry: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let title: String
    public let url: String?
    public let duration: Double?
}

/// The decoded output of `yt-dlp -J`.
public struct MediaInfo: Equatable, Sendable, Decodable {
    public let title: String
    public let uploader: String?
    public let duration: Double?
    public let thumbnailURL: URL?
    public let formats: [RawFormat]
    public let entries: [PlaylistEntry]

    public var isPlaylist: Bool { !entries.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case title, uploader, duration, formats, entries
        case thumbnailURL = "thumbnail"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        uploader = try container.decodeIfPresent(String.self, forKey: .uploader)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        formats = try container.decodeIfPresent([RawFormat].self, forKey: .formats) ?? []
        entries = try container.decodeIfPresent([PlaylistEntry].self, forKey: .entries) ?? []
    }

    public static func decode(from data: Data) throws -> MediaInfo {
        try JSONDecoder().decode(MediaInfo.self, from: data)
    }

    /// "3:33", or "1:02:03" for anything an hour or longer.
    public var formattedDuration: String {
        guard let duration, duration > 0 else { return "" }
        let total = Int(duration.rounded())
        let (hours, minutes, seconds) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
