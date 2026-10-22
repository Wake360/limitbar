import Foundation

struct Availability: Equatable {
    let provider: Provider
    let window: UsageWindow
    let hot: Bool
    let backAt: Date?
}

enum Limits {
    static let hot: Double = 80

    static func current(_ window: UsageWindow, now: Date) -> UsageWindow {
        guard let resetsAt = window.resetsAt, resetsAt <= now else { return window }
        return UsageWindow(label: window.label, usedPercent: 0, resetsAt: resetsAt, kind: window.kind)
    }

    static func availability(_ provider: Provider, _ status: ProviderStatus, now: Date) -> Availability? {
        let snapshot: Snapshot?
        switch status {
        case .fresh(let s): snapshot = s
        case .stale(let s, _): snapshot = s
        case .empty, .loggedOut: snapshot = nil
        }
        guard let snapshot else { return nil }
        let windows = snapshot.windows.map { current($0, now: now) }
        guard let window = windows.max(by: { $0.usedPercent < $1.usedPercent }) else { return nil }
        let hotWindows = windows.filter { $0.usedPercent >= hot }
        guard !hotWindows.isEmpty else {
            return Availability(provider: provider, window: window, hot: false, backAt: window.resetsAt)
        }
        let resets = hotWindows.compactMap(\.resetsAt)
        let backAt = resets.count == hotWindows.count ? resets.max() : nil
        return Availability(provider: provider, window: window, hot: true, backAt: backAt)
    }

    static func ordered(_ status: [Provider: ProviderStatus], now: Date) -> [Provider] {
        let usable = Provider.allCases
            .compactMap { p in status[p].flatMap { availability(p, $0, now: now) } }
            .sorted { $0.window.usedPercent > $1.window.usedPercent }
            .map(\.provider)
        return usable + Provider.allCases.filter { !usable.contains($0) }
    }

    static func tightest(_ status: [Provider: ProviderStatus], now: Date) -> Availability? {
        ordered(status, now: now).first.flatMap { p in status[p].flatMap { availability(p, $0, now: now) } }
    }
}
