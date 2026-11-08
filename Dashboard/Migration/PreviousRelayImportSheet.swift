import SwiftUI

/// Asks whether to import settings from the earlier closed-source Relay.
struct PreviousRelayImportSheet: View {
    let summary: PreviousRelayImporter.Summary
    let isFirstLaunchOffer: Bool
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import from your previous Relay?")
                .font(.title2.bold())

            Text("Relay 2.0 is a new app, so your earlier Relay's settings weren't carried over automatically. Relay can copy them from the old app now. Your old app and its data are not changed.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Label(importedLine, systemImage: "arrow.down.doc")
                Label("Not imported: Planning Center, YouTube and other sign-ins. Reconnect them in Settings.", systemImage: "person.badge.key")
                Label("Dashboards are separate files. Open your saved .relay files from the Home screen.", systemImage: "doc.on.doc")
                if !isFirstLaunchOffer {
                    Label("Matching settings in this app will be replaced.", systemImage: "exclamationmark.triangle")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text("Relay restarts to finish the import. Save any open dashboard first.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack {
                Button(isFirstLaunchOffer ? "Don't Import" : "Cancel") {
                    if isFirstLaunchOffer { PreviousRelayImporter.declineOffer() }
                    onFinish()
                }
                Spacer()
                Button("Import and Restart") {
                    PreviousRelayImporter.requestImportAndRelaunch()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 320)
    }

    private var importedLine: String {
        var parts = ["\(summary.settingCount) settings"]
        if let devices = summary.deviceCount, devices > 0 {
            parts.append("\(devices) external device\(devices == 1 ? "" : "s")")
        }
        return "Will import: " + parts.joined(separator: ", ") + ", plus audio, shared values, MIDI/OSC and tile preferences."
    }
}
