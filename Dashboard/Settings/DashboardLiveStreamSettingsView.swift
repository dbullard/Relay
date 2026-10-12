import SwiftUI

struct DashboardLiveStreamSettingsView: View {
    @AppStorage("dashboard_youtube_connected") private var isConnected: Bool = false
    @AppStorage("dashboard_youtube_account_name") private var accountName: String = ""

    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var isShowingHelp = false

    private let tokenStore = YouTubeKeychainTokenStore()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 8) {
                        Text("Live Stream Settings")
                            .font(.title2.bold())
                        Button {
                            isShowingHelp = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .buttonStyle(.plain)
                        .help("How to connect YouTube")
                        .popover(isPresented: $isShowingHelp) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Connect YouTube")
                                    .font(.headline)
                                Text("Sign in through the browser and approve access. Relay stores the token locally.")
                                    .font(.callout)
                                VStack(alignment: .leading, spacing: 6) {
                                    Label("Click “Connect YouTube…”", systemImage: "1.circle")
                                    Label("Complete the browser sign-in and approval.", systemImage: "2.circle")
                                    Label("Return to Relay; status should show connected.", systemImage: "3.circle")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: 320)
                        }
                        Spacer()
                    }

                    if !LiveStreamFeatureFlags.isEnabled {
                        Text("Live stream integrations are only available in Relay beta and debug builds right now.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let configurationError {
                        Text(configurationError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(isActuallyConnected ? Color.green : Color.red)
                                .frame(width: 10, height: 10)

                            if isActuallyConnected, !accountName.isEmpty {
                                Text("Connected as \(accountName)")
                                    .foregroundStyle(.primary)
                            } else if isActuallyConnected {
                                Text("Connected to YouTube")
                                    .foregroundStyle(.primary)
                            } else {
                                Text("Not connected")
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }

                        if isActuallyConnected {
                            Button(role: .destructive) {
                                disconnect()
                            } label: {
                                Label("Disconnect YouTube", systemImage: "x.circle.fill")
                            }
                            .padding(.bottom, 8)
                        } else {
                            Button {
                                connect()
                            } label: {
                                if isBusy {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .scaleEffect(0.8)
                                } else {
                                    Label("Connect YouTube…", systemImage: "link.badge.plus")
                                }
                            }
                            .disabled(isBusy)
                            .padding(.bottom, 8)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Text("Use this connection for the YouTube Stream Monitor module. Relay opens Google sign-in in a browser sheet, then securely stores the token for live status, viewer counts, and health checks.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 72)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
#if os(iOS)
            .scrollDismissesKeyboard(.immediately)
#endif
        }
#if os(iOS)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                if isActuallyConnected {
                    Button(role: .destructive) {
                        disconnect()
                    } label: {
                        Label("Disconnect", systemImage: "x.circle.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        connect()
                    } label: {
                        if isBusy {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        } else {
                            Label("Connect…", systemImage: "link.badge.plus")
                        }
                    }
                    .disabled(isBusy || !LiveStreamFeatureFlags.isEnabled || configurationError != nil)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
#endif
        .padding(24)
#if os(macOS)
        .frame(
            minWidth: 480,
            idealWidth: 520,
            maxWidth: 640,
            minHeight: 220,
            idealHeight: 280,
            maxHeight: 360
        )
#else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
#endif
        .task {
            await refreshConnectionState()
        }
    }

    private var isActuallyConnected: Bool {
        tokenStore.loadTokens() != nil
    }

    private var configurationError: String? {
        do {
            _ = try YouTubeOAuthConfiguration.load()
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func connect() {
        guard LiveStreamFeatureFlags.isEnabled else { return }
        guard configurationError == nil else { return }

        isBusy = true
        errorMessage = nil

        Task {
            do {
                let service = YouTubeOAuthService(
                    configuration: try YouTubeOAuthConfiguration.load(),
                    tokenStore: tokenStore
                )
                try await service.startLogin()
                await refreshConnectionState()
                await MainActor.run {
                    isBusy = false
                    isConnected = isActuallyConnected
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    isConnected = false
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func disconnect() {
        tokenStore.clear()
        isConnected = false
        accountName = ""
        errorMessage = nil
    }

    private func refreshConnectionState() async {
        await MainActor.run {
            isConnected = isActuallyConnected
        }

        guard LiveStreamFeatureFlags.isEnabled, isActuallyConnected else {
            await MainActor.run {
                accountName = ""
            }
            return
        }

        do {
            let client = try makeClient()
            let channel = try await client.fetchCurrentChannel()
            await MainActor.run {
                accountName = channel?.title ?? ""
                isConnected = isActuallyConnected
            }
        } catch {
            await MainActor.run {
                accountName = ""
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func makeClient() throws -> YouTubeAPIClient {
        let configuration = try YouTubeOAuthConfiguration.load()
        let service = YouTubeOAuthService(configuration: configuration, tokenStore: tokenStore)
        return YouTubeAPIClient(oauthService: service, tokenStore: tokenStore)
    }
}
