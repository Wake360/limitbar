import Foundation

struct History: Sendable {
    let url: URL

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("limitbar/history.jsonl")
    }

    init(url: URL, now: Date = Date()) {
        self.url = url
        let cutoff = now - 14 * 86400
        let lines = Self.lines(at: url)
        let kept = lines.filter { ($0.snapshot?.fetchedAt ?? .distantPast) >= cutoff }
        guard kept.count < lines.count else { return }
        let text = kept.map { $0.text + "\n" }.joined()
        try? Data(text.utf8).write(to: url, options: .atomic)
    }

    func append(_ s: Snapshot) {
        guard var data = try? JSONEncoder().encode(s) else { return }
        data.append(10)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    func load(_ p: Provider, since: Date) -> [Snapshot] {
        Self.lines(at: url).compactMap(\.snapshot).filter { $0.provider == p && $0.fetchedAt >= since }
    }

    static func readings(_ snaps: [Snapshot], label: String, resetsAt: Date) -> [(at: Date, percent: Double)] {
        snaps.compactMap { s -> (at: Date, percent: Double)? in
            guard let w = s.windows.first(where: { $0.label == label }),
                  let r = w.resetsAt, abs(r.timeIntervalSince(resetsAt)) <= 60 else { return nil }
            return (s.fetchedAt, w.usedPercent)
        }
        .sorted { $0.at < $1.at }
    }

    private static func lines(at url: URL) -> [(text: String, snapshot: Snapshot?)] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").map { line in
            (String(line), try? decoder.decode(Snapshot.self, from: Data(line.utf8)))
        }
    }
}
