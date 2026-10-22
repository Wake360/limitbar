import Testing
import Foundation
@testable import limitbar

private func tmp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/snapshots.json") }
private func snap(_ p: Provider) -> Snapshot { Snapshot(provider: p, plan: "", windows: [], fetchedAt: Date()) }

@MainActor @Test func storeSuccessIsFreshAndPersisted() async throws {
    let url = tmp()
    let store = Store(fetcher: { snap($0) }, fileURL: url)
    await store.refresh()
    guard case .fresh(let s) = store.status[.claude], s.provider == .claude else { Issue.record("expected fresh"); return }
    #expect(store.lastRefresh != nil)
    let reloaded = Store(fetcher: { _ in throw CredentialError.missing("x") }, fileURL: url)
    guard case .stale(_, "cached") = reloaded.status[.claude] else { Issue.record("expected cached stale"); return }
}

@MainActor @Test func storeExpiredBecomesLoggedOutAndKeepsSnapshot() async {
    let store = Store(fetcher: { snap($0) }, fileURL: tmp())
    await store.refresh()
    let failing = Store(fetcher: { _ in throw CredentialError.expired("run claude") }, fileURL: tmp())
    failing.status = store.status
    await failing.refresh()
    guard case .loggedOut(let s, "run claude") = failing.status[.claude], s != nil else { Issue.record("expected loggedOut with snapshot"); return }
}

@MainActor @Test func storeOneFailureDoesNotBlockOthers() async {
    let store = Store(fetcher: { p in if p == .grok { throw URLError(.badServerResponse) }; return snap(p) }, fileURL: tmp())
    await store.refresh()
    guard case .fresh = store.status[.claude] else { Issue.record("expected fresh"); return }
    guard case .stale(nil, _) = store.status[.grok] else { Issue.record("expected stale(nil)"); return }
}

@MainActor @Test func storeNetworkErrorKeepsPreviousAsStale() async {
    let store = Store(fetcher: { snap($0) }, fileURL: tmp())
    await store.refresh()
    let failing = Store(fetcher: { _ in throw URLError(.notConnectedToInternet) }, fileURL: tmp())
    failing.status = store.status
    await failing.refresh()
    guard case .stale(_, let msg) = failing.status[.codex] else { Issue.record("expected stale"); return }
    #expect(!msg.isEmpty)
}

@MainActor @Test func storeEmptyWithoutFileOnFreshMachine() {
    let store = Store(fetcher: { snap($0) }, fileURL: tmp())
    #expect(Provider.allCases.allSatisfy { store.status[$0] == .empty })
}

@MainActor @Test func storeSlowProviderDoesNotDelayOthers() async throws {
    let store = Store(fetcher: { p in
        if p == .grok { try await Task.sleep(for: .seconds(2)) }
        return snap(p)
    }, fileURL: tmp())
    let refresh = Task { await store.refresh() }
    try await Task.sleep(for: .milliseconds(300))
    guard case .fresh = store.status[.claude] else { Issue.record("claude should be fresh before grok finishes"); refresh.cancel(); return }
    #expect(store.status[.grok] == .empty)
    refresh.cancel()
}
