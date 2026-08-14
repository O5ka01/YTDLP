import Testing
@testable import YTDLPCore

@Test func everyFormatHasItsOwnMenuLabel() {
    let labels = AudioFormat.allCases.map(\.displayName)
    #expect(labels.allSatisfy { !$0.isEmpty })
    #expect(Set(labels).count == AudioFormat.allCases.count)
}

@Test func menuLabelNamesTheCodecRatherThanTheContainer() {
    // "m4a" is the container; AAC is what a person is actually choosing.
    #expect(AudioFormat.m4a.displayName == "AAC (m4a)")
    #expect(AudioFormat.mp3.displayName == "MP3")
    #expect(AudioFormat.opus.displayName == "Opus")
}
