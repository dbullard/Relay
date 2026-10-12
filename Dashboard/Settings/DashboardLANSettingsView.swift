//
//  DashboardLANSettingsView.swift
//  Relay
//
//  Sync & Mirror settings: device pairing, LAN broadcast (Mirror), and
//  editable cross-device tabs (Sync) share one page now that pairing is
//  trust infrastructure underneath both, rather than something either
//  feature owns on its own.
//

import SwiftUI

#if os(iOS)
import UIKit
#endif

#if os(macOS)
import AppKit
#endif

struct DashboardLANSettingsView: View {

    @EnvironmentObject private var lanService: LANSharedTabsService
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.proUpgradeAction) private var proUpgradeAction
    @Environment(\.joinSyncedTabAction) private var joinSyncedTabAction
    @Environment(\.leaveSyncedTabAction) private var leaveSyncedTabAction
    @Environment(\.openURL) private var openURL

    @AppStorage("lan_sharing_enabled")
    private var sharingEnabled: Bool = true

    @AppStorage("lan_browser_view_only_enabled")
    private var browserViewOnlyEnabled: Bool = false

    @AppStorage("lan_browser_listen_port")
    private var browserListenPort: Int = 38475

    @AppStorage("lan_allow_unpaired_read")
    private var allowUnpairedRead: Bool = false

    @AppStorage("lan_allow_legacy_unsigned")
    private var allowLegacyUnsigned: Bool = true

    @AppStorage("lan_pairing_code")
    private var legacyPairingCode: String = ""

    @State private var isShowingHelp = false
    @State private var copiedToast: String? = nil

    private var browserListenPortText: Binding<String> {
        Binding(
            get: { String(browserListenPort) },
            set: { newValue in
                let digitsOnly = newValue.filter(\.isNumber)
                guard !digitsOnly.isEmpty else { return }
                browserListenPort = min(max(Int(digitsOnly) ?? 38475, 1024), 65_535)
            }
        )
    }

    var body: some View {
        let isPro = subscriptionManager.hasPro
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Text("Sync & Mirror")
                        .font(.title2.bold())
                    Button {
                        isShowingHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .buttonStyle(.plain)
                    .help("How Sync and Mirror differ")
                    .popover(isPresented: $isShowingHelp) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Sync & Mirror")
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Mirror broadcasts a live, read-only view of a tab. Sync shares an editable canvas everyone can rearrange. Both use the same device pairing below.")
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(width: 340)
                    }
                }

                Text("Mirror broadcasts a live, read-only view. Sync shares an editable canvas. Approve devices below to let them import mirrors or join synced tabs.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox("Browser View-Only Link") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $browserViewOnlyEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable browser view-only link")
                                Text("Creates a stable browser link for this device without advertising to Relay peers or allowing imports.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            if browserViewOnlyEnabled {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Browser port")
                                            .font(.callout.weight(.semibold))
                                        Text("Relay keeps using this port so the browser URL stays stable.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Spacer()

                                    TextField("Port", text: browserListenPortText)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 110)
#if os(iOS)
                                        .keyboardType(.numberPad)
