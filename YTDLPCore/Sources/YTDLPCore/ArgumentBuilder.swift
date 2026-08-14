import Foundation

/// Builds the yt-dlp command line. The only place in the codebase that does so.
public enum ArgumentBuilder {
    /// Kept verbatim in the spec; `ProgressParser` parses exactly this shape.
    public static let progressTemplate =
        "dl:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s"

    public static func argv(url: String, options resolved: ResolvedOptions) -> [String] {
        let options = resolved.options
        var argv: [String] = [
            "--newline",
            "--progress-template", progressTemplate,
            "--ffmpeg-location", options.ffmpegPath,
            "--paths", options.downloadFolder,
            "-N", String(options.concurrentFragments),
            "-R", "infinite",
            "--fragment-retries", "infinite",
            "--embed-metadata",
            "--embed-chapters",
        ]

        // deno is the only runtime yt-dlp enables by default, and the only one
        // `BinaryManager` looks for, so the runtime name is fixed here.
        if let jsRuntimePath = options.jsRuntimePath {
            argv += ["--js-runtimes", "deno:\(jsRuntimePath)"]
        }

        argv += outputArguments(options)
        argv += modeArguments(options)
        argv += featureArguments(options)
        // Without `--`, yt-dlp (like any getopt-style parser) can misread a
        // URL that happens to start with a dash as an option instead of the
        // positional argument it is.
        argv.append("--")
        argv.append(url)
        return argv
    }

    private static func outputArguments(_ options: DownloadOptions) -> [String] {
        if options.isPlaylist {
            return [
                "--yes-playlist",
                "--download-archive", options.archivePath,
                "-o", "%(playlist_title)s/%(playlist_index)03d - %(title)s.%(ext)s",
            ]
        }
        return ["--no-playlist", "-o", "%(title)s.%(ext)s"]
    }

    private static func modeArguments(_ options: DownloadOptions) -> [String] {
        switch options.mode {
        case .video(let maxHeight):
            let selector = maxHeight.map { "bv*[height<=\($0)]+ba/b[height<=\($0)]" } ?? "bv*+ba/b"
            var argv = ["-f", selector, "--merge-output-format", "mp4"]
            if options.preferAppleCodecs {
                argv += ["-S", "vcodec:h264,acodec:aac"]
            }
            return argv

        case .audio(let format):
            return [
                "-f", "ba/b",
                "-x",
                "--audio-format", format.rawValue,
                "--audio-quality", "0",
                "--embed-thumbnail",
            ]
        }
    }

    private static func featureArguments(_ options: DownloadOptions) -> [String] {
        var argv: [String] = []

        if !options.sponsorBlockCategories.isEmpty {
            argv += ["--sponsorblock-remove", options.sponsorBlockCategories.joined(separator: ",")]
        }
        if let clip = options.clip {
            argv += ["--download-sections", clip.sectionArgument, "--force-keyframes-at-cuts"]
        }
        if let languages = options.subtitleLanguages, !languages.isEmpty {
            argv += [
                "--write-subs",
                "--write-auto-subs",
                "--sub-langs", languages.joined(separator: ","),
                "--embed-subs",
                "--convert-subs", "srt",
            ]
        }
        if let browser = options.cookieBrowser {
            argv += ["--cookies-from-browser", browser]
        }
        return argv
    }
}
