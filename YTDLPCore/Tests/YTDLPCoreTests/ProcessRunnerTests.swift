import Testing
@testable import YTDLPCore

@Test func processEventsAreEquatable() {
    #expect(ProcessEvent.stdout("a") == ProcessEvent.stdout("a"))
    #expect(ProcessEvent.stdout("a") != ProcessEvent.stderr("a"))
    #expect(ProcessEvent.exit(code: 0) != ProcessEvent.exit(code: 1))
}
