import Foundation

struct Verdict: Equatable {
    let headline: String
    let line: String

    static func make(_ status: [Provider: ProviderStatus], now: Date) -> Verdict {
        let available = Limits.ordered(status, now: now).compactMap { p in status[p].flatMap { Limits.availability(p, $0, now: now) } }
        guard let tightest = available.first else {
            let signedOut = status.values.contains { if case .loggedOut = $0 { true } else { false } }
            let failed = status.values.contains { if case .stale = $0 { true } else { false } }
            let line = signedOut ? "Sign in to a provider to see limits." : failed ? "Couldn't load limits. Retrying at the next refresh." : "Waiting for the first refresh."
            return Verdict(headline: "No data yet", line: line)
        }
        let hot = available.filter(\.hot)
        let free = available.filter { !$0.hot }
        guard !hot.isEmpty else {
            let left = Int((100 - tightest.window.usedPercent).rounded())
            return Verdict(
                headline: "All clear",
                line: "Tightest is \(tightest.provider.displayName) \(kindWord(tightest.window.kind)), \(left)% left."
            )
        }
        guard !free.isEmpty else {
            let first = hot.filter { $0.backAt != nil }.min { $0.backAt! < $1.backAt! }
            let line = first.map { "First back: \($0.provider.displayName) \(backWithClock($0, now: now))." }
                ?? "Nothing has a reset time yet."
            return Verdict(headline: "Everything is used up", line: line)
        }
        let freeSentence = " \(names(free)) \(free.count == 1 ? "is" : "are") free now."
        let headline = "\(names(hot)) \(hot.count == 1 ? "is" : "are") nearly out"
        if hot.count == 1, let one = hot.first {
            let lead = one.backAt == nil
                ? "At \(Int(one.window.usedPercent.rounded()))%, no reset time."
                : "Back \(backWithClock(one, now: now))."
            return Verdict(headline: headline, line: lead + freeSentence)
        }
        let parts = hot.enumerated().map { index, a -> String in
            let text = a.backAt == nil ? "at " + Format.backText(a, now: now) : Format.backText(a, now: now)
            return "\(a.provider.displayName) \(index == 0 && a.backAt != nil ? "back " : "")\(text)"
        }
        return Verdict(headline: headline, line: parts.joined(separator: ", ") + "." + freeSentence)
    }

    private static func names(_ list: [Availability]) -> String {
        let all = list.map(\.provider.displayName)
        guard let last = all.last, all.count > 1 else { return all.first ?? "" }
        return all.dropLast().joined(separator: ", ") + " and " + last
    }

    private static func backWithClock(_ a: Availability, now: Date) -> String {
        let text = Format.backText(a, now: now)
        guard text.hasPrefix("in "), let backAt = a.backAt else { return text }
        return text + ", at " + Format.clock(backAt)
    }

    static func kindWord(_ kind: WindowKind) -> String {
        switch kind {
        case .fiveHour: "5-hour"
        case .daily: "daily"
        case .weekly: "weekly"
        case .credits: "credits"
        }
    }
}
