import Testing
@testable import YTDLPCore

@Test func timeRangeFormatsAsYtDlpSection() {
    let range = TimeRange(start: "00:01:30", end: "00:02:45")
    #expect(range.sectionArgument == "*00:01:30-00:02:45")
}

@Test func defaultOptionsAreVideoBestQuality() {
    let options = DownloadOptions.preview
    #expect(options.mode == .video(maxHeight: nil))
    #expect(options.clip == nil)
    #expect(options.subtitleLanguages == nil)
    #expect(options.cookieBrowser == nil)
}

@Test func clipDisablesSponsorBlock() {
    var raw = DownloadOptions.preview
    raw.sponsorBlockCategories = ["sponsor", "intro"]
    raw.clip = TimeRange(start: "00:01:00", end: "00:02:00")

    let resolved = OptionResolver.resolve(raw)

    #expect(resolved.options.sponsorBlockCategories.isEmpty)
    #expect(resolved.options.clip == raw.clip)
    #expect(resolved.notices == [.sponsorBlockDisabledByClip])
}

@Test func audioModeDisablesSubtitles() {
    var raw = DownloadOptions.preview
    raw.mode = .audio(format: .m4a)
    raw.subtitleLanguages = ["en"]

    let resolved = OptionResolver.resolve(raw)

    #expect(resolved.options.subtitleLanguages == nil)
    #expect(resolved.notices == [.subtitlesUnavailableInAudioMode])
}

@Test func playlistDisablesClip() {
    var raw = DownloadOptions.preview
    raw.isPlaylist = true
    raw.clip = TimeRange(start: "00:01:00", end: "00:02:00")

    let resolved = OptionResolver.resolve(raw)

    #expect(resolved.options.clip == nil)
    #expect(resolved.notices == [.clipUnavailableForPlaylist])
}

@Test func playlistDroppingClipLeavesSponsorBlockOn() {
    var raw = DownloadOptions.preview
    raw.isPlaylist = true
    raw.clip = TimeRange(start: "00:01:00", end: "00:02:00")
    raw.sponsorBlockCategories = ["sponsor"]

    let resolved = OptionResolver.resolve(raw)

    #expect(resolved.options.sponsorBlockCategories == ["sponsor"])
    #expect(resolved.notices == [.clipUnavailableForPlaylist])
}

@Test func cleanOptionsProduceNoNotices() {
    #expect(OptionResolver.resolve(.preview).notices.isEmpty)
}
