import Foundation
import Observation

@MainActor @Observable final class Store {
    var status: [Provider: ProviderStatus]
    var lastRefresh: Date?

    private let fetcher: Fetcher
    private let fileURL: URL
    private(set) var history: History
    private var prunedAt = Date()
    private var timer: Timer?
    private(set) var refreshing = false

    static let liveFetcher: Fetcher = { provider in
        switch provider {
        case .claude: try await Claude.fetch()
        case .codex: try await Codex.fetch()
        case .gemini: try await Antigravity.fetch()
        case .grok: try await Grok.fetch()
        }
    }

    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("limitbar/snapshots.json")
    }

    init(fetcher: @escaping Fetcher = Store.liveFetcher, fileURL: URL = Store.defaultFileURL, historyURL: URL? = nil) {
        self.fetcher = fetcher
        self.fileURL = fileURL
        history = History(url: historyURL ?? fileURL.deletingLastPathComponent().appendingPathComponent("history.jsonl"))
        let saved = (try? JSONDecoder().decode([Snapshot].self, from: Data(contentsOf: fileURL))) ?? []
        status = Dictionary(uniqueKeysWithValues: Provider.allCases.map { p in
            (p, saved.first { $0.provider == p }.map { .stale($0, "cached") } ?? .empty)
        })
    }

    nonisolated static func refreshMinutes(_ defaults: UserDefaults) -> Int {
        let stored = defaults.integer(forKey: "refreshMinutes")
        return stored > 0 ? stored : 5
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let fetcher = self.fetcher
        await withTaskGroup(of: (Provider, Result<Snapshot, Error>).self) { group in
            for p in Provider.allCases {
                group.addTask { (p, await Result { try await fetcher(p) }) }
            }
            for await (p, result) in group { apply(result, to: p) }
        }
        lastRefresh = Date()
        if lastRefresh!.timeIntervalSince(prunedAt) >= 86400 {
            history = History(url: history.url)
            prunedAt = Date()
        }
    }

    private func apply(_ result: Result<Snapshot, Error>, to p: Provider) {
        let previous = status[p]?.snapshot
        switch result {
        case .success(let s):
            status[p] = .fresh(s)
            history.append(s)
        case .failure(CredentialError.missing(let m)), .failure(CredentialError.expired(let m)): status[p] = .loggedOut(previous, m)
        case .failure(let e): status[p] = .stale(previous, Self.message(e))
        }
        save()
    }

    nonisolated static func message(_ error: Error) -> String {
        switch error {
        case let e as URLError where e.code == .badServerResponse:
            guard let code = e.userInfo["status"] as? Int else { return "Unexpected response" }
            return code == 429 ? "Rate limited, retrying later" : "Server error \(code)"
        case let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(e.code): return "Offline"
        case let e as URLError where e.code == .timedOut: return "Timed out"
        case is URLError: return "Network error"
        case is DecodingError: return "Unexpected response"
        default: return error.localizedDescription
        }
    }

    func startTimer(interval: TimeInterval = 300) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in await self.refresh() }
        }
    }

    private func save() {
        let snapshots = Provider.allCases.compactMap { status[$0]?.snapshot }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(snapshots).write(to: fileURL, options: .atomic)
    }
}

extension ProviderStatus {
    var snapshot: Snapshot? {
        switch self {
        case .empty: nil
        case .fresh(let s): s
        case .stale(let s, _), .loggedOut(let s, _): s
        }
    }
}

extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
