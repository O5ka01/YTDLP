import SwiftUI
import YTDLPCore

struct OptionsDrawer: View {
    @Binding var audioOnly: Bool
    @Binding var audioFormat: AudioFormat
    @Binding var subtitlesEnabled: Bool
    @Binding var cookiesEnabled: Bool
    @Binding var clipEnabled: Bool
    @Binding var clipStart: String
    @Binding var clipEnd: String

    let isPlaylist: Bool
    let notices: [OptionNotice]
    let cookieBrowser: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Audio only", isOn: $audioOnly)
            if audioOnly {
                Picker("Format", selection: $audioFormat) {
                    ForEach(AudioFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle("Subtitles", isOn: $subtitlesEnabled)
                .disabled(audioOnly)

            Toggle("Use \(cookieBrowser.capitalized) cookies", isOn: $cookiesEnabled)

            Toggle("Clip", isOn: $clipEnabled)
                .disabled(isPlaylist)
            if clipEnabled, !isPlaylist {
                HStack(spacing: 6) {
                    TextField("00:00:00", text: $clipStart).frame(width: 80)
                    Text("–").foregroundStyle(.secondary)
                    TextField("00:00:00", text: $clipEnd).frame(width: 80)
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            }

            ForEach(notices, id: \.self) { notice in
                Label(notice.message, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
    }
}
