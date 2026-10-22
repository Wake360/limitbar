import Testing
import Foundation
@testable import limitbar

private func varint(_ v: UInt64) -> [UInt8] {
    var v = v
    var out: [UInt8] = []
    while v >= 0x80 { out.append(UInt8(v & 0x7f) | 0x80); v >>= 7 }
    return out + [UInt8(v)]
}

private func message(_ number: Int, _ bytes: [UInt8]) -> [UInt8] {
    varint(UInt64(number << 3 | 2)) + varint(UInt64(bytes.count)) + bytes
}

private func frame(_ payload: [UInt8]) -> Data {
    let n = payload.count
    return Data([0, UInt8(n >> 24 & 0xff), UInt8(n >> 16 & 0xff), UInt8(n >> 8 & 0xff), UInt8(n & 0xff)] + payload)
}

@Test func grokParsesWeeklyCreditsFrame() throws {
    let percent = withUnsafeBytes(of: Float(67).bitPattern.littleEndian, Array.init)
    let end = message(3, varint(8 << 3 | 0) + varint(1_792_000_000))
    let config = [0x0d] + percent + message(8, end)
    let s = try Grok.parse(frame(message(1, config)), now: Date())
    #expect(s.provider == .grok)
    #expect(s.plan == "SuperGrok")
    #expect(s.windows.count == 1)
    #expect(s.windows[0].usedPercent == 67)
    #expect(s.windows[0].kind == .weekly)
    #expect(s.windows[0].resetsAt == nil)
    #expect(s.longWindow?.usedPercent == 67)
}

@Test func grokReadsPeriodEndTimestamp() throws {
    let timestamp = [0x08] + varint(1_792_000_000)
    let config = message(8, message(3, timestamp))
    let s = try Grok.parse(frame(message(1, config)), now: Date())
    #expect(s.windows[0].resetsAt == Date(timeIntervalSince1970: 1_792_000_000))
    #expect(s.windows[0].usedPercent == 0)
}

@Test func grokUnauthenticatedTrailerMeansExpired() {
    let trailer = Array("grpc-status:16\r\ngrpc-message:unauthenticated\r\n".utf8)
    let body = Data([0x80, 0, 0, 0, UInt8(trailer.count)] + trailer)
    #expect(throws: CredentialError.expired(Grok.loginHint)) { try Grok.parse(body, now: Date()) }
}

@Test func grokSurvivesHugeLengthAndOversizedFloat() throws {
    let huge: [UInt8] = [0x0a, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]
    #expect(Grok.fields(Data(huge)).isEmpty)
    let config: [UInt8] = [0x08] + [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]
    _ = try Grok.parse(frame(message(1, config)), now: Date())
}
