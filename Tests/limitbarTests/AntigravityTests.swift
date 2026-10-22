import Testing
import Foundation
@testable import limitbar

@Test func antigravityParseFixture() throws {
    let now = ISO8601DateFormatter().date(from: "2026-10-22T07:00:00Z")!
    let s = try Antigravity.parse(try fixture("antigravity"), now: now)
    #expect(s.provider == .gemini)
    #expect(s.plan == "Antigravity")
    #expect(s.windows.map(\.label) == ["Gemini 3 Pro (High)", "Gemini 3 Flash", "Claude Sonnet 5.5 (High)"])
    #expect(s.windows.map { $0.usedPercent.rounded() } == [100, 40, 0])
    #expect(s.windows.map(\.kind) == [.fiveHour, .weekly, .fiveHour])
    #expect(s.shortWindow?.label == "Gemini 3 Pro (High)")
}

@Test func antigravityRefreshTokenFromGoKeyring() throws {
    let json = #"{"auth_method":"consumer","token":{"access_token":"test-token","refresh_token":"test-token","token_type":"Bearer"}}"#
    let stored = Data((Antigravity.keyringPrefix + Data(json.utf8).base64EncodedString()).utf8)
    #expect(try Antigravity.refreshToken(from: stored) == "test-token")
}
