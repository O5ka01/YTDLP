import Testing
@testable import YTDLPCore

@Test func parsesPaddedProgressLine() {
    let event = ProgressParser.parse("dl: 42.5%|  1.23MiB/s|00:31")
    #expect(event == .progress(percent: 42.5, speed: "1.23MiB/s", eta: "00:31"))
}

@Test func parsesHundredPercent() {
    #expect(ProgressParser.parse("dl:100.0%|  5.00MiB/s|00:00")
            == .progress(percent: 100, speed: "5.00MiB/s", eta: "00:00"))
}

@Test func unknownPercentIsIgnoredRatherThanReportedAsZero() {
    #expect(ProgressParser.parse("dl:Unknown|Unknown B/s|Unknown") == nil)
}

@Test func nonProgressLinesAreIgnored() {
    #expect(ProgressParser.parse("[youtube] Extracting URL: https://youtu.be/x") == nil)
    #expect(ProgressParser.parse("") == nil)
}

@Test func recognisesPostProcessingStages() {
    #expect(ProgressParser.parse(#"[Merger] Merging formats into "video.mp4""#) == .stage(.merging))
    #expect(ProgressParser.parse("[ModifyChapters] Removing chapters from video.mp4") == .stage(.removingSponsors))
    #expect(ProgressParser.parse("[ExtractAudio] Destination: audio.m4a") == .stage(.extractingAudio))
    #expect(ProgressParser.parse("[EmbedSubtitle] Embedding subtitles in video.mp4") == .stage(.embeddingSubtitles))
}

@Test func recognisesRetries() {
    #expect(ProgressParser.parse("[download] Got error: timed out. Retrying (1/10)...") == .retrying)
}

@Test func malformedProgressLineIsIgnoredNotCrashed() {
    #expect(ProgressParser.parse("dl:42.5%") == nil)
    #expect(ProgressParser.parse("dl:|||") == nil)
}
