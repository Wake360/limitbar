import Testing
import Foundation
@testable import limitbar

private func local(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

private let now = local(22, 11, 25)
private let soon = local(22, 13, 0)
private let sunday = local(25, 9, 0)

private func fresh(_ p: Provider, _ kind: WindowKind, _ pct: Double, _ reset: Date?) -> ProviderStatus {
    .fresh(Snapshot(provider: p, plan: "", windows: [UsageWindow(label: "w", usedPercent: pct, resetsAt: reset, kind: kind)], fetchedAt: now))
}

@Test func verdictNoData() {
    let v = Verdict.make([.claude: .empty, .codex: .empty], now: now)
    #expect(v == Verdict(headline: "No data yet", line: "Waiting for the first refresh."))
}

@Test func verdictNoDataWithSignedOutAsksToSignIn() {
    let v = Verdict.make([.claude: .empty, .codex: .loggedOut(nil, "x")], now: now)
    #expect(v == Verdict(headline: "No data yet", line: "Sign in to a provider to see limits."))
}

@Test func verdictAllClear() {
    let v = Verdict.make([
        .claude: fresh(.claude, .fiveHour, 17, soon),
        .grok: fresh(.grok, .weekly, 67, sunday),
    ], now: now)
    #expect(v == Verdict(headline: "All clear", line: "Tightest is Grok weekly, 33% left."))
}

@Test func verdictOneHotSoon() {
    let v = Verdict.make([
        .claude: fresh(.claude, .fiveHour, 92, soon),
        .codex: fresh(.codex, .fiveHour, 20, soon),
        .gemini: fresh(.gemini, .daily, 10, soon),
    ], now: now)
    #expect(v == Verdict(headline: "Claude is nearly out", line: "Back in 1 h 35 min, at 13:00. Codex and Gemini are free now."))
}

@Test func verdictOneHotLater() {
    let v = Verdict.make([
        .grok: fresh(.grok, .weekly, 91, sunday),
        .claude: fresh(.claude, .fiveHour, 10, soon),
    ], now: now)
    #expect(v == Verdict(headline: "Grok is nearly out", line: "Back Sun 09:00. Claude is free now."))
}

@Test func verdictOneHotNoReset() {
    let v = Verdict.make([
        .grok: fresh(.grok, .credits, 95, nil),
        .claude: fresh(.claude, .fiveHour, 10, soon),
    ], now: now)
    #expect(v == Verdict(headline: "Grok is nearly out", line: "At 95%, no reset time. Claude is free now."))
}

@Test func verdictTwoHot() {
    let v = Verdict.make([
        .claude: fresh(.claude, .fiveHour, 92, soon),
        .grok: fresh(.grok, .weekly, 91, sunday),
        .codex: fresh(.codex, .fiveHour, 20, soon),
    ], now: now)
    #expect(v == Verdict(headline: "Claude and Grok are nearly out", line: "Claude back in 1 h 35 min, Grok Sun 09:00. Codex is free now."))
}

@Test func verdictEverythingUsedUp() {
    let v = Verdict.make([
        .claude: fresh(.claude, .fiveHour, 92, soon),
        .grok: fresh(.grok, .weekly, 91, sunday),
    ], now: now)
    #expect(v == Verdict(headline: "Everything is used up", line: "First back: Claude in 1 h 35 min, at 13:00."))
}

@Test func verdictEverythingUsedUpLater() {
    let v = Verdict.make([.grok: fresh(.grok, .weekly, 91, sunday)], now: now)
    #expect(v == Verdict(headline: "Everything is used up", line: "First back: Grok Sun 09:00."))
}

@Test func verdictEverythingUsedUpNoReset() {
    let v = Verdict.make([.grok: fresh(.grok, .credits, 95, nil)], now: now)
    #expect(v == Verdict(headline: "Everything is used up", line: "Nothing has a reset time yet."))
}

@Test func verdictIgnoresLoggedOut() {
    let s = Snapshot(provider: .claude, plan: "", windows: [UsageWindow(label: "w", usedPercent: 92, resetsAt: soon, kind: .fiveHour)], fetchedAt: now)
    let v = Verdict.make([.claude: .loggedOut(s, "x"), .codex: fresh(.codex, .fiveHour, 0, soon)], now: now)
    #expect(v.headline == "All clear")
}
