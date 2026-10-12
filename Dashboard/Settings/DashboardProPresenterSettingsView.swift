//
//  DashboardProPresenterSettingsView.swift
//  Relay
//
//  Created by David Bullard on 12/16/25.
//

import SwiftUI
import Network
import Combine
import Foundation
#if os(macOS)
import AppKit
#endif

/// ProPresenter connection settings page (moved out of DashboardSettingsView.swift).
struct DashboardProPresenterSettingsView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.proUpgradeAction) private var proUpgradeAction
    @AppStorage("propresenter_host") private var host: String = ""
    @AppStorage("propresenter_port") private var port: Int = 1025

    /// Transport mode for ProPresenter connectivity.
    /// - auto: detect based on response
    /// - http: direct REST calls
    /// - tcpip: ProPresenter TCP/IP JSON bridge (newline-delimited requests)
    @AppStorage("propresenter_transport") private var transportRaw: String = ProPresenterTransport.auto.rawValue

    /// Optional password/token (if your ProPresenter configuration requires it).
    @State private var password: String = ProPresenterKeychainStore.shared.password

    /// Poll interval (seconds) for status updates when not using a streaming mode.
    @AppStorage("propresenter_pollInterval") private var pollInterval: Double = 0.5

    // Multiple connection profiles
    @AppStorage("propresenter_profiles") private var profilesData: Data = Data()

    @State private var isPresentingSaveProfileSheet: Bool = false
    @State private var profileNameDraft: String = ""
    @State private var editingProfile: ProPresenterConnectionProfile? = nil
    @State private var quickAddDevice: ProPresenterDiscoveredDevice? = nil
    @State private var isShowingHelp: Bool = false
    @State private var lastTestOK: [UUID: Bool] = [:]
    @State private var lastTestLatencyMs: [UUID: Int] = [:]
    @State private var lastTestMessage: [UUID: String] = [:]
    @State private var isTesting: Set<UUID> = []
    @StateObject private var discoveryService = ProPresenterDiscoveryService()
    private let isDiscoveryEnabled = true

    private var profilesList: [ProPresenterConnectionProfile] {
        guard !profilesData.isEmpty else { return [] }



        return (try? JSONDecoder().decode([ProPresenterConnectionProfile].self, from: profilesData)) ?? []
    }

    private var savedConnectionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Saved Connections")
                        .font(.headline)
                    Spacer()
                    Button {
                        profileNameDraft = ""
                        isPresentingSaveProfileSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("Add Profile")
                        }
                    }
                    .buttonStyle(.bordered)
                }

                if profilesList.isEmpty {
                    Text("No saved connections yet. Use Discovered ProPresenter below or click Add Profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(profilesList) { profile in
                            let ok = lastTestOK[profile.id]
                            let latency = lastTestLatencyMs[profile.id]
                            let msg = lastTestMessage[profile.id]
                            let testing = isTesting.contains(profile.id)

                            HStack(spacing: 12) {
                                Circle()
                                    .fill(statusColor(ok: ok, testing: testing))
                                    .frame(width: 10, height: 10)
                                    .help(statusHelpText(ok: ok, testing: testing, msg: msg, latency: latency))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name)
                                        .font(.callout)

                                    Text("\(profile.host):\(profile.port)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    if let msg, !msg.isEmpty {
                                        Text(msg)
                                            .font(.caption2)
                                            .foregroundStyle(ok == false ? .red : .secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()
                                Button {
                                    applyProfile(profile)
                                } label: {
                                    Image(systemName: "checkmark.circle")
                                }
                                .buttonStyle(.borderless)

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                beginEditProfile(profile)
                            }
                            .contextMenu {
                                Button("Use") { applyProfile(profile) }
                                Button("Edit") { beginEditProfile(profile) }
                                Divider()
                                Button(role: .destructive) {
                                    // Delete just this profile
                                    if let idx = profilesList.firstIndex(where: { $0.id == profile.id }) {
                                        deleteProfiles(at: IndexSet(integer: idx))
                                    }
                                } label: {
                                    Text("Delete")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(minHeight: 140)
                }

                Text("Tap a connection to edit it. Use ✓ to set as the active connection.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var discoveredConnectionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Discovered ProPresenter")
                        .font(.headline)
                    Spacer()
                    Button {
                        discoveryService.startScan(password: password)
                    } label: {
                        HStack(spacing: 6) {
                            if discoveryService.isScanning {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                            Text(discoveryService.isScanning ? "Scanning…" : "Rescan")
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Text(discoveryService.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

#if os(macOS)
                if discoveryService.statusText.contains("Local Network permission") {
                    HStack(spacing: 10) {
                        Button("Open Local Network Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)

                        Text("Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if discoveryService.statusText.contains("missing Bonjour") {
                    Text("Bundle path: \(Bundle.main.bundlePath)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
#endif

                if discoveryService.results.isEmpty {
                    Text("No ProPresenter instances discovered yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(discoveryService.results) { device in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(discoveryStatusColor(for: device))
                                    .frame(width: 10, height: 10)
                                    .help(discoveryStatusHelpText(for: device))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.callout)
                                    Text("\(device.host):\(device.port)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if let note = device.detailNote, !note.isEmpty {
                                        Text(note)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                let alreadySaved = profilesList.contains {
                                    $0.host == device.host && $0.port == device.port
                                }
                                if alreadySaved {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                        .help("Already saved")
                                } else {
                                    Button {
                                        quickAddDevice = device
                                    } label: {
                                        Image(systemName: "plus.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Add as Profile")
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .frame(minHeight: 120)
                }

                Text("Tip: Relay scans via Bonjour. Ensure ProPresenter’s network/remote control is enabled.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // defaultsForModulesSection removed per UI request.

    private func storeProfiles(_ newValue: [ProPresenterConnectionProfile]) {
        profilesData = (try? JSONEncoder().encode(newValue)) ?? Data()
    }


    private func saveCurrentAsNewProfile(named name: String) -> ProPresenterConnectionProfile? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var list = profilesList
        let new = ProPresenterConnectionProfile(
            id: UUID(),
            name: trimmed,
            host: host,
            port: port,
            transportRaw: transportRaw,
            password: password
        )
        list.append(new)
        list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        storeProfiles(list)
        return new
    }

    private func applyProfile(_ profile: ProPresenterConnectionProfile) {
        host = profile.host
        port = profile.port
        // Transport is auto-detected per request; keep the global default in auto.
        transportRaw = ProPresenterTransport.auto.rawValue
        password = profile.password
    }

    private func deleteProfiles(at offsets: IndexSet) {
        var list = profilesList
        for idx in offsets {
            let id = list[idx].id
            lastTestOK[id] = nil
            lastTestLatencyMs[id] = nil
            lastTestMessage[id] = nil
            isTesting.remove(id)
        }
        list.remove(atOffsets: offsets)
        storeProfiles(list)
    }

    private func beginEditProfile(_ profile: ProPresenterConnectionProfile) {
        editingProfile = profile
    }

    private func commitEditProfile(_ updated: ProPresenterConnectionProfile) {
        var list = profilesList
        if let idx = list.firstIndex(where: { $0.id == updated.id }) {
            list[idx] = updated
            list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            storeProfiles(list)
        }
    }

    fileprivate static let portFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.allowsFloats = false
        f.minimum = 1
        f.maximum = 65535
        return f
    }()

    var body: some View {
        let isPro = subscriptionManager.hasPro
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("ProPresenter")
                    .font(.title2.bold())
                Button {
                    isShowingHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .help("How to connect ProPresenter")
                .popover(isPresented: $isShowingHelp) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Connect ProPresenter")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Make sure ProPresenter’s network/remote control is enabled, then enter the host and port.")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Enable ProPresenter’s network/remote control settings.", systemImage: "1.circle")
                            Label("Use the same host (IP) and port configured in ProPresenter.", systemImage: "2.circle")
                            Label("If a password is set, add it here.", systemImage: "3.circle")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(width: 380)
                }
            }

            Group {
                savedConnectionsSection
                if isDiscoveryEnabled {
                    discoveredConnectionsSection
                }

                // defaultsForModulesSection removed per UI request

                Spacer()
            }
            .disabled(!isPro)
            .opacity(isPro ? 1.0 : 0.35)
            .allowsHitTesting(isPro)
        }
        .padding(24)
        .overlay {
            if !isPro {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.7)
                        .ignoresSafeArea()
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .ignoresSafeArea()
#if os(iOS)
                    ProUpgradePromptViewIOS(
                        buttonTitle: "Upgrade to Pro",
                        secondaryButtonTitle: "Continue with Free",
                        secondaryAction: {},
                        showPlanSelector: true,
                        showManageLinks: true
                    ) { }
#else
                    ProUpgradePromptView(
                        buttonTitle: "Upgrade to Pro",
                        secondaryButtonTitle: "Continue with Free",
                        secondaryAction: {},
                        showPlanSelector: true,
                        showManageLinks: true
                    ) { }
#endif
                }
            }
        }
        .onAppear {
            if isDiscoveryEnabled {
                discoveryService.startScan(password: password)
            }
            Task { await testProfiles(profilesList) }
        }
        .onChange(of: profilesData, initial: false) { _, _ in
            Task { await testProfiles(profilesList) }
        }
        .onChange(of: password, initial: false) { _, newValue in
            ProPresenterKeychainStore.shared.password = newValue
            if isDiscoveryEnabled {
                discoveryService.updatePassword(newValue)
            }
        }
        .onDisappear {
            if isDiscoveryEnabled {
                discoveryService.stopScan()
            }
        }

        .sheet(isPresented: $isPresentingSaveProfileSheet) {
            ProPresenterSaveProfileSheet(
                name: $profileNameDraft,
                host: $host,
                port: $port,
                password: $password,
                pollInterval: $pollInterval,
                onCancel: { isPresentingSaveProfileSheet = false },
                onSave: {
                    let saved = saveCurrentAsNewProfile(named: profileNameDraft)
                    isPresentingSaveProfileSheet = false
                    if let profile = saved {
                        Task { await testProfile(profile) }
                    }
                }
            )
        }
        .sheet(item: $editingProfile) { profile in
            ProPresenterEditProfileSheet(
                profile: profile,
                onCancel: {
                    editingProfile = nil
                },
                onSave: { updated in
                    commitEditProfile(updated)
                    editingProfile = nil
                    Task { await testProfile(updated) }
                }
            )
        }
        .sheet(item: $quickAddDevice) { device in
            ProPresenterQuickAddSheet(
                device: device,
                onCancel: { quickAddDevice = nil },
                onSave: { pwd in
                    addProfile(from: device, withPassword: pwd)
                    quickAddDevice = nil
                }
            )
        }
    }

    private func statusColor(ok: Bool?, testing: Bool) -> Color {
        if testing { return .yellow }
        if ok == true { return .green }
        if ok == false { return .red }
        return .gray.opacity(0.6)
    }

    private func statusHelpText(ok: Bool?, testing: Bool, msg: String?, latency: Int?) -> String {
        if testing { return "Testing…" }
        if ok == true {
            if let latency { return "Connected ✓ (\(latency) ms)" }
            return "Connected ✓"
        }
        if ok == false { return msg ?? "Connection failed" }
        return "Not tested yet"
    }

    private func testProfiles(_ profiles: [ProPresenterConnectionProfile]) async {
        for profile in profiles {
            await testProfile(profile)
        }
    }

    private func testProfile(_ profile: ProPresenterConnectionProfile) async {
        let id = profile.id
        let trimmedHost = profile.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            await MainActor.run {
                lastTestOK[id] = false
                lastTestLatencyMs[id] = nil
                lastTestMessage[id] = "Missing host"
                isTesting.remove(id)
            }
            return
        }

        await MainActor.run {
            isTesting.insert(id)
            lastTestMessage[id] = ""
        }

        let normalized = ProPresenterConnection.normalizeHostAndPort(host: trimmedHost, port: profile.port)
        let start = Date()
        print("[ProPresenter] Testing profile=\"\(profile.name)\" host=\(normalized.host):\(normalized.port)")

        do {
            try await ProPresenterSettingsConnectionProbe.testHTTP(
                host: normalized.host,
                port: normalized.port,
                password: profile.password
            )
            let ms = max(0, Int(Date().timeIntervalSince(start) * 1000.0))
            print("[ProPresenter] Connected (HTTP) profile=\"\(profile.name)\" host=\(normalized.host):\(normalized.port) latencyMs=\(ms)")
            await MainActor.run {
                isTesting.remove(id)
                lastTestOK[id] = true
                lastTestLatencyMs[id] = ms
                lastTestMessage[id] = "Connected (HTTP)"
            }
        } catch {
            do {
                try await ProPresenterSettingsConnectionProbe.testTCPBridge(
                    host: normalized.host,
                    port: normalized.port
                )
                let ms = max(0, Int(Date().timeIntervalSince(start) * 1000.0))
                print("[ProPresenter] Connected (TCP fallback) profile=\"\(profile.name)\" host=\(normalized.host):\(normalized.port) latencyMs=\(ms)")
                await MainActor.run {
                    isTesting.remove(id)
                    lastTestOK[id] = true
                    lastTestLatencyMs[id] = ms
                    lastTestMessage[id] = "Connected (TCP fallback)"
                }
            } catch {
                print("[ProPresenter] Connection failed profile=\"\(profile.name)\" host=\(normalized.host):\(normalized.port) error=\(error.localizedDescription)")
                await MainActor.run {
                    isTesting.remove(id)
                    lastTestOK[id] = false
                    lastTestLatencyMs[id] = nil
                    lastTestMessage[id] = error.localizedDescription
                }
            }
        }
    }

    private func addProfile(from device: ProPresenterDiscoveredDevice, withPassword profilePassword: String = "") {
        var list = profilesList
        let exists = list.contains { $0.host == device.host && $0.port == device.port }
        guard !exists else { return }

        let name = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = ProPresenterConnectionProfile(
            id: UUID(),
            name: name.isEmpty ? "ProPresenter" : name,
            host: device.host,
            port: device.port,
            transportRaw: ProPresenterTransport.auto.rawValue,
            password: profilePassword
        )
        list.append(profile)
        list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        storeProfiles(list)
        Task { await testProfile(profile) }
    }

    private func discoveryStatusColor(for device: ProPresenterDiscoveredDevice) -> Color {
        if device.isValidating { return .yellow }
        if device.isValidated { return .green }
        if device.lastError != nil { return .red }
        return .gray.opacity(0.6)
    }

    private func discoveryStatusHelpText(for device: ProPresenterDiscoveredDevice) -> String {
        if device.isValidating { return "Validating…" }
        if device.isValidated { return "Connected ✓" }
        if let error = device.lastError { return error }
        return "Not validated"
    }

    private func endpointKey(host: String, port: Int) -> String {
        "\(host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()):\(port)"
    }

}

struct ProPresenterConnectionProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var transportRaw: String
    var password: String
}

private struct ProPresenterQuickAddSheet: View {
    let device: ProPresenterDiscoveredDevice
    @State private var password: String = ""
    var onCancel: () -> Void
    var onSave: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add ProPresenter Connection")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name.isEmpty ? "ProPresenter" : device.name)
                    .font(.callout)
                Text("\(device.host):\(device.port)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Password / Token")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Leave blank if ProPresenter has no password set", text: $password)
                    .textFieldStyle(.roundedBorder)
                Text("Enter the password configured in ProPresenter's Network or Remote settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Add") { onSave(password) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

private struct ProPresenterSaveProfileSheet: View {
    @Binding var name: String
    @Binding var host: String
    @Binding var port: Int
    @Binding var password: String
    @Binding var pollInterval: Double

    var onCancel: () -> Void
    var onSave: () -> Void


    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add ProPresenter Profile")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text("Connection Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Main Room, Youth, Overflow", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            Divider().padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Host / IP")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g. 192.168.1.50", text: $host)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(minWidth: 280)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Port")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DeferredNumberField("1025", value: $port, formatter: DashboardProPresenterSettingsView.portFormatter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                    }

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Password / Token (optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("", text: $password)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Polling")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Slider(value: $pollInterval, in: 0.1...5.0, step: 0.1)
                        Text(String(format: "%.1fs", pollInterval))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 46, alignment: .trailing)
                    }

                    Text("Relay can poll ProPresenter for status updates at this interval.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

}

private struct ProPresenterEditProfileSheet: View {
    @State var profile: ProPresenterConnectionProfile
    var onCancel: () -> Void
    var onSave: (ProPresenterConnectionProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit ProPresenter Connection")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Profile name", text: $profile.name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Host / IP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. 192.168.1.50", text: $profile.host)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Port")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DeferredNumberField("1025", value: $profile.port, formatter: DashboardProPresenterSettingsView.portFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Password / Token (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("", text: $profile.password)
                    .textFieldStyle(.roundedBorder)
            }

            Text("Transport is detected automatically based on the ProPresenter response.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Save") {
                    let trimmed = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    profile.name = trimmed
                    onSave(profile)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

// MARK: - ProPresenter Discovery (Bonjour)
// Service types: _proapiv1ws, _pro7, _pro6, _propresenter, _pro7proremote, _pro6proremote

struct ProPresenterDiscoveredDevice: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var host: String
    var port: Int
    var serviceTypes: Set<String>
    var isValidated: Bool
    var isValidating: Bool
    var lastError: String?
    var matchedProfileName: String?

    var detailNote: String? {
        var parts: [String] = []
        if let matchedProfileName, !matchedProfileName.isEmpty {
            parts.append("Already saved as \(matchedProfileName)")
        }
        #if DEBUG
        if !serviceTypes.isEmpty {
            parts.append("Services: " + serviceTypes.sorted().joined(separator: ", "))
        }
        #endif
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}

@MainActor
final class ProPresenterDiscoveryService: ObservableObject {
    @Published private(set) var results: [ProPresenterDiscoveredDevice] = []
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var statusText: String = "Idle"

    private let serviceTypes = [
        "_proapiv1ws._tcp",
        "_pro7._tcp",
        "_pro6._tcp",
        "_propresenter._tcp",
        "_pro7proremote._tcp",
        "_pro6proremote._tcp",
        "_http._tcp"
    ]
    private let httpFallbackServiceType = "_http._tcp"
    private var browsers: [NWBrowser] = []
    private let queue = DispatchQueue(label: "ProPresenterDiscoveryService")
    private var seenKeys: Set<String> = []
    private var password: String = ""
    private var lastScanErrorMessage: String?
    private var noAuthServiceTypes: Set<String> = []
    private var scanIdleTimeoutWorkItem: DispatchWorkItem?
    private let scanIdleTimeoutSeconds: TimeInterval = 6
    private var activeResolvers: [String: ProPresenterBonjourResolver] = [:]
    private var pendingHTTPFallbackKeys: Set<String> = []
    private var subnetFallbackTask: Task<Void, Never>?

    func updatePassword(_ password: String) {
        self.password = password
    }

    func startScan(password: String) {
        updatePassword(password)
        stopScan(reason: "restart")
        results.removeAll()
        seenKeys.removeAll()
        lastScanErrorMessage = nil
        noAuthServiceTypes.removeAll()
        let missingServiceTypes = missingDeclaredServiceTypes()
        let declaredBonjourServices = (Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String]) ?? []
        debugLog("bundle path=\(Bundle.main.bundlePath)")
        debugLog("bundle id=\(Bundle.main.bundleIdentifier ?? "unknown")")
        debugLog("declared Bonjour services=\(declaredBonjourServices.joined(separator: ","))")
        if !missingServiceTypes.isEmpty {
            statusText = "This Relay build is missing Bonjour service declarations for scan: \(missingServiceTypes.joined(separator: ", ")). Rebuild and relaunch the updated app."
            debugLog("scan blocked missing Bonjour declarations bundle=\(Bundle.main.bundlePath) missing=\(missingServiceTypes.joined(separator: ","))")
            return
        }
        isScanning = true
        statusText = "Scanning for ProPresenter…"
        scheduleIdleTimeout()
        debugLog("start scan")
        scheduleSubnetFallbackScan()

        for type in serviceTypes {
            debugLog("starting browser type=\(type)")
            let descriptor = NWBrowser.Descriptor.bonjour(type: type, domain: nil)
            let browser = NWBrowser(for: descriptor, using: .tcp)

            browser.browseResultsChangedHandler = { results, _ in
                Task { @MainActor [weak self] in
                    self?.handleBrowseResults(results, serviceType: type)
                }
            }

            browser.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .setup:
                    Task { @MainActor in
                        self.debugLog("state type=\(type) setup")
                    }
                case .ready:
                    Task { @MainActor in
                        self.debugLog("state type=\(type) ready")
                    }
                case .waiting(let error), .failed(let error):
                    Task { @MainActor in
                        self.handleBrowserError(error, serviceType: type)
                    }
                case .cancelled:
                    Task { @MainActor in
                        self.debugLog("state type=\(type) cancelled")
                    }
                default:
                    break
                }
            }

            browsers.append(browser)
            browser.start(queue: queue)
        }
    }

    func stopScan(reason: String = "user") {
        scanIdleTimeoutWorkItem?.cancel()
        scanIdleTimeoutWorkItem = nil

        for browser in browsers {
            browser.cancel()
        }
        browsers.removeAll()
        for resolver in activeResolvers.values {
            resolver.cancel()
        }
        activeResolvers.removeAll()
        pendingHTTPFallbackKeys.removeAll()
        noAuthServiceTypes.removeAll()
        subnetFallbackTask?.cancel()
        subnetFallbackTask = nil
        isScanning = false
        if let lastScanErrorMessage, results.isEmpty {
            statusText = lastScanErrorMessage
        } else {
            statusText = results.isEmpty ? "No ProPresenter instances discovered" : "Scan complete"
        }
        debugLog("stop scan reason=\(reason)")
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>, serviceType: String) {
        #if DEBUG
        if !results.isEmpty {
            debugLog("browse results type=\(serviceType) count=\(results.count)")
            for result in results {
                debugLog("multicast result type=\(serviceType) endpoint=\(result.endpoint)")
            }
        }
        #endif
        for result in results {
            resolve(result: result, serviceType: serviceType)
        }
    }

    private func resolve(result: NWBrowser.Result, serviceType: String) {
        switch result.endpoint {
        case .hostPort(let host, let port):
            handleResolvedCandidate(
                name: host.debugDescription,
                host: host.debugDescription,
                port: Int(port.rawValue),
                serviceType: serviceType
            )
        case .service(let name, let type, let domain, _):
            let resolverKey = "\(name)|\(type)|\(domain)"
            guard activeResolvers[resolverKey] == nil else { return }
            let resolver = ProPresenterBonjourResolver(name: name, type: type, domain: domain)
            activeResolvers[resolverKey] = resolver
            resolver.resolve(
                onResolved: { [weak self] resolvedHost, resolvedPort in
                    Task { @MainActor in
                        guard let self else { return }
                        self.activeResolvers.removeValue(forKey: resolverKey)
                        self.handleResolvedCandidate(
                            name: name,
                            host: resolvedHost,
                            port: resolvedPort,
                            serviceType: serviceType
                        )
                    }
                },
                onFailure: { [weak self] error in
                    Task { @MainActor in
                        guard let self else { return }
                        self.activeResolvers.removeValue(forKey: resolverKey)
                        self.debugLog("resolve failed name=\(name) type=\(serviceType) error=\(error.localizedDescription)")
                    }
                }
            )
        default:
            break
        }
    }

    private func handleResolvedCandidate(name: String, host: String, port: Int, serviceType: String) {
        if serviceType == httpFallbackServiceType {
            let key = "\(host):\(port)"
            guard !seenKeys.contains(key), !pendingHTTPFallbackKeys.contains(key) else { return }
            pendingHTTPFallbackKeys.insert(key)
            Task {
                await validateHTTPFallbackCandidate(name: name, host: host, port: port, serviceType: serviceType, key: key)
            }
            return
        }
        addResolvedResult(name: name, host: host, port: port, serviceType: serviceType)
    }

    private func addResolvedResult(name: String, host: String, port: Int, serviceType: String) {
        let endpointHost = NWEndpoint.Host(host)
        let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) ?? .any
        addResult(name: name, host: endpointHost, port: endpointPort, serviceType: serviceType)
    }

    private func validateHTTPFallbackCandidate(name: String, host: String, port: Int, serviceType: String, key: String) async {
        defer { pendingHTTPFallbackKeys.remove(key) }

        do {
            try await ProPresenterSettingsConnectionProbe.testHTTP(
                host: host,
                port: port,
                password: password,
                timeout: 0.75
            )
            addResolvedResult(name: name, host: host, port: port, serviceType: serviceType)
            debugLog("validated http fallback name=\(name) host=\(host) port=\(port)")
        } catch {
            debugLog("ignored http fallback name=\(name) host=\(host) port=\(port) error=\(error.localizedDescription)")
        }
    }

    private func scheduleSubnetFallbackScan() {
        subnetFallbackTask?.cancel()
        subnetFallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await self?.runSubnetFallbackScanIfNeeded()
        }
    }

    private func runSubnetFallbackScanIfNeeded() async {
        guard !Task.isCancelled else { return }
        guard results.isEmpty else { return }

        let candidates = subnetFallbackCandidates()
        guard !candidates.isEmpty else {
            debugLog("subnet fallback skipped no candidates")
            return
        }

        debugLog("subnet fallback started candidates=\(candidates.count)")
        let maxConcurrent = 24
        var index = 0
        while index < candidates.count, !Task.isCancelled {
            let batch = Array(candidates[index..<min(index + maxConcurrent, candidates.count)])
            await withTaskGroup(of: Void.self) { group in
                for (host, port) in batch {
                    group.addTask { [weak self] in
                        await self?.probeSubnetCandidate(host: host, port: port)
                    }
                }
            }
            index += maxConcurrent
        }
        debugLog("subnet fallback finished results=\(results.count)")
    }

    private func probeSubnetCandidate(host: String, port: Int) async {
        guard !Task.isCancelled else { return }
        let key = "\(host):\(port)"
        guard !seenKeys.contains(key) else { return }

        do {
            try await ProPresenterSettingsConnectionProbe.testHTTP(
                host: host,
                port: port,
                password: password,
                timeout: 0.5
            )
            guard !Task.isCancelled else { return }
            addResolvedResult(name: host, host: host, port: port, serviceType: "subnet-http")
            debugLog("validated subnet fallback host=\(host) port=\(port)")
        } catch {
            // Keep quiet for subnet misses; there can be many.
        }
    }

    private func subnetFallbackCandidates() -> [(String, Int)] {
        let defaults = UserDefaults.standard
        let ports = candidatePorts(from: defaults)
        let subnets = candidateSubnets(from: defaults)
        guard !ports.isEmpty, !subnets.isEmpty else { return [] }

        var seen = Set<String>()
        var candidates: [(String, Int)] = []
        for subnet in subnets {
            for host in hosts(in: subnet) {
                for port in ports {
                    let key = "\(host):\(port)"
                    if seen.insert(key).inserted {
                        candidates.append((host, port))
                    }
                }
            }
        }
        return candidates
    }

    private func candidatePorts(from defaults: UserDefaults) -> [Int] {
        var seedPorts = Set<Int>([49864])
        let globalPort = defaults.integer(forKey: "propresenter_port")
        if globalPort > 0 { seedPorts.insert(globalPort) }

        if let host = defaults.string(forKey: "propresenter_host"),
           !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           globalPort > 0 {
            seedPorts.insert(globalPort)
        }

        if let profiles = decodedSavedProfiles(from: defaults) {
            for profile in profiles where profile.port > 0 {
                seedPorts.insert(profile.port)
            }
        }

        var orderedPorts: [Int] = []
        var seen = Set<Int>()
        for basePort in seedPorts.sorted() {
            for candidate in expandedPortCandidates(around: basePort) {
                guard candidate > 0, candidate <= 65535 else { continue }
                if seen.insert(candidate).inserted {
                    orderedPorts.append(candidate)
                }
            }
        }
        return orderedPorts
    }

    private func expandedPortCandidates(around port: Int) -> [Int] {
        guard port > 0 else { return [] }
        // ProPresenter API ports in this environment appear to vary per machine,
        // but cluster near the known saved port(s), so scan a tight window first.
        let offsets = [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6]
        return offsets.map { port + $0 }
    }

    private func candidateSubnets(from defaults: UserDefaults) -> [String] {
        var prefixes = Set<String>()

        if let current = NetworkUtils.currentIPv4(), let prefix = ipv4Prefix(for: current) {
            prefixes.insert(prefix)
        }

        if let host = defaults.string(forKey: "propresenter_host"), let prefix = ipv4Prefix(for: host) {
            prefixes.insert(prefix)
        }

        if let profiles = decodedSavedProfiles(from: defaults) {
            for profile in profiles {
                if let prefix = ipv4Prefix(for: profile.host) {
                    prefixes.insert(prefix)
                }
            }
        }

        return prefixes.sorted()
    }

    private func loadSavedProfiles(from defaults: UserDefaults) -> [ProPresenterConnectionProfile]? {
        guard let data = defaults.data(forKey: "propresenter_profiles"), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode([ProPresenterConnectionProfile].self, from: data)
    }

    private func ipv4Prefix(for value: String) -> String? {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 4,
              parts.allSatisfy({ Int($0).map { (0...255).contains($0) } == true }) else { return nil }
        return "\(parts[0]).\(parts[1]).\(parts[2])"
    }

    private func hosts(in prefix: String) -> [String] {
        (1...254).map { "\(prefix).\($0)" }
    }

    private func addResult(name: String, host: NWEndpoint.Host, port: NWEndpoint.Port, serviceType: String) {
        let hostString = host.debugDescription
        let portValue = Int(port.rawValue)
        let key = "\(hostString):\(portValue)"
        let isNew = !seenKeys.contains(key)
        if isNew { seenKeys.insert(key) }
        let matchedProfileName = matchedSavedProfileName(host: hostString, port: portValue)

        if let idx = results.firstIndex(where: { $0.host == hostString && $0.port == portValue }) {
            results[idx].serviceTypes.insert(serviceType)
            if results[idx].matchedProfileName == nil {
                results[idx].matchedProfileName = matchedProfileName
            }
        } else {
            let device = ProPresenterDiscoveredDevice(
                name: name,
                host: hostString,
                port: portValue,
                serviceTypes: [serviceType],
                isValidated: false,
                isValidating: false,
                lastError: nil,
                matchedProfileName: matchedProfileName
            )
            results.append(device)
            results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        if isNew {
            scheduleIdleTimeout()
            Task { await validate(host: hostString, port: portValue) }
        }
    }

    private func validate(host: String, port: Int) async {
        guard let idx = results.firstIndex(where: { $0.host == host && $0.port == port }) else { return }
        results[idx].isValidating = true
        results[idx].lastError = nil

        do {
            try await ProPresenterSettingsConnectionProbe.testHTTP(
                host: host,
                port: port,
                password: password
            )
            if let idx = results.firstIndex(where: { $0.host == host && $0.port == port }) {
                results[idx].isValidated = true
                results[idx].isValidating = false
                debugLog("validated http host=\(host) port=\(port)")
            }
        } catch {
            do {
                try await ProPresenterSettingsConnectionProbe.testTCPBridge(
                    host: host,
                    port: port
                )
                if let idx = results.firstIndex(where: { $0.host == host && $0.port == port }) {
                    results[idx].isValidated = true
                    results[idx].isValidating = false
                    debugLog("validated tcp host=\(host) port=\(port)")
                }
            } catch {
                if let idx = results.firstIndex(where: { $0.host == host && $0.port == port }) {
                    results[idx].isValidated = false
                    results[idx].isValidating = false
                    results[idx].lastError = error.localizedDescription
                    debugLog("validation failed host=\(host) port=\(port) error=\(error.localizedDescription)")
                }
            }
        }
    }

    private func scheduleIdleTimeout() {
        scanIdleTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.stopScan(reason: "idle-timeout")
        }
        scanIdleTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + scanIdleTimeoutSeconds, execute: workItem)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[ProPresenterDiscovery] \(message)")
        #endif
    }

    private func handleBrowserError(_ error: NWError, serviceType: String) {
        let message = String(describing: error)
        if message.contains("NoAuth") {
            noAuthServiceTypes.insert(serviceType)
            if noAuthServiceTypes.count == serviceTypes.count {
                lastScanErrorMessage = "Local Network permission is required to scan. Enable Relay in System Settings -> Privacy & Security -> Local Network."
                statusText = lastScanErrorMessage ?? statusText
            }
        } else {
            lastScanErrorMessage = "Scan error: \(error.localizedDescription)"
            statusText = lastScanErrorMessage ?? statusText
        }
        debugLog("browser failed type=\(serviceType) error=\(error.localizedDescription)")
    }

    private func missingDeclaredServiceTypes() -> [String] {
        let declared = Set((Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String]) ?? [])
        return serviceTypes.filter { !declared.contains($0) }
    }

    private func matchedSavedProfileName(host: String, port: Int) -> String? {
        guard let profiles = decodedSavedProfiles(from: .standard) else { return nil }
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return profiles.first {
            $0.port == port &&
            $0.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedHost
        }?.name
    }

    private func decodedSavedProfiles(from defaults: UserDefaults) -> [ProPresenterConnectionProfile]? {
        guard let data = defaults.data(forKey: "propresenter_profiles"), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode([ProPresenterConnectionProfile].self, from: data)
    }
}

private final class ProPresenterBonjourResolver: NSObject, NetServiceDelegate {
    private let service: NetService
    private var onResolved: ((String, Int) -> Void)?
    private var onFailure: ((Error) -> Void)?
    private var didFinish = false

    init(name: String, type: String, domain: String) {
        self.service = NetService(domain: domain, type: type, name: name)
        super.init()
        service.delegate = self
    }

    func resolve(onResolved: @escaping (String, Int) -> Void, onFailure: @escaping (Error) -> Void) {
        self.onResolved = onResolved
        self.onFailure = onFailure
        service.resolve(withTimeout: 4)
    }

    func cancel() {
        finishFailure(URLError(.cancelled))
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard !didFinish else { return }
        if let hostName = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
           !hostName.isEmpty {
            didFinish = true
            onResolved?(hostName, sender.port)
            clearCallbacks()
        } else {
            finishFailure(URLError(.cannotFindHost))
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        let code = errorDict[NetService.errorCode]?.intValue ?? -1
        finishFailure(NSError(domain: "NetService", code: code, userInfo: [
            NSLocalizedDescriptionKey: "Bonjour resolve failed"
        ]))
    }

    private func finishFailure(_ error: Error) {
        guard !didFinish else { return }
        didFinish = true
        service.stop()
        onFailure?(error)
        clearCallbacks()
    }

    private func clearCallbacks() {
        onResolved = nil
        onFailure = nil
    }
}

private struct ProUpgradeOverlayFallbackView: View {
    let action: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.7)
                    .ignoresSafeArea()
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    Text("Unlock more with Pro")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("ProPresenter is available with Pro.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Subscribe") {
                        action()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)
                .background(Color.black.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .allowsHitTesting(true)
    }
}
