import Testing
import Foundation
@testable import limitbar

@Test func codexParseFixture() throws {
    let s = try Codex.parse(try fixture("codex"), now: Date())
    #expect(s.provider == .codex)
    #expect(s.plan == "ChatGPT Plus")
    #expect(s.windows.map(\.label) == ["5-hour", "Weekly"])
    #expect(s.windows.map(\.usedPercent) == [0, 2])
    #expect(s.windows[1].resetsAt == Date(timeIntervalSince1970: 1761674520))
}

@Test func codexUnknownPlanPassesThrough() throws {
    let data = Data(#"{"plan_type":"team","rate_limit":{"primary_window":{"used_percent":1,"limit_window_seconds":1,"reset_at":1},"secondary_window":{"used_percent":1,"limit_window_seconds":1,"reset_at":1}}}"#.utf8)
    #expect(try Codex.parse(data, now: Date()).plan == "team")
}
