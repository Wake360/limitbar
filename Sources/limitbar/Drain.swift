import Foundation

struct SessionShare: Equatable, Sendable {
    let id: String
    let name: String
    let detail: String?
    let share: Double
    let first: Date
    let last: Date
    let slot: Int
}

struct Band: Equatable, Sendable {
    let slot: Int
    let at: Date
    let value: Double
}

struct Climb: Equatable, Sendable {
    let from: Date
    let to: Date
    let rise: Double
    let session: String
}

struct Drain: Equatable, Sendable {
    let sessions: [SessionShare]
    let others: [SessionShare]
    let bands: [Band]
    let climb: Climb?
    let measured: Bool

    private struct Source {
        let id: String
        let name: String
        let detail: String?
        let amounts: [(at: Date, amount: Double)]
    }

    static func estimated(_ events: [UsageEvent], usedPercent: Double, start: Date, now: Date, step: TimeInterval) -> Drain {
        let inside = events.filter { $0.at >= start && $0.at <= now }
        let total = inside.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return build([], start: start, now: now, step: step, measured: false) }
        let k = usedPercent / total
        let sources = Dictionary(grouping: inside, by: \.session).map { id, events in
            let sorted = events.sorted { $0.at < $1.at }
            let branch = sorted.last { $0.branch != nil }?.branch
            let agents = Set(sorted.compactMap(\.agent)).count
            let parts = [branch, agents > 0 ? "\(agents) subagents" : nil].compactMap { $0 }
            return Source(
                id: id,
                name: sorted[0].project,
                detail: parts.isEmpty ? nil : parts.joined(separator: ", "),
                amounts: sorted.map { ($0.at, $0.weight * k) }
            )
        }
        return build(sources, start: start, now: now, step: step, measured: false)
    }

    static func measured(_ points: [PercentPoint], start: Date, now: Date, step: TimeInterval) -> Drain {
        var previous = 0.0
        var names: [String: String] = [:]
        var rises: [String: [(at: Date, amount: Double)]] = [:]
        for point in points.filter({ $0.at >= start && $0.at <= now }).sorted(by: { $0.at < $1.at }) {
            let rise = point.usedPercent - previous
            previous = max(previous, point.usedPercent)
            guard rise > 0 else { continue }
            names[point.session] = names[point.session] ?? point.project
            rises[point.session, default: []].append((point.at, rise))
        }
        let sources = rises.map { Source(id: $0.key, name: names[$0.key]!, detail: nil, amounts: $0.value) }
        return build(sources, start: start, now: now, step: step, measured: true)
    }

    private static func build(_ sources: [Source], start: Date, now: Date, step: TimeInterval, measured: Bool) -> Drain {
        let ranked = sources.compactMap { source -> SessionShare? in
            let positive = source.amounts.filter { $0.amount > 0 }
            guard let first = positive.map(\.at).min(), let last = positive.map(\.at).max() else { return nil }
            return SessionShare(
                id: source.id,
                name: source.name,
                detail: source.detail,
                share: positive.reduce(0) { $0 + $1.amount },
                first: first,
                last: last,
                slot: 3
            )
        }.sorted { $0.share != $1.share ? $0.share > $1.share : $0.id < $1.id }
        guard !ranked.isEmpty else { return Drain(sessions: [], others: [], bands: [], climb: nil, measured: measured) }

        var sessions = ranked.prefix(3).enumerated().map { slot, s in
            SessionShare(id: s.id, name: s.name, detail: s.detail, share: s.share, first: s.first, last: s.last, slot: slot)
        }
        let others = Array(ranked.dropFirst(3))
        if !others.isEmpty {
            sessions.append(SessionShare(
                id: "other",
                name: "Other",
                detail: "\(others.count) sessions",
                share: others.reduce(0) { $0 + $1.share },
                first: others.map(\.first).min()!,
                last: others.map(\.last).max()!,
                slot: 3
            ))
        }

        let slotOf = Dictionary(uniqueKeysWithValues: ranked.enumerated().map { ($1.id, min($0, 3)) })
        let contributions = sources.flatMap { source in
            source.amounts.compactMap { item in slotOf[source.id].map { (slot: $0, at: item.at, amount: item.amount) } }
        }

        var grid: [Date] = []
        var t = start
        while t < now {
            grid.append(t)
            t += step
        }
        grid.append(now)

        let bands = grid.flatMap { time in
            sessions.map { session in
                Band(
                    slot: session.slot,
                    at: time,
                    value: contributions.filter { $0.slot == session.slot && $0.at <= time }.reduce(0) { $0 + $1.amount }
                )
            }
        }

        let span = max(1800, step)
        var best: (from: Date, rise: Double)?
        for from in grid where from.addingTimeInterval(span) <= now {
            let to = from.addingTimeInterval(span)
            let rise = contributions.filter { $0.at > from && $0.at <= to }.reduce(0) { $0 + $1.amount }
            if rise > (best?.rise ?? -.infinity) { best = (from, rise) }
        }
        var climb: Climb?
        if let best, best.rise >= 10 {
            let to = best.from.addingTimeInterval(span)
            let inSpan = contributions.filter { $0.at > best.from && $0.at <= to }
            let top = sessions.max { a, b in
                let x = inSpan.filter { $0.slot == a.slot }.reduce(0) { $0 + $1.amount }
                let y = inSpan.filter { $0.slot == b.slot }.reduce(0) { $0 + $1.amount }
                return x != y ? x < y : a.slot > b.slot
            }!
            climb = Climb(from: best.from, to: to, rise: best.rise, session: top.name)
        }

        return Drain(sessions: sessions, others: others, bands: bands, climb: climb, measured: measured)
    }
}