#endif

                                    Button("Reset") {
                                        browserListenPort = 38475
                                    }
                                    .buttonStyle(.bordered)
                                }

                                Divider().padding(.vertical, 2)
                            }

                            if browserViewOnlyEnabled, let baseURL = lanService.browserBaseURL() {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Viewer link")
                                        .font(.callout.weight(.semibold))
                                    Text(baseURL.absoluteString)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    HStack(spacing: 10) {
                                        Button("Open") {
                                            openURL(baseURL)
                                        }
                                        .buttonStyle(.bordered)

                                        Button("Copy Link") {
                                            copyToPasteboard(baseURL.absoluteString)
                                            copiedToast = "Copied browser viewer link."
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                                if copiedToast == "Copied browser viewer link." {
                                                    copiedToast = nil
                                                }
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    Text("This URL always shows the tab currently open on the source Relay device.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } else {
                                Text(browserViewOnlyEnabled ? "Waiting for a local LAN address and server port…" : "Turn on browser view-only to generate a link you can paste into Safari or Chrome.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                    }
                    .onChange(of: browserListenPort, initial: true) { _, newValue in
                        browserListenPort = min(max(newValue, 1024), 65_535)
                    }
                    .padding(.top, 2)
                }

                GroupBox("Devices") {
                    VStack(alignment: .leading, spacing: 10) {
                        if isPro {
                            Toggle(isOn: $sharingEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Enable LAN sharing")
                                    Text("Makes this device visible to other Relay clients for Sync and Mirror.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Toggle(isOn: $allowUnpairedRead) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Allow view-only without pairing")
                                    Text("Relay mirrors can open shared tabs without approval, but importing or joining a Synced Tab still requires pairing.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .disabled(!sharingEnabled)

                            Toggle(isOn: $allowLegacyUnsigned) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Allow computers that haven't been re-paired")
                                    Text("Computers paired by older versions of Relay can't prove who they are. Turn this off once every computer has been re-paired.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .disabled(!sharingEnabled)

                            VStack(alignment: .leading, spacing: 5) {
                                SecureField("Legacy pairing code", text: $legacyPairingCode)
                                    .textFieldStyle(.roundedBorder)
                                Text("Set the same code on older Relay computers to keep them connected. Newer versions use device approval.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Divider().padding(.vertical, 4)

                            HStack {
                                Text("Devices on this network")
                                    .font(.callout.weight(.semibold))
                                Spacer()
                                if !lanService.peers.isEmpty {
                                    Text("\(lanService.peers.count)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if lanService.peers.isEmpty {
                                Text("No devices discovered yet.")
                                    .font(.callout)
                                Text("Make sure both Relay devices are on the same network and that Local Network access is allowed.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(lanService.peers.sorted(by: { $0.lastSeen > $1.lastSeen })) { peer in
                                    DevicesTableRow(peer: peer, lanService: lanService)
                                }
                            }
                        } else {
                            Text("Upgrade to Pro to use Relay-to-Relay LAN discovery, Mirror, and Synced Tabs.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button("Upgrade to Pro") {
                                proUpgradeAction()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.top, 2)
                }

                if let copiedToast {
                    Text(copiedToast)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(24)
            .toggleStyle(.switch)
        }
        .alert("Could Not Connect", isPresented: Binding(
            get: { lanService.lastPairingFailureMessage != nil },
            set: { if !$0 { lanService.clearPairingFailure() } }
        )) {
            Button("OK", role: .cancel) { lanService.clearPairingFailure() }
        } message: {
            Text(lanService.lastPairingFailureMessage ?? "Try connecting again.")
        }
    }

    private func copyToPasteboard(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}

/// One row of the Devices table: identity, pairing status, per-feature tab
/// counts, and the enable/disable switch (approves/pre-blocks an unpaired
/// device, or revokes/restores trust for a paired one).
private struct DevicesTableRow: View {
    let peer: LANSharedTabsService.Peer
    @ObservedObject var lanService: LANSharedTabsService

    @State private var isConnecting = false
    @State private var showingConnectedNotice = false

    private var status: DevicePairingStatus {
        DevicePairingStore.status(for: peer.deviceId, in: lanService.pairedDevices)
    }

    private var mirroredTabCount: Int {
        lanService.remoteTabs.filter { $0.deviceId == peer.deviceId }.count
    }

    // Only counts tabs actually joined from this device — syncedRemoteManifests holds
    // discoverable-but-not-yet-joined tabs, which aren't "synced" yet and would also
    // double-count an orphaned-then-rediscovered group that reappears there while still
    // sitting in joinedSyncedManifests.
    private var syncedTabCount: Int {
        lanService.joinedSyncedManifests.filter { $0.deviceID == peer.deviceId }.count
    }

    // A synced tab can be joined but no longer actually authorized (e.g. this device's
    // trust with the host was revoked after joining) — every request to the host then
    // silently fails with 401. Surface that here since nothing else in the app does
    // after the old per-tab "Pairing code mismatch" warning was removed along with the
    // settings page it lived on.
    private var hasAuthFailedSyncedTab: Bool {
        lanService.joinedSyncedManifests
            .filter { $0.deviceID == peer.deviceId }
            .contains { lanService.isSyncGroupAuthFailed($0.groupID) }
    }

    // Also covers a paired computer that rejects us without any joined tab involved — e.g. an
    // older Relay build that started pairing and saved this device under its name.
    private var needsReconnect: Bool {
        hasAuthFailedSyncedTab || lanService.peerNeedsReconnect(peer)
    }

    private var statusText: String {
        switch status {
        case .notPaired: return "Not Paired"
        case .paired: return "Paired"
        case .blocked: return "Blocked"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: LANDeviceKind.iconName(for: peer.deviceKind, fallbackDeviceName: peer.deviceName ?? ""))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.deviceName ?? "Device")
                HStack(spacing: 6) {
                    Text(statusText)
                    if mirroredTabCount > 0 {
                        Text("· \(mirroredTabCount) mirrored")
                    }
                    if syncedTabCount > 0 {
                        Text("· \(syncedTabCount) synced")
                    }
                    if needsReconnect {
                        Label("Not authorized", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    if status == .paired, !lanService.hasPairingSecret(for: peer.deviceId) {
                        Text("Not secured — re-pair to fix")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if status == .paired {
                    Toggle("Share variables across devices", isOn: Binding(
                        get: { lanService.pairedDevices[peer.deviceId]?.sharesVariables == true },
                        set: { lanService.setVariableSharing($0, for: peer) }
                    ))
                    .font(.caption)
                    .controlSize(.small)
                    .help("Share this computer's variables with this linked device and show its variables here. Synced tabs work independently.")
                }
            }
            Spacer()
            Text(peer.lastSeen.formatted(date: .numeric, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
            // A Not Paired device gets an explicit Connect button rather than the old bare
            // toggle, which looked like a way to "enable" a connection but only ever granted
            // one-sided local trust on whichever device's Settings you used it from — no
            // request was ever sent to the peer. Connect triggers the real live handshake
            // (same approval sheet on the host, same waiting overlay here) that Join/Import
            // already used; a device only gets the disable/forget controls once that
            // handshake has actually succeeded.
            if status == .notPaired {
                Button {
                    isConnecting = true
                    Task {
                        let connected = await lanService.connectToDevice(peer)
                        isConnecting = false
                        showingConnectedNotice = connected
                    }
                } label: {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isConnecting)
            } else {
                // A synced tab's group-level authorization can be revoked on the host
                // after joining even though this device's own pairing still looks fine
                // locally (see hasAuthFailedSyncedTab above). connectToDevice would
                // short-circuit on that already-.paired local state without ever
                // contacting the host, so use reconnectDevice, which always performs a
                // fresh handshake, instead of making the user forget-and-rejoin the
                // whole device over one broken sync group.
                if needsReconnect {
                    Button {
                        isConnecting = true
                        Task {
                            _ = await lanService.reconnectDevice(peer)
                            isConnecting = false
                        }
                    } label: {
                        if isConnecting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Reconnect")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isConnecting)
                }

                Toggle(
                    "",
                    isOn: Binding(
                        get: { status == .paired },
                        set: { newValue in
                            lanService.setDeviceEnabled(newValue, for: peer)
                        }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()

                Menu {
                    Button(role: .destructive) {
                        lanService.forgetDevice(peer)
                    } label: {
                        Label("Forget This Device", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
                .help("Disconnect and forget this device")
            }
        }
        .opacity(status == .blocked ? 0.6 : 1.0)
        .alert("Computer Connected", isPresented: $showingConnectedNotice) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Pairing is ready. To share an editable tab, choose Join next to that tab in Synced Tabs.")
        }
    }
}
