import SwiftUI
import AppKit

struct MenuBarItem: Equatable {
    let provider: Provider
    let percent: Int?
    let weekly: Bool
    let hot: Bool
    let stale: Bool
}

struct MenuBarLabel: View {
    let store: Store

    nonisolated static let order: [Provider] = [.claude, .gemini, .codex, .grok]

    var body: some View {
        let now = Date()
        Image(nsImage: Self.image(Self.items(store.status, now: now)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibility(store.status, now: now))
    }

    private nonisolated static let height: CGFloat = 16
    private nonisolated static let logoSize: CGFloat = 12
    private nonisolated static let logoGap: CGFloat = 3
    private nonisolated static let itemGap: CGFloat = 10

    private nonisolated static func tint(_ item: MenuBarItem) -> NSColor {
        if item.hot { return .warn }
        return item.stale ? .secondaryLabelColor : item.provider.accentNS
    }

    private nonisolated static func numberColor(_ item: MenuBarItem) -> NSColor {
        if item.hot { return .warnText }
        return item.stale ? .secondaryLabelColor : .labelColor
    }

    private nonisolated static func segments(_ item: MenuBarItem) -> [(text: NSAttributedString, raised: CGFloat)] {
        let number = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        let small = NSFont.systemFont(ofSize: 9, weight: .medium)
        func text(_ string: String, _ font: NSFont) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: numberColor(item)])
        }
        var result: [(NSAttributedString, CGFloat)] = []
        if let percent = item.percent { result.append((text("\(percent)", number), 0)) }
        if item.weekly { result.append((text("w", small), 2)) }
        if item.stale { result.append((text("!", number), 0)) }
        return result
    }

    nonisolated static func image(_ items: [MenuBarItem]) -> NSImage {
        guard !items.isEmpty else { return Ring.image(percent: nil, hot: false, dashed: true) }
        let laid = items.map { (item: $0, segments: segments($0), logo: $0.provider.nsIcon) }
        let widths = laid.map { logoSize + logoGap + $0.segments.reduce(0) { $0 + ceil($1.text.size().width) + 1 } - 1 }
        let total = widths.reduce(0, +) + itemGap * CGFloat(items.count - 1)
        let image = NSImage(size: NSSize(width: ceil(total), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for entry in laid {
                let logoRect = NSRect(x: x, y: (height - logoSize) / 2, width: logoSize, height: logoSize)
                let tinted = NSImage(size: logoRect.size, flipped: false) { rect in
                    entry.logo.draw(in: rect)
                    tint(entry.item).set()
                    rect.fill(using: .sourceIn)
                    return true
                }
                tinted.draw(in: logoRect)
                x += logoSize + logoGap
                for segment in entry.segments {
                    let size = segment.text.size()
                    segment.text.draw(at: NSPoint(x: x, y: (height - size.height) / 2 + segment.raised))
                    x += ceil(size.width) + 1
                }
                x += itemGap - 1
            }
            return true
        }
        image.cacheMode = .never
        return image
    }

    private nonisolated static func entries(_ status: [Provider: ProviderStatus], now: Date) -> [(item: MenuBarItem, availability: Availability?)] {
        order.compactMap { provider in
            guard let providerStatus = status[provider] else { return nil }
            let availability = Limits.availability(provider, providerStatus, now: now)
            var stale = false
            switch providerStatus {
            case .empty, .loggedOut: return nil
            case .stale(_, let message): stale = message != "cached"
            case .fresh: break
            }
            if availability == nil && !stale { return nil }
            let item = MenuBarItem(
                provider: provider,
                percent: availability.map { Int($0.window.usedPercent.rounded()) },
                weekly: availability?.window.kind == .weekly,
                hot: availability?.hot ?? false,
                stale: stale
            )
            return (item, availability)
        }
    }

    nonisolated static func items(_ status: [Provider: ProviderStatus], now: Date) -> [MenuBarItem] {
        entries(status, now: now).map(\.item)
    }

    nonisolated static func accessibility(_ status: [Provider: ProviderStatus], now: Date) -> String {
        let entries = entries(status, now: now)
        guard !entries.isEmpty else { return "limitbar, no data" }
        let parts = entries.flatMap { item, availability -> [String] in
            let name = item.provider.displayName
            guard let availability, let percent = item.percent else { return [name + " not updating"] }
            var parts = ["\(name) \(Verdict.kindWord(availability.window.kind)) \(percent)%"]
            if item.hot {
                parts.append("nearly out")
                if availability.backAt != nil { parts.append("back " + Format.backText(availability, now: now)) }
            }
            if item.stale { parts.append("not updating") }
            return parts
        }
        return (["limitbar"] + parts).joined(separator: ", ")
    }
}
