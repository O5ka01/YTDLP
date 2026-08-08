import SwiftUI
import YTDLPCore

struct MetadataCard: View {
    let info: MediaInfo

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: info.thumbnailURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 96, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.headline)
                    .lineLimit(2)
                Text([info.uploader, info.formattedDuration.isEmpty ? nil : info.formattedDuration]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
