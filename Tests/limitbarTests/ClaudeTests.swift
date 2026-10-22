import Testing
import Foundation
@testable import limitbar

func fixture(_ name: String) throws -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    return try Data(contentsOf: url)
}

@Test func claudeParseFixture() throws {
    let s = try Claude.parse(try fixture("claude"), plan: "Max", now: Date(timeIntervalSince1970: 0))
    #expect(s.provider == .claude)
    #expect(s.plan == "Max")
    #expect(s.windows.map(\.label) == ["5-hour", "Weekly", "Opus weekly"])
    #expect(s.windows.map(\.usedPercent) == [6, 32, 12])
    #expect(s.windows.map(\.kind) == [.fiveHour, .weekly, .weekly])
    #expect(s.windows[0].resetsAt == ISO8601DateFormatter().date(from: "2026-10-22T19:10:00Z"))
}

@Test func claudeParseWithoutOpusYieldsTwoWindows() throws {
    let data = Data(#"{"five_hour":{"utilization":1,"resets_at":"2026-10-22T19:10:00Z"},"seven_day":{"utilization":2,"resets_at":"2026-10-25T21:00:00Z"}}"#.utf8)
    #expect(try Claude.parse(data, plan: "Max", now: Date()).windows.count == 2)
}

@Test func claudeParseGarbageThrows() {
    #expect(throws: (any Error).self) { try Claude.parse(Data("{}".utf8), plan: "Max", now: Date()) }
}
