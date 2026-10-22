import Testing
import Foundation
@testable import limitbar

private let now = Date(timeIntervalSince1970: 1_000_000)

@Test func resetTextForms() {
    let soon = UsageWindow(label: "5-hour", usedPercent: 6, resetsAt: now.addingTimeInterval(3600), kind: .fiveHour)
    let far = UsageWindow(label: "Weekly", usedPercent: 32, resetsAt: now.addingTimeInterval(3 * 86400), kind: .weekly)
    let credits = UsageWindow(label: "Credits", usedPercent: 1, resetsAt: now.addingTimeInterval(3 * 86400), kind: .credits)
    let past = UsageWindow(label: "5-hour", usedPercent: 0, resetsAt: now.addingTimeInterval(-60), kind: .fiveHour)
    #expect(Format.resetText(soon, now: now) == "resets " + Format.clock(soon.resetsAt!))
    #expect(Format.resetText(far, now: now) == "resets " + Format.day(far.resetsAt!))
    #expect(Format.resetText(credits, now: now) == "ends " + Format.day(credits.resetsAt!))
    #expect(Format.resetText(past, now: now) == nil)
    #expect(Format.resetText(UsageWindow(label: "x", usedPercent: 0, resetsAt: nil, kind: .weekly), now: now) == nil)
}

@Test func cardWindowsKeepClaudeOrderAndTopTwoGemini() {
    let claude = Snapshot(provider: .claude, plan: "Max", windows: ["5-hour", "Weekly", "Opus weekly"].map { UsageWindow(label: $0, usedPercent: 10, resetsAt: nil, kind: .weekly) }, fetchedAt: now)
    #expect(ProviderCard.windows(.claude, claude, now: now).map(\.label) == ["5-hour", "Weekly", "Opus weekly"])
    let gemini = Snapshot(provider: .gemini, plan: "", windows: [("A", 5.0), ("B", 78), ("C", 40)].map { UsageWindow(label: $0.0, usedPercent: $0.1, resetsAt: nil, kind: .daily) }, fetchedAt: now)
    #expect(ProviderCard.windows(.gemini, gemini, now: now).map(\.label) == ["B", "C"])
}

@Test func cardWindowPastItsResetReadsZero() {
    let stale = UsageWindow(label: "5-hour", usedPercent: 92, resetsAt: now.addingTimeInterval(-60), kind: .fiveHour)
    let snapshot = Snapshot(provider: .claude, plan: "Max", windows: [stale], fetchedAt: now)
    let card = ProviderCard.windows(.claude, snapshot, now: now)
    #expect(card.map(\.usedPercent) == [0])
    #expect(Format.resetText(card[0], now: now) == nil)
}

@Test func refreshStatusDot() {
    let ok = Snapshot(provider: .claude, plan: "", windows: [], fetchedAt: now)
    let earlier = now.addingTimeInterval(-120)
    #expect(RefreshStatus.make([:], lastRefresh: nil, refreshing: false, now: now) == RefreshStatus(fresh: false, text: "Updating"))
    #expect(RefreshStatus.make([.claude: .fresh(ok)], lastRefresh: earlier, refreshing: true, now: now) == RefreshStatus(fresh: false, text: "Updating"))
    #expect(RefreshStatus.make([.claude: .stale(ok, "cached")], lastRefresh: earlier, refreshing: false, now: now) == RefreshStatus(fresh: false, text: "Updating"))
    #expect(RefreshStatus.make([.claude: .fresh(ok), .grok: .stale(nil, "Offline")], lastRefresh: earlier, refreshing: false, now: now) == RefreshStatus(fresh: false, text: "updated 2 min ago"))
    #expect(RefreshStatus.make([.claude: .fresh(ok)], lastRefresh: earlier, refreshing: false, now: now) == RefreshStatus(fresh: true, text: "updated 2 min ago"))
}
