import Foundation
import Testing
@testable import limitbar

private let windowStart = ISO8601DateFormatter().date(from: "2026-10-22T08:00:00Z")!
private let windowNow = windowStart.addingTimeInterval(2 * 3600 + 12 * 60 + 30)

private func at(_ minutes: Double) -> Date {
    windowStart.addingTimeInterval(minutes * 60)
}

private func event(_ session: String, _ minutes: Double, _ weight: Double, branch: String? = nil, agent: String? = nil) -> UsageEvent {
    UsageEvent(session: session, project: "proj-\(session)", branch: branch, agent: agent, at: at(minutes), weight: weight)
}

private func mockupEvents() -> [UsageEvent] {
    var events: [UsageEvent] = []
    let agents: [String?] = [nil, "a1", "a2", "a3", "a4"]
    for i in 0..<45 {
        events.append(UsageEvent(
            session: "w",
            project: "waldean",
            branch: "agent-baseline",
            agent: agents[i % 5],
            at: at(58 + Double(i)),
            weight: 56.0 / 45
        ))
    }
    for i in 0..<25 {
        events.append(UsageEvent(session: "l", project: "limitbar", branch: "main", agent: nil, at: at(Double(i) * 5), weight: 1))
    }
    for i in 0..<6 {
        events.append(UsageEvent(session: "o", project: "LifeOS", branch: "vault", agent: nil, at: at(10 + Double(i) * 20), weight: 1))
    }
    events.append(event("t1", 120, 2))
    events.append(event("t2", 125, 2))
    events.append(event("t3", 131, 1))
    return events
}

private func mockupDrain() -> Drain {
    Drain.estimated(mockupEvents(), usedPercent: 92, start: windowStart, now: windowNow, step: 300)
}

private func lastBandSum(_ drain: Drain) -> Double {
    let last = drain.bands.map(\.at).max()!
    return drain.bands.filter { $0.at == last }.reduce(0) { $0 + $1.value }
}

@Test func drainMockupShares() {
    let drain = mockupDrain()
    let expected: [Double] = [56, 25, 6, 5]
    #expect(drain.sessions.count == expected.count)
    for (share, value) in zip(drain.sessions.map(\.share), expected) {
        #expect(abs(share - value) < 0.5)
    }
    #expect(drain.sessions.map(\.name) == ["waldean", "limitbar", "LifeOS", "Other"])
    #expect(drain.sessions.map(\.slot) == [0, 1, 2, 3])
    #expect(drain.sessions[3].detail == "3 sessions")
    #expect(drain.others.map(\.id) == ["t1", "t2", "t3"])
    #expect(drain.sessions[0].detail == "agent-baseline, 4 subagents")
    #expect(drain.sessions[0].first == at(58))
    #expect(drain.sessions[0].last == at(102))
    #expect(drain.measured == false)
}

@Test func drainLastBandsSumToUsedPercentAtNow() {
    let drain = mockupDrain()
    #expect(drain.bands.map(\.at).max() == windowNow)
    #expect(abs(lastBandSum(drain) - 92) < 0.01)
    #expect(Set(drain.bands.filter { $0.at == windowNow }.map(\.slot)) == [0, 1, 2, 3])
}

@Test func drainBandsAreCumulativePerSlot() {
    let drain = mockupDrain()
    let waldean = drain.bands.filter { $0.slot == 0 }
    #expect(waldean.first { $0.at == at(55) }?.value == 0)
    #expect(abs(waldean.first { $0.at == at(110) }!.value - 56) < 0.01)
    #expect(zip(waldean, waldean.dropFirst()).allSatisfy { $0.value <= $1.value })
}

@Test func drainClimbFindsWaldean() {
    let climb = mockupDrain().climb
    #expect(climb?.session == "waldean")
    #expect(climb!.rise >= 30)
    #expect(climb!.to.timeIntervalSince(climb!.from) == 1800)
}

@Test func drainZeroWeightIsEmpty() {
    let drain = Drain.estimated([event("a", 10, 0), event("b", 20, 0)], usedPercent: 40, start: windowStart, now: windowNow, step: 300)
    #expect(drain.sessions.isEmpty)
    #expect(drain.others.isEmpty)
    #expect(drain.bands.isEmpty)
    #expect(drain.climb == nil)
    let none = Drain.estimated([], usedPercent: 40, start: windowStart, now: windowNow, step: 300)
    #expect(none.sessions.isEmpty && none.bands.isEmpty && none.climb == nil)
}

@Test func drainSixSessionsPutThreeInOthers() {
    let events = [
        event("a", 10, 30), event("b", 20, 25), event("c", 30, 20),
        event("d", 40, 15), event("e", 50, 6), event("f", 60, 4),
    ]
    let drain = Drain.estimated(events, usedPercent: 100, start: windowStart, now: windowNow, step: 300)
    #expect(drain.sessions.count == 4)
    #expect(drain.others.map(\.id) == ["d", "e", "f"])
    #expect(drain.others.allSatisfy { $0.slot == 3 })
    let other = drain.sessions[3]
    #expect(other.id == "other")
    #expect(other.name == "Other")
    #expect(other.detail == "3 sessions")
    #expect(abs(other.share - 25) < 0.0001)
    #expect(other.first == at(40))
    #expect(other.last == at(60))
}

