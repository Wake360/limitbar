import Testing
import AppKit
@testable import limitbar

private let now = Date(timeIntervalSince1970: 1_000_000)

@Test func ringIsTemplateWhenNotHot() {
    #expect(Ring.image(percent: 50, hot: false).isTemplate)
}

@Test func ringIsNotTemplateWhenHot() {
    #expect(!Ring.image(percent: 92, hot: true).isTemplate)
}

@Test func ringSizeFollowsParameter() {
    #expect(Ring.image(percent: 50, hot: false).size == NSSize(width: 16, height: 16))
    #expect(Ring.image(percent: nil, hot: false, size: 20).size == NSSize(width: 20, height: 20))
}

@MainActor @Test func rowAccessibilityReadsBothWindowsAndBack() {
    let status = ProviderStatus.fresh(Snapshot(provider: .claude, plan: "Max", windows: [
        UsageWindow(label: "5-hour", usedPercent: 92, resetsAt: now.addingTimeInterval(95 * 60), kind: .fiveHour),
        UsageWindow(label: "Weekly", usedPercent: 17, resetsAt: now.addingTimeInterval(3 * 86400), kind: .weekly)
    ], fetchedAt: now))
    #expect(ProviderRow.spokenValue(.claude, status, now: now, style: .popover) == "5-hour 92%, weekly 17%, back in 1 h 35 min")
    #expect(ProviderRow.spokenValue(.claude, status, now: now, style: .sidebar) == "5-hour 92%, back in 1 h 35 min")
    #expect(ProviderRow.spokenValue(.claude, .loggedOut(nil, "x"), now: now, style: .popover) == "signed out")
}
