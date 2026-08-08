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
