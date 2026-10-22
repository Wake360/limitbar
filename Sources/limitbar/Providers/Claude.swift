import Foundation

enum Claude {
    static let service = "Claude Code-credentials"
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let loginHint = "run claude to re-login"

    struct Keychain: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let expiresAt: Int
            let subscriptionType: String?
        }
        let claudeAiOauth: OAuth
    }

    struct Usage: Decodable {
        struct Window: Decodable {
            let utilization: Double
            let resets_at: Date?
        }
        let five_hour: Window?
        let seven_day: Window?
        let seven_day_opus: Window?
    }

    static func parse(_ data: Data, plan: String, now: Date) throws -> Snapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let u = try decoder.decode(Usage.self, from: data)
        var windows: [UsageWindow] = []
        if let five = u.five_hour {
            windows.append(UsageWindow(label: "5-hour", usedPercent: five.utilization, resetsAt: five.resets_at, kind: .fiveHour))
        }
        if let week = u.seven_day {
            windows.append(UsageWindow(label: "Weekly", usedPercent: week.utilization, resetsAt: week.resets_at, kind: .weekly))
        }
        if let opus = u.seven_day_opus {
            windows.append(UsageWindow(label: "Opus weekly", usedPercent: opus.utilization, resetsAt: opus.resets_at, kind: .weekly))
        }
        guard !windows.isEmpty else { throw URLError(.badServerResponse) }
        return Snapshot(provider: .claude, plan: plan, windows: windows, fetchedAt: now)
    }

    static func fetch() async throws -> Snapshot {
        let oauth = try Credentials.hinted(loginHint) { try Credentials.keychainJSON(service: service, as: Keychain.self).claudeAiOauth }
        let now = Date()
        guard Double(oauth.expiresAt) / 1000 > now.timeIntervalSince1970 else { throw CredentialError.expired(loginHint) }
        var request = URLRequest(url: usageURL)
        request.setValue("Bearer \(oauth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTP.check(response, loginHint: loginHint)
        return try parse(data, plan: (oauth.subscriptionType ?? "").capitalized, now: now)
    }
}

enum HTTP {
    static func check(_ response: URLResponse, loginHint: String) throws {
        guard let code = (response as? HTTPURLResponse)?.statusCode else { return }
        if code == 401 || code == 403 { throw CredentialError.expired(loginHint) }
        guard (200..<300).contains(code) else { throw URLError(.badServerResponse, userInfo: ["status": code]) }
    }
}
