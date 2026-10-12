//
//  DashboardResolumeSettingsView.swift
//  Relay
//
//  Resolume REST connection profiles (multiple allowed).
//

import SwiftUI
import Foundation

// MARK: - Dashboard Settings View

struct DashboardResolumeSettingsView: View {
    @StateObject private var store = ResolumeConnection.shared.profilesStore

    @State private var isPresentingAddSheet: Bool = false
    @State private var editingProfile: ResolumeConnectionProfile? = nil

    // Per-profile test results
    @State private var lastTestOK: [UUID: Bool] = [:]
    @State private var lastTestLatencyMs: [UUID: Int] = [:]
    @State private var lastTestMessage: [UUID: String] = [:]
    @State private var isTesting: Set<UUID> = []
    @State private var isShowingHelp: Bool = false

    private let core = ResolumeConnectionCore()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Resolume")
                    .font(.title2.bold())
                Button {
                    isShowingHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .help("How to connect Resolume")
                .popover(isPresented: $isShowingHelp) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Connect Resolume")
                            .font(.headline)
                        Text("Enable Resolume’s HTTP/REST API and use the host/port shown in Resolume.")
                            .font(.callout)
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Enable the REST API / Web Server in Resolume.", systemImage: "1.circle")
                            Label("Use the host IP and port (typically 8080).", systemImage: "2.circle")
                            Label("Add a profile and Relay will verify it automatically.", systemImage: "3.circle")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(width: 380)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Saved Connections")
                            .font(.headline)
                        Spacer()
                        Button {
                            isPresentingAddSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                Text("Add Profile")
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("Configure the Resolume connection used by Resolume modules. This is global (like Planning Center settings). Enable the ones you want active.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if store.profiles.isEmpty {
                        Text("No saved connections yet. Add a profile to start polling via REST.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        List {
                            ForEach(store.profiles) { profile in
                                profileRow(profile)
                            }
                            .onDelete(perform: deleteProfiles)
                            .onMove(perform: moveProfiles)
                        }
                        .frame(minHeight: 140)
                    }

                    Text("Tip: Resolume’s REST API is stateless—Relay can poll multiple Resolume servers at the same time. Enable the ones you want active.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(24)
        .sheet(isPresented: $isPresentingAddSheet) {
            ResolumeProfileEditorSheet(
                title: "Add Resolume Connection",
                initial: ResolumeConnectionProfile(),
                onCancel: { isPresentingAddSheet = false },
                onSave: { newProfile in
                    store.profiles.append(newProfile)
                    isPresentingAddSheet = false
                    Task { await testProfile(newProfile) }
                }
            )
        }
        .sheet(item: $editingProfile) { profile in
            ResolumeProfileEditorSheet(
                title: "Edit Resolume Connection",
                initial: profile,
                onCancel: { editingProfile = nil },
                onSave: { updated in
                    if let idx = store.profiles.firstIndex(where: { $0.id == updated.id }) {
                        store.profiles[idx] = updated
                    }
                    editingProfile = nil
                    Task { await testProfile(updated) }
                }
            )
        }
        .onAppear {
            // Ensure the shared store is hydrated.
            store.loadFromDisk()
            Task { await testProfiles(store.profiles) }
        }
        .onChange(of: store.profiles, initial: false) { _, enabled in
            store.saveToDisk()
            Task { await testProfiles(store.profiles) }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func profileRow(_ profile: ResolumeConnectionProfile) -> some View {
        let ok = lastTestOK[profile.id]
        let latency = lastTestLatencyMs[profile.id]
        let msg = lastTestMessage[profile.id]
        let testing = isTesting.contains(profile.id)

        HStack(spacing: 12) {

            // Status dot (green/red/gray)
            Circle()
                .fill(statusColor(ok: ok, testing: testing, enabled: profile.isEnabled))
                .frame(width: 10, height: 10)
                .help(statusHelpText(ok: ok, testing: testing, enabled: profile.isEnabled, msg: msg, latency: latency))

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name.isEmpty ? "Resolume" : profile.name)
                    .font(.callout)
                    .lineLimit(1)

                Text(profile.displayHostPort)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let msg, !msg.isEmpty, profile.isEnabled {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(ok == false ? .red : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                if let idx = store.profiles.firstIndex(where: { $0.id == profile.id }) {
                    store.profiles[idx].isEnabled.toggle()
                }
            } label: {
                Image(systemName: profile.isEnabled ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .buttonStyle(.borderless)
            .help(profile.isEnabled ? "Disable connection" : "Enable connection")

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)

        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            editingProfile = profile
        }
    }

    private func statusColor(ok: Bool?, testing: Bool, enabled: Bool) -> Color {
        if !enabled { return .gray.opacity(0.35) }
        if testing { return .yellow }
        if ok == true { return .green }
        if ok == false { return .red }
        return .gray.opacity(0.6)
    }

    private func statusHelpText(ok: Bool?, testing: Bool, enabled: Bool, msg: String?, latency: Int?) -> String {
        if !enabled { return "Disabled" }
        if testing { return "Testing…" }
        if ok == true {
            if let latency { return "Connected ✓ (\(latency) ms)" }
            return "Connected ✓"
        }
        if ok == false { return msg ?? "Connection failed" }
        return "Not tested yet"
    }

    // MARK: - List helpers

    private func deleteProfiles(at offsets: IndexSet) {
        for idx in offsets {
            let id = store.profiles[idx].id
            lastTestOK[id] = nil
            lastTestLatencyMs[id] = nil
            lastTestMessage[id] = nil
            isTesting.remove(id)
        }
        store.profiles.remove(atOffsets: offsets)
    }

    private func moveProfiles(from source: IndexSet, to destination: Int) {
        store.profiles.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Test

    private func testProfile(_ profile: ResolumeConnectionProfile) async {
        let id = profile.id
        await MainActor.run {
            isTesting.insert(id)
            lastTestMessage[id] = ""
        }

        let start = Date()
        print("[Resolume] Testing profile=\"\(profile.name)\" host=\(profile.endpoint.host):\(profile.endpoint.port)")
        do {
            // Use a simple “composition” request as a health check.
            _ = try await core.requestJSONObject(
                endpoint: profile.endpoint,
                path: "/api/v1/composition"
            )

            let ms = max(0, Int(Date().timeIntervalSince(start) * 1000.0))
            print("[Resolume] Connected profile=\"\(profile.name)\" host=\(profile.endpoint.host):\(profile.endpoint.port) latencyMs=\(ms)")
            await MainActor.run {
                isTesting.remove(id)
                lastTestOK[id] = true
                lastTestLatencyMs[id] = ms
                lastTestMessage[id] = "Connected ✓"
            }
        } catch {
            print("[Resolume] Connection failed profile=\"\(profile.name)\" host=\(profile.endpoint.host):\(profile.endpoint.port) error=\(error.localizedDescription)")
            await MainActor.run {
                isTesting.remove(id)
                lastTestOK[id] = false
                lastTestLatencyMs[id] = nil
                lastTestMessage[id] = error.localizedDescription
            }
        }
    }

    private func testProfiles(_ profiles: [ResolumeConnectionProfile]) async {
        for profile in profiles where profile.isEnabled {
            await testProfile(profile)
        }
    }

}

// MARK: - Add/Edit Sheet

private struct ResolumeProfileEditorSheet: View {
    let title: String
    let initial: ResolumeConnectionProfile
    let onCancel: () -> Void
    let onSave: (ResolumeConnectionProfile) -> Void

    @State private var working: ResolumeConnectionProfile

    init(
        title: String,
        initial: ResolumeConnectionProfile,
        onCancel: @escaping () -> Void,
        onSave: @escaping (ResolumeConnectionProfile) -> Void
    ) {
        self.title = title
        self.initial = initial
        self.onCancel = onCancel
        self.onSave = onSave
        _working = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.bold())

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Name")
                        TextField("Front Wall", text: $working.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Host")
                        TextField("10.0.0.10", text: $working.host)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
#if os(iOS)
                            .textInputAutocapitalization(.never)
#endif
                    }

                    HStack {
                        Text("Port")
                        DeferredNumberField(value: $working.port, formatter: portFormatter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }

                    Toggle("Enabled", isOn: $working.isEnabled)
                }
                .padding(.vertical, 6)
            }

            Spacer()

            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Save") {
                    // Basic sanitization
                    working.host = working.host.trimmingCharacters(in: .whitespacesAndNewlines)
                    if working.port < 1 { working.port = 1 }
                    if working.port > 65535 { working.port = 65535 }
                    onSave(working)
                }
                .buttonStyle(.borderedProminent)
                .disabled(working.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 320)
    }

    // Prevent commas/grouping in numeric entry
    private var portFormatter: NumberFormatter {
        let nf = NumberFormatter()
        nf.numberStyle = .none
        nf.usesGroupingSeparator = false
        nf.minimum = 1
        nf.maximum = 65535
        nf.maximumFractionDigits = 0
        return nf
    }
}
