import Testing
@testable import YTDLPCore

@Test func ageRestrictionSuggestsCookies() {
    let stderr = "ERROR: [youtube] abc: Sign in to confirm your age. This video may be inappropriate for some users."
    #expect(ErrorMapper.message(forStderr: stderr)
            == "This video needs a login — try turning on Use Safari cookies.")
}

@Test func membersOnlyAndPrivateAlsoSuggestCookies() {
    #expect(ErrorMapper.message(forStderr: "ERROR: Join this channel to get access to members-only content")
            == "This video needs a login — try turning on Use Safari cookies.")
    #expect(ErrorMapper.message(forStderr: "ERROR: [youtube] abc: Private video. Sign in if you've been granted access")
            == "This video needs a login — try turning on Use Safari cookies.")
}

@Test func unavailableVideoIsReportedPlainly() {
    #expect(ErrorMapper.message(forStderr: "ERROR: [youtube] abc: Video unavailable")
            == "This video isn't available.")
    #expect(ErrorMapper.message(forStderr: "ERROR: This video has been removed by the uploader")
            == "This video isn't available.")
}

@Test func unsupportedSiteIsNamed() {
    #expect(ErrorMapper.message(forStderr: "ERROR: Unsupported URL: https://example.com/x")
            == "yt-dlp doesn't recognise this site.")
}

@Test func missingFfmpegSuggestsHomebrew() {
    #expect(ErrorMapper.message(forStderr: "ERROR: ffmpeg not found. Please install")
            == "ffmpeg wasn't found. Install it with:  brew install ffmpeg")
}

@Test func missingJavaScriptRuntimeSuggestsHomebrew() {
    // yt-dlp warns on stderr and then fails further down with a 403; the
    // warning is the actionable half, so it has to win over the ERROR line.
    let stderr = """
        WARNING: [youtube] No supported JavaScript runtime could be found. Only deno is enabled \
        by default; to use another runtime add  --js-runtimes RUNTIME[:PATH]  to your command/config.
        ERROR: unable to download video data: HTTP Error 403: Forbidden
        """
    #expect(ErrorMapper.message(forStderr: stderr)
            == "YouTube needs a JavaScript runtime. Install it with:  brew install deno")
}

@Test func unrecognisedErrorFallsBackToFirstNonEmptyLine() {
    let stderr = "\n\nWARNING: something\nERROR: some brand new failure mode\n"
    #expect(ErrorMapper.message(forStderr: stderr) == "WARNING: something")
}

@Test func emptyStderrStillProducesAMessage() {
    #expect(ErrorMapper.message(forStderr: "   \n\n") == "The download failed for an unknown reason.")
}

@Test func matchingIsCaseInsensitive() {
    #expect(ErrorMapper.message(forStderr: "error: VIDEO UNAVAILABLE") == "This video isn't available.")
}
