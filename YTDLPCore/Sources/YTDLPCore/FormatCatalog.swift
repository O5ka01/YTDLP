import Foundation

public struct FormatChoice: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    /// `nil` for "Best" — no height cap.
    public let maxHeight: Int?
}

/// Collapses yt-dlp's long format list into the handful of choices worth showing.
///
/// Reports heights rather than format ids, because ids can change between the
/// probe and the download.
public enum FormatCatalog {
    public static func choices(from formats: [RawFormat]) -> [FormatChoice] {
        let best = FormatChoice(id: "best", label: "Best", maxHeight: nil)

        var largestFilesize: [Int: Int] = [:]
        for format in formats where format.hasVideo {
            guard let height = format.height else { continue }
            largestFilesize[height] = max(largestFilesize[height] ?? 0, format.filesize ?? 0)
        }

        let rest = largestFilesize.keys.sorted(by: >).map { height in
            FormatChoice(
                id: String(height),
                label: label(height: height, filesize: largestFilesize[height] ?? 0),
                maxHeight: height
            )
        }
        return [best] + rest
    }

    /// The size shown is the largest at that height across codecs, which is not
    /// necessarily the variant yt-dlp ends up selecting.
    private static func label(height: Int, filesize: Int) -> String {
        let name = height >= 2160 ? "4K" : "\(height)p"
        guard filesize > 0 else { return name }
        return "\(name) · \(humanSize(filesize))"
    }

    /// Deliberately not `ByteCountFormatter`: that renders "91,2 MB" in a German
    /// locale and "91.2 MB" in a US one, which would make the label untestable.
    /// Base 1000, matching what Finder reports.
    private static func humanSize(_ bytes: Int) -> String {
        let megabytes = Double(bytes) / 1_000_000
        return megabytes >= 1000
            ? String(format: "%.1f GB", megabytes / 1000)
            : String(format: "%.0f MB", megabytes)
    }
}
