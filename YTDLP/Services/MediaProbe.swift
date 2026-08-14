import Foundation
import YTDLPCore

/// Fetches metadata for a URL without downloading it.
///
/// Takes already-resolved binary paths rather than a `BinaryManager` reference:
/// `BinaryManager` is `@MainActor`-isolated and exposes `ytDlpPath`/`ffmpegPath`
/// as `String?`, so callers resolve those optionals on the main actor and pass
/// concrete strings in here. That avoids an actor hop in this type's async,
/// non-isolated `probe(url:)` and keeps `MediaProbe` trivially testable.
struct MediaProbe {
    var runner: any ProcessRunner = SystemProcessRunner()
    let ytDlpPath: String
    let ffmpegPath: String
    /// See `BinaryManager.jsRuntimePath`. The probe needs it for the same
    /// reason the download does: without a JavaScript runtime YouTube's
    /// extractor falls back to a client that reports a reduced format list,
    /// which would leave the quality menu short of the real options.
    let jsRuntimePath: String?

    struct ProbeError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func probe(url: String) async throws -> MediaInfo {
        var stdout: [String] = []
        var stderr: [String] = []
        var exitCode: Int32 = -1

        var arguments = [
            "-J",
            "--no-warnings",
            "--flat-playlist",
            "--ffmpeg-location", ffmpegPath,
        ]
        if let jsRuntimePath {
            arguments += ["--js-runtimes", "deno:\(jsRuntimePath)"]
        }
        arguments += ["--", url]

        for await event in runner.run(executable: ytDlpPath, arguments: arguments) {
            switch event {
            case .stdout(let line): stdout.append(line)
            case .stderr(let line): stderr.append(line)
            case .exit(let code): exitCode = code
            }
        }

        try Task.checkCancellation()

        guard exitCode == 0 else {
            throw ProbeError(message: ErrorMapper.message(forStderr: stderr.joined(separator: "\n")))
        }
        do {
            return try MediaInfo.decode(from: Data(stdout.joined().utf8))
        } catch {
            throw ProbeError(message: "Couldn't read the video details.")
        }
    }
}
