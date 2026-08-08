import SwiftUI

struct QueueList: View {
    let jobs: [DownloadJob]
    let onCancel: (DownloadJob) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(jobs) { job in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.title).font(.callout).lineLimit(1)
                            statusLine(for: job)
                        }
                        Spacer(minLength: 0)
                        Button {
                            onCancel(job)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxHeight: 160)
    }

    @ViewBuilder
    private func statusLine(for job: DownloadJob) -> some View {
        switch job.state {
        case .waiting:
            Text("Waiting…").font(.caption).foregroundStyle(.secondary)
        case .downloading(let percent, let speed, let eta):
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: percent, total: 100)
                Text("\(speed) · \(eta) left").font(.caption).foregroundStyle(.secondary)
            }
        case .processing(let label):
            VStack(alignment: .leading, spacing: 2) {
                ProgressView().progressViewStyle(.linear)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        case .retrying:
            Text("Retrying…").font(.caption).foregroundStyle(.secondary)
        case .finished:
            HStack(spacing: 6) {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
                Button("Show in Finder") {
                    Notifier.shared.reveal(folder: job.downloadFolder)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        case .failed(let message, _):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red).lineLimit(2)
        }
    }
}
