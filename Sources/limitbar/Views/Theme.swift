import SwiftUI
import AppKit

extension NSColor {
    static func adaptive(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        }
    }

    static let warn = adaptive(0xD97706, 0xF59E0B)
    static let warnText = adaptive(0xB45309, 0xFBBF24)
    static let claudeAccent = adaptive(0xD97757, 0xD97757)
    static let claudeText = adaptive(0xA8492A, 0xF0A890)
    static let geminiAccent = adaptive(0x5B8DEF, 0x5B8DEF)
    static let neutral = adaptive(0x1A1D24, 0xE6E8EC)
    static let sessionViolet = adaptive(0x8B5CF6, 0xA78BFA)
    static let sessionTeal = adaptive(0x0D9488, 0x2DD4BF)
    static let sessionSky = adaptive(0x2563EB, 0x60A5FA)
    static let sessionOther = adaptive(0x9CA3AF, 0x6B7280)
    static let fresh = adaptive(0x16A34A, 0x4ADE80)
    static let canvas = adaptive(0xF5F6F8, 0x0D1019)
    static let card = adaptive(0xFFFFFF, 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.04)
    static let cardBorder = adaptive(0x000000, 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.08)
}

extension Color {
    static let warn = Color(nsColor: .warn)
    static let warnText = Color(nsColor: .warnText)
    static let claudeAccent = Color(nsColor: .claudeAccent)
    static let claudeText = Color(nsColor: .claudeText)
    static let geminiAccent = Color(nsColor: .geminiAccent)
    static let neutral = Color(nsColor: .neutral)
    static let sessionViolet = Color(nsColor: .sessionViolet)
    static let sessionTeal = Color(nsColor: .sessionTeal)
    static let sessionSky = Color(nsColor: .sessionSky)
    static let sessionOther = Color(nsColor: .sessionOther)
    static let fresh = Color(nsColor: .fresh)
    static let canvas = Color(nsColor: .canvas)
    static let card = Color(nsColor: .card)
    static let cardBorder = Color(nsColor: .cardBorder)
}

extension Provider {
    var accentNS: NSColor {
        switch self {
        case .claude: .claudeAccent
        case .gemini: .geminiAccent
        case .codex, .grok: .neutral
        }
    }

    var accent: Color { Color(nsColor: accentNS) }
}
