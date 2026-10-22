import Testing
import Foundation
@testable import limitbar

@Test func staleMessagesAreReadable() {
    #expect(Store.message(URLError(.notConnectedToInternet)) == "Offline")
    #expect(Store.message(URLError(.timedOut)) == "Timed out")
    #expect(Store.message(URLError(.badServerResponse)) == "Unexpected response")
    #expect(Store.message(URLError(.badServerResponse, userInfo: ["status": 429])) == "Rate limited, retrying later")
    #expect(Store.message(URLError(.badServerResponse, userInfo: ["status": 503])) == "Server error 503")
    struct A: Decodable { let x: Int }
    #expect(Store.message(Result { try JSONDecoder().decode(A.self, from: Data("{}".utf8)) }.failure!) == "Unexpected response")
}

@Test func httpCheckKeepsStatusCode() {
    let response = HTTPURLResponse(url: URL(string: "https://x")!, statusCode: 429, httpVersion: nil, headerFields: nil)!
    #expect(throws: URLError.self) { try HTTP.check(response, loginHint: "h") }
    do { try HTTP.check(response, loginHint: "h") } catch { #expect(Store.message(error) == "Rate limited, retrying later") }
}

extension Result {
    var failure: Failure? { if case .failure(let e) = self { e } else { nil } }
}

@Test func codexWithoutWeeklyWindowParses() throws {
    let json = #"{"plan_type":"free","rate_limit":{"primary_window":{"used_percent":40,"reset_at":1761166080},"secondary_window":null}}"#
    let s = try Codex.parse(Data(json.utf8), now: Date())
    #expect(s.windows.map(\.label) == ["5-hour"])
}

@Test func claudeWithNullWindowsParses() throws {
    let json = #"{"five_hour":null,"seven_day":{"utilization":10,"resets_at":null},"seven_day_opus":null}"#
    let s = try Claude.parse(Data(json.utf8), plan: "Pro", now: Date())
    #expect(s.windows.map(\.label) == ["Weekly"])
}

@Test func jsonlKeepsOnlyMarkedLines() {
    let data = Data("{\"a\":1}\n{\"usage\":2}\n\n{\"b\":\"usage\"}\n{\"usage\":3}".utf8)
    let lines = JSONL.lines(data, containing: ["\"usage\""]).map { String(decoding: $0, as: UTF8.self) }
    #expect(lines == ["{\"usage\":2}", "{\"b\":\"usage\"}", "{\"usage\":3}"])
}

@Test func historyPrunesOnReopen() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("limitbar-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    let now = Date()
    let history = History(url: url, now: now)
    history.append(Snapshot(provider: .grok, plan: "", windows: [], fetchedAt: now - 20 * 86400))
    history.append(Snapshot(provider: .grok, plan: "", windows: [], fetchedAt: now))
    _ = History(url: url, now: now)
    #expect(history.load(.grok, since: .distantPast).count == 1)
}

@Test func verdictSaysWhenEveryFetchFailed() {
    let status = Dictionary(uniqueKeysWithValues: Provider.allCases.map { ($0, ProviderStatus.stale(nil, "Offline")) })
    #expect(Verdict.make(status, now: Date()).line == "Couldn't load limits. Retrying at the next refresh.")
}
