//
//  DashboardPCOSettingsView.swift
//  Relay
//
//  Created by David Bullard on 11/16/25.
//

import SwiftUI

struct DashboardPCOSettingsView: View {
    // These keys can be whatever you want; keep them stable.
    @AppStorage("dashboard_pco_connected") private var isConnected: Bool = false
    @AppStorage("dashboard_pco_account_name") private var accountName: String = ""

    @Environment(\.dismiss) private var dismiss

    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var isShowingHelp: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    HStack(spacing: 8) {
                        Text("Planning Center Settings")
                            .font(.title2.bold())
                        Button {
                            isShowingHelp = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .buttonStyle(.plain)
                        .help("How to connect Planning Center")
                        .popover(isPresented: $isShowingHelp) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Connect Planning Center")
                                    .font(.headline)
                                Text("Sign in through the browser and approve access. Relay stores the token locally.")
                                    .font(.callout)
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(DashboardPlatformCopy.planningCenterConnectHelpStep, systemImage: "1.circle")
                                    Label("Complete the browser sign‑in and approval.", systemImage: "2.circle")
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

                    // Connection status row
                    HStack(spacing: 10) {
                        Circle()
                            .fill(isConnected ? Color.green : Color.red)
                            .frame(width: 10, height: 10)

                        if isConnected, !accountName.isEmpty {
                            Text("Connected as \(accountName)")
                                .foregroundStyle(.primary)
                        } else if isConnected {
                            Text("Connected to Planning Center")
                                .foregroundStyle(.primary)
                        } else {
                            Text("Not connected")
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    // Action button
                    if isConnected {
                        Button(role: .destructive) {
                            disconnectFromPCO()
                        } label: {
                            Label("Disconnect from Planning Center", systemImage: "x.circle.fill")
                        }
                        .padding(.bottom, 8)
#if os(iOS)
                        Text("Tip: the primary action is also available in the bottom bar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
#endif
                    } else {
                        Button {
                            connectToPCO()
                        } label: {
                            if isBusy {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8)
                            } else {
                                Label("Connect to Planning Center…", systemImage: "link.badge.plus")
                            }
                        }
                        .disabled(isBusy)
                        .padding(.bottom, 8)
#if os(iOS)
                        Text("Tip: the primary action is also available in the bottom bar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
#endif
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    // Help text
                    Text(DashboardPlatformCopy.planningCenterOAuthHelpText)
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
                if isConnected {
                    Button(role: .destructive) {
                        disconnectFromPCO()
                    } label: {
                        Label("Disconnect", systemImage: "x.circle.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        connectToPCO()
                    } label: {
                        if isBusy {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        } else {
                            Label("Connect…", systemImage: "link.badge.plus")
                        }
                    }
                    .disabled(isBusy)
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
            idealHeight: 260,
            maxHeight: 320
        )
#else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
#endif
    }

    // MARK: - Actions

    /// Kick off the OAuth flow using the shared OAuthService / TokenStore.
    /// This assumes the existing OAuthService, TokenStore, and PCOClient
    /// files are added to the Relay Dashboard target.
    private func connectToPCO() {
        // Replace this with your actual client id from the PCO Developer portal.
        let clientID = "740fe16ab8a3025b6920a7290b5f244f4416d5bfb0ea88826521dc10101e8d9d"

        isBusy = true
        errorMessage = nil
        print("[PCO] Connect requested")

        Task {
            let tokenStore = KeychainTokenStore()
            let oauth = OAuthService(clientID: clientID, tokenStore: tokenStore)

            do {
                // This uses the default parameters (scope, redirect, etc.)
                try await oauth.startLogin()

                await MainActor.run {
                    isBusy = false

                    if let tokens = tokenStore.loadTokens(), !tokens.accessToken.isEmpty {
                        isConnected = true
                        print("[PCO] Connected (tokens present)")

                        // Fetch user name from PCO
                        Task {
                            if let name = await loadAccountName() {
                                await MainActor.run { accountName = name }
                            }
                        }
                    } else {
                        isConnected = false
                        errorMessage = "Could not find saved tokens after login."
                        RelayDiagnosticsStore.shared.recordError(errorMessage ?? "PCO token missing", tag: "PCO")
                    }
                }
            } catch OAuthService.OAuthError.cancelled {
                await MainActor.run {
                    isBusy = false
                    isConnected = false
                    errorMessage = nil
                }
                print("[PCO] Connect canceled by user")
            } catch {
                await MainActor.run {
                    isBusy = false
                    isConnected = false
                    errorMessage = error.localizedDescription
                }
                RelayDiagnosticsStore.shared.recordError(error.localizedDescription, tag: "PCO")
            }
        }
    }

    private func disconnectFromPCO() {
        let tokenStore = KeychainTokenStore()
        tokenStore.clear()

        isConnected = false
        accountName = ""
        errorMessage = nil
        print("[PCO] Disconnected")
    }

    private func loadAccountName() async -> String? {
        let tokenStore = KeychainTokenStore()
        let clientID = "740fe16ab8a3025b6920a7290b5f244f4416d5bfb0ea88826521dc10101e8d9d"
        let oauth = OAuthService(clientID: clientID, tokenStore: tokenStore)
        let client = PCOClient(oauthService: oauth, tokenStore: tokenStore)

        do {
            let me = try await client.fetchCurrentUser()
            if let name = me.name {
                return name
            }
        } catch {
            print("Failed to load account name: \(error.localizedDescription)")
        }

        return nil
    }
}
