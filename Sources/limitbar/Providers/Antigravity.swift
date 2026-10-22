import Foundation
import Security

enum Antigravity {
    static let clientID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    static let clientSecret = "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"
    static let loginHint = "open Antigravity and sign in"
    static let keyringPrefix = "go-keyring-base64:"
    static let userAgent = "antigravity/1.11.5 darwin/arm64"
    static let loadURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
    static let modelsURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels")!
    static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    struct Stored: Decodable {
        struct Token: Decodable { let refresh_token: String }
        let token: Token
    }

    struct TokenResponse: Decodable { let access_token: String }

    struct Load: Decodable { let cloudaicompanionProject: String? }

    struct Models: Decodable {
        struct Model: Decodable {
            struct Quota: Decodable {
                let remainingFraction: Double?
                let resetTime: Date?
            }
            let displayName: String?
            let quotaInfo: Quota?
        }
        let models: [String: Model]?
    }

    static func refreshToken(from data: Data) throws -> String {
        let raw = String(decoding: data, as: UTF8.self)
        let json = raw.hasPrefix(keyringPrefix) ? Data(base64Encoded: String(raw.dropFirst(keyringPrefix.count))) : data
        guard let json else { throw CredentialError.malformed("antigravity keychain") }
        return try JSONDecoder().decode(Stored.self, from: json).token.refresh_token
    }

    static func parse(_ data: Data, now: Date) throws -> Snapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let models = try decoder.decode(Models.self, from: data).models ?? [:]
        let windows = models.compactMap { id, m -> UsageWindow? in
            guard let q = m.quotaInfo else { return nil }
            let left = (q.resetTime ?? now).timeIntervalSince(now)
            let kind: WindowKind = left > 86400 ? .weekly : left > 5 * 3600 + 60 ? .daily : .fiveHour
            return UsageWindow(label: m.displayName ?? id, usedPercent: (1 - (q.remainingFraction ?? 0)) * 100, resetsAt: q.resetTime, kind: kind)
        }
        let sorted = windows.sorted { $0.usedPercent != $1.usedPercent ? $0.usedPercent > $1.usedPercent : $0.label < $1.label }
        return Snapshot(provider: .gemini, plan: "Antigravity", windows: sorted, fetchedAt: now)
    }

    static func storedRefreshToken() throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "gemini",
            kSecAttrAccount: "antigravity",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { throw CredentialError.missing(loginHint) }
        return try refreshToken(from: data)
    }

    static func accessToken(refreshToken: String) async throws -> String {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("client_id=\(clientID)&client_secret=\(clientSecret)&refresh_token=\(refreshToken)&grant_type=refresh_token".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CredentialError.expired(loginHint) }
        return try JSONDecoder().decode(TokenResponse.self, from: data).access_token
    }

    static func fetch() async throws -> Snapshot {
        let refresh = try Credentials.hinted(loginHint) { try storedRefreshToken() }
        let token = try await accessToken(refreshToken: refresh)
        let load = try await post(loadURL, token: token, body: ["metadata": ["ideType": "ANTIGRAVITY", "platform": "PLATFORM_UNSPECIFIED", "pluginType": "GEMINI"]])
        guard let project = try JSONDecoder().decode(Load.self, from: load).cloudaicompanionProject else { throw CredentialError.missing(loginHint) }
        return try parse(try await post(modelsURL, token: token, body: ["project": project]), now: Date())
    }

    private static func post(_ url: URL, token: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTP.check(response, loginHint: loginHint)
        return data
    }
}
