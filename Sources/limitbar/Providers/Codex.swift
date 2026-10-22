import Foundation

enum Codex {
    static let authPath = "~/.codex/auth.json"
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let loginHint = "run codex login"

    struct Auth: Decodable {
        struct Tokens: Decodable {
            let access_token: String
            let account_id: String
        }
        let tokens: Tokens
    }

    struct Usage: Decodable {
        struct Window: Decodable {
            let used_percent: Double
            let reset_at: Double
        }
        struct RateLimit: Decodable {
            let primary_window: Window
            let secondary_window: Window?
        }
        let plan_type: String
        let rate_limit: RateLimit
    }

    static func parse(_ data: Data, now: Date) throws -> Snapshot {
        let u = try JSONDecoder().decode(Usage.self, from: data)
        let plan: String
        switch u.plan_type {
        case "plus": plan = "ChatGPT Plus"
        case "pro": plan = "ChatGPT Pro"
        default: plan = u.plan_type
        }
        let primary = u.rate_limit.primary_window
        var windows = [UsageWindow(label: "5-hour", usedPercent: primary.used_percent, resetsAt: Date(timeIntervalSince1970: primary.reset_at), kind: .fiveHour)]
        if let secondary = u.rate_limit.secondary_window {
            windows.append(UsageWindow(label: "Weekly", usedPercent: secondary.used_percent, resetsAt: Date(timeIntervalSince1970: secondary.reset_at), kind: .weekly))
        }
        return Snapshot(provider: .codex, plan: plan, windows: windows, fetchedAt: now)
    }

    static func fetch() async throws -> Snapshot {
        let tokens = try Credentials.hinted(loginHint) { try Credentials.fileJSON(at: authPath, as: Auth.self).tokens }
        var request = URLRequest(url: usageURL)
        request.setValue("Bearer \(tokens.access_token)", forHTTPHeaderField: "Authorization")
        request.setValue(tokens.account_id, forHTTPHeaderField: "ChatGPT-Account-Id")
        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTP.check(response, loginHint: loginHint)
        return try parse(data, now: Date())
    }
}
