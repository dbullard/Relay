import SwiftUI

struct UsageDiagnosticsConsentSheet: View {
    @EnvironmentObject private var relayAccountCoordinator: RelayAccountCoordinator
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    private let preferences = UsageDiagnosticsPreferences.shared
    @State private var diagnosticsEnabled = false
    @State private var showingEmailEntry = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Help Improve Relay")
                .font(.title2.bold())

            Text("Choose whether to share crash and usage diagnostics. You can change this anytime in Settings > Access.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle("Share Crash and Usage Diagnostics", isOn: $diagnosticsEnabled)

            Text("Relay shares app version, platform, a random installation ID, active time, and technical crash details. It does not include dashboard content, connected-device data, location, audio, account email, or Relay network addresses.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !relayAccountCoordinator.isSignedIn {
                Divider()

                Text("Use Relay on another device")
                    .font(.headline)

                Text("Connecting an email is optional and does not enable diagnostics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Connect Email", action: connectEmail)
                    .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Not Now") {
                    preferences.markPromptSeenWithoutEnabling()
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Continue") {
                    preferences.recordPromptChoice(enabled: diagnosticsEnabled)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 340)
        .interactiveDismissDisabled()
        .sheet(isPresented: $showingEmailEntry) {
            AppStoreSubscriptionLinkSheet(presentation: .accountEmailEntry)
                .environmentObject(relayAccountCoordinator)
                .environmentObject(subscriptionManager)
        }
    }

    private func connectEmail() {
        if subscriptionManager.pendingAppStoreSubscriptionLink != nil {
            dismiss()
            DispatchQueue.main.async {
                subscriptionManager.presentAppStoreAccountLinkSheet()
            }
        } else {
            showingEmailEntry = true
        }
    }
}
