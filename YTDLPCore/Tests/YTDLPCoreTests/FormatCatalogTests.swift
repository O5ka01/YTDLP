import Foundation
import Testing
@testable import YTDLPCore

private func videoFormat(height: Int, filesize: Int? = nil) -> RawFormat {
    let json = """
    {"format_id":"f\(height)","ext":"mp4","height":\(height),"vcodec":"avc1","acodec":"none"\
    \(filesize.map { ",\"filesize\":\($0)" } ?? "")}
    """
    return try! JSONDecoder().decode(RawFormat.self, from: Data(json.utf8))
}

private func audioFormat() -> RawFormat {
    let json = #"{"format_id":"139","ext":"m4a","vcodec":"none","acodec":"mp4a"}"#
    return try! JSONDecoder().decode(RawFormat.self, from: Data(json.utf8))
}

@Test func firstChoiceIsAlwaysBest() {
    let choices = FormatCatalog.choices(from: [videoFormat(height: 720)])
    #expect(choices.first?.id == "best")
    #expect(choices.first?.label == "Best")
    #expect(choices.first?.maxHeight == nil)
}

@Test func heightsAreListedHighestFirstWithoutDuplicates() {
    let formats = [
        videoFormat(height: 360), videoFormat(height: 1080),
        videoFormat(height: 720), videoFormat(height: 1080),
    ]
    #expect(FormatCatalog.choices(from: formats).map(\.maxHeight) == [nil, 1080, 720, 360])
}

@Test func audioOnlyFormatsAreExcluded() {
    let choices = FormatCatalog.choices(from: [audioFormat(), videoFormat(height: 480)])
    #expect(choices.map(\.maxHeight) == [nil, 480])
}

@Test func labelsUseFamiliarResolutionNames() {
    let formats = [2160, 1440, 1080, 720, 480].map { videoFormat(height: $0) }
    #expect(FormatCatalog.choices(from: formats).map(\.label)
            == ["Best", "4K", "1440p", "1080p", "720p", "480p"])
}

@Test func labelIncludesFilesizeWhenKnown() {
    let choices = FormatCatalog.choices(from: [videoFormat(height: 1080, filesize: 91_226_112)])
    #expect(choices[1].label == "1080p · 91 MB")
}

@Test func filesizeLabelIsLocaleIndependent() {
    // `ByteCountFormatter` renders "91,2 MB" in a German locale and "91.2 MB" in
    // a US one, so the catalog must not use it. This test fails if someone swaps
    // the deterministic formatter back out for the Foundation one.
    let choices = FormatCatalog.choices(from: [videoFormat(height: 720, filesize: 2_500_000_000)])
    #expect(choices[1].label == "720p · 2.5 GB")
}

@Test func audioOnlySourceOffersOnlyBest() {
    #expect(FormatCatalog.choices(from: [audioFormat()]).map(\.id) == ["best"])
}

@Test func noFormatsStillOffersBest() {
    #expect(FormatCatalog.choices(from: []).map(\.id) == ["best"])
}
