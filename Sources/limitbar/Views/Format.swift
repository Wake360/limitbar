import Foundation

enum Format {
    static func duration(_ seconds: TimeInterval, compact: Bool = false) -> String {
        if seconds <= 0 { return "now" }
        let minutes = Int((seconds / 60).rounded(.up))
        let hours = minutes / 60
        let rest = minutes % 60
        let hourUnit = compact ? "h" : " h"
        let minuteUnit = compact ? "m" : " min"
        if hours == 0 { return "\(rest)\(minuteUnit)" }
        if rest == 0 { return "\(hours)\(hourUnit)" }
        return "\(hours)\(hourUnit) \(rest)\(minuteUnit)"
    }

    static func backText(_ availability: Availability, now: Date) -> String {
        guard let backAt = availability.backAt else {
            return "\(Int(availability.window.usedPercent.rounded()))%"
        }
        let delta = backAt.timeIntervalSince(now)
        if delta <= 0 { return "now" }
        if delta < 86400 { return "in " + duration(delta) }
        return day(backAt)
    }

    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func when(_ date: Date, now: Date) -> String {
        date.timeIntervalSince(now) >= 86400 ? day(date) : clock(date)
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: date)
    }

    static func updatedText(_ fetchedAt: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(fetchedAt)
        if seconds < 60 { return "updated just now" }
        if seconds < 3600 { return "updated \(Int(seconds / 60)) min ago" }
        return "updated \(Int(seconds / 3600)) h ago"
    }

    static func resetText(_ window: UsageWindow, now: Date) -> String? {
        guard let resetsAt = window.resetsAt, resetsAt > now else { return nil }
        return (window.kind == .credits ? "ends " : "resets ") + when(resetsAt, now: now)
    }
}

struct RefreshStatus: Equatable {
    let fresh: Bool
    let text: String

    static func make(_ status: [Provider: ProviderStatus], lastRefresh: Date?, refreshing: Bool, now: Date) -> RefreshStatus {
        let cached = status.values.contains { if case .stale(_, "cached") = $0 { true } else { false } }
        guard let lastRefresh, !refreshing, !cached else { return RefreshStatus(fresh: false, text: "Updating") }
        let erroring = status.values.contains { if case .stale = $0 { true } else { false } }
        return RefreshStatus(fresh: !erroring, text: Format.updatedText(lastRefresh, now: now))
    }
}
