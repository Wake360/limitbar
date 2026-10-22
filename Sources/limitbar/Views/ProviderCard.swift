import SwiftUI

struct ProviderCard: View {
    let provider: Provider
    let status: ProviderStatus
    let now: Date
    @Environment(\.colorScheme) private var colorScheme

    nonisolated static func windows(_ provider: Provider, _ snapshot: Snapshot, now: Date) -> [UsageWindow] {
        let current = snapshot.windows.map { Limits.current($0, now: now) }
        guard provider == .gemini else { return current }
        return Array(current.sorted { $0.usedPercent > $1.usedPercent }.prefix(2))
    }

    private var hot: Bool { Limits.availability(provider, status, now: now)?.hot == true }

    private var signedOut: Bool {
        if case .loggedOut = status { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder))
        .shadow(color: colorScheme == .light ? .black.opacity(0.05) : .clear, radius: 12, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(provider.displayName)
        .accessibilityValue(ProviderRow.spokenValue(provider, status, now: now, style: .popover))
    }

    private var header: some View {
        HStack(spacing: 8) {
            provider.icon
                .resizable().scaledToFit().frame(width: 16, height: 16)
                .foregroundStyle(signedOut ? AnyShapeStyle(.secondary) : AnyShapeStyle(hot ? Color.warn : provider.accent))
            Text(provider.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(signedOut ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .layoutPriority(2)
            if let plan = status.snapshot?.plan, !plan.isEmpty, !signedOut {
                Text(plan).font(.system(size: 12)).foregroundStyle(.secondary).layoutPriority(1)
            }
            Spacer(minLength: 0)
            if case .stale(_, let message) = status, message != "cached" {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch status {
        case .empty:
            Text("Loading").font(.system(size: 12)).foregroundStyle(.secondary)
        case .loggedOut(_, let hint):
            VStack(alignment: .leading, spacing: 2) {
                Text(ProviderRow.signedOutTitle(hint)).font(.system(size: 12))
                Text(hint).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        case .fresh(let snapshot), .stale(let snapshot?, _):
            VStack(spacing: 8) {
                ForEach(Self.windows(provider, snapshot, now: now), id: \.label) { window in
                    CardRow(window: window, accent: provider.accent, now: now)
                }
            }
        case .stale(nil, _):
            EmptyView()
        }
    }
}

private struct CardRow: View {
    let window: UsageWindow
    let accent: Color
    let now: Date

    private var hot: Bool { window.usedPercent >= Limits.hot }

    var body: some View {
        HStack(spacing: 8) {
            Text(window.label).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                .frame(width: 86, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(hot ? Color.warn : accent)
                        .frame(width: geo.size.width * min(max(window.usedPercent, 0), 100) / 100)
                }
            }
            .frame(height: 5)
            Text("\(Int(window.usedPercent.rounded()))%")
                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .lineLimit(1)
                .frame(width: 40, alignment: .trailing)
            Text(Format.resetText(window, now: now) ?? "")
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(hot ? Color.warnText : Color.secondary)
                .lineLimit(1)
                .frame(width: 96, alignment: .trailing)
        }
    }
}
