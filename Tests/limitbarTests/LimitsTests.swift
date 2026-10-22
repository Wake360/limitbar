import Testing
import Foundation
@testable import limitbar

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func win(_ kind: WindowKind, _ pct: Double, _ reset: TimeInterval?) -> UsageWindow {
    UsageWindow(label: "w", usedPercent: pct, resetsAt: reset.map { t0.addingTimeInterval($0) }, kind: kind)
}

private func snap(_ p: Provider, _ windows: [UsageWindow]) -> Snapshot {
    Snapshot(provider: p, plan: "", windows: windows, fetchedAt: t0)
}

@Test func availabilityHotUsesLatestHotReset() {
    let s = snap(.claude, [win(.fiveHour, 92, 3600), win(.weekly, 100, 3 * 86400)])
    let a = Limits.availability(.claude, .fresh(s), now: t0)
    #expect(a?.hot == true)
    #expect(a?.window.usedPercent == 100)
    #expect(a?.backAt == t0.addingTimeInterval(3 * 86400))
}

@Test func availabilityNotHotUsesTightestReset() {
    let s = snap(.claude, [win(.fiveHour, 10, 3600), win(.weekly, 67, 2 * 86400)])
    let a = Limits.availability(.claude, .fresh(s), now: t0)
    #expect(a?.hot == false)
    #expect(a?.backAt == t0.addingTimeInterval(2 * 86400))
}

@Test func availabilityHotWithNilResetHasNilBackAt() {
    let s = snap(.codex, [win(.credits, 95, nil)])
    let a = Limits.availability(.codex, .fresh(s), now: t0)
    #expect(a?.hot == true)
    #expect(a?.backAt == nil)
}

@Test func availabilityExactlyEightyIsHot() {
    let s = snap(.claude, [win(.fiveHour, 80, 3600)])
    #expect(Limits.availability(.claude, .fresh(s), now: t0)?.hot == true)
}

@Test func availabilityExcludesLoggedOutAndEmpty() {
    let s = snap(.claude, [win(.fiveHour, 92, 3600)])
    #expect(Limits.availability(.claude, .loggedOut(s, "x"), now: t0) == nil)
    #expect(Limits.availability(.claude, .empty, now: t0) == nil)
    #expect(Limits.availability(.claude, .stale(s, "x"), now: t0) != nil)
}

@MainActor @Test func cachedWindowPastItsResetIsNotHot() {
    let s = snap(.claude, [win(.fiveHour, 92, 3600), win(.weekly, 17, 3 * 86400)])
    let now = t0.addingTimeInterval(3600 + 300)
    let status: [Provider: ProviderStatus] = [
        .claude: .stale(s, "cached"),
        .codex: .fresh(snap(.codex, [win(.fiveHour, 40, 7200)])),
    ]
    let a = Limits.availability(.claude, .stale(s, "cached"), now: now)
    #expect(a?.hot == false)
    #expect(a?.window.usedPercent == 17)
    #expect(Limits.ordered(status, now: now) == [.codex, .claude, .grok])
    let items = MenuBarLabel.items(status, now: now)
    #expect(!items.isEmpty)
    #expect(items.allSatisfy { !$0.hot })
    #expect(!Verdict.make(status, now: now).headline.contains("nearly out"))
}

@Test func orderedSortsByUsageThenEnumOrder() {
    let status: [Provider: ProviderStatus] = [
        .claude: .fresh(snap(.claude, [win(.fiveHour, 17, 3600)])),
        .grok: .fresh(snap(.grok, [win(.daily, 67, 3600)])),
        .codex: .empty,
    ]
    #expect(Limits.ordered(status, now: t0) == [.grok, .claude, .codex])
}

@Test func tightestIsNilWhenNothingUsable() {
    let status: [Provider: ProviderStatus] = [.claude: .empty, .codex: .loggedOut(nil, "x")]
    #expect(Limits.tightest(status, now: t0) == nil)
}
