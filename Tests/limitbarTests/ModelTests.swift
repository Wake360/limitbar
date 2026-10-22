import Testing
import Foundation
@testable import limitbar

@Test func highestPicksWeeklyWhenLarger() {
    let s = Snapshot(provider: .claude, plan: "Max 5x", windows: [
        UsageWindow(label: "5-hour", usedPercent: 6, resetsAt: nil, kind: .fiveHour),
        UsageWindow(label: "Weekly", usedPercent: 32, resetsAt: nil, kind: .weekly),
    ], fetchedAt: Date())
    #expect(s.highest?.kind == .weekly)
    #expect(s.highest?.usedPercent == 32)
}

@Test func highestIsNilForNoWindows() {
    let s = Snapshot(provider: .grok, plan: "", windows: [], fetchedAt: Date())
    #expect(s.highest == nil)
}
