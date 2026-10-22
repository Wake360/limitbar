import Foundation
import Testing
@testable import limitbar

private func fixtureData() -> Data {
    let url = Bundle.module.url(forResource: "claude-session", withExtension: "jsonl", subdirectory: "Fixtures")!
    return try! Data(contentsOf: url)
}

@Test func sessionFixtureYieldsThreeEvents() {
    let events = ClaudeSessions.parse(fixtureData())
    #expect(events.count == 3)
    #expect(events.allSatisfy { $0.project == "sampleproj" && $0.branch == "feature-x" })
}

@Test func sessionWeightMatchesFormula() {
    let events = ClaudeSessions.parse(fixtureData())
    #expect(events.last?.weight == 2 + 40520 + 96 + 0.1 * 30121)
    #expect(events.first?.weight == 15)
}

@Test func subagentEventKeepsParentSession() {
    let events = ClaudeSessions.parse(fixtureData())
    let agent = events.first { $0.agent != nil }
    #expect(agent?.agent == "agent-7")
    #expect(agent?.session == "11111111-aaaa-bbbb-cccc-000000000001")
}

@Test func loadIgnoresOldFilesAndFiltersRange() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let nested = root.appendingPathComponent("proj/sess/subagents")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let data = fixtureData()
    let recent = root.appendingPathComponent("proj/new.jsonl")
    let old = nested.appendingPathComponent("agent-old.jsonl")
    try data.write(to: recent)
    try data.write(to: old)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: old.path)

    let from = ISO8601DateFormatter().date(from: "2026-10-22T09:00:00Z")!
    let to = ISO8601DateFormatter().date(from: "2026-10-22T10:00:00Z")!
    try FileManager.default.setAttributes([.modificationDate: to], ofItemAtPath: recent.path)
    let events = ClaudeSessions.load(root: root, from: from, to: to)
    #expect(events.count == 2)
    #expect(events == events.sorted { $0.at < $1.at })
    #expect(ClaudeSessions.load(root: root.appendingPathComponent("missing"), from: from, to: to).isEmpty)
}
