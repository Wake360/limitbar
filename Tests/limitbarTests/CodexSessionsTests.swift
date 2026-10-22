import Foundation
import Testing
@testable import limitbar

private func codexFixtureData() -> Data {
    let url = Bundle.module.url(forResource: "codex-session", withExtension: "jsonl", subdirectory: "Fixtures")!
    return try! Data(contentsOf: url)
}

@Test func codexFixtureYieldsFivePoints() {
    let points = CodexSessions.parse(codexFixtureData())
    #expect(points.count == 5)
    #expect(points.filter { $0.windowMinutes == 300 }.count == 3)
    #expect(points.filter { $0.windowMinutes == 10080 }.count == 2)
}

@Test func codexPointsCarrySessionProjectAndReset() {
    let points = CodexSessions.parse(codexFixtureData())
    #expect(points.allSatisfy { $0.session == "22222222-aaaa-bbbb-cccc-000000000002" && $0.project == "sampleproj" })
    let first = points[0]
    #expect(first.usedPercent == 10.0)
    #expect(first.windowMinutes == 300)
    #expect(first.resetsAt == Date(timeIntervalSince1970: 1792000000))
    #expect(first.at == ISO8601DateFormatter().date(from: "2026-10-22T09:10:00Z")!.addingTimeInterval(0.5))
}

@Test func codexLoadIgnoresOldFilesAndFiltersRange() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let day = root.appendingPathComponent("2026/10/22")
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let data = codexFixtureData()
    let recent = day.appendingPathComponent("rollout-new.jsonl")
    let old = day.appendingPathComponent("rollout-old.jsonl")
    try data.write(to: recent)
    try data.write(to: old)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: old.path)

    let from = ISO8601DateFormatter().date(from: "2026-10-22T09:00:00Z")!
    let to = ISO8601DateFormatter().date(from: "2026-10-22T09:25:00Z")!
    try FileManager.default.setAttributes([.modificationDate: to], ofItemAtPath: recent.path)
    let points = CodexSessions.load(root: root, from: from, to: to)
    #expect(points.count == 4)
    #expect(points == points.sorted { $0.at < $1.at })
    #expect(CodexSessions.load(root: root.appendingPathComponent("missing"), from: from, to: to).isEmpty)
}
