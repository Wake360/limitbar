import Foundation

struct PercentPoint: Equatable, Sendable {
    let session: String
    let project: String
    let at: Date
    let windowMinutes: Int
    let usedPercent: Double
    let resetsAt: Date
}

enum CodexSessions {
    private struct Line: Decodable {
        struct Window: Decodable {
            let used_percent: Double?
            let window_minutes: Int?
            let resets_at: Double?
        }
        struct RateLimits: Decodable {
            let primary: Window?
            let secondary: Window?
        }
        struct Payload: Decodable {
            let type: String?
            let id: String?
            let session_id: String?
            let cwd: String?
            let rate_limits: RateLimits?
        }
        let timestamp: String?
        let type: String?
        let payload: Payload?
    }

    static func parse(_ data: Data) -> [PercentPoint] {
        let decoder = JSONDecoder()
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var session = ""
        var project = ""
        var points: [PercentPoint] = []
        for raw in JSONL.lines(data, containing: ["\"session_meta\"", "\"rate_limits\""]) {
            guard let line = try? decoder.decode(Line.self, from: raw),
                  let payload = line.payload else { continue }
            if line.type == "session_meta" {
                session = payload.session_id ?? payload.id ?? ""
                project = payload.cwd.map { ($0 as NSString).lastPathComponent } ?? ""
                continue
            }
            guard line.type == "event_msg",
                  payload.type == "token_count",
                  let stamp = line.timestamp,
                  let at = fractional.date(from: stamp) ?? plain.date(from: stamp) else { continue }
            for window in [payload.rate_limits?.primary, payload.rate_limits?.secondary] {
                guard let window,
                      let used = window.used_percent,
                      let minutes = window.window_minutes,
                      let reset = window.resets_at else { continue }
                points.append(PercentPoint(
                    session: session,
                    project: project,
                    at: at,
                    windowMinutes: minutes,
                    usedPercent: used,
                    resetsAt: Date(timeIntervalSince1970: reset)
                ))
            }
        }
        return points
    }

    static func load(root: URL, from: Date, to: Date) -> [PercentPoint] {
        guard let files = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }
        var points: [PercentPoint] = []
        for case let url as URL in files where url.pathExtension == "jsonl" {
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified >= from,
                  let data = try? Data(contentsOf: url) else { continue }
            points += parse(data).filter { $0.at >= from && $0.at <= to }
        }
        return points.sorted { $0.at < $1.at }
    }
}
