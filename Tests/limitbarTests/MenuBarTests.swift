import Testing
import Foundation
import AppKit
@testable import limitbar

private let now = Date(timeIntervalSince1970: 1_000_000)

private func snap(_ p: Provider, _ windows: [UsageWindow]) -> Snapshot {
    Snapshot(provider: p, plan: "", windows: windows, fetchedAt: now)
}

private let claude = snap(.claude, [
    UsageWindow(label: "5-hour", usedPercent: 92, resetsAt: now.addingTimeInterval(95 * 60), kind: .fiveHour),
    UsageWindow(label: "Weekly", usedPercent: 17, resetsAt: now.addingTimeInterval(3 * 86400), kind: .weekly)
])
private let grok = snap(.grok, [UsageWindow(label: "Weekly", usedPercent: 78.4, resetsAt: now.addingTimeInterval(4 * 86400), kind: .weekly)])

@Test func menuBarItemsFollowFixedOrderAndSkipSignedOut() {
    let status: [Provider: ProviderStatus] = [.claude: .fresh(claude), .codex: .loggedOut(nil, "x"), .grok: .fresh(grok)]
    #expect(MenuBarLabel.items(status, now: now) == [
        MenuBarItem(provider: .claude, percent: 92, weekly: false, hot: true, stale: false),
        MenuBarItem(provider: .grok, percent: 78, weekly: true, hot: false, stale: false)
    ])
}

@Test func menuBarStaleHotKeepsHotAndCachedIsNotStale() {
    let status: [Provider: ProviderStatus] = [.claude: .stale(claude, "Offline"), .grok: .stale(grok, "cached")]
    let items = MenuBarLabel.items(status, now: now)
    #expect(items[0].hot && items[0].stale)
    #expect(!items[1].stale)
}

@Test func menuBarAllFailingShowsLogosWithoutNumbers() {
    let status = Dictionary(uniqueKeysWithValues: Provider.allCases.map { ($0, ProviderStatus.stale(nil, "Offline")) })
    #expect(MenuBarLabel.items(status, now: now).map(\.percent) == [nil, nil, nil])
    #expect(MenuBarLabel.items(status, now: now).allSatisfy { $0.stale })
}

@Test func menuBarPastResetCountsAsZero() {
    let reset = snap(.claude, [UsageWindow(label: "5-hour", usedPercent: 92, resetsAt: now.addingTimeInterval(-60), kind: .fiveHour)])
    #expect(MenuBarLabel.items([.claude: .fresh(reset)], now: now).first?.percent == 0)
}

@Test func menuBarAccessibility() {
    let status: [Provider: ProviderStatus] = [.claude: .fresh(claude), .codex: .stale(nil, "Offline"), .grok: .fresh(grok)]
    #expect(MenuBarLabel.accessibility(status, now: now) == "limitbar, Claude 5-hour 92%, nearly out, back in 1 h 35 min, Codex not updating, Grok weekly 78%")
    #expect(MenuBarLabel.accessibility([:], now: now) == "limitbar, no data")
}

@Test func menuBarImageEmptyIsDashedTemplateRing() {
    let image = MenuBarLabel.image([])
    #expect(image.isTemplate)
    #expect(image.size == NSSize(width: 16, height: 16))
}

@Test func menuBarImageIsColouredAndWide() {
    let items = [MenuBarItem(provider: .claude, percent: 92, weekly: false, hot: true, stale: false), MenuBarItem(provider: .codex, percent: 0, weekly: true, hot: false, stale: false)]
    let image = MenuBarLabel.image(items)
    #expect(!image.isTemplate)
    #expect(image.size.height == 16)
    #expect(image.size.width > 40)
}

@Test func menuBarImageFollowsAppearance() {
    let image = MenuBarLabel.image([MenuBarItem(provider: .codex, percent: 5, weekly: false, hot: false, stale: false)])
    func png(_ name: NSAppearance.Name) -> Data {
        var data = Data()
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * 2), pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(x: 0, y: 0, width: image.size.width * 2, height: 32))
            NSGraphicsContext.restoreGraphicsState()
            data = rep.representation(using: .png, properties: [:])!
        }
        return data
    }
    #expect(png(.aqua) != png(.darkAqua))
}
