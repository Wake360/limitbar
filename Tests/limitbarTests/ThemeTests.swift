import Testing
import AppKit
@testable import limitbar

private func hex(_ color: NSColor, dark: Bool) -> UInt32 {
    var result: UInt32 = 0
    NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
        let c = color.usingColorSpace(.sRGB)!
        result = UInt32((c.redComponent * 255).rounded()) << 16 | UInt32((c.greenComponent * 255).rounded()) << 8 | UInt32((c.blueComponent * 255).rounded())
    }
    return result
}

@Test func themeTokensMatchSpec() {
    #expect(hex(.warn, dark: false) == 0xD97706)
    #expect(hex(.warn, dark: true) == 0xF59E0B)
    #expect(hex(.warnText, dark: false) == 0xB45309)
    #expect(hex(.warnText, dark: true) == 0xFBBF24)
    #expect(hex(.claudeAccent, dark: true) == 0xD97757)
    #expect(hex(.neutral, dark: false) == 0x1A1D24)
    #expect(hex(.neutral, dark: true) == 0xE6E8EC)
    #expect(hex(.sessionSky, dark: true) == 0x60A5FA)
    #expect(hex(.canvas, dark: true) == 0x0D1019)
}

@Test func providerAccents() {
    #expect(Provider.claude.accentNS == .claudeAccent)
    #expect(Provider.gemini.accentNS == .geminiAccent)
    #expect(Provider.codex.accentNS == .neutral)
    #expect(Provider.grok.accentNS == .neutral)
}
