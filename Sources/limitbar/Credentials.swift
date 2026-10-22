import CommonCrypto
import Foundation
import SQLite3
import Security

enum CredentialError: Error, Equatable {
    case missing(String)
    case expired(String)
    case malformed(String)
}

enum Credentials {
    static func keychainJSON<T: Decodable>(service: String, as: T.Type) throws -> T {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw CredentialError.missing(service) }
        guard status == errSecSuccess, let data = item as? Data else { throw CredentialError.malformed(service) }
        return try decode(data, as: T.self, source: service)
    }

    static func hinted<T>(_ hint: String, _ body: () throws -> T) throws -> T {
        do { return try body() }
        catch CredentialError.expired(let m) { throw CredentialError.expired(m) }
        catch { throw CredentialError.missing(hint) }
    }

    static func fileJSON<T: Decodable>(at path: String, as: T.Type) throws -> T {
        let expanded = NSString(string: path).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: expanded) else { throw CredentialError.missing(path) }
        return try decode(data, as: T.self, source: path)
    }

    static let keychainHint = "relaunch limitbar and click Always Allow on the Keychain prompt for your browser's Safe Storage, or paste the sso cookie in Settings"

    static let fullDiskHint = "give limitbar Full Disk Access in System Settings, Privacy & Security, then relaunch it, or paste the sso cookie in Settings"

    nonisolated(unsafe) private static var safeStoragePasswords: [String: String?] = [:]

    static let chromiumBrowsers = [
        ("Google/Chrome", "Chrome Safe Storage"),
        ("BraveSoftware/Brave-Browser", "Brave Safe Storage"),
        ("Arc/User Data", "Arc Safe Storage"),
        ("Microsoft Edge", "Microsoft Edge Safe Storage"),
        ("Chromium", "Chromium Safe Storage"),
    ]

    static func chromiumStores(home: String = NSHomeDirectory()) -> [(path: String, service: String)] {
        chromiumBrowsers.flatMap { dir, service in
            let base = "\(home)/Library/Application Support/\(dir)"
            let profiles = ((try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []).filter { $0 == "Default" || $0.hasPrefix("Profile") }.sorted()
            return (profiles.isEmpty ? ["Default"] : profiles).map { (path: "\(base)/\($0)/Cookies", service: service) }
        }
    }

    static func chromeCookie(domain: String, name: String) throws -> String {
        var blocked = false
        var locked = false
        for store in chromiumStores() where FileManager.default.fileExists(atPath: store.path) {
            let blob: Data
            do { blob = try encryptedCookie(in: store.path, domain: domain, name: name) }
            catch CredentialError.missing(fullDiskHint) { blocked = true; continue }
            catch { continue }
            guard let password = safeStoragePassword(store.service) else { locked = true; continue }
            if let value = try? decryptChromeValue(blob, key: chromeKey(password: password)) { return value }
        }
        throw CredentialError.missing(locked ? keychainHint : blocked ? fullDiskHint : "chrome cookie")
    }

    private static func safeStoragePassword(_ service: String) -> String? {
        if let cached = safeStoragePasswords[service] { return cached }
        let password = try? keychainString(service: service)
        safeStoragePasswords[service] = password
        return password
    }

    static func chromiumCookie(stores: [(String, String)], domain: String, name: String) throws -> String {
        var blocked = false
        for (path, password) in stores {
            do { return try decryptChromeValue(encryptedCookie(in: path, domain: domain, name: name), key: chromeKey(password: password)) }
            catch CredentialError.missing(fullDiskHint) { blocked = true }
            catch {}
        }
        throw CredentialError.missing(blocked ? fullDiskHint : "chrome cookie")
    }

    private static func encryptedCookie(in source: String, domain: String, name: String) throws -> Data {
        guard FileManager.default.fileExists(atPath: source) else { throw CredentialError.missing("chrome cookie") }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("limitbar-cookies-\(UUID().uuidString).sqlite")
        do { try FileManager.default.copyItem(atPath: source, toPath: copy.path) }
        catch { throw CredentialError.missing(fullDiskHint) }
        defer { try? FileManager.default.removeItem(at: copy) }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw CredentialError.malformed("chrome cookie db") }
        var statement: OpaquePointer?
        let sql = "SELECT encrypted_value FROM cookies WHERE host_key IN (?, '.' || ?) AND name = ? ORDER BY expires_utc DESC LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw CredentialError.malformed("chrome cookie db") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, domain, -1, transient)
        sqlite3_bind_text(statement, 2, domain, -1, transient)
        sqlite3_bind_text(statement, 3, name, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw CredentialError.missing("chrome cookie") }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
    }

    static func chromeKey(password: String) -> Data {
        var key = Data(count: 16)
        let salt = Data("saltysalt".utf8)
        key.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count,
                                         saltBytes.baseAddress, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                                         keyBytes.baseAddress, 16)
            }
        }
        return key
    }

    static func decryptChromeValue(_ blob: Data, key: Data) throws -> String {
        guard blob.count > 3, blob.prefix(3) == Data("v10".utf8) else { throw CredentialError.malformed("chrome cookie") }
        let plain = try chromeCrypt(CCOperation(kCCDecrypt), blob.dropFirst(3), key: key)
        let body = plain.count > 32 && !plain.prefix(32).allSatisfy({ (0x20...0x7e).contains($0) }) ? plain.dropFirst(32) : plain[...]
        guard let value = String(data: body, encoding: .utf8) else { throw CredentialError.malformed("chrome cookie") }
        return value
    }

    static func chromeCrypt(_ operation: CCOperation, _ input: Data, key: Data) throws -> Data {
        let iv = Data(repeating: 0x20, count: 16)
        var out = Data(count: input.count + kCCBlockSizeAES128)
        var moved = 0
        let status = out.withUnsafeMutableBytes { outBytes in
            input.withUnsafeBytes { inBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                inBytes.baseAddress, input.count,
                                outBytes.baseAddress, outBytes.count, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw CredentialError.malformed("chrome cookie") }
        return out.prefix(moved)
    }

    static func keychainString(service: String) throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw CredentialError.missing(service) }
        guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else { throw CredentialError.malformed(service) }
        return value
    }

    static func setKeychainString(service: String, _ value: String) {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func decode<T: Decodable>(_ data: Data, as: T.Type, source: String) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw CredentialError.malformed(source) }
    }
}