@Test func drainNoOtherWhenThreeOrFewer() {
    let drain = Drain.estimated([event("a", 10, 3), event("b", 20, 1)], usedPercent: 40, start: windowStart, now: windowNow, step: 300)
    #expect(drain.sessions.map(\.id) == ["a", "b"])
    #expect(drain.others.isEmpty)
    #expect(drain.sessions.map(\.share) == [30, 10])
}

@Test func drainIgnoresEventsOutsideWindow() {
    let events = [
        event("a", 10, 1),
        event("b", 20, 1),
        event("a", -1, 1000),
        UsageEvent(session: "c", project: "late", branch: nil, agent: nil, at: windowNow.addingTimeInterval(1), weight: 1000),
    ]
    let drain = Drain.estimated(events, usedPercent: 40, start: windowStart, now: windowNow, step: 300)
    #expect(drain.sessions.map(\.id) == ["a", "b"])
    #expect(drain.sessions.map(\.share) == [20, 20])
    #expect(drain.sessions[0].first == at(10))
}

@Test func drainDetailVariants() {
    let events = [
        event("a", 10, 1, branch: "old"), event("a", 20, 1, branch: "new"), event("a", 30, 1),
        event("b", 10, 1, agent: "x"), event("b", 20, 1, agent: "y"), event("b", 30, 1, agent: "x"),
        event("c", 10, 1),
    ]
    let drain = Drain.estimated(events, usedPercent: 70, start: windowStart, now: windowNow, step: 300)
    let details = Dictionary(uniqueKeysWithValues: drain.sessions.map { ($0.id, $0.detail) })
    #expect(details["a"] == .some("new"))
    #expect(details["b"] == .some("2 subagents"))
    #expect(details["c"] == .some(nil))
}

@Test func drainClimbNilWhenRiseUnderTen() {
    let events = (0..<100).map { event("a", Double($0), 1) }
    let drain = Drain.estimated(events, usedPercent: 20, start: windowStart, now: windowNow, step: 300)
    #expect(drain.climb == nil)
}

@Test func drainClimbNilWhenWindowShorterThanSpan() {
    let now = at(20)
    let drain = Drain.estimated([event("a", 5, 1)], usedPercent: 50, start: windowStart, now: now, step: 300)
    #expect(drain.climb == nil)
    #expect(drain.bands.map(\.at).max() == now)
}

@Test func drainMeasuredAttributesRisesToLaterPoint() {
    let points = [
        PercentPoint(session: "s2", project: "two", at: at(40), windowMinutes: 300, usedPercent: 40, resetsAt: at(300)),
        PercentPoint(session: "s1", project: "one", at: at(10), windowMinutes: 300, usedPercent: 0, resetsAt: at(300)),
        PercentPoint(session: "s2", project: "two", at: at(30), windowMinutes: 300, usedPercent: 10, resetsAt: at(300)),
        PercentPoint(session: "s1", project: "one", at: at(20), windowMinutes: 300, usedPercent: 10, resetsAt: at(300)),
    ]
    let drain = Drain.measured(points, start: windowStart, now: windowNow, step: 300)
    #expect(drain.measured == true)
    #expect(drain.sessions.map(\.id) == ["s2", "s1"])
    #expect(drain.sessions.map(\.share) == [30, 10])
    #expect(drain.sessions.map(\.name) == ["two", "one"])
    #expect(drain.sessions.allSatisfy { $0.detail == nil })
    #expect(drain.sessions[0].first == at(40))
    #expect(drain.sessions[1].first == at(20))
    #expect(abs(lastBandSum(drain) - 40) < 0.01)
    #expect(drain.climb?.session == "two")
    #expect(drain.climb?.rise == 40)
}

@Test func drainMeasuredIgnoresDrops() {
    let points = [
        PercentPoint(session: "s1", project: "one", at: at(10), windowMinutes: 300, usedPercent: 40, resetsAt: at(300)),
        PercentPoint(session: "s2", project: "two", at: at(20), windowMinutes: 300, usedPercent: 38, resetsAt: at(300)),
        PercentPoint(session: "s2", project: "two", at: at(30), windowMinutes: 300, usedPercent: 40, resetsAt: at(300)),
    ]
    let drain = Drain.measured(points, start: windowStart, now: windowNow, step: 300)
    #expect(drain.sessions.map(\.id) == ["s1"])
    #expect(drain.sessions.map(\.share) == [40])
    #expect(abs(lastBandSum(drain) - 40) < 0.01)
}

@Test func drainMeasuredEmptyWithoutPoints() {
    let drain = Drain.measured([], start: windowStart, now: windowNow, step: 300)
    #expect(drain.sessions.isEmpty && drain.bands.isEmpty && drain.climb == nil)
}
