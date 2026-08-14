import SwiftUI
import YTDLPCore

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var binaries = BinaryManager.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(settings.downloadFolder)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…", action: chooseFolder)
                }
            } header: {
                Text("Save to")
            }

            Section {
                ForEach(AppSettings.availableSponsorBlockCategories, id: \.self) { category in
                    Toggle(category.replacingOccurrences(of: "_", with: " ").capitalized, isOn: binding(for: category))
                }
            } header: {
                Text("Remove segments")
            }

            Section {
                Toggle("Prefer H.264 / AAC", isOn: $settings.preferAppleCodecs)
                Text("Plays natively in QuickTime and on Apple TV. Turn off for smaller files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Stepper("Parallel fragments: \(settings.concurrentFragments)",
                        value: $settings.concurrentFragments, in: 1...16)

                Picker("Audio format", selection: $settings.defaultAudioFormat) {
                    ForEach(AudioFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }

                TextField("Subtitle languages", text: $settings.subtitleLanguages)

                Picker("Cookies from", selection: $settings.cookieBrowser) {
                    ForEach(AppSettings.availableCookieBrowsers, id: \.self) { Text($0.capitalized).tag($0) }
                }
            } header: {
                Text("Downloads")
            }

            Section {
                LabeledContent("yt-dlp", value: binaries.version)
                pathRow(label: "yt-dlp path", path: binaries.ytDlpPath, installHint: "brew install yt-dlp")
                pathRow(label: "ffmpeg path", path: binaries.ffmpegPath, installHint: "brew install ffmpeg")
                pathRow(label: "deno path", path: binaries.jsRuntimePath, installHint: "brew install deno")
                Text("deno runs YouTube's player JavaScript. Without it some formats go missing and downloads can fail with HTTP 403.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Refresh") {
                    Task { await binaries.refreshVersion() }
                }
                Text("Updates come from Homebrew — run brew upgrade yt-dlp")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Tools")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func pathRow(label: String, path: String?, installHint: String) -> some View {
        if let path {
            LabeledContent(label) {
                Text(path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
        } else {
            LabeledContent(label) {
                Text("Not found — \(installHint)")
                    .foregroundStyle(.red)
            }
        }
    }

    private func binding(for category: String) -> Binding<Bool> {
        Binding(
            get: { settings.sponsorBlockCategories.contains(category) },
            set: { isOn in
                if isOn {
                    if !settings.sponsorBlockCategories.contains(category) {
                        settings.sponsorBlockCategories.append(category)
                    }
                } else {
                    settings.sponsorBlockCategories.removeAll { $0 == category }
                }
            }
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.downloadFolder = url.path
        }
    }
}
