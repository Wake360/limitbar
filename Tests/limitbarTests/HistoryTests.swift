import Testing
import Foundation
@testable import limitbar

private func tmp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/history.jsonl") }

private func snap(_ p: Provider = .claude, at: Date, percent: Double = 10, resetsAt: Date? = nil) -> Snapshot {
    Snapshot(provider: p, plan: "", windows: [UsageWindow(label: "5h", usedPercent: percent, resetsAt: resetsAt, kind: .fiveHour)], fetchedAt: at)
}

@Test func historyAppendsAndLoadsInOrder() {
    let url = tmp()
    let now = Date()
    let history = History(url: url, now: now)
    let times = [now - 300, now - 200, now - 100]
    times.forEach { history.append(snap(at: $0)) }
    history.append(snap(.codex, at: now - 50))
    let loaded = history.load(.claude, since: now - 250)
    #expect(loaded.map(\.fetchedAt) == Array(times[1...]))
}

@Test func historyInitPrunesOldLines() {
    let url = tmp()
    let now = Date()
    let old = History(url: url, now: now - 20 * 86400)
    old.append(snap(at: now - 15 * 86400))
    old.append(snap(at: now - 1 * 86400))
    let history = History(url: url, now: now)
    #expect(history.load(.claude, since: .distantPast).count == 1)
    let lines = (try? String(contentsOf: url, encoding: .utf8))?.split(separator: "\n") ?? []
    #expect(lines.count == 1)
}

@Test func historySkipsMalformedLines() throws {
    let url = tmp()
    let now = Date()
    let history = History(url: url, now: now)
    history.append(snap(at: now - 10))
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("garbage\n".utf8))
    try handle.close()
    history.append(snap(at: now - 5))
    #expect(history.load(.claude, since: .distantPast).count == 2)
    _ = History(url: url, now: now)
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(!text.contains("garbage"))
}

@Test func historyReadingsMatchResetWithinSixtySeconds() {
    let now = Date()
    let reset = now + 3600
    let snaps = [
        snap(at: now - 200, percent: 30, resetsAt: reset + 30),
        snap(at: now - 100, percent: 20, resetsAt: reset + 120),
        snap(at: now - 300, percent: 10, resetsAt: reset),
    ]
    let readings = History.readings(snaps, label: "5h", resetsAt: reset)
    #expect(readings.map(\.percent) == [10, 30])
    #expect(readings.map(\.at) == [now - 300, now - 200])
}

@MainActor @Test func storeRefreshAppendsHistoryForSuccessOnly() async {
    let url = tmp()
    let store = Store(fetcher: { p in
        if p == .grok { throw URLError(.badServerResponse) }
        return snap(p, at: Date())
    }, fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"), historyURL: url)
    await store.refresh()
    let lines = (try? String(contentsOf: url, encoding: .utf8))?.split(separator: "\n") ?? []
    #expect(lines.count == 3)
    #expect(store.history.load(.grok, since: .distantPast).isEmpty)
}
