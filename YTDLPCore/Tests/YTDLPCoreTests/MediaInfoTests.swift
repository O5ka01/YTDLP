import Foundation
import Testing
@testable import YTDLPCore

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
    return try Data(contentsOf: url)
}

@Test func decodesSingleVideoMetadata() throws {
    let info = try MediaInfo.decode(from: fixture("single-video"))

    #expect(info.title == "Never Gonna Give You Up")
    #expect(info.uploader == "Rick Astley")
    #expect(info.duration == 213)
    #expect(info.thumbnailURL?.host == "i.ytimg.com")
    #expect(info.isPlaylist == false)
    #expect(info.entries.isEmpty)
    #expect(info.formats.count == 6)
}

@Test func decodesFormatFields() throws {
    let info = try MediaInfo.decode(from: fixture("single-video"))
    let format = try #require(info.formats.first { $0.formatID == "137" })

    #expect(format.height == 1080)
    #expect(format.vcodec == "avc1.640028")
    #expect(format.acodec == "none")
    #expect(format.filesize == 91_226_112)
}

@Test func audioOnlyFormatHasNoHeight() throws {
    let info = try MediaInfo.decode(from: fixture("single-video"))
    let format = try #require(info.formats.first { $0.formatID == "139" })

    #expect(format.height == nil)
    #expect(format.vcodec == "none")
}

@Test func decodesPlaylist() throws {
    let info = try MediaInfo.decode(from: fixture("playlist"))

    #expect(info.isPlaylist)
    #expect(info.title == "Lecture Series")
    #expect(info.entries.count == 4)
    #expect(info.entries[2].title == "Lecture 3")
    #expect(info.entries[0].url == "https://youtu.be/aaa")
    #expect(info.formats.isEmpty)
}

@Test func formattedDurationIsHumanReadable() throws {
    let info = try MediaInfo.decode(from: fixture("single-video"))
    #expect(info.formattedDuration == "3:33")
}

@Test func playlistEntryWithNullTitleDecodesWithPlaceholder() throws {
    let info = try MediaInfo.decode(from: fixture("playlist"))
    let unavailable = try #require(info.entries.first { $0.id == "ddd" })
    #expect(unavailable.title == nil)
    #expect(unavailable.displayTitle == "[Unavailable]")
    #expect(info.entries.count == 4)
}

@Test func availableEntryDisplaysItsRealTitle() throws {
    let info = try MediaInfo.decode(from: fixture("playlist"))
    let normal = try #require(info.entries.first { $0.id == "aaa" })
    #expect(normal.displayTitle == "Lecture 1")
}

@Test func garbageInputThrows() {
    #expect(throws: (any Error).self) {
        try MediaInfo.decode(from: Data("not json".utf8))
    }
}
