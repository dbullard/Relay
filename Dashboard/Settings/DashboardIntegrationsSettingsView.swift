import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Where people enter the IDs and keys for services Relay can't ship credentials for.
/// Values are stored locally (client IDs in UserDefaults, the YouTube secret in the Keychain)
/// and take effect immediately; no rebuild is needed.
///
/// Like the other settings pages, edits apply as you go: a field is saved when you press
/// Return, move focus out of it, or leave the page. Only fields whose value changed are
/// written, so the Keychain is touched only when the secret actually changes.
struct DashboardIntegrationsSettingsView: View {
    private enum Field: Hashable {
        case pcoClientID, youTubeClientID, youTubeClientSecret, youTubeRedirectURI
    }

    /// The values last written to storage. Status rows read these, so "Configured"
    /// reflects what's saved rather than what's being typed.
    private struct SavedValues: Equatable {
        var pcoClientID = ""
        var youTubeClientID = ""
        var youTubeClientSecret = ""
        var youTubeRedirectURI = ""
    }

    private static let docsURL = URL(string: "https://github.com/dbullard/Relay/blob/main/docs/INTEGRATIONS.md")!
    private static let pcoDeveloperURL = URL(string: "https://api.planningcenteronline.com/oauth/applications")!
    private static let googleConsoleURL = URL(string: "https://console.cloud.google.com/apis/credentials")!

    @State private var pcoClientID = ""
    @State private var youTubeClientID = ""
    @State private var youTubeClientSecret = ""
    @State private var youTubeRedirectURI = ""
    @State private var saved = SavedValues()
    @State private var hasLoaded = false
    @State private var savedMessage: String?
    @FocusState private var focusedField: Field?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Integrations")
                    .font(.title2.bold())

                Text("Some services need your own app registration because Relay can't include shared keys. Enter your IDs here. They stay on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                GroupBox("Planning Center") {
                    VStack(alignment: .leading, spacing: 10) {
                        statusRow(isSet: !saved.pcoClientID.isEmpty)

                        TextField("Client ID (Application ID)", text: $pcoClientID)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .pcoClientID)
                            .onSubmit(commitChanges)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Redirect URI to register on your Planning Center app")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text(PCOOAuthConfiguration.redirectURI)
                                    .font(.system(.callout, design: .monospaced))
                                    .textSelection(.enabled)
                                Button("Copy") { copy(PCOOAuthConfiguration.redirectURI) }
                                    .buttonStyle(.borderless)
                            }
                        }

                        HStack(spacing: 12) {
                            Link("Open Planning Center applications", destination: Self.pcoDeveloperURL)
                            Link("Setup guide", destination: Self.docsURL)
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .padding(.vertical, 6)
                }

                if RelayBuildConfig.isPreviewEnabled {
                    GroupBox("YouTube Live (preview)") {
                        VStack(alignment: .leading, spacing: 10) {
                            statusRow(isSet: !saved.youTubeClientID.isEmpty)

                            TextField("Google OAuth client ID", text: $youTubeClientID)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .youTubeClientID)
                                .onSubmit(commitChanges)
                            SecureField("Client secret (only if your client has one)", text: $youTubeClientSecret)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .youTubeClientSecret)
                                .onSubmit(commitChanges)
                            TextField("Redirect URI (leave blank for the default)", text: $youTubeRedirectURI)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .youTubeRedirectURI)
                                .onSubmit(commitChanges)

                            HStack(spacing: 12) {
                                Link("Open Google Cloud credentials", destination: Self.googleConsoleURL)
                                Link("Setup guide", destination: Self.docsURL)
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .padding(.vertical, 6)
                    }
                }

                HStack {
                    if let savedMessage {
                        Label(savedMessage, systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                    } else {
                        Text("Changes save when you press Return or leave a field.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Text("Clearing a field removes the saved value. If you build Relay yourself, values in Config/Local.xcconfig are used when a field here is empty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: load)
        .onChange(of: focusedField) { oldValue, _ in
            if oldValue != nil { commitChanges() }
        }
        .onDisappear(perform: commitChanges)
    }

    private func statusRow(isSet: Bool) -> some View {
        Label(isSet ? "Configured" : "Not configured",
              systemImage: isSet ? "checkmark.circle.fill" : "exclamationmark.circle")
            .font(.callout)
            .foregroundStyle(isSet ? Color.green : Color.secondary)
    }

    private func load() {
        pcoClientID = PCOOAuthConfiguration.clientID
        youTubeClientID = ServiceCredentials.resolved(
            defaultsKey: ServiceCredentials.Key.youTubeClientID, plistKeys: [])
        youTubeRedirectURI = ServiceCredentials.resolved(
            defaultsKey: ServiceCredentials.Key.youTubeRedirectURI, plistKeys: [])
        youTubeClientSecret = ServiceCredentials.youTubeClientSecret() ?? ""
        saved = currentValues
        hasLoaded = true
    }

    private var currentValues: SavedValues {
        SavedValues(
            pcoClientID: pcoClientID.trimmingCharacters(in: .whitespacesAndNewlines),
            youTubeClientID: youTubeClientID.trimmingCharacters(in: .whitespacesAndNewlines),
            youTubeClientSecret: youTubeClientSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            youTubeRedirectURI: youTubeRedirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Writes only the fields that differ from what's stored.
    private func commitChanges() {
        guard hasLoaded else { return }
        let current = currentValues
        guard current != saved else { return }
        if current.pcoClientID != saved.pcoClientID {
            ServiceCredentials.set(current.pcoClientID, forKey: ServiceCredentials.Key.pcoClientID)
        }
        if RelayBuildConfig.isPreviewEnabled {
            if current.youTubeClientID != saved.youTubeClientID {
                ServiceCredentials.set(current.youTubeClientID, forKey: ServiceCredentials.Key.youTubeClientID)
            }
            if current.youTubeRedirectURI != saved.youTubeRedirectURI {
                ServiceCredentials.set(current.youTubeRedirectURI, forKey: ServiceCredentials.Key.youTubeRedirectURI)
            }
            if current.youTubeClientSecret != saved.youTubeClientSecret {
                ServiceCredentials.setYouTubeClientSecret(current.youTubeClientSecret)
            }
        }
        saved = current
        savedMessage = "Saved"
    }

    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
