import SwiftUI

struct SettingsView: View {
    let store: Store
    @State private var grokCookie = Grok.pastedCookie()
    @AppStorage("refreshMinutes") private var refreshMinutes = 5

    var body: some View {
        Form {
            LoginToggle()
            Stepper("Refresh every \(refreshMinutes) min", value: $refreshMinutes, in: 1...60)
                .onChange(of: refreshMinutes) { _, minutes in store.startTimer(interval: TimeInterval(minutes * 60)) }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SecureField("grok.com sso cookie", text: $grokCookie)
                        .onSubmit(saveCookie)
                    Button("Save", action: saveCookie)
                }
                Text("The `sso` cookie from grok.com. When saved, limitbar uses it and never reads your browser's cookies.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }

    private func saveCookie() {
        Credentials.setKeychainString(service: Grok.cookieService, grokCookie.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
