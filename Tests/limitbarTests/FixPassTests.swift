import Testing
import Foundation
@testable import limitbar

private func snap(_ p: Provider) -> Snapshot { Snapshot(provider: p, plan: "", windows: [], fetchedAt: Date()) }
private func tmp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/snapshots.json") }

@Test func refreshMinutesDefaultsToFive() {
    let defaults = UserDefaults(suiteName: "limitbar-test-\(UUID().uuidString)")!
    #expect(Store.refreshMinutes(defaults) == 5)
    defaults.set(2, forKey: "refreshMinutes")
    #expect(Store.refreshMinutes(defaults) == 2)
}

@Test func credentialReadErrorsBecomeMissingWithHint() throws {
    #expect(throws: CredentialError.missing("run codex login")) {
        try Credentials.hinted("run codex login") { throw CredentialError.malformed("/x") }
    }
    #expect(try Credentials.hinted("h") { 1 } == 1)
}

@Test func expiredPassesThroughHinted() {
    #expect(throws: CredentialError.expired("e")) {
        try Credentials.hinted("h") { throw CredentialError.expired("e") }
    }
}

@Test func httpCheckMapsStatusCodes() throws {
    func response(_ code: Int) -> URLResponse { HTTPURLResponse(url: URL(string: "https://x")!, statusCode: code, httpVersion: nil, headerFields: nil)! }
    #expect(throws: CredentialError.expired("h")) { try HTTP.check(response(401), loginHint: "h") }
    #expect(throws: CredentialError.expired("h")) { try HTTP.check(response(403), loginHint: "h") }
    #expect(throws: URLError.self) { try HTTP.check(response(500), loginHint: "h") }
    try HTTP.check(response(200), loginHint: "h")
}

@Test func snapshotColumnsFallBackToDaily() {
    let daily = UsageWindow(label: "2.5 Pro", usedPercent: 10, resetsAt: nil, kind: .daily)
    let credits = UsageWindow(label: "c", usedPercent: 1, resetsAt: nil, kind: .credits)
    let s = Snapshot(provider: .grok, plan: "", windows: [daily, credits], fetchedAt: Date())
    #expect(s.shortWindow == daily)
    #expect(s.longWindow == credits)
}

@MainActor @Test func failureWithoutSnapshotIsStaleNil() async {
    let store = Store(fetcher: { _ in throw URLError(.badServerResponse) }, fileURL: tmp())
    await store.refresh()
    guard case .stale(nil, _) = store.status[.claude] else { Issue.record("expected stale(nil)"); return }
}

@MainActor @Test func overlappingRefreshRunsOnce() async throws {
    let counter = Counter()
    let store = Store(fetcher: { p in await counter.bump(); try await Task.sleep(for: .milliseconds(200)); return snap(p) }, fileURL: tmp())
    async let a: Void = store.refresh()
    async let b: Void = store.refresh()
    _ = await (a, b)
    #expect(await counter.value == Provider.allCases.count)
}

actor Counter { var value = 0; func bump() { value += 1 } }
