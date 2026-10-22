import Testing
import Foundation
@testable import limitbar

struct Probe: Decodable, Equatable { let token: String }

@Test func fileJSONReadsTempFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("probe.json")
    try #"{"token":"test-token"}"#.write(to: url, atomically: true, encoding: .utf8)
    #expect(try Credentials.fileJSON(at: url.path, as: Probe.self) == Probe(token: "test-token"))
}

@Test func fileJSONMissingThrowsMissing() {
    #expect(throws: CredentialError.missing("/nonexistent/x.json")) {
        try Credentials.fileJSON(at: "/nonexistent/x.json", as: Probe.self)
    }
}

@Test func fileJSONMalformedThrowsMalformed() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("bad.json")
    try "nope".write(to: url, atomically: true, encoding: .utf8)
    #expect(throws: CredentialError.malformed(url.path)) {
        try Credentials.fileJSON(at: url.path, as: Probe.self)
    }
}

@Test func keychainMissingServiceThrowsMissing() {
    #expect(throws: CredentialError.missing("limitbar-no-such-service")) {
        try Credentials.keychainJSON(service: "limitbar-no-such-service", as: Probe.self)
    }
}
