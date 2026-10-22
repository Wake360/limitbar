import CommonCrypto
import SQLite3
import Testing
import Foundation
@testable import limitbar

@Test func chromeKeyDerivationIsDeterministic() {
    let k = Credentials.chromeKey(password: "test-token")
    #expect(k.count == 16)
    #expect(k == Credentials.chromeKey(password: "test-token"))
    #expect(k != Credentials.chromeKey(password: "other"))
}

@Test func chromeValueRoundTrip() throws {
    let key = Credentials.chromeKey(password: "test-token")
    let blob = try Credentials.encryptChromeValueForTest("hello", key: key)
    #expect(blob.prefix(3) == Data("v10".utf8))
    #expect(try Credentials.decryptChromeValue(blob, key: key) == "hello")
}

@Test func chromeValueStripsHostHashPrefix() throws {
    let key = Credentials.chromeKey(password: "test-token")
    let hash = Data(repeating: 0x01, count: 32)
    let blob = try Credentials.encryptChromeValueForTest(hash + Data("cookie".utf8), key: key)
    #expect(try Credentials.decryptChromeValue(blob, key: key) == "cookie")
}

@Test func chromeValueWrongPrefixThrows() {
    let key = Credentials.chromeKey(password: "test-token")
    #expect(throws: CredentialError.malformed("chrome cookie")) {
        try Credentials.decryptChromeValue(Data("v20xxxxxxxxxxxxxxxxxxx".utf8), key: key)
    }
}

extension Credentials {
    static func encryptChromeValueForTest(_ value: String, key: Data) throws -> Data {
        try encryptChromeValueForTest(Data(value.utf8), key: key)
    }
    static func encryptChromeValueForTest(_ plain: Data, key: Data) throws -> Data {
        Data("v10".utf8) + (try chromeCrypt(CCOperation(kCCEncrypt), plain, key: key))
    }
}

@Test func chromiumCookieReadsFromAnyStore() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("limitbar-store-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let db = dir.appendingPathComponent("Cookies").path
    let key = Credentials.chromeKey(password: "test-token")
    let blob = try Credentials.encryptChromeValueForTest("secret", key: key)
    try makeCookieDB(at: db, host: ".grok.com", name: "sso", blob: blob)
    let found = try Credentials.chromiumCookie(stores: [(db, "test-token")], domain: "grok.com", name: "sso")
    #expect(found == "secret")
    #expect(throws: CredentialError.missing("chrome cookie")) {
        try Credentials.chromiumCookie(stores: [(dir.appendingPathComponent("nope").path, "test-token")], domain: "grok.com", name: "sso")
    }
}

@Test func chromiumStoresIncludeBraveAndChromeProfiles() {
    let stores = Credentials.chromiumStores(home: "/h")
    #expect(stores.contains { $0.path == "/h/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cookies" && $0.service == "Brave Safe Storage" })
    #expect(stores.contains { $0.path == "/h/Library/Application Support/Google/Chrome/Default/Cookies" && $0.service == "Chrome Safe Storage" })
}

private func makeCookieDB(at path: String, host: String, name: String, blob: Data) throws {
    var db: OpaquePointer?
    defer { sqlite3_close(db) }
    try #require(sqlite3_open(path, &db) == SQLITE_OK)
    try #require(sqlite3_exec(db, "CREATE TABLE cookies (host_key TEXT, name TEXT, encrypted_value BLOB, expires_utc INTEGER)", nil, nil, nil) == SQLITE_OK)
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try #require(sqlite3_prepare_v2(db, "INSERT INTO cookies VALUES (?, ?, ?, 1)", -1, &statement, nil) == SQLITE_OK)
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    sqlite3_bind_text(statement, 1, host, -1, transient)
    sqlite3_bind_text(statement, 2, name, -1, transient)
    _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32(blob.count), transient) }
    try #require(sqlite3_step(statement) == SQLITE_DONE)
}
