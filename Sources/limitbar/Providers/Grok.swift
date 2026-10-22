import Foundation

enum Grok {
    static let cookieDefaultsKey = "grokSSOCookie"
    static let cookieService = "limitbar grok sso"
    static let creditsURL = URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig")!
    static let loginHint = "paste the grok.com sso cookie in Settings, or log in to grok.com in Chrome or Brave"

    struct Field {
        let number: Int
        let value: UInt64
        let bytes: Data
    }

    static func fields(_ data: Data) -> [Field] {
        let b = [UInt8](data)
        var i = 0
        var out: [Field] = []
        func varint() -> UInt64 {
            var v: UInt64 = 0
            var shift: UInt64 = 0
            while i < b.count {
                let c = b[i]
                i += 1
                v |= UInt64(c & 0x7f) << shift
                if c < 0x80 { break }
                shift += 7
            }
            return v
        }
        func fixed(_ n: Int) -> UInt64? {
            guard n <= b.count - i else { return nil }
            defer { i += n }
            return b[i..<i + n].reversed().reduce(0) { $0 << 8 | UInt64($1) }
        }
        while i < b.count {
            let tag = varint()
            let number = Int(tag >> 3)
            switch tag & 7 {
            case 0: out.append(Field(number: number, value: varint(), bytes: Data()))
            case 1: guard let v = fixed(8) else { return out }; out.append(Field(number: number, value: v, bytes: Data()))
            case 5: guard let v = fixed(4) else { return out }; out.append(Field(number: number, value: v, bytes: Data()))
            case 2:
                let n = Int(clamping: varint())
                guard n <= b.count - i else { return out }
                out.append(Field(number: number, value: 0, bytes: Data(b[i..<i + n])))
                i += n
            default: return out
            }
        }
        return out
    }

    static func parse(_ body: Data, now: Date) throws -> Snapshot {
        let b = [UInt8](body)
        guard b.count >= 5, b[0] == 0 else {
            let trailer = String(decoding: b.dropFirst(5), as: UTF8.self)
            if trailer.contains("grpc-status:16") || trailer.contains("grpc-status:7") { throw CredentialError.expired(loginHint) }
            throw URLError(.badServerResponse)
        }
        let length = b[1...4].reduce(0) { $0 << 8 | Int($1) }
        guard b.count >= 5 + length else { throw URLError(.badServerResponse) }
        let config = fields(fields(Data(b[5..<5 + length])).first { $0.number == 1 }?.bytes ?? Data())
        let percent = config.first { $0.number == 1 }.map { Double(Float(bitPattern: UInt32(truncatingIfNeeded: $0.value))) } ?? 0
        let period = fields(config.first { $0.number == 8 }?.bytes ?? Data())
        let end = fields(period.first { $0.number == 3 }?.bytes ?? Data()).first { $0.number == 1 }.map { Date(timeIntervalSince1970: TimeInterval($0.value)) }
        let window = UsageWindow(label: "Weekly", usedPercent: percent, resetsAt: end, kind: .weekly)
        return Snapshot(provider: .grok, plan: "SuperGrok", windows: [window], fetchedAt: now)
    }

    static func pastedCookie() -> String {
        if let legacy = UserDefaults.standard.string(forKey: cookieDefaultsKey) {
            Credentials.setKeychainString(service: cookieService, legacy)
            UserDefaults.standard.removeObject(forKey: cookieDefaultsKey)
        }
        return (try? Credentials.keychainString(service: cookieService)) ?? ""
    }

    static func cookie() throws -> String {
        let pasted = pastedCookie()
        if !pasted.isEmpty { return pasted }
        do { return try Credentials.chromeCookie(domain: "grok.com", name: "sso") }
        catch CredentialError.missing(let m) where m == Credentials.keychainHint || m == Credentials.fullDiskHint { throw CredentialError.missing(m) }
        catch { throw CredentialError.missing(loginHint) }
    }

    static func fetch() async throws -> Snapshot {
        let sso = try cookie()
        var request = URLRequest(url: creditsURL)
        request.httpMethod = "POST"
        request.setValue("application/grpc-web+proto", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Grpc-Web")
        request.setValue("sso=\(sso)", forHTTPHeaderField: "Cookie")
        request.httpBody = Data([0, 0, 0, 0, 0])
        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTP.check(response, loginHint: loginHint)
        if let status = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "grpc-status"), status == "16" || status == "7" { throw CredentialError.expired(loginHint) }
        return try parse(data, now: Date())
    }
}
