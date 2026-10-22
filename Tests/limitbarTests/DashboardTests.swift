import Testing
import Foundation
import SwiftUI
@testable import limitbar

private func local(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

@MainActor @Test func dashboardWeeklyTimesNameTheDay() {
    #expect(DashboardDetail.activeHeader(start: local(19, 9, 0), end: local(26, 9, 0)) == "Active, Mon 09:00 to Mon 09:00")
    let top = SessionShare(id: "s", name: "waldean", detail: "main, 4 subagents", share: 31.4, first: local(20, 9, 10), last: local(21, 8, 40), slot: 0)
    #expect(DashboardDetail.topLine(top, measured: false, long: true) == "waldean's agent run used about 31% of the limit between Tue 09:10 and Wed 08:40.")
    #expect(DashboardDetail.topLine(top, measured: true, long: true) == "waldean used 31% of the limit between Tue 09:10 and Wed 08:40.")
}

@MainActor @Test func dashboardFiveHourTimesStayClock() {
    #expect(DashboardDetail.activeHeader(start: local(22, 8, 0), end: local(22, 13, 0)) == "Active, 08:00 to 13:00")
    let top = SessionShare(id: "s", name: "limitbar", detail: "main", share: 25, first: local(22, 8, 58), last: local(22, 9, 42), slot: 0)
    #expect(DashboardDetail.topLine(top, measured: false, long: false) == "limitbar used about 25% of the limit between 08:58 and 09:42.")
}

@MainActor @Test func dashboardDefaultSkipsAResetWindow() async {
    let now = Date()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = Store(fetcher: { p in
        Snapshot(provider: p, plan: "", windows: [
            UsageWindow(label: "5-hour", usedPercent: 92, resetsAt: now.addingTimeInterval(-300), kind: .fiveHour),
            UsageWindow(label: "Weekly", usedPercent: 17, resetsAt: now.addingTimeInterval(3 * 86400), kind: .weekly)
        ], fetchedAt: now)
    }, fileURL: directory.appendingPathComponent("snapshots.json"))
    await store.refresh()
    let detail = DashboardDetail(store: store, provider: .claude, now: now, claudeRoot: directory, codexRoot: directory)
    #expect(detail.window?.label == "Weekly")
}

private let base = Date(timeIntervalSince1970: 1_000_000)

@Test func sidebarLines() {
    let hot = Snapshot(provider: .claude, plan: "", windows: [UsageWindow(label: "5-hour", usedPercent: 86, resetsAt: base.addingTimeInterval(95 * 60), kind: .fiveHour)], fetchedAt: base)
    let cool = Snapshot(provider: .gemini, plan: "", windows: [UsageWindow(label: "Pro", usedPercent: 78, resetsAt: base.addingTimeInterval(4 * 86400), kind: .weekly)], fetchedAt: base)
    #expect(ProviderRow.sidebarLine(.claude, .fresh(hot), now: base) == "back in 1 h 35 min")
    #expect(ProviderRow.sidebarLine(.gemini, .fresh(cool), now: base) == "78%, resets " + Format.day(base.addingTimeInterval(4 * 86400)))
    #expect(ProviderRow.sidebarLine(.codex, .loggedOut(nil, "run codex login"), now: base) == "Signed out")
}

@Test func countdownForms() {
    let five = UsageWindow(label: "5-hour", usedPercent: 86, resetsAt: base.addingTimeInterval(95 * 60), kind: .fiveHour)
    let hot = Availability(provider: .claude, window: five, hot: true, backAt: five.resetsAt)
    #expect(DashboardDetail.countdown(hot, windows: [five], now: base) == Countdown(caption: "Back in", value: "1 h 35 min", line: "at \(Format.clock(five.resetsAt!)), when the 5-hour window resets"))
    let gone = Availability(provider: .claude, window: five, hot: true, backAt: base.addingTimeInterval(-60))
    #expect(DashboardDetail.countdown(gone, windows: [five], now: base) == Countdown(caption: "Used", value: "86%", line: Format.resetText(five, now: base)))
    let week = UsageWindow(label: "Weekly", usedPercent: 32, resetsAt: base.addingTimeInterval(3 * 86400), kind: .weekly)
    let cool = Availability(provider: .claude, window: week, hot: false, backAt: week.resetsAt)
    #expect(DashboardDetail.countdown(cool, windows: [week], now: base) == Countdown(caption: "Resets", value: Format.day(week.resetsAt!), line: "when the weekly window resets"))
    let credits = UsageWindow(label: "Credits", usedPercent: 95, resetsAt: nil, kind: .credits)
    #expect(DashboardDetail.countdown(Availability(provider: .grok, window: credits, hot: true, backAt: nil), windows: [credits], now: base) == Countdown(caption: "Used", value: "95%", line: nil))
}

@Test func cardsAndSelectableWindows() {
    let claude = Snapshot(provider: .claude, plan: "", windows: [
        UsageWindow(label: "5-hour", usedPercent: 86, resetsAt: nil, kind: .fiveHour),
        UsageWindow(label: "Weekly", usedPercent: 32, resetsAt: nil, kind: .weekly),
        UsageWindow(label: "Opus weekly", usedPercent: 12, resetsAt: nil, kind: .weekly)
    ], fetchedAt: base)
    #expect(DashboardDetail.cards(.claude, claude, now: base).count == 3)
    #expect(DashboardDetail.selectable(.claude, claude) == ["5-hour", "Weekly"])
    let grok = Snapshot(provider: .grok, plan: "", windows: [UsageWindow(label: "Weekly", usedPercent: 1, resetsAt: nil, kind: .weekly)], fetchedAt: base)
    #expect(DashboardDetail.cards(.grok, grok, now: base).map(\.label) == ["Weekly"])
    #expect(DashboardDetail.selectable(.grok, grok) == ["Weekly"])
    let gemini = Snapshot(provider: .gemini, plan: "", windows: (1...6).map { UsageWindow(label: "M\($0)", usedPercent: Double($0), resetsAt: nil, kind: .daily) }, fetchedAt: base)
    #expect(DashboardDetail.cards(.gemini, gemini, now: base).map(\.label) == ["M6", "M5", "M4", "M3"])
}

@Test func slotColours() {
    #expect(DrainChart.color(slot: 0, provider: .claude) == .claudeAccent)
    #expect(DrainChart.color(slot: 1, provider: .claude) == .sessionViolet)
    #expect(DrainChart.color(slot: 3, provider: .claude) == .sessionOther)
    #expect(DrainChart.color(slot: 0, provider: .codex) == .sessionViolet)
    #expect(DrainChart.color(slot: 2, provider: .codex) == .sessionSky)
    #expect(DrainChart.color(slot: 3, provider: .codex) == .sessionOther)
}
