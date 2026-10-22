import SwiftUI

@main
struct LimitbarApp: App {
    @State private var store: Store

    init() {
        let minutes = Store.refreshMinutes(.standard)
        let store = Store()
        _store = State(initialValue: store)
        store.startTimer(interval: TimeInterval(minutes * 60))
        Task { await store.refresh() }
    }

    var body: some Scene {
        Window("limitbar", id: "dashboard") { DashboardView(store: store) }
            .defaultSize(width: 980, height: 720)
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentMinSize)
            .defaultLaunchBehavior(.suppressed)
        MenuBarExtra { PopoverView(store: store) } label: { MenuBarLabel(store: store) }
            .menuBarExtraStyle(.window)
        Settings { SettingsView(store: store) }
    }
}
