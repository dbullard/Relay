import SwiftUI

struct UsageDiagnosticsConsentSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let preferences = UsageDiagnosticsPreferences.shared
    @State private var diagnosticsEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Help Improve Relay")
                .font(.title2.bold())

            Text("Choose whether to share crash and usage diagnostics. You can change this anytime in Settings > Access.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle("Share Crash and Usage Diagnostics", isOn: $diagnosticsEnabled)

            Text("Relay shares app version, platform, a random installation ID, active time, and technical crash details. It does not include dashboard content, connected-device data, location, audio, or Relay network addresses. Nothing is sent unless a crash-reporting project has been configured for this build.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
        .frame(minWidth: 420, minHeight: 260)
        .interactiveDismissDisabled()
    }
}
