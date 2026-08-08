import SwiftUI
import YTDLPCore

struct ContentView: View {
    @State private var settings = AppSettings.shared
    @State private var queue = DownloadQueue.shared
    @State private var binaries = BinaryManager.shared

    @State private var urlText = ""
    @State private var info: MediaInfo?
    @State private var probeError: String?
    @State private var isProbing = false
    @State private var probeTask: Task<Void, Never>?

    @State private var choices: [FormatChoice] = []
    @State private var selectedHeight: Int?

    @State private var showOptions = false
    @State private var audioOnly = false
    @State private var audioFormat: AudioFormat = .m4a
    @State private var subtitlesEnabled = false
    @State private var cookiesEnabled = false
    @State private var clipEnabled = false
    @State private var clipStart = "00:00:00"
    @State private var clipEnd = "00:00:00"

    /// Set when `BinaryManager.prepare()` throws — yt-dlp and/or ffmpeg
    /// couldn't be found. Shown in place of the metadata card, and the
    /// Download button stays disabled while it's set (nothing downstream
    /// works without both paths).
    @State private var toolchainError: String?

    private var isToolchainReady: Bool {
        binaries.ytDlpPath != nil && binaries.ffmpegPath != nil
    }

    /// `nil` until `BinaryManager` has resolved `ffmpegPath` — `AppSettings.makeOptions`
    /// requires a concrete path, so there is nothing to build until then.
    private var draftOptions: DownloadOptions? {
        guard let ffmpegPath = binaries.ffmpegPath else { return nil }
        return settings.makeOptions(
            mode: audioOnly ? .audio(format: audioFormat) : .video(maxHeight: selectedHeight),
            isPlaylist: info?.isPlaylist ?? false,
            clip: clipEnabled ? TimeRange(start: clipStart, end: clipEnd) : nil,
            subtitlesEnabled: subtitlesEnabled,
            cookiesEnabled: cookiesEnabled,
            ffmpegPath: ffmpegPath
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Paste a video URL", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .onSubmit(startDownload)
                .onChange(of: urlText) { _, new in scheduleProbe(for: new) }

            if let toolchainError {
                Label(toolchainError, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if isProbing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading…").foregroundStyle(.secondary)
                }
            } else if let info {
                MetadataCard(info: info)
            } else if let probeError {
                Label(probeError, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if let info, info.isPlaylist {
                PlaylistEntryList(entries: info.entries)
            }

            if !queue.jobs.isEmpty {
                Divider()
                QueueList(jobs: queue.jobs) { queue.cancel($0) }
            }

            HStack(spacing: 10) {
                Picker("", selection: $selectedHeight) {
                    ForEach(choices) { choice in
                        Text(choice.label).tag(choice.maxHeight)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
                .disabled(audioOnly || choices.count <= 1)

                Button(showOptions ? "Options ⌄" : "Options ›") {
                    withAnimation(.snappy(duration: 0.15)) { showOptions.toggle() }
                }
                .buttonStyle(.link)

                Spacer()

                Button("Download", action: startDownload)
                    .keyboardShortcut(.defaultAction)
                    .disabled(info == nil || !isToolchainReady)
            }

            if showOptions, let draftOptions {
                Divider()
                OptionsDrawer(
                    audioOnly: $audioOnly,
                    audioFormat: $audioFormat,
                    subtitlesEnabled: $subtitlesEnabled,
                    cookiesEnabled: $cookiesEnabled,
                    clipEnabled: $clipEnabled,
                    clipStart: $clipStart,
                    clipEnd: $clipEnd,
                    isPlaylist: info?.isPlaylist ?? false,
                    notices: OptionResolver.resolve(draftOptions).notices,
                    cookieBrowser: settings.cookieBrowser
                )
            }
        }
        .padding(16)
        .frame(width: 460)
        .task {
            do {
                try await binaries.prepare()
                toolchainError = nil
            } catch {
                toolchainError = error.localizedDescription
            }
        }
    }

    private func scheduleProbe(for text: String) {
        probeTask?.cancel()
        info = nil
        probeError = nil
        choices = []
        selectedHeight = nil

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http") else {
            isProbing = false
            return
        }

        // Nothing to probe with until the toolchain resolves; `toolchainError`
        // is already on screen in this case.
        guard let ytDlpPath = binaries.ytDlpPath, let ffmpegPath = binaries.ffmpegPath else {
            isProbing = false
            return
        }

        isProbing = true
        probeTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                let probed = try await MediaProbe(ytDlpPath: ytDlpPath, ffmpegPath: ffmpegPath).probe(url: trimmed)
                guard !Task.isCancelled else { return }
                info = probed
                choices = FormatCatalog.choices(from: probed.formats)
                selectedHeight = choices.first(where: { $0.maxHeight == 1080 })?.maxHeight
                    ?? choices.first?.maxHeight
                audioFormat = settings.defaultAudioFormat
            } catch is CancellationError {
                // The debounce cancels the previous probe on every keystroke —
                // that's expected, not an error to surface.
                return
            } catch {
                guard !Task.isCancelled else { return }
                probeError = error.localizedDescription
            }
            isProbing = false
        }
    }

    private func startDownload() {
        guard let info, let options = draftOptions else { return }
        queue.start(
            url: urlText.trimmingCharacters(in: .whitespacesAndNewlines),
            options: options,
            title: info.title
        )
        resetDrawer()
    }

    /// Per-download options do not carry over, per the spec.
    private func resetDrawer() {
        urlText = ""
        self.info = nil
        choices = []
        selectedHeight = nil
        audioOnly = false
        subtitlesEnabled = false
        cookiesEnabled = false
        clipEnabled = false
        clipStart = "00:00:00"
        clipEnd = "00:00:00"
        showOptions = false
    }
}
