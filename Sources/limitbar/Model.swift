import Foundation

enum Provider: String, CaseIterable, Codable, Sendable { case claude, codex, gemini, grok }

enum WindowKind: String, Codable, Sendable { case fiveHour, weekly, daily, credits }

struct UsageWindow: Codable, Equatable, Sendable {
    let label: String
    let usedPercent: Double
    let resetsAt: Date?
    let kind: WindowKind
}

struct Snapshot: Codable, Equatable, Sendable {
    let provider: Provider
    let plan: String
    let windows: [UsageWindow]
    let fetchedAt: Date
}

enum ProviderStatus: Equatable, Sendable {
    case empty
    case fresh(Snapshot)
    case stale(Snapshot?, String)
    case loggedOut(Snapshot?, String)
}

extension Snapshot {
    var shortWindow: UsageWindow? { windows.first { $0.kind == .fiveHour } ?? windows.first { $0.kind == .daily } }
    var longWindow: UsageWindow? { windows.first { $0.kind == .weekly } ?? windows.first { $0.kind == .credits } }

    var highest: UsageWindow? {
        windows.reduce(nil) { best, w in
            guard let best else { return w }
            return w.usedPercent > best.usedPercent ? w : best
        }
    }
}

typealias Fetcher = @Sendable (Provider) async throws -> Snapshot
