import SwiftUI

struct PopoverView: View {
    let store: Store
    @Environment(\.openWindow) private var openWindow
    @State private var now = Date()

    var body: some View {
        let verdict = Verdict.make(store.status, now: now)
        let refresh = RefreshStatus.make(store.status, lastRefresh: store.lastRefresh, refreshing: store.refreshing, now: now)
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verdict.headline).font(.system(size: 16, weight: .semibold))
                    Text(verdict.line).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Circle().fill(refresh.fresh ? Color.fresh : Color.secondary).frame(width: 7, height: 7)
                    Text(refresh.text).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                    RefreshButton(store: store) { now = Date() }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
            VStack(spacing: 10) {
                ForEach(Limits.ordered(store.status, now: now), id: \.self) { provider in
                    ProviderCard(provider: provider, status: store.status[provider] ?? .empty, now: now)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            Divider()
            HStack(spacing: 0) {
                LoginToggle()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                Spacer()
                Button {
                    openWindow(id: "dashboard")
                    NSApp.activate()
                } label: { footerLabel("macwindow", "Dashboard") }
                .keyboardShortcut("d")
                SettingsLink { footerLabel("gearshape", "Settings") }
                    .keyboardShortcut(",")
                Button { NSApplication.shared.terminate(nil) } label: {
                    Image(systemName: "power")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .padding(.horizontal, 4).frame(height: 26)
                        .contentShape(Rectangle())
                }
                .keyboardShortcut("q")
                .help("Quit")
                .accessibilityLabel("Quit")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10).frame(minHeight: 36)
        }
        .frame(width: 400)
        .onAppear {
            now = Date()
            guard store.lastRefresh.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { return }
            Task { await store.refresh(); now = Date() }
        }
    }

    private func footerLabel(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize().padding(.horizontal, 4).frame(height: 26)
            .contentShape(Rectangle())
    }
}

struct RefreshButton: View {
    let store: Store
    var done: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { Task { await store.refresh(); done() } } label: {
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(store.refreshing && !reduceMotion ? 360 : 0))
                .animation(store.refreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: store.refreshing)
        }
        .buttonStyle(.borderless)
        .disabled(store.refreshing)
        .keyboardShortcut("r")
        .help("Refresh now")
    }
}
