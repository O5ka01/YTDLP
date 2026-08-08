import SwiftUI
import YTDLPCore

/// A compact, scrollable list of a probed playlist's entries.
///
/// Not part of the Task 14 brief's `ContentView` — the brief's `QueueList`
/// renders `DownloadJob`s, and a playlist is queued as a single job, so
/// nothing there ever reads `MediaInfo.entries`. This is the only consumer
/// of `PlaylistEntry.displayTitle`, which substitutes "[Unavailable]" for
/// deleted or private videos so numbering still lines up with yt-dlp's own
/// `--playlist-index`. Deliberately plain: just an index and a title, no
/// per-entry controls.
struct PlaylistEntryList: View {
    let entries: [PlaylistEntry]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 26, alignment: .trailing)
                        Text(entry.displayTitle)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 160)
    }
}
