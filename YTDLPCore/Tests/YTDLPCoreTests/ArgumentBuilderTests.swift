import Testing
@testable import YTDLPCore

/// True if `argv` contains `slice` as a contiguous run.
private func contains(_ argv: [String], _ slice: [String]) -> Bool {
    guard !slice.isEmpty, argv.count >= slice.count else { return false }
    return (0...(argv.count - slice.count)).contains { start in
        Array(argv[start..<(start + slice.count)]) == slice
    }
}

private func argv(_ transform: (inout DownloadOptions) -> Void = { _ in }) -> [String] {
    var raw = DownloadOptions.preview
    transform(&raw)
    return ArgumentBuilder.argv(url: "URL", options: OptionResolver.resolve(raw))
}

@Test func alwaysAppliedArgumentsArePresent() {
    let result = argv()
    #expect(result.contains("--newline"))
    #expect(contains(result, ["--progress-template", ArgumentBuilder.progressTemplate]))
    #expect(contains(result, ["--ffmpeg-location", "/App/ffmpeg"]))
    #expect(contains(result, ["--paths", "/Users/me/Downloads"]))
    #expect(contains(result, ["-N", "4"]))
    #expect(result.contains("--embed-metadata"))
    #expect(result.contains("--embed-chapters"))
    #expect(result.last == "URL")
}

@Test func urlIsLastSoItIsNeverParsedAsAFlagValue() {
    #expect(argv { $0.cookieBrowser = "safari" }.last == "URL")
}

@Test func bestVideoUsesNoHeightCap() {
    let result = argv { $0.mode = .video(maxHeight: nil) }
    #expect(contains(result, ["-f", "bv*+ba/b"]))
    #expect(contains(result, ["--merge-output-format", "mp4"]))
}

@Test func cappedVideoFiltersOnHeight() {
    let result = argv { $0.mode = .video(maxHeight: 1080) }
    #expect(contains(result, ["-f", "bv*[height<=1080]+ba/b[height<=1080]"]))
}

@Test func appleCodecPreferenceAddsSortOrder() {
    #expect(contains(argv { $0.preferAppleCodecs = true }, ["-S", "vcodec:h264,acodec:aac"]))
    #expect(!argv { $0.preferAppleCodecs = false }.contains("-S"))
}

@Test func audioModeExtractsAndEmbedsThumbnail() {
    let result = argv { $0.mode = .audio(format: .m4a) }
    #expect(contains(result, ["-f", "ba/b"]))
    #expect(result.contains("-x"))
    #expect(contains(result, ["--audio-format", "m4a"]))
    #expect(contains(result, ["--audio-quality", "0"]))
    #expect(result.contains("--embed-thumbnail"))
    #expect(!result.contains("--merge-output-format"))
    #expect(!result.contains("-S"))
}

@Test func singleVideoOptsOutOfPlaylists() {
    #expect(argv().contains("--no-playlist"))
}
