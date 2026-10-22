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
                SecureField("grok.com sso cookie", text: $grokCookie)
                    .onChange(of: grokCookie) { _, value in Credentials.setKeychainString(service: Grok.cookieService, value) }
                Text("The `sso` cookie from grok.com. Used only if limitbar can't read it from your browser.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
