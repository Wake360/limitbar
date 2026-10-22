import SwiftUI

struct ProviderRow: View {
    enum Style { case popover, sidebar }

    let provider: Provider
    let status: ProviderStatus
    let now: Date
    var style: Style = .sidebar

    private var availability: Availability? { Limits.availability(provider, status, now: now) }

    private var isSignedOut: Bool {
        if case .loggedOut = status { return true }
        return false
    }

    private var hot: Bool { availability?.hot == true }

    private var tint: Color { isSignedOut ? .secondary : hot ? .warn : provider.accent }

    static func spokenValue(_ provider: Provider, _ status: ProviderStatus, now: Date, style: Style) -> String {
        if case .loggedOut(_, let hint) = status { return signedOutTitle(hint).lowercased() }
        if case .stale(nil, let message) = status { return message }
        guard let snapshot = status.snapshot, let availability = Limits.availability(provider, status, now: now) else { return "loading" }
        var parts = style == .sidebar
            ? ["\(Verdict.kindWord(availability.window.kind)) \(Int(availability.window.usedPercent.rounded()))%"]
            : ProviderCard.windows(provider, snapshot, now: now).map { window in
                let name = window.label.lowercased()
                return "\(name) \(Int(window.usedPercent.rounded()))%"
            }
        if availability.backAt != nil { parts.append("back " + Format.backText(availability, now: now)) }
        return parts.joined(separator: ", ")
    }

    nonisolated static func sidebarLine(_ provider: Provider, _ status: ProviderStatus, now: Date) -> String? {
        if case .loggedOut(_, let hint) = status { return signedOutTitle(hint) }
        guard let availability = Limits.availability(provider, status, now: now) else { return nil }
        if availability.hot, availability.backAt != nil { return "back " + Format.backText(availability, now: now) }
        let percent = "\(Int(availability.window.usedPercent.rounded()))%"
        return [percent, Format.resetText(availability.window, now: now)].compactMap { $0 }.joined(separator: ", ")
    }

    nonisolated static func signedOutTitle(_ hint: String) -> String {
        hint == Credentials.keychainHint || hint == Credentials.fullDiskHint ? "Needs access" : "Signed out"
    }

    var body: some View {
        HStack(spacing: 10) {
            Ring.View(percent: availability?.window.usedPercent ?? status.snapshot?.highest?.usedPercent, color: tint, size: 34, dashed: isSignedOut)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    provider.icon.resizable().scaledToFit().frame(width: 14, height: 14).foregroundStyle(tint)
                    Text(provider.displayName).font(.system(size: 13, weight: .semibold))
                }
                if let line = Self.sidebarLine(provider, status, now: now) {
                    Text(line).font(.system(size: 11)).monospacedDigit().foregroundStyle(hot ? Color.warnText : Color.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(provider.displayName)
        .accessibilityValue(Self.spokenValue(provider, status, now: now, style: style))
    }
}
