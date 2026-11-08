import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Where people enter the IDs and keys for services Relay can't ship credentials for.
/// Values are stored locally (client IDs in UserDefaults, the YouTube secret in the Keychain)
/// and take effect immediately; no rebuild is needed.
struct DashboardIntegrationsSettingsView: View {
    private static let docsURL = URL(string: "https://github.com/dbullard/Relay/blob/main/docs/INTEGRATIONS.md")!
    private static let pcoDeveloperURL = URL(string: "https://api.planningcenteronline.com/oauth/applications")!
    private static let googleConsoleURL = URL(string: "https://console.cloud.google.com/apis/credentials")!

    @State private var pcoClientID = ""
    @State private var youTubeClientID = ""
    @State private var youTubeClientSecret = ""
    @State private var youTubeRedirectURI = ""
    @State private var savedMessage: String?

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
                        statusRow(isSet: !pcoClientID.trimmingCharacters(in: .whitespaces).isEmpty)

                        TextField("Client ID (Application ID)", text: $pcoClientID)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()

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

                if RelayBuildConfig.isDebugBuild {
                    GroupBox("YouTube Live (debug builds)") {
                        VStack(alignment: .leading, spacing: 10) {
                            statusRow(isSet: !youTubeClientID.trimmingCharacters(in: .whitespaces).isEmpty)

                            TextField("Google OAuth client ID", text: $youTubeClientID)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                            SecureField("Client secret (only if your client has one)", text: $youTubeClientSecret)
                                .textFieldStyle(.roundedBorder)
                            TextField("Redirect URI (leave blank for the default)", text: $youTubeRedirectURI)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()

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
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    if let savedMessage {
                        Label(savedMessage, systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                    }
                    Spacer()
                }

                Text("Clearing a field and saving removes it. If you build Relay yourself, values in Config/Local.xcconfig are used when a field here is empty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: load)
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
    }

    private func save() {
        ServiceCredentials.set(pcoClientID, forKey: ServiceCredentials.Key.pcoClientID)
        if RelayBuildConfig.isDebugBuild {
            ServiceCredentials.set(youTubeClientID, forKey: ServiceCredentials.Key.youTubeClientID)
            ServiceCredentials.set(youTubeRedirectURI, forKey: ServiceCredentials.Key.youTubeRedirectURI)
            ServiceCredentials.setYouTubeClientSecret(youTubeClientSecret)
        }
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
