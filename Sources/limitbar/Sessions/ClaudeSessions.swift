import Foundation

struct UsageEvent: Equatable, Sendable {
    let session: String
    let project: String
    let branch: String?
    let agent: String?
    let at: Date
    let weight: Double
}

enum ClaudeSessions {
    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                let input_tokens: Double?
                let cache_creation_input_tokens: Double?
                let cache_read_input_tokens: Double?
                let output_tokens: Double?
            }
            let id: String?
            let usage: Usage?
        }
        let timestamp: String?
        let sessionId: String?
        let cwd: String?
        let gitBranch: String?
        let agentId: String?
        let requestId: String?
        let message: Message?
    }

    static func parse(_ data: Data) -> [UsageEvent] {
        var seen = Set<String>()
        return keyedEvents(data).compactMap { key, event in
            if let key, !seen.insert(key).inserted { return nil }
            return event
        }
    }

    static func load(root: URL, from: Date, to: Date) -> [UsageEvent] {
        guard let files = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }
        var seen = Set<String>()
        var events: [UsageEvent] = []
        for case let url as URL in files where url.pathExtension == "jsonl" {
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified >= from,
                  let data = try? Data(contentsOf: url) else { continue }
            for (key, event) in keyedEvents(data) {
                if let key, !seen.insert(key).inserted { continue }
                if event.at >= from && event.at <= to { events.append(event) }
            }
        }
        return events.sorted { $0.at < $1.at }
    }

    private static func keyedEvents(_ data: Data) -> [(String?, UsageEvent)] {
        let decoder = JSONDecoder()
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return JSONL.lines(data, containing: ["\"usage\""]).compactMap { raw in
            guard let line = try? decoder.decode(Line.self, from: raw),
                  let usage = line.message?.usage,
                  let session = line.sessionId,
                  let stamp = line.timestamp,
                  let at = fractional.date(from: stamp) ?? plain.date(from: stamp) else { return nil }
            let weight = (usage.input_tokens ?? 0)
                + (usage.cache_creation_input_tokens ?? 0)
                + (usage.output_tokens ?? 0)
                + 0.1 * (usage.cache_read_input_tokens ?? 0)
            let project = line.cwd.map { ($0 as NSString).lastPathComponent } ?? ""
            var key: String?
            if let id = line.message?.id, let request = line.requestId { key = "\(id)|\(request)" }
            let event = UsageEvent(
                session: session,
                project: project,
                branch: line.gitBranch,
                agent: line.agentId,
                at: at,
                weight: weight
            )
            return (key, event)
        }
    }
}

enum JSONL {
    static func lines(_ data: Data, containing markers: [String]) -> [Data] {
        let markers = markers.map { Data($0.utf8) }
        return data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return [] }
            var out: [Data] = []
            var start = 0
            while start < buffer.count {
                let end = memchr(base + start, 0x0a, buffer.count - start).map { base.distance(to: UnsafeRawPointer($0)) } ?? buffer.count
                let line = UnsafeRawBufferPointer(rebasing: buffer[start..<end])
                let hit = markers.contains { marker in
                    marker.withUnsafeBytes { memmem(line.baseAddress, line.count, $0.baseAddress, $0.count) != nil }
                }
                if hit { out.append(Data(line)) }
                start = end + 1
            }
            return out
        }
    }
}
