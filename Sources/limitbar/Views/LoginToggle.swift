import SwiftUI
import ServiceManagement

struct LoginToggle: View {
    @State private var openAtLogin = LoginToggle.registered
    @State private var loginError: String?

    private static var registered: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Launch at login", isOn: $openAtLogin)
                .onAppear { openAtLogin = Self.registered }
                .onChange(of: openAtLogin) { _, enabled in
                    guard enabled != Self.registered else { return }
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        loginError = nil
                    } catch {
                        openAtLogin = !enabled
                        loginError = error.localizedDescription
                    }
                }
            if let loginError {
                Text(loginError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
