//
//  ExternalDevicesSettingsView.swift
//  Relay
//
//  Created by David Bullard on 11/19/25.
//

import SwiftUI
import UniformTypeIdentifiers
import Network
import Combine
#if os(macOS)
import CoreMIDI
import AppKit
#endif

private let sennheiserEnabled: Bool = true

struct ExternalDevicesSettingsView: View {
    @StateObject private var store = ExternalDevicesStore.shared
    @StateObject private var discoveryService = ExternalDeviceDiscoveryService()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var lanService: LANSharedTabsService
    @Environment(\.proUpgradeAction) private var proUpgradeAction

    enum EntryMode {
        /// Shows the full External Devices settings experience (device list + editor).
        case full
        /// Legacy alias for `full` (kept so older call sites still compile).
        case list
        /// Opens directly into editing a specific device (hides list UI).
        case editDeviceOnly
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
                    Text("External Devices are available with Pro.")
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

    /// If provided, the view will auto-select this device and open the editor when it appears.
    let initialDeviceID: ExternalDeviceConfig.ID?
    let entryMode: EntryMode

    @State private var selectedDeviceID: ExternalDeviceConfig.ID?
    @State private var selectedDeviceIDs: Set<ExternalDeviceConfig.ID> = []
    @State private var showingEditor = false
    @State private var pendingNewDeviceID: ExternalDeviceConfig.ID? = nil
    @State private var didConfirmNewDevice: Bool = false
    @State private var showsDiscoverySheet: Bool = false
    @State private var isRefreshingShureAfterScan: Bool = false
    @State private var shureRefreshStatus: String = "Refreshing Shure device names…"
    @State private var shureRefreshToken: UUID = UUID()
    @State private var isRefreshingX32AfterScan: Bool = false
    @State private var x32RefreshToken: UUID = UUID()
#if os(iOS)
    @State private var editMode: EditMode = .inactive
#else
    @State private var isReordering: Bool = false
#endif
    @State private var isSelectingDevices: Bool = false

    // Collapsible list sections (by device kind)
    @State private var expandedKinds: Set<ExternalDeviceKind> = Set(ExternalDeviceKind.allCases)
    @State private var searchText: String = ""
    @State private var isShowingHelp: Bool = false
    @State private var pendingDeleteDevice: ExternalDeviceConfig?
    @State private var pendingDeleteDeviceIDs: [ExternalDeviceConfig.ID] = []
    @State private var pendingDeleteAllDevices: Bool = false
    @State private var selectedDiscoveryKeys: Set<String> = []
    @FocusState private var isListFocused: Bool
    private let hiddenKinds: Set<ExternalDeviceKind> = {
        var set: Set<ExternalDeviceKind> = [.lightingConsole, .genericOsc]
        if !RelayLicensingConfig.isVistaIntegrationEnabled {
            set.insert(.vistaConsole)
        }
        if !sennheiserEnabled {
            set.insert(.sennheiserWireless)
        }
        return set
    }()

    private var visibleKinds: [ExternalDeviceKind] {
        ExternalDeviceKind.sortedByDisplayName(
            ExternalDeviceKind.allCases.filter { !hiddenKinds.contains($0) }
        )
    }

    private func isExpandedBinding(for kind: ExternalDeviceKind) -> Binding<Bool> {
        Binding(
            get: { expandedKinds.contains(kind) },
            set: { newValue in
                if newValue {
                    expandedKinds.insert(kind)
                } else {
                    expandedKinds.remove(kind)
                }
            }
        )
    }

    private func isX32FamilyModel(_ modelIdentifier: String?) -> Bool {
        let model = (modelIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if model.isEmpty { return false }
        return model == "Behringer_X32" || model == "Midas_M32" ||
            model == "Behringer X32" || model == "Midas M32" ||
            model == "X32" || model == "M32"
    }

    private func autoSyncX32AfterDiscovery(_ devices: [ExternalDeviceConfig]) {
        let x32Devices = devices.filter { device in
            device.kind == .audioConsole && device.isEnabled && isX32FamilyModel(device.consoleModelIdentifier)
        }
        guard !x32Devices.isEmpty else { return }

        let token = UUID()
        x32RefreshToken = token
        isRefreshingX32AfterScan = true

        Task.detached(priority: .utility) {
            for device in x32Devices {
                let shouldContinue = await MainActor.run {
                    isRefreshingX32AfterScan && x32RefreshToken == token
                }
                guard shouldContinue else { break }

                let map = await ConsoleConnectorRegistry.shared
                    .syncX32ChannelNames(externalDeviceId: device.id, channelCount: 32, timeout: 2.0)

                if !map.isEmpty {
                    let defaultsKey = "prodlink.x32sync.map.\(device.id.uuidString)"
                    let tsKey = "prodlink.x32sync.ts.\(device.id.uuidString)"
                    if let data = try? JSONEncoder().encode(map) {
                        UserDefaults.standard.set(data, forKey: defaultsKey)
                        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: tsKey)
                    }
                }

                try? await Task.sleep(nanoseconds: 150_000_000)
            }

            await MainActor.run {
                if x32RefreshToken == token {
                    isRefreshingX32AfterScan = false
                }
            }
        }
    }

    private func autoSyncDLiveAfterDiscovery(_ devices: [ExternalDeviceConfig]) {
        let dLiveDevices = devices.filter { device in
            device.kind == .audioConsole && device.isEnabled && device.audioConsoleModel == .allenHeathDlive
        }
        guard !dLiveDevices.isEmpty else { return }

        Task.detached(priority: .utility) {
            for device in dLiveDevices {
                let map = await ConsoleConnectorRegistry.shared
                    .syncAllenHeathChannelNames(externalDeviceId: device.id, channelCount: 128, timeout: 1.0)

                guard !map.isEmpty else { continue }

                await MainActor.run {
                    store.updateDevice(id: device.id) { device in
                        device.lastChannelSyncAt = Date()
                    }
                    persistDLiveSync(map: map, at: Date(), deviceID: device.id)
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    init(initialDeviceID: ExternalDeviceConfig.ID? = nil, entryMode: EntryMode = .full) {
        self.initialDeviceID = initialDeviceID
        self.entryMode = entryMode
        _selectedDeviceID = State(initialValue: initialDeviceID)
        _selectedDeviceIDs = State(initialValue: initialDeviceID.map { [$0] } ?? [])
    }

    // Group and sort devices by kind for sectioned list display
    private var devicesGroupedByKind: [(kind: ExternalDeviceKind, devices: [ExternalDeviceConfig])] {
        let grouped = Dictionary(grouping: filteredDevices) { $0.kind }
        return ExternalDeviceKind.sortedByDisplayName(Array(grouped.keys)).map { kind in
            let devices = grouped[kind] ?? []
            return (kind, devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    private var filteredDevices: [ExternalDeviceConfig] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleDevices = store.devices.filter { !hiddenKinds.contains($0.kind) }
        guard !trimmed.isEmpty else { return visibleDevices }
        let query = trimmed.lowercased()
        return visibleDevices.filter { device in
            let hostPort = "\(device.host):\(device.port)".lowercased()
            return device.name.lowercased().contains(query)
                || hostPort.contains(query)
                || device.kind.displayName.lowercased().contains(query)
        }
    }

    private var isReorderingActive: Bool {
#if os(iOS)
        return editMode == .active
#else
        return isReordering
#endif
    }

#if os(iOS)
    private var listEditMode: EditMode {
        (editMode == .active || isSelectingDevices) ? .active : .inactive
    }
#endif

    private var visibleDeviceIDsInListOrder: [ExternalDeviceConfig.ID] {
        if isReorderingActive {
            return store.devices
                .filter { !hiddenKinds.contains($0.kind) }
                .map(\.id)
        }

        return devicesGroupedByKind
            .flatMap(\.devices)
            .map(\.id)
    }

    private func openEditor(for id: ExternalDeviceConfig.ID, proxy: ScrollViewProxy) {
        // Ensure selection + sheet happen after the view has mounted (fixes "works second time")
        Task { @MainActor in
            await Task.yield()
            selectedDeviceID = id
            showingEditor = true
            withAnimation {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    // Helper for PSM900 detection
    private func isPSM900(_ device: ExternalDeviceConfig) -> Bool {
        if let code = device.shureModelIdentifier?.uppercased(), code.contains("PSM900") {
            return true
        }
        let upper = device.name.uppercased()
        return upper.contains("PSM 900") || upper.contains("PSM900")
    }

    private static nonisolated func isP10TDevice(_ device: ExternalDeviceConfig) -> Bool {
        let model = device.shureModelIdentifier?.uppercased() ?? ""
        let name = device.name.uppercased()
        if model.contains("P10T") || model.contains("PSM1000") {
            return true
        }
        if name.contains("P10T") || name.contains("PSM 1000") || name.contains("PSM1000") {
            return true
        }
        if let uacn = device.shureDiscoveryUACN?.uppercased(),
           uacn.contains("P10T") || uacn.contains("PSM1000") {
            return true
        }
        if let fctn = device.shureDiscoveryFCTN?.uppercased(),
           fctn.contains("P10T") || fctn.contains("PSM1000") {
            return true
        }
        return false
    }

    private func isPSM1000Name(_ name: String) -> Bool {
        let upper = name.uppercased()
        return upper.contains("P10T") || upper.contains("PSM 1000") || upper.contains("PSM1000")
    }

    var body: some View {
        // In deep-link mode we want to land directly on the editor (no underlying list UI).
        Group {
            if entryMode == .editDeviceOnly {
                editDeviceOnlyBody
            } else {
                fullSettingsBody
            }
        }
        .onAppear {
            lanService.setPollingOverrideDisabled(true)
        }
        .onDisappear {
            lanService.setPollingOverrideDisabled(false)
        }
    }

    // MARK: - Full/List Settings Body

    private var fullSettingsBody: some View {
        ScrollViewReader { proxy in
            fullSettingsContent(proxy: proxy)
        }
    }

    private func fullSettingsContent(proxy: ScrollViewProxy) -> some View {
        let isPro = subscriptionManager.hasPro
        let content = VStack(alignment: .leading, spacing: 10) {
            headerRow(proxy: proxy)
#if os(macOS)
            if !isReorderingActive {
                searchRow
            }
#endif
            devicesList
            footerHint
        }
        .disabled(!isPro)
        .opacity(isPro ? 1.0 : 0.35)
        .allowsHitTesting(isPro)
        #if os(iOS)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 0)
        #else
        .padding(16)
        #endif
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        #if os(iOS)
        let base = AnyView(
            Group {
                if #available(iOS 16.0, *) {
                    content
                        .navigationTitle("External Devices")
                        .searchable(
                            text: $searchText,
                            placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "Search devices"
                        )
                } else {
                    content
                        .navigationTitle("External Devices")
                        .searchable(text: $searchText, prompt: "Search devices")
                }
            }
        )
        #else
        let base = AnyView(content)
        #endif

        let withSheet = base
            .sheet(isPresented: $showsDiscoverySheet) {
                discoverySheet
            }
            .sheet(isPresented: $isRefreshingShureAfterScan) {
                shureRefreshSheet
            }
            .onChange(of: showsDiscoverySheet) { _, isPresented in
                if !isPresented {
                    discoveryService.stopScan()
                }
            }

        let withConfirmDialog = withSheet.confirmationDialog(
            "Delete device?",
            isPresented: Binding(
                get: { pendingDeleteDevice != nil },
                set: { newValue in
                    if !newValue { pendingDeleteDevice = nil }
                }
            )
        ) {
            Button("Delete Device", role: .destructive) {
                if let device = pendingDeleteDevice {
                    deleteDevice(device)
                }
                pendingDeleteDevice = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteDevice = nil
            }
        } message: {
            if let device = pendingDeleteDevice {
                Text("This will remove “\(device.name)” from External Devices.")
            }
        }

        let withSelectedDialog = withConfirmDialog.confirmationDialog(
            "Delete Selected Devices?",
            isPresented: Binding(
                get: { !pendingDeleteDeviceIDs.isEmpty },
                set: { newValue in
                    if !newValue { pendingDeleteDeviceIDs = [] }
                }
            )
        ) {
            Button("Delete Selected", role: .destructive) {
                deleteDevices(withIDs: pendingDeleteDeviceIDs)
                pendingDeleteDeviceIDs = []
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteDeviceIDs = []
            }
        } message: {
            Text("This will remove \(pendingDeleteDeviceIDs.count) device(s) from External Devices.")
        }

        let withAllDialog = withSelectedDialog.confirmationDialog(
            "Delete All External Devices?",
            isPresented: $pendingDeleteAllDevices
        ) {
            Button("Delete All", role: .destructive) {
                deleteAllDevices()
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteAllDevices = false
            }
        } message: {
            Text("This will remove all external devices from this dashboard.")
        }

        let withLifecycle = withAllDialog
        .task(id: initialDeviceID) {
            // If we were launched with an initial id, prefer it as selection.
            if let id = initialDeviceID {
                selectedDeviceID = id
                selectedDeviceIDs = [id]
            }

            // Default selection for full/list mode.
            if selectedDeviceID == nil, let first = store.devices.first {
                selectedDeviceID = first.id
                selectedDeviceIDs = [first.id]
            }

            // If initial device exists, open the editor.
            if let id = initialDeviceID,
               store.devices.contains(where: { $0.id == id }) {
                openEditor(for: id, proxy: proxy)
            }
        }
        .onChange(of: selectedDeviceIDs, initial: false) { _, newValue in
            if newValue.count == 1 {
                selectedDeviceID = newValue.first
            } else if newValue.isEmpty {
                selectedDeviceID = nil
            }
        }
        .onChange(of: store.devices.map(\.id)) { _, _ in
            // Re-apply initial selection once devices load.
            if let id = initialDeviceID, store.devices.contains(where: { $0.id == id }) {
                if selectedDeviceID != id {
                    selectedDeviceID = id
                    selectedDeviceIDs = [id]
                }
                return
            }

            // Otherwise ensure we have *some* selection.
            if selectedDeviceID == nil, let first = store.devices.first {
                selectedDeviceID = first.id
                selectedDeviceIDs = [first.id]
            }

            // If current selection was deleted, clear it.
            if let selected = selectedDeviceID,
               !store.devices.contains(where: { $0.id == selected }) {
                selectedDeviceID = nil
            }
            let validIDs = Set(store.devices.map(\.id))
            let pruned = selectedDeviceIDs.intersection(validIDs)
            if pruned != selectedDeviceIDs {
                selectedDeviceIDs = pruned
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .prodlinkOpenExternalDeviceSettings)) { note in
            guard let id = note.object as? ExternalDeviceConfig.ID else { return }
            guard store.devices.contains(where: { $0.id == id }) else { return }
            openEditor(for: id, proxy: proxy)
        }
        .sheet(isPresented: $showingEditor, onDismiss: handleEditorDismiss) {
            if let binding = selectedBinding {
                VStack(spacing: 0) {
                    HStack {
                        Text("Edit Device")
                            .font(.headline)
                        Spacer()
                        Button("Cancel") {
                            didConfirmNewDevice = false
                            showingEditor = false
                        }
                        .keyboardShortcut(.cancelAction)
                        Button("Save") {
                            // Changes are applied live via onChange in the editor,
                            // so Save simply closes the sheet.
                            didConfirmNewDevice = true
                            showingEditor = false
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding([.top, .horizontal])

                    Divider()

                    ExternalDeviceDetailEditor(device: binding) {
                        store.updateDevice(binding.wrappedValue)
                    }
                    .padding()
                }
                .frame(minWidth: 420, minHeight: 360)
            } else {
                Text("No device selected.")
                    .padding()
            }
        }

#if os(macOS)
        return withLifecycle.toolbar { }
#else
        return withLifecycle.toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                externalDevicesToolbar(proxy: proxy)
            }
        }
#endif
    }

    private func headerRow(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
#if os(macOS)
            Text("External Devices")
                .font(.headline)

            Button {
                isShowingHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $isShowingHelp, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("External Devices")
                        .font(.headline)
                    Text("Add devices to show their status, control them from modules, or keep a shared device list across dashboards.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tip: Use search to find devices by name, model, or IP.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(width: 280)
            }
#endif

            Spacer()

#if os(iOS)
            if editMode == .active || isSelectingDevices {
                Button("Done") {
                    stopListEditingModes()
                }
                .buttonStyle(.bordered)
            }
#else
            if isReorderingActive {
                Button("Done") {
                    stopListEditingModes()
                }
                .buttonStyle(.bordered)
            }
#endif

#if os(macOS)
            Button {
                store.addDevice()
                if let last = store.devices.last {
                    selectedDeviceID = last.id
                    selectedDeviceIDs = [last.id]
                    pendingNewDeviceID = last.id
                    didConfirmNewDevice = false
                    showingEditor = true
                    expandedKinds.insert(last.kind)
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .center)
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.body)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .labelStyle(.iconOnly)
            .help("Add Device")
            .accessibilityLabel("Add Device")

            Button {
                showsDiscoverySheet = true
            } label: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.body)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .labelStyle(.iconOnly)
            .help("Scan Network")
            .accessibilityLabel("Scan Network")

            Menu {
                Button(isReorderingActive ? "Done Reordering" : "Reorder Devices") {
                    toggleReorderingMode()
                }
                Divider()
                Button("Collapse All") {
                    expandedKinds.removeAll()
                }
                Button("Expand All") {
                    expandedKinds = Set(ExternalDeviceKind.allCases)
                }
                Divider()
                Button("Resync Devices") {
                    startResyncDevices()
                }
                Divider()
                Button("Delete Selected", role: .destructive) {
                    pendingDeleteDeviceIDs = Array(selectedDeviceIDs)
                }
                .disabled(selectedDeviceIDs.isEmpty)
                Button("Delete All Devices", role: .destructive) {
                    pendingDeleteAllDevices = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .labelStyle(.iconOnly)
            .menuStyle(.borderlessButton)
            .help("More Actions")
#endif
        }
    }

#if os(macOS)
    private var searchRow: some View {
        HStack {
            TextField("Search devices", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
            Spacer()
        }
    }
#endif

    private func externalDevicesToolbar(proxy: ScrollViewProxy) -> some View {
        Group {
            Button {
                store.addDevice()
                if let last = store.devices.last {
                    selectedDeviceID = last.id
                    selectedDeviceIDs = [last.id]
                    pendingNewDeviceID = last.id
                    didConfirmNewDevice = false
                    showingEditor = true
                    expandedKinds.insert(last.kind)
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .center)
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .help("Add Device")
            .accessibilityLabel("Add Device")

            Button {
                showsDiscoverySheet = true
            } label: {
                Image(systemName: "dot.radiowaves.left.and.right")
            }
            .help("Scan Network")
            .accessibilityLabel("Scan Network")

            Menu {
                Button("External Devices Help") {
                    isShowingHelp = true
                }
                Divider()
                Button(isReorderingActive ? "Done Reordering" : "Reorder Devices") {
                    toggleReorderingMode()
                }
                Divider()
                Button("Collapse All") {
                    expandedKinds.removeAll()
                }
                Button("Expand All") {
                    expandedKinds = Set(ExternalDeviceKind.allCases)
                }
                Divider()
                Button("Delete Selected", role: .destructive) {
                    pendingDeleteDeviceIDs = Array(selectedDeviceIDs)
                }
                .disabled(selectedDeviceIDs.isEmpty)
                Button("Delete All Devices", role: .destructive) {
                    pendingDeleteAllDevices = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("More Actions")
#if os(iOS)
            .popover(isPresented: $isShowingHelp, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("External Devices")
                        .font(.headline)
                    Text("Add devices to show their status, control them from modules, or keep a shared device list across dashboards.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tip: Use search to find devices by name, model, or IP.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(width: 280)
            }
#endif
        }
    }

    private var discoverySheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Network Scan")
                        .font(.headline)
                    Spacer()
                    Button(allDiscoverySelected ? "Unselect All" : "Select All") {
                        if allDiscoverySelected {
                            clearAllDiscoverySelections()
                        } else {
                            selectAllDiscoverySelections()
                        }
                    }
                    .buttonStyle(.bordered)
                    Button {
                        if discoveryService.isScanning {
                            discoveryService.stopScan()
                        } else {
                            discoveryService.startScan()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if discoveryService.isScanning {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                            Text(discoveryService.isScanning ? "Stop" : "Scan")
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Text(discoveryService.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Shure ANX4 / ADTD / ADTQ devices do not respond to network discovery and must be added manually by IP.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if discoveryService.statusText.contains("Local Network permission") {
#if os(macOS)
                    Button("Open Local Network Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
#endif
                    Text("Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                List {
                    ForEach(discoveryResultsByKind, id: \.0) { kind, results in
                        Section(kind.displayName) {
                            ForEach(results) { result in
                                let isSelected = selectedDiscoveryKeys.contains(discoveryKey(for: result))
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(result.name)
                                                .font(.body)
                                            if result.isProvisional {
                                                Text("Provisional")
                                                    .font(.caption2)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
                                            }
                                        }
                                        Text(detailLine(for: result))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        toggleDiscoverySelection(result)
                                    } label: {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .imageScale(.large)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    toggleDiscoverySelection(result)
                                }
                            }
                        }
                    }

                    if discoveryService.results.isEmpty {
                        Section {
                            Text("No devices discovered yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
#if os(iOS)
            .listStyle(.insetGrouped)
#else
            .listStyle(.inset)
#endif
            HStack {
                Button("Cancel") {
                    selectedDiscoveryKeys.removeAll()
                    discoveryService.stopScan()
                    showsDiscoverySheet = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: {
                    let addedDevices = addSelectedDiscoveryResults()
                    autoSyncX32AfterDiscovery(addedDevices)
                    autoSyncDLiveAfterDiscovery(addedDevices)
                    selectedDiscoveryKeys.removeAll()
                    discoveryService.stopScan()
                    showsDiscoverySheet = false
                    var shureDevices = store.devices.filter { $0.kind == .shureWireless }
                    guard !shureDevices.isEmpty else { return }
                    let backfillCount = applyShureSLPDeviceIDBackfill(devices: shureDevices)
                    if backfillCount > 0 {
                        shureDevices = store.devices.filter { $0.kind == .shureWireless }
                    }
                    startShureRefresh(devices: shureDevices)
                }) {
                    Text("Done")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDiscoveryKeys.isEmpty)
            }
            }
            .padding(16)
            .onAppear {
                selectedDiscoveryKeys.removeAll()
                discoveryService.startScan()
            }
            .onDisappear {
                discoveryService.stopScan()
            }

        .frame(minWidth: 520, minHeight: 520)
    }

    }

    private var shureRefreshSheet: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Refreshing Devices")
                .font(.headline)
            Text(shureRefreshStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 320, minHeight: 200)
    }

    private var discoveryResultsByKind: [(ExternalDeviceKind, [ExternalDeviceDiscoveryResult])] {
        let grouped = Dictionary(grouping: discoveryService.results) { $0.kind }
        return grouped
            .sorted { $0.key.displayName.localizedCaseInsensitiveCompare($1.key.displayName) == .orderedAscending }
            .map { (kind: $0.key, results: $0.value) }
    }

    private func detailLine(for result: ExternalDeviceDiscoveryResult) -> String {
        let ipLine = "\(result.displayHost):\(result.port)"
        let model = normalizedShureModelName(result.model)
        if let model, !model.isEmpty {
            return "\(model) - \(ipLine)"
        }
        return ipLine
    }

    private func discoveryKey(for result: ExternalDeviceDiscoveryResult) -> String {
        "\(result.kind.rawValue)|\(result.storedHost)|\(resolvedDiscoveryPort(for: result))"
    }

    private func resolvedDiscoveryPort(for result: ExternalDeviceDiscoveryResult) -> UInt16 {
        if result.kind == .shureWireless {
            return 2202
        }
        return result.port
    }

    private func resolvedShureDeviceIDName(for result: ExternalDeviceDiscoveryResult) -> String? {
        guard result.kind == .shureWireless else { return nil }

        if let uacn = result.shureUacn, uacn.uppercased().contains("IEM") {
            return uacn.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if result.serviceType == "slp-udp-8427" {
            if let model = normalizedShureModelName(result.model),
               result.name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                == model.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
                return nil
            }
            return result.name
        }

        let slpMatch = discoveryService.results.first {
            $0.kind == .shureWireless &&
            $0.serviceType == "slp-udp-8427" &&
            $0.storedHost == result.storedHost
        }

        if let slpMatch {
            if let uacn = slpMatch.shureUacn, uacn.uppercased().contains("IEM") {
                return uacn.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let model = normalizedShureModelName(slpMatch.model),
               slpMatch.name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                == model.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
                return nil
            }
            return slpMatch.name
        }

        return nil
    }

    private func applyShureSLPDeviceIDBackfill(devices: [ExternalDeviceConfig]) -> Int {
        guard !discoveryService.results.isEmpty else { return 0 }
        var updates = 0
        for device in devices where device.kind == .shureWireless {
            if let existing = device.shureDeviceIDName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !existing.isEmpty {
                continue
            }
            if let uacn = device.shureDiscoveryUACN,
               uacn.uppercased().contains("IEM") {
                let trimmed = uacn.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    store.updateShureDeviceIDName(deviceID: device.id, name: trimmed)
                    updates += 1
                }
                continue
            }
            guard let slpMatch = discoveryService.results.first(where: {
                $0.kind == .shureWireless &&
                $0.serviceType == "slp-udp-8427" &&
                $0.storedHost == device.host
            }) else { continue }
            if let uacn = slpMatch.shureUacn,
               uacn.uppercased().contains("IEM") {
                let trimmed = uacn.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    store.updateShureDeviceIDName(deviceID: device.id, name: trimmed)
                    updates += 1
                }
            }
        }
#if DEBUG
        if updates > 0 {
            print("[ExternalDevices] Shure SLP device ID backfill applied count=\(updates)")
        }
#endif
        return updates
    }

    private func resolvedShureModelIdentifier(for result: ExternalDeviceDiscoveryResult) -> String? {
        guard result.kind == .shureWireless else { return result.model }

        let slpMatch = discoveryService.results.first {
            $0.kind == .shureWireless &&
            $0.serviceType == "slp-udp-8427" &&
            $0.storedHost == result.storedHost
        }

        if let model = ShureNetworkModel.mostSpecific(from: [
            slpMatch?.model,
            result.model,
            slpMatch?.name,
            result.name
        ]) {
            return model.rawValue
        }

        let raw = slpMatch?.model ?? result.model
        return normalizedShureModelName(raw)
    }

    private func normalizedShureModelName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let upper = trimmed.uppercased()
        if upper.contains("PSM1000") {
            return "P10T"
        }
        if upper.contains("PSM900") {
            return "P9T"
        }
        if upper.contains("MCR AD") || upper.contains("MCR_AD") {
            return "ANX4"
        }
        if upper.hasSuffix("_RX") || upper.hasSuffix("-RX") {
            return String(trimmed.dropLast(3))
        }
        if upper.hasSuffix("_TX") || upper.hasSuffix("-TX") {
            return String(trimmed.dropLast(3))
        }
        return trimmed
    }

    private func startResyncDevices() {
        let shureDevices = store.devices.filter { $0.kind == .shureWireless }
        let x32Devices = store.devices.filter { device in
            device.kind == .audioConsole && device.isEnabled && isX32FamilyModel(device.consoleModelIdentifier)
        }
        guard !shureDevices.isEmpty || !x32Devices.isEmpty else { return }

        isRefreshingShureAfterScan = true
        let refreshToken = UUID()
        shureRefreshToken = refreshToken
        shureRefreshStatus = "Resyncing devices…"

        Task.detached(priority: .utility) {
            // Hard stop so the modal can't hang forever.
            Task.detached(priority: .background) {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                await MainActor.run {
                    guard isRefreshingShureAfterScan, shureRefreshToken == refreshToken else { return }
                    shureRefreshStatus = "Timed out refreshing devices."
                    isRefreshingShureAfterScan = false
                }
            }

            if !shureDevices.isEmpty {
                await runShureRefresh(devices: shureDevices, refreshToken: refreshToken)
            }

            if !x32Devices.isEmpty {
                await runX32Resync(devices: x32Devices, refreshToken: refreshToken)
            }

            await MainActor.run {
                if shureRefreshToken == refreshToken {
                    isRefreshingShureAfterScan = false
                }
            }
        }
    }

    private func startShureRefresh(devices: [ExternalDeviceConfig]) {
        guard !devices.isEmpty else { return }

        isRefreshingShureAfterScan = true
        let refreshToken = UUID()
        shureRefreshToken = refreshToken
        shureRefreshStatus = "Refreshing Shure devices…"

        Task.detached(priority: .utility) {
            // Hard stop so the modal can't hang forever.
            Task.detached(priority: .background) {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                await MainActor.run {
                    guard isRefreshingShureAfterScan, shureRefreshToken == refreshToken else { return }
                    shureRefreshStatus = "Timed out refreshing Shure devices."
                    isRefreshingShureAfterScan = false
                }
            }

            await runShureRefresh(devices: devices, refreshToken: refreshToken)

            await MainActor.run {
                if shureRefreshToken == refreshToken {
                    isRefreshingShureAfterScan = false
                }
            }
        }
    }

    private func runShureRefresh(devices: [ExternalDeviceConfig], refreshToken: UUID) async {
        let p10tDevices = devices.filter { Self.isP10TDevice($0) }
        let nonP10tDevices = devices.filter { !Self.isP10TDevice($0) }
#if DEBUG
        print("[ExternalDevices] Shure refresh classification p10t=\(p10tDevices.count) nonP10t=\(nonP10tDevices.count)")
        for device in p10tDevices {
            let model = device.shureModelIdentifier ?? ""
            let uacn = device.shureDiscoveryUACN ?? ""
            let fctn = device.shureDiscoveryFCTN ?? ""
            print("[ExternalDevices] Shure refresh P10T device=\(device.name) host=\(device.host):\(device.port) model=\(model) uacn=\(uacn) fctn=\(fctn)")
        }
#endif
        let p10tSnapshot = p10tDevices
        let nonP10tSnapshot = nonP10tDevices

        async let nonP10tRefresh: Void = {
            let total = nonP10tSnapshot.count
            var completedCount = 0
            var timeoutCount = 0
            let maxConcurrent = 4
            var iterator = Array(nonP10tSnapshot.enumerated()).makeIterator()

            await withTaskGroup(of: (Int, Bool, ExternalDeviceConfig).self) { group in
                func submitNext() {
                    guard let next = iterator.next() else { return }
                    let (index, device) = next
                    group.addTask {
                        let shouldContinue = await MainActor.run {
                            isRefreshingShureAfterScan && shureRefreshToken == refreshToken
                        }
                        guard shouldContinue else { return (index, false, device) }
                        let label = "(\(index + 1)/\(total)) \(device.name) \(device.host)"
                        await MainActor.run {
                            shureRefreshStatus = "Refreshing \(label)…"
                        }
                        let completed = await Self.refreshShureAfterScanWithTimeout(device)
                        if completed {
                            await MainActor.run {
                                store.updateDevice(id: device.id) { device in
                                    device.lastChannelSyncAt = Date()
                                }
                            }
                        }
                        return (index, completed, device)
                    }
                }

                if total > 0 {
                    for _ in 0..<min(maxConcurrent, total) {
                        submitNext()
                    }

                    while let (_, completed, device) = await group.next() {
                        if completed {
                            completedCount += 1
                        } else {
                            timeoutCount += 1
                            let label = "\(device.name) \(device.host)"
                            await MainActor.run {
                                shureRefreshStatus = "Timed out \(label)"
                            }
#if DEBUG
                            print("[ExternalDevices] Shure refresh timed out device=\(device.name) host=\(device.host):\(device.port)")
#endif
                        }
                        submitNext()
                    }
                }
            }
#if DEBUG
            if completedCount < total {
                print("[ExternalDevices] Shure refresh incomplete completed=\(completedCount) total=\(total) timeouts=\(timeoutCount)")
            } else {
                print("[ExternalDevices] Shure refresh complete completed=\(completedCount) total=\(total)")
            }
#endif
        }()

        if !p10tSnapshot.isEmpty {
#if DEBUG
            print("[ExternalDevices] Shure P10T post-refresh start count=\(p10tSnapshot.count)")
#endif
            for (index, device) in p10tSnapshot.enumerated() {
#if DEBUG
                let existing = device.shureDeviceIDName ?? ""
                print("[ExternalDevices] Shure P10T device ID refresh start device=\(device.name) host=\(device.host):\(device.port) existing=\(existing)")
#endif
                let label = "(\(index + 1)/\(p10tSnapshot.count)) \(device.name) \(device.host)"
                await MainActor.run {
                    shureRefreshStatus = "Refreshing \(label) names…"
                }
                _ = await ShureWirelessService.refreshDeviceIDNameSync(
                    for: device,
                    allowP10T: true,
                    forceRefresh: true,
                    timeoutSeconds: 8.0
                )
                await MainActor.run {
                    shureRefreshStatus = "Refreshing \(label) channel names…"
                }
                _ = await ShureWirelessService.refreshChannelNamesSync(
                    for: device,
                    timeoutSeconds: 3.0
                )
                await MainActor.run {
                    store.updateDevice(id: device.id) { device in
                        device.lastChannelSyncAt = Date()
                    }
                }
            }
#if DEBUG
            print("[ExternalDevices] Shure P10T post-refresh done")
#endif
        }

        _ = await nonP10tRefresh
        Task.detached(priority: .utility) {
#if DEBUG
            print("[ExternalDevices] Shure device ID post-refresh start count=\(devices.count)")
#endif

            for device in nonP10tSnapshot {
                await ShureWirelessService.refreshDeviceIDName(for: device)
            }

#if DEBUG
            print("[ExternalDevices] Shure device ID post-refresh done")
#endif
        }

#if DEBUG
        print("[ExternalDevices] Shure refresh main loop complete")
#endif
    }

    private func runX32Resync(devices: [ExternalDeviceConfig], refreshToken: UUID) async {
        let total = devices.count
        for (index, device) in devices.enumerated() {
            let shouldContinue = await MainActor.run {
                isRefreshingShureAfterScan && shureRefreshToken == refreshToken
            }
            guard shouldContinue else { return }

            let label = "(\(index + 1)/\(total)) \(device.name) \(device.host)"
            await MainActor.run {
                shureRefreshStatus = "Syncing X32 \(label)…"
            }

            let map = await ConsoleConnectorRegistry.shared
                .syncX32ChannelNames(externalDeviceId: device.id, channelCount: 32, timeout: 2.0)

            if map.isEmpty {
                await MainActor.run {
                    shureRefreshStatus = "No channel names returned for \(device.name)."
                }
            } else {
                let now = Date()
                await MainActor.run {
                    store.updateDevice(id: device.id) { device in
                        device.lastChannelSyncAt = now
                    }
                }
                persistX32Sync(map: map, at: now, deviceID: device.id)
            }

            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func persistX32Sync(map: [Int: String], at: Date, deviceID: UUID) {
        let mapKey = "prodlink.x32sync.map.\(deviceID.uuidString)"
        let tsKey = "prodlink.x32sync.ts.\(deviceID.uuidString)"
        do {
            let data = try JSONEncoder().encode(map)
            UserDefaults.standard.set(data, forKey: mapKey)
        } catch {
            UserDefaults.standard.removeObject(forKey: mapKey)
        }
        UserDefaults.standard.set(at.timeIntervalSince1970, forKey: tsKey)
    }

    private func persistDLiveSync(map: [Int: String], at: Date, deviceID: UUID) {
        let mapKey = "prodlink.ah.sync.map.\(deviceID.uuidString)"
        let tsKey = "prodlink.ah.sync.ts.\(deviceID.uuidString)"
        do {
            let data = try JSONEncoder().encode(map)
            UserDefaults.standard.set(data, forKey: mapKey)
        } catch {
            UserDefaults.standard.removeObject(forKey: mapKey)
        }
        UserDefaults.standard.set(at.timeIntervalSince1970, forKey: tsKey)
        UserDefaults.standard.removeObject(forKey: "prodlink.dlive.sync.map.\(deviceID.uuidString)")
        UserDefaults.standard.removeObject(forKey: "prodlink.dlive.sync.ts.\(deviceID.uuidString)")
    }

    private static nonisolated func refreshShureAfterScanWithTimeout(_ device: ExternalDeviceConfig) async -> Bool {
        let isP10T = Self.isP10TDevice(device)

#if DEBUG
        print("[ExternalDevices] Shure refresh task start device=\(device.name) host=\(device.host):\(device.port)")
#endif

        if isP10T {
            // Skip P10T during the concurrent phase; a sequential pass runs later.
            return true
        }

        let timeout: TimeInterval = 18.0
        return await withTaskGroup(of: (Bool, Bool)?.self) { group in
            group.addTask {
                let result = await ShureWirelessService.refreshShureAfterScan(for: device)
                return result
            }
            group.addTask {
                let nanos = UInt64(max(0, timeout) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                return nil
            }
            let resultTuple = await group.next() ?? nil
            group.cancelAll()
            let result = resultTuple.map { $0.0 || $0.1 } ?? false
#if DEBUG
            if let resultTuple {
                print("[ExternalDevices] Shure refresh task done device=\(device.name) idOK=\(resultTuple.0) channelOK=\(resultTuple.1)")
            } else {
                print("[ExternalDevices] Shure refresh task timeout device=\(device.name)")
            }
#endif
            return result
        }
    }

    private func toggleDiscoverySelection(_ result: ExternalDeviceDiscoveryResult) {
        let key = discoveryKey(for: result)
        if selectedDiscoveryKeys.contains(key) {
            selectedDiscoveryKeys.remove(key)
        } else {
            selectedDiscoveryKeys.insert(key)
        }
    }

    private func addSelectedDiscoveryResults() -> [ExternalDeviceConfig] {
        let selectedKeys = selectedDiscoveryKeys
        guard !selectedKeys.isEmpty else { return [] }
        var added: [ExternalDeviceConfig] = []
        for result in discoveryService.results {
            let key = discoveryKey(for: result)
            guard selectedKeys.contains(key) else { continue }
            let resolvedPort = resolvedDiscoveryPort(for: result)
            let shureDeviceIDName = resolvedShureDeviceIDName(for: result)
            let shureModelIdentifier = resolvedShureModelIdentifier(for: result)
            let psmSessionHost = result.shureSdtHost
            let psmSessionPort = result.shureSdtPort
            #if DEBUG
            print("[ExternalDeviceScan] add name=\(result.name) kind=\(result.kind.rawValue) host=\(result.storedHost) port=\(resolvedPort) service=\(result.serviceType)")
            #endif
            if result.kind == .shureWireless, WirelessLoggingPreferences.shureMasterVerbose {
                let modelDescription = shureModelIdentifier ?? result.model ?? "unknown"
                RelayDiagnosticsStore.shared.recordShureTrace(
                    "discovery add_device name=\(result.name) host=\(result.storedHost) port=\(resolvedPort) service=\(result.serviceType) model=\(modelDescription)"
                )
            }
            let device = store.addDevice(
                name: result.name,
                kind: result.kind,
                host: result.storedHost,
                port: resolvedPort,
                consoleModelIdentifier: result.consoleModelIdentifier,
                consoleSubmodelIdentifier: result.consoleSubmodelIdentifier,
                shureModelIdentifier: shureModelIdentifier,
                shureDeviceIDName: shureDeviceIDName,
                psmSessionHost: psmSessionHost,
                psmSessionPort: psmSessionPort,
                shureDiscoveryCID: result.shureCID,
                shureDiscoveryUACN: result.shureUacn,
                shureDiscoveryFCTN: result.shureFctn,
                shureSdtHost: result.shureSdtHost,
                shureSdtPort: result.shureSdtPort,
                shureDiscoveryDDLURL: result.shureDdlURL
            )
            added.append(device)
        }
        return added
    }

    private var allDiscoverySelected: Bool {
        let allKeys = Set(discoveryService.results.map { discoveryKey(for: $0) })
        return !allKeys.isEmpty && allKeys.isSubset(of: selectedDiscoveryKeys)
    }

    private func selectAllDiscoverySelections() {
        selectedDiscoveryKeys = Set(discoveryService.results.map { discoveryKey(for: $0) })
    }

    private func clearAllDiscoverySelections() {
        selectedDiscoveryKeys.removeAll()
    }

    private var devicesList: some View {
        List(selection: $selectedDeviceIDs) {
            if isReorderingActive {
                let orderedDevices = store.devices.filter { !hiddenKinds.contains($0.kind) }
                ForEach(orderedDevices) { device in
                    deviceRow(device)
                }
                #if os(iOS)
                .onMove(perform: moveDevices)
                #endif
            } else if devicesGroupedByKind.isEmpty {
                emptyDevicesView
            } else {
                ForEach(devicesGroupedByKind, id: \.kind) { group in
                    DisclosureGroup(isExpanded: isExpandedBinding(for: group.kind)) {
                        ForEach(group.devices) { device in
                            deviceRow(device)
                        }
                    } label: {
                        groupHeader(group)
                    }
                }
            }
        }
        .listStyle(.inset)
        .focused($isListFocused)
        .focusable(true)
        #if os(iOS)
        .environment(\.editMode, .constant(listEditMode))
        #endif
#if os(macOS)
        .onDeleteCommand {
            let ids = Array(selectedDeviceIDs)
            if ids.count == 1, let device = store.devices.first(where: { $0.id == ids[0] }) {
                pendingDeleteDevice = device
            } else if !ids.isEmpty {
                pendingDeleteDeviceIDs = ids
            }
        }
#endif
    }

    private var emptyDevicesView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No devices match your search.")
                .font(.subheadline)
            Text("Try a different name, model, or IP address.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func groupHeader(_ group: (kind: ExternalDeviceKind, devices: [ExternalDeviceConfig])) -> some View {
        HStack(spacing: 8) {
            Image(systemName: group.kind.systemImage)
            Text(group.kind.displayName)
                .font(.headline)
            Spacer()
            Text("\(group.devices.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func syncStatusText(for device: ExternalDeviceConfig) -> String {
        guard deviceSupportsChannelSync(device) else {
            return "Sync: n/a"
        }

        let timestamp: Date?
        switch device.kind {
        case .shureWireless:
            timestamp = device.lastChannelSyncAt
        case .audioConsole:
            timestamp = device.lastChannelSyncAt ?? loadX32SyncTimestamp(for: device.id)
        default:
            timestamp = nil
        }

        if let timestamp {
            return "Sync: \(timestamp.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Sync: Not yet"
    }

    private func deviceSupportsChannelSync(_ device: ExternalDeviceConfig) -> Bool {
        switch device.kind {
        case .shureWireless:
            return !isPSM900(device)
        case .audioConsole:
            guard let model = device.audioConsoleModel else { return false }
            switch model {
            case .behringerX32, .midasM32:
                return true
            case .allenHeathDlive, .allenHeathAvantis, .allenHeathSq:
                return true
            case .digico:
                return true  // DiGiCo supports OSC channel sync
            case .allenHeathQu:
                return false
            default:
                return false
            }
        default:
            return false
        }
    }

    private func loadX32SyncTimestamp(for deviceID: UUID) -> Date? {
        let key = "prodlink.x32sync.ts.\(deviceID.uuidString)"
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        let ts = UserDefaults.standard.double(forKey: key)
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    private func deviceRow(_ device: ExternalDeviceConfig) -> some View {
        HStack {
            Image(systemName: device.kind.systemImage)

            VStack(alignment: .leading, spacing: 2) {
                if device.kind == .shureWireless {
                    let deviceIDName = device.shureDeviceIDName?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let primaryName = (deviceIDName?.isEmpty == false) ? deviceIDName! : device.name
                    Text(primaryName)
                        .font(.body)

                    let modelName = (device.shureModelIdentifier ?? device.name).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !modelName.isEmpty {
                        Text("Model: \(modelName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(device.name)
                        .font(.body)
                }

                if !(device.kind == .shureWireless && isPSM900(device)) {
                    let hostPort = "\(device.host):\(String(device.port))"
                    let brandPrefix: String = {
                        guard device.kind == .audioConsole else {
                            return ""
                        }
                        if let model = device.audioConsoleModel {
                            return "\(model.displayName) - "
                        }
                        return "Audio Console - "
                    }()
                    Text(brandPrefix + hostPort)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(syncStatusText(for: device))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

#if os(macOS)
            if isReorderingActive {
                HStack(spacing: 6) {
                    Button {
                        moveDeviceUp(device)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canMoveUp(device))

                    Button {
                        moveDeviceDown(device)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canMoveDown(device))
                }
            } else {
                HStack(spacing: 6) {
                    if device.kind == .sennheiserWireless || device.audioConsoleModel?.isBeta == true {
                        BetaBadgeView(fontSize: 9)
                    }
                    Text(device.kind.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
#else
            HStack(spacing: 6) {
                if device.kind == .sennheiserWireless || device.audioConsoleModel?.isBeta == true {
                    BetaBadgeView(fontSize: 9)
                }
                Text(device.kind.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
#endif
        }
        .padding(.vertical, 8)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .onTapGesture {
            handleDeviceTap(device)
            isListFocused = true
        }
        .onTapGesture(count: 2) {
            guard !isReorderingActive else { return }
#if os(iOS)
            guard !isSelectingDevices else { return }
#endif
            selectedDeviceID = device.id
            selectedDeviceIDs = [device.id]
            showingEditor = true
        }
        .contextMenu {
#if os(macOS)
            if selectedDeviceIDs.count > 1 && selectedDeviceIDs.contains(device.id) {
                Button("Delete Selected", role: .destructive) {
                    pendingDeleteDeviceIDs = Array(selectedDeviceIDs)
                }
            } else {
                Button("Edit Device") {
                    selectedDeviceID = device.id
                    selectedDeviceIDs = [device.id]
                    showingEditor = true
                }
                Divider()
                Button("Delete Device", role: .destructive) {
                    pendingDeleteDevice = device
                }
                Divider()
                Button("Move Up") {
                    moveDeviceUp(device)
                }
                .disabled(!canMoveUp(device))
                Button("Move Down") {
                    moveDeviceDown(device)
                }
                .disabled(!canMoveDown(device))
            }
#else
            Button("Edit Device") {
                selectedDeviceID = device.id
                selectedDeviceIDs = [device.id]
                showingEditor = true
            }
            Divider()
            Button("Delete Device", role: .destructive) {
                pendingDeleteDevice = device
            }
            Divider()
            Button("Move Up") {
                moveDeviceUp(device)
            }
            .disabled(!canMoveUp(device))
            Button("Move Down") {
                moveDeviceDown(device)
            }
            .disabled(!canMoveDown(device))
#endif
        }
        .id(device.id)
        .tag(device.id)
    }

    private var footerHint: some View {
        let hintText: String = {
            if isReorderingActive {
                return "Reorder devices, then click “Done Reordering” when finished."
            }
            if isSelectingDevices {
#if os(iOS)
                return "Tap devices to select multiple items, then use More Actions to delete them."
#else
                return "Command-click toggles devices and Shift-click selects ranges."
#endif
            }
#if os(iOS)
            return "Double-tap a device to edit its settings."
#else
            return "Double-click a device to edit its settings. Command-click toggles devices and Shift-click selects ranges."
#endif
        }()
        return Text(hintText)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    // MARK: - Edit-Only Body

    private var editDeviceOnlyBody: some View {
        let isPro = subscriptionManager.hasPro
        return VStack(spacing: 0) {
            HStack {
                Text("Edit Device")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    // Changes are applied live; Save just closes this presentation.
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding([.top, .horizontal])

            Divider()

            Group {
                if let binding = selectedBinding {
                    ExternalDeviceDetailEditor(device: binding) {
                        store.updateDevice(binding.wrappedValue)
                    }
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView()
                        Text("Loading device…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .disabled(!isPro)
            .opacity(isPro ? 1.0 : 0.35)
            .allowsHitTesting(isPro)
        }
        .frame(minWidth: 520, minHeight: 420)
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
        .task(id: initialDeviceID) {
            // Always prefer the deep-linked id.
            if let id = initialDeviceID {
                selectedDeviceID = id
            }

            // If we already have the device loaded, ensure selection sticks.
            if let id = initialDeviceID,
               store.devices.contains(where: { $0.id == id }) {
                selectedDeviceID = id
            }
        }
        .onChange(of: store.devices.map(\.id)) { _, _ in
            // Re-apply selection once devices load.
            if let id = initialDeviceID,
               store.devices.contains(where: { $0.id == id }) {
                if selectedDeviceID != id {
                    selectedDeviceID = id
                }
            }
        }
    }

    // MARK: - Helpers

    private var selectedBinding: Binding<ExternalDeviceConfig>? {
        guard let id = selectedDeviceID else { return nil }
        guard let idx = store.devices.firstIndex(where: { $0.id == id }) else { return nil }

        return Binding(
            get: { store.devices[idx] },
            set: { store.devices[idx] = $0 }
        )
    }

    private func canMoveUp(_ device: ExternalDeviceConfig) -> Bool {
        guard let index = store.devices.firstIndex(where: { $0.id == device.id }) else { return false }
        return index > 0
    }

    private func canMoveDown(_ device: ExternalDeviceConfig) -> Bool {
        guard let index = store.devices.firstIndex(where: { $0.id == device.id }) else { return false }
        return index < store.devices.count - 1
    }

    private func moveDevices(from offsets: IndexSet, to destination: Int) {
        store.devices.move(fromOffsets: offsets, toOffset: destination)
    }

    private func moveDeviceUp(_ device: ExternalDeviceConfig) {
        if let index = store.devices.firstIndex(where: { $0.id == device.id }), index > 0 {
            let element = store.devices.remove(at: index)
            store.devices.insert(element, at: index - 1)
        }
    }

    private func moveDeviceDown(_ device: ExternalDeviceConfig) {
        if let index = store.devices.firstIndex(where: { $0.id == device.id }), index < store.devices.count - 1 {
            let element = store.devices.remove(at: index)
            store.devices.insert(element, at: index + 1)
        }
    }

    private func handleEditorDismiss() {
        guard let newID = pendingNewDeviceID else { return }
        if !didConfirmNewDevice {
            deleteDevices(withIDs: [newID])
        }
        pendingNewDeviceID = nil
        didConfirmNewDevice = false
    }

    private func deleteDevice(_ device: ExternalDeviceConfig) {
        store.devices.removeAll { $0.id == device.id }
        if selectedDeviceID == device.id {
            selectedDeviceID = nil
        }
    }

    private func deleteDevices(withIDs ids: [ExternalDeviceConfig.ID]) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        store.devices.removeAll { idSet.contains($0.id) }
        if let selected = selectedDeviceID, idSet.contains(selected) {
            selectedDeviceID = nil
        }
        selectedDeviceIDs.subtract(idSet)
    }

    private func deleteAllDevices() {
        store.devices.removeAll()
        selectedDeviceID = nil
        selectedDeviceIDs.removeAll()
        pendingDeleteAllDevices = false
    }

    private func toggleSelectionMode() {
        if isSelectingDevices {
            isSelectingDevices = false
            if selectedDeviceIDs.count <= 1 {
                selectedDeviceID = selectedDeviceIDs.first
            } else {
                selectedDeviceID = nil
            }
            return
        }

#if os(iOS)
        editMode = .inactive
#else
        isReordering = false
#endif
        isSelectingDevices = true
        if let selectedDeviceID {
            selectedDeviceIDs = [selectedDeviceID]
        }
    }

    private func toggleReorderingMode() {
        if isSelectingDevices {
            isSelectingDevices = false
        }

#if os(iOS)
        editMode = (editMode == .active) ? .inactive : .active
#else
        isReordering.toggle()
#endif

        if isReorderingActive {
            selectedDeviceIDs.removeAll()
            selectedDeviceID = nil
        }
    }

    private func stopListEditingModes() {
        isSelectingDevices = false
#if os(iOS)
        editMode = .inactive
#else
        isReordering = false
#endif
    }

    private func handleDeviceTap(_ device: ExternalDeviceConfig) {
        guard !isReorderingActive else {
            selectedDeviceID = device.id
            selectedDeviceIDs = [device.id]
            return
        }

#if os(iOS)
        guard isSelectingDevices else {
            selectedDeviceID = device.id
            selectedDeviceIDs = [device.id]
            return
        }
#endif

#if os(macOS)
        let modifierFlags = NSEvent.modifierFlags
        let isShiftSelecting = modifierFlags.contains(.shift)
        let isCommandSelecting = modifierFlags.contains(.command)

        if isShiftSelecting {
            selectDeviceRange(endingAt: device.id, extendingExistingSelection: isCommandSelecting)
            return
        }

        if isCommandSelecting {
            toggleDeviceSelection(device.id)
            return
        }

        selectedDeviceID = device.id
        selectedDeviceIDs = [device.id]
        return
#endif
#if os(iOS)
        toggleDeviceSelection(device.id)
#endif
    }

    private func toggleDeviceSelection(_ deviceID: ExternalDeviceConfig.ID) {
        if selectedDeviceIDs.contains(deviceID) {
            selectedDeviceIDs.remove(deviceID)
        } else {
            selectedDeviceIDs.insert(deviceID)
        }

        if selectedDeviceIDs.count == 1 {
            selectedDeviceID = selectedDeviceIDs.first
        } else {
            selectedDeviceID = deviceID
        }
    }

    private func selectDeviceRange(
        endingAt deviceID: ExternalDeviceConfig.ID,
        extendingExistingSelection: Bool
    ) {
        let orderedIDs = visibleDeviceIDsInListOrder
        guard let endIndex = orderedIDs.firstIndex(of: deviceID) else {
            selectedDeviceID = deviceID
            selectedDeviceIDs = [deviceID]
            return
        }

        let anchorID = selectedDeviceID ?? selectedDeviceIDs.first ?? deviceID
        guard let startIndex = orderedIDs.firstIndex(of: anchorID) else {
            selectedDeviceID = deviceID
            selectedDeviceIDs = [deviceID]
            return
        }

        let lowerBound = min(startIndex, endIndex)
        let upperBound = max(startIndex, endIndex)
        let rangeSelection = Set(orderedIDs[lowerBound...upperBound])

        if extendingExistingSelection {
            selectedDeviceIDs.formUnion(rangeSelection)
        } else {
            selectedDeviceIDs = rangeSelection
        }

        selectedDeviceID = deviceID
    }
}

// MARK: - Detail Editor

private struct ExternalDeviceDetailEditor: View {
    /// Port formatter: non-grouping, decimal, 0-65535, no commas.
    private static let portFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.usesGroupingSeparator = false
        nf.minimum = 0
        nf.maximum = 65535
        return nf
    }()
    /// MIDI Program Change formatter: 0-127.
    private static let midiProgramFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.usesGroupingSeparator = false
        nf.minimum = 0
        nf.maximum = 127
        return nf
    }()

    private static func plainNumberString<T: BinaryInteger>(_ value: T) -> String {
        portFormatter.string(from: NSNumber(value: Int(value))) ?? String(value)
    }

    @Binding var device: ExternalDeviceConfig
    let onChange: () -> Void

    @StateObject private var shureService = ShureConnectionService()
    @StateObject private var sennheiserService = SennheiserConnectionService()
    @StateObject private var quTestService = QuConnectionTestService()
    @StateObject private var digicoSyncService = DiGiCoConsoleSyncService()
    @State private var localAnx4Mode: ShureAnx4Mode = .axient
    private let visibleKinds: [ExternalDeviceKind] = ExternalDeviceKind.sortedByDisplayName(
        ExternalDeviceKind.allCases.filter { kind in
            if kind == .sennheiserWireless && !sennheiserEnabled {
                return false
            }
            if kind == .vistaConsole && !RelayLicensingConfig.isVistaIntegrationEnabled {
                return false
            }
            return kind != .lightingConsole && kind != .genericOsc
        }
    )

    private func capabilityIndicatorSection(device: ExternalDeviceConfig) -> some View {
        let capabilities = device.consoleCapabilities
        let transports = orderedUniqueTransports(capabilities.transports)
        let sceneSupport = consolidatedSceneSupport(capabilities)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Capabilities")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !transports.isEmpty {
                HStack(spacing: 6) {
                    ForEach(transports, id: \.self) { transport in
                        transportPill(transport)
                    }
                }
            }

            HStack(spacing: 12) {
                capabilityIndicator(label: "Channel Names", support: capabilities.channelNameChange)
                capabilityIndicator(label: "Scenes/Snapshots", support: sceneSupport)
            }
        }
        .padding(.vertical, 2)
    }

    private func orderedUniqueTransports(_ transports: [ConsoleTransport]) -> [ConsoleTransport] {
        var seen = Set<ConsoleTransport>()
        var result: [ConsoleTransport] = []
        for transport in transports {
            if seen.contains(transport) { continue }
            seen.insert(transport)
            result.append(transport)
        }
        return result
    }

    private func shouldShowNetworkSection(for device: ExternalDeviceConfig) -> Bool {
        guard device.kind == .audioConsole else { return true }
        let transports = orderedUniqueTransports(device.consoleCapabilities.transports)
        if transports.contains(.osc) || transports.contains(.tcp) { return true }
        if transports.count == 1, transports.first == .midi { return false }
        return true
    }

    private func consolidatedSceneSupport(_ capabilities: ConsoleCapabilities) -> ConsoleCapabilitySupport {
        if capabilities.sceneRecall == .supported || capabilities.sceneStore == .supported {
            return .supported
        }
        if capabilities.sceneRecall == .unknown || capabilities.sceneStore == .unknown {
            return .unknown
        }
        return .unsupported
    }

    private func capabilityIndicator(label: String, support: ConsoleCapabilitySupport) -> some View {
        let (systemImage, color): (String, Color) = {
            switch support {
            case .supported:
                return ("checkmark.circle.fill", .green)
            case .unsupported:
                return ("xmark.circle", .secondary)
            case .unknown:
                return ("questionmark.circle", .secondary)
            }
        }()
        return HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func transportPill(_ transport: ConsoleTransport) -> some View {
        let label: String
        switch transport {
        case .osc: label = "OSC"
        case .tcp: label = "TCP"
        case .midi: label = "MIDI"
        case .unknown: label = "Unknown"
        }
        return Text(label)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }

#if os(macOS)
    private struct MIDIDeviceOption: Identifiable, Hashable {
        let id: Int32
        let name: String
    }

    private enum MIDIEndpointDiscovery {
        static func currentSources() -> [MIDIDeviceOption] {
            let count = MIDIGetNumberOfSources()
            var result: [MIDIDeviceOption] = []
            result.reserveCapacity(Int(count))

            for i in 0..<count {
                let endpoint = MIDIGetSource(i)
                guard endpoint != 0 else { continue }

                var uniqueID: Int32 = 0
                MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)

                var nameRef: Unmanaged<CFString>?
                MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &nameRef)
                let name = (nameRef?.takeRetainedValue() as String?) ?? "MIDI Source \(i)"

                result.append(MIDIDeviceOption(id: uniqueID, name: name))
            }

            return result
        }

        static func currentDestinations() -> [MIDIDeviceOption] {
            let count = MIDIGetNumberOfDestinations()
            var result: [MIDIDeviceOption] = []
            result.reserveCapacity(Int(count))

            for i in 0..<count {
                let endpoint = MIDIGetDestination(i)
                guard endpoint != 0 else { continue }

                var uniqueID: Int32 = 0
                MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)

                var nameRef: Unmanaged<CFString>?
                MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &nameRef)
                let name = (nameRef?.takeRetainedValue() as String?) ?? "MIDI Destination \(i)"

                result.append(MIDIDeviceOption(id: uniqueID, name: name))
            }

            return result
        }
    }
#endif

    /// Shure/Sennheiser model enums are defined in ExternalDevices.swift for reuse.

    @State private var selectedShureModel: ShureNetworkModel?
    @State private var selectedSennheiserModel: SennheiserNetworkModel?
    @State private var specteraPassword: String = ""
    @State private var isTestingSpecteraConnection = false
    @State private var specteraConnectionSucceeded = false
    @State private var specteraConnectionError: String?
    @State private var specteraCertificateFingerprint: String?
    @State private var specteraConnectionClient = SpecteraClient()

    @State private var showingDiGiCoRTFImporter: Bool = false
    @State private var showingDiGiCoPadHelp: Bool = false
    @State private var showingDiGiCoSyncedChannels: Bool = false
    @State private var showingDLiveHelp: Bool = false
    @State private var showingVistaOSCHelp: Bool = false
    @State private var digicoRTFImportError: String?

    // MARK: X32 / M32 Send Mode (Cues vs Snippets)

    private enum X32ShowSendMode: String, CaseIterable, Identifiable {
        case cues
        case snippets
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .cues: return "Cues"
            case .snippets: return "Snippets"
            }
        }
    }

    @State private var x32ShowSendMode: X32ShowSendMode = .cues

    // MARK: X32 / M32 Sync (channel name pull)
    @State private var isSyncingX32: Bool = false
    @State private var x32SyncError: String?
    @State private var x32LastSyncAt: Date?
    @State private var x32SyncedChannels: [(ch: Int, name: String)] = []
    @State private var showsX32SyncedChannels: Bool = false

    // MARK: Allen & Heath Sync (channel name pull)
    @State private var isSyncingDLive: Bool = false
    @State private var dLiveSyncError: String?
    @State private var dLiveLastSyncAt: Date?
    @State private var dLiveSyncedChannels: [(ch: Int, name: String)] = []
    @State private var showsDLiveSyncedChannels: Bool = false
    @State private var dLiveTargetSelection: String = "dlive_mixrack"

    private var normalizedDLiveTargetIdentifier: String {
        switch device.consoleSubmodelIdentifier {
        case "dlive_surface":
            return "dlive_surface"
        default:
            return "dlive_mixrack"
        }
    }

    private func syncDLiveTargetSelectionFromDevice() {
        let normalized = normalizedDLiveTargetIdentifier
        if dLiveTargetSelection != normalized {
            dLiveTargetSelection = normalized
        }
    }

    private var showsRundownSnapshotSettings: Bool {
        guard let model = device.audioConsoleModel else { return false }
        switch model {
        case .digico, .behringerX32, .midasM32:
            return true
        default:
            return false
        }
    }

#if os(macOS)
    @State private var midiSources: [MIDIDeviceOption] = MIDIEndpointDiscovery.currentSources()
    @State private var midiDestinations: [MIDIDeviceOption] = MIDIEndpointDiscovery.currentDestinations()
#endif

    /// Builds the pill label text for DiGiCo synced channels (e.g. "86 in · 19 aux · 15 grp · 24 mtx · 24 CG").
    /// Returns empty string if nothing has been synced yet.
    private func digicoChannelCountPill(device: ExternalDeviceConfig) -> String {
        guard !device.digicoInputChannels.isEmpty || !device.digicoDiscoveredChannels.isEmpty else { return "" }
        let grouped = Dictionary(grouping: device.digicoDiscoveredChannels, by: \.channelType)
        return [
            device.digicoInputChannels.count > 0 ? "\(device.digicoInputChannels.count) in" : nil,
            (grouped[.auxOutput]?.count   ?? 0) > 0 ? "\(grouped[.auxOutput]!.count) aux"   : nil,
            (grouped[.groupOutput]?.count ?? 0) > 0 ? "\(grouped[.groupOutput]!.count) grp"  : nil,
            (grouped[.matrixOutput]?.count ?? 0) > 0 ? "\(grouped[.matrixOutput]!.count) mtx" : nil,
            (grouped[.controlGroup]?.count ?? 0) > 0 ? "\(grouped[.controlGroup]!.count) CG"  : nil,
        ].compactMap { $0 }.joined(separator: " · ")
    }

    /// Helper to convert a stored map into the preview array.
    private func setSyncedPreview(from map: [Int: String]) {
        x32SyncedChannels = map.keys.sorted().map { ch in (ch: ch, name: map[ch] ?? "") }
    }

    private func setAllenHeathSyncedPreview(from map: [Int: String]) {
        dLiveSyncedChannels = map.keys.sorted().map { ch in (ch: ch, name: map[ch] ?? "") }
    }

    // MARK: - X32 Sync Persistence (stored outside ExternalDeviceConfig)

    private var x32SyncMapDefaultsKey: String {
        "prodlink.x32sync.map.\(device.id.uuidString)"
    }

    private var x32SyncTimestampDefaultsKey: String {
        "prodlink.x32sync.ts.\(device.id.uuidString)"
    }

    private var x32ShowSendModeDefaultsKey: String {
        "prodlink.x32show.sendmode.\(device.id.uuidString)"
    }

    private var allenHeathSyncMapDefaultsKey: String {
        "prodlink.ah.sync.map.\(device.id.uuidString)"
    }

    private var allenHeathSyncTimestampDefaultsKey: String {
        "prodlink.ah.sync.ts.\(device.id.uuidString)"
    }

    private var legacyDLiveSyncMapDefaultsKey: String {
        "prodlink.dlive.sync.map.\(device.id.uuidString)"
    }

    private var legacyDLiveSyncTimestampDefaultsKey: String {
        "prodlink.dlive.sync.ts.\(device.id.uuidString)"
    }

    private var allenHeathSyncChannelCount: Int {
        switch device.audioConsoleModel {
        case .allenHeathDlive:
            return 128
        case .allenHeathAvantis, .allenHeathSq:
            return 64
        default:
            return 0
        }
    }

    private var allenHeathSyncFailureHint: String {
        switch device.audioConsoleModel {
        case .allenHeathDlive:
            if device.consoleUseTLS {
                return "No channel names returned. Verify host/IP, endpoint selection, and dLive TLS credentials. Relay uses TLS profile 1 by default, and a blank password is allowed when that profile has no password."
            }
            return "No channel names returned. Verify host/IP, endpoint selection, TLS settings, and that the MixRack is reachable."
        case .allenHeathAvantis:
            return "No channel names returned. Verify host/IP, MIDI channel, and that the Avantis console is reachable on the network."
        case .allenHeathSq:
            return "No channel names returned. Verify host/IP, MIDI channel, and that the SQ console is reachable on the network."
        default:
            return "No channel names returned. Verify host/IP and that the console is reachable."
        }
    }

    private func persistX32Sync(map: [Int: String], at: Date?) {
        do {
            let data = try JSONEncoder().encode(map)
            UserDefaults.standard.set(data, forKey: x32SyncMapDefaultsKey)
        } catch {
            // If encoding fails, clear saved map so we don't keep stale/partial state.
            UserDefaults.standard.removeObject(forKey: x32SyncMapDefaultsKey)
        }

        if let at {
            UserDefaults.standard.set(at.timeIntervalSince1970, forKey: x32SyncTimestampDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: x32SyncTimestampDefaultsKey)
        }
    }

    private func persistX32ShowSendMode(_ mode: X32ShowSendMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: x32ShowSendModeDefaultsKey)
    }

    private func loadPersistedX32ShowSendMode() -> X32ShowSendMode {
        if let raw = UserDefaults.standard.string(forKey: x32ShowSendModeDefaultsKey),
           let mode = X32ShowSendMode(rawValue: raw) {
            return mode
        }
        return .cues
    }

    private func loadPersistedX32Sync() -> (map: [Int: String], at: Date?) {
        var map: [Int: String] = [:]
        if let data = UserDefaults.standard.data(forKey: x32SyncMapDefaultsKey) {
            if let decoded = try? JSONDecoder().decode([Int: String].self, from: data) {
                map = decoded
            }
        }

        var at: Date? = nil
        if UserDefaults.standard.object(forKey: x32SyncTimestampDefaultsKey) != nil {
            let ts = UserDefaults.standard.double(forKey: x32SyncTimestampDefaultsKey)
            if ts > 0 { at = Date(timeIntervalSince1970: ts) }
        }

        return (map, at)
    }

    private func clearPersistedX32Sync() {
        UserDefaults.standard.removeObject(forKey: x32SyncMapDefaultsKey)
        UserDefaults.standard.removeObject(forKey: x32SyncTimestampDefaultsKey)
    }

    private func persistDLiveSync(map: [Int: String], at: Date?) {
        do {
            let data = try JSONEncoder().encode(map)
            UserDefaults.standard.set(data, forKey: allenHeathSyncMapDefaultsKey)
        } catch {
            UserDefaults.standard.removeObject(forKey: allenHeathSyncMapDefaultsKey)
        }

        if let at {
            UserDefaults.standard.set(at.timeIntervalSince1970, forKey: allenHeathSyncTimestampDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: allenHeathSyncTimestampDefaultsKey)
        }
    }

    private func loadPersistedDLiveSync() -> (map: [Int: String], at: Date?) {
        var map: [Int: String] = [:]
        if let data = UserDefaults.standard.data(forKey: allenHeathSyncMapDefaultsKey),
           let decoded = try? JSONDecoder().decode([Int: String].self, from: data) {
            map = decoded
        } else if let data = UserDefaults.standard.data(forKey: legacyDLiveSyncMapDefaultsKey),
                  let decoded = try? JSONDecoder().decode([Int: String].self, from: data) {
            map = decoded
        }

        var at: Date? = nil
        if UserDefaults.standard.object(forKey: allenHeathSyncTimestampDefaultsKey) != nil {
            let ts = UserDefaults.standard.double(forKey: allenHeathSyncTimestampDefaultsKey)
            if ts > 0 { at = Date(timeIntervalSince1970: ts) }
        } else if UserDefaults.standard.object(forKey: legacyDLiveSyncTimestampDefaultsKey) != nil {
            let ts = UserDefaults.standard.double(forKey: legacyDLiveSyncTimestampDefaultsKey)
            if ts > 0 { at = Date(timeIntervalSince1970: ts) }
        }

        return (map, at)
    }

    private func clearPersistedDLiveSync() {
        UserDefaults.standard.removeObject(forKey: allenHeathSyncMapDefaultsKey)
        UserDefaults.standard.removeObject(forKey: allenHeathSyncTimestampDefaultsKey)
        UserDefaults.standard.removeObject(forKey: legacyDLiveSyncMapDefaultsKey)
        UserDefaults.standard.removeObject(forKey: legacyDLiveSyncTimestampDefaultsKey)
    }

    /// Resolve the effective Shure model for this device, preferring an explicit
    /// selection in this editor session, then a persisted identifier, then an
    /// inference from the device name.
    private var resolvedShureModel: ShureNetworkModel? {
        if let explicit = selectedShureModel {
            return explicit
        }
        if let inferred = ShureNetworkModel.mostSpecific(from: [
            device.shureModelIdentifier,
            device.name,
            device.shureDeviceIDName
        ]) {
            return inferred
        }
        return nil
    }

    private var supportsShureUdpTelemetryOverride: Bool {
        guard device.kind == .shureWireless, let model = resolvedShureModel else { return false }
        switch model {
        // Only ANX4/ADTD/ADTQ get this picker. Every other model
        // (AD4/AD4D/AD4Q, ULX-D4Q/D4D, and anything else) always uses TCP
        // -- their UDP sidecars are disabled at the connection level (see
        // isFastUdpTelemetryDisabledByDefault in ShureWirelessModule.swift)
        // rather than left as a user-facing choice that wouldn't actually
        // do anything -- a Transport picker with an inert option is more
        // confusing than no picker at all. ANX4/ADTD/ADTQ genuinely need
        // the choice: some receivers in the field don't have TCP command
        // strings enabled, and UDP is their only working fallback.
        case .anx4, .adtd, .adtq:
            return true
        default:
            return false
        }
    }

    private var usesShureUdpTelemetryOverride: Bool {
        let host = device.shureSdtHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !host.isEmpty || device.shureSdtPort != nil
    }

    private var effectiveShureTransportMode: ShureTransportMode {
        device.shureTransportMode ?? .auto
    }

    private var shouldShowShureUdpTelemetryControls: Bool {
#if DEBUG || BETA
        return supportsShureUdpTelemetryOverride
#else
        return false
#endif
    }

    private func syncPrimaryShurePortIfNeeded() {
        guard device.kind == .shureWireless, device.port != 2202 else { return }
        device.port = 2202
        onChange()
    }

    private func setShureUdpTelemetryOverrideEnabled(_ isEnabled: Bool) {
        if isEnabled {
            let trimmedHost = device.shureSdtHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmedHost.isEmpty {
                let fallbackHost = device.host.trimmingCharacters(in: .whitespacesAndNewlines)
                device.shureSdtHost = fallbackHost.isEmpty ? "127.0.0.1" : fallbackHost
            }
            if device.shureSdtPort == nil || device.shureSdtPort == 0 {
                device.shureSdtPort = 57383
            }
        } else {
            device.shureSdtHost = nil
            device.shureSdtPort = nil
        }
        onChange()
    }

    private func setShureTransportMode(_ mode: ShureTransportMode) {
        device.shureTransportMode = mode
        if mode == .tcpOnly {
            device.shureSdtHost = nil
            device.shureSdtPort = nil
        } else {
            let trimmedHost = device.shureSdtHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmedHost.isEmpty {
                let fallbackHost = device.host.trimmingCharacters(in: .whitespacesAndNewlines)
                device.shureSdtHost = fallbackHost.isEmpty ? "127.0.0.1" : fallbackHost
            }
            if device.shureSdtPort == nil || device.shureSdtPort == 0 {
                device.shureSdtPort = 57383
            }
        }
        onChange()
    }

    private var shureManualChannelCountOptions: [Int] {
        guard let model = resolvedShureModel else { return [] }
        switch model {
        case .anx4:
            let mode = device.shureAnx4Mode ?? .axient
            return Array(1...mode.maxChannels)
        case .adtq:
            return Array(1...16)
        case .adtd:
            return Array(1...8)
        default:
            return []
        }
    }

    private var effectiveShureChannelCount: Int {
        device.effectiveShureChannelCount
    }

    private func applyP10TAutoChannelNamesIfNeeded() {
        guard resolvedShureModel == .p10t else { return }

        let names = device.shureChannelNames
        var didChange = false

        if let name = names[1]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty,
           (device.psmChannel1Name ?? "").isEmpty {
            device.psmChannel1Name = name
            didChange = true
        }

        if let name = names[2]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty,
           (device.psmChannel2Name ?? "").isEmpty {
            device.psmChannel2Name = name
            didChange = true
        }

        if didChange {
            onChange()
        }
    }

    /// Resolve the effective Sennheiser model for this device, preferring an explicit
    /// selection in this editor session, then a persisted identifier, then an
    /// inference from the device name.
    private var resolvedSennheiserModel: SennheiserNetworkModel? {
        if let explicit = selectedSennheiserModel {
            return explicit
        }
        if let code = device.sennheiserModelIdentifier,
           let model = SennheiserNetworkModel(rawValue: code) {
            return model
        }
        return SennheiserNetworkModel.from(deviceName: device.name)
    }

    private var sennheiserPickerModels: [SennheiserNetworkModel] {
        SennheiserNetworkModel.supportedCases
    }

    @ViewBuilder
    private var yamahaMidiSection: some View {
        GroupBox("Yamaha MIDI") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select MIDI input for scene recall feedback and MIDI output for Program Change recall (CL/QL).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

#if os(macOS)
                Picker("MIDI Input", selection: Binding<Int32>(
                    get: { device.yamahaMidiInputSourceID ?? -1 },
                    set: { newValue in
                        device.yamahaMidiInputSourceID = (newValue == -1) ? nil : newValue
                        onChange()
                    }
                )) {
                    Text("Automatic").tag(Int32(-1))
                    ForEach(midiSources) { src in
                        Text(src.name).tag(src.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!device.isEnabled)

                Picker("MIDI Output", selection: Binding<Int32>(
                    get: { device.yamahaMidiOutputDestinationID ?? -1 },
                    set: { newValue in
                        device.yamahaMidiOutputDestinationID = (newValue == -1) ? nil : newValue
                        onChange()
                    }
                )) {
                    Text("Automatic").tag(Int32(-1))
                    ForEach(midiDestinations) { dest in
                        Text(dest.name).tag(dest.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!device.isEnabled)

                Button("Refresh MIDI devices") {
                    midiSources = MIDIEndpointDiscovery.currentSources()
                    midiDestinations = MIDIEndpointDiscovery.currentDestinations()
                }
                .dashboardLinkButtonStyle()
#else
                Text("MIDI device selection is available on macOS.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
#endif
            }
        }
        .disabled(!device.isEnabled)
    }

    @ViewBuilder
    private var yamahaSceneMappingSection: some View {
        GroupBox("Scene Recall Mapping") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Map MIDI Program Change values to Yamaha scene numbers (format: 4.00).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if device.yamahaProgramChangeMappings.isEmpty {
                    Text("No mappings yet.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                ForEach($device.yamahaProgramChangeMappings) { $mapping in
                    HStack(spacing: 10) {
                        DeferredNumberField("PC", value: $mapping.program, formatter: Self.midiProgramFormatter)
                            .frame(width: 60)
                            .onChange(of: mapping.program) { _, newValue in
                                let clamped = max(0, min(127, newValue))
                                if mapping.program != clamped {
                                    $mapping.program.wrappedValue = clamped
                                }
                                onChange()
                            }

                        TextField("Scene (e.g. 4.00)", text: $mapping.sceneNumber)
                            .onChange(of: mapping.sceneNumber) { _, _ in
                                onChange()
                            }

                        Spacer()

                        Button(role: .destructive) {
                            device.yamahaProgramChangeMappings.removeAll { $0.id == mapping.id }
                            onChange()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button("Add Mapping") {
                    device.yamahaProgramChangeMappings.append(
                        YamahaProgramChangeMapping(program: 0, sceneNumber: "1.00")
                    )
                    onChange()
                }
                .buttonStyle(.borderless)
            }
        }
        .disabled(!device.isEnabled)
    }

    @MainActor
    private func runX32Sync(deviceId: UUID) {
        // Avoid overlapping syncs.
        if isSyncingX32 { return }
        isSyncingX32 = true
        x32SyncError = nil

        Task { @MainActor in
            defer { isSyncingX32 = false }

            let map = await ConsoleConnectorRegistry.shared
                .syncX32ChannelNames(externalDeviceId: deviceId, channelCount: 32, timeout: 2.0)

            if map.isEmpty {
                x32SyncedChannels = []
                x32SyncError = "No channel names returned. Verify host/IP, that UDP listen port is allowed, and that the console is reachable."
                return
            }

            // Update local preview UI
            x32LastSyncAt = Date()
            device.lastChannelSyncAt = x32LastSyncAt
            setSyncedPreview(from: map)

            // Persist sync results per-device so they survive reopening settings / app relaunch.
            persistX32Sync(map: map, at: x32LastSyncAt)
            onChange()
        }
    }

    @MainActor
    private func runDLiveSync(deviceId: UUID) {
        if isSyncingDLive { return }
        isSyncingDLive = true
        dLiveSyncError = nil

        Task { @MainActor in
            defer { isSyncingDLive = false }

            let channelCount = allenHeathSyncChannelCount
            let map = await ConsoleConnectorRegistry.shared
                .syncAllenHeathChannelNames(externalDeviceId: deviceId, channelCount: channelCount, timeout: 1.0)

            if map.isEmpty {
                dLiveSyncedChannels = []
                dLiveSyncError = allenHeathSyncFailureHint
                return
            }

            dLiveLastSyncAt = Date()
            device.lastChannelSyncAt = dLiveLastSyncAt
            setAllenHeathSyncedPreview(from: map)
            persistDLiveSync(map: map, at: dLiveLastSyncAt)
            onChange()
        }
    }

    private var basicsSection: some View {
        GroupBox("Basics") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Name", text: $device.name)
                    .onChange(of: device.name) { _, _ in onChange() }

                Picker("Device Type", selection: $device.kind) {
                    ForEach(visibleKinds) { kind in
                        Label(kind.displayName, systemImage: kind.systemImage)
                            .tag(kind)
                    }
                }
                .onChange(of: device.kind) { _, newKind in
                    if newKind == .shureWireless {
                        syncPrimaryShurePortIfNeeded()
                    } else if newKind == .vistaConsole {
                        if device.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || device.name == "New Device" {
                            device.name = "Vista 3"
                        }
                        if device.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || device.host == "192.168.1.100" {
                            device.host = "127.0.0.1"
                        }
                        if device.port == 0 {
                            device.port = 8000
                        }
                        if device.vistaConsoleTarget?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                            device.vistaConsoleTarget = "EX1"
                        }
                    }
                    onChange()
                }

                // Global enable toggle for all devices
                Toggle("Enabled", isOn: $device.isEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: device.isEnabled) { _, _ in onChange() }
            }
        }
    }

    @ViewBuilder
    private var networkSection: some View {
        if shouldShowNetworkSection(for: device) {
            GroupBox("Network") {
                VStack(alignment: .leading, spacing: 8) {
                    // For Shure Wireless devices, hide IP/Port when configured as PSM 900 placeholder.
                    if device.kind == .shureWireless, resolvedShureModel == .psm900 {
                        Text("Network settings are not used for PSM 900 placeholders. No IP address or port is required for this device.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Group {
                            let isQuConsole: Bool = {
                                guard device.kind == .audioConsole,
                                      let modelId = device.consoleModelIdentifier,
                                      let model = AudioConsoleModel.from(identifier: modelId) else {
                                    return false
                                }
                                return model == .allenHeathQu
                            }()
                            let allenHeathConsoleModel: AudioConsoleModel? = {
                                guard device.kind == .audioConsole,
                                      let modelId = device.consoleModelIdentifier,
                                      let model = AudioConsoleModel.from(identifier: modelId) else {
                                    return nil
                                }
                                switch model {
                                case .allenHeathDlive, .allenHeathAvantis, .allenHeathSq:
                                    return model
                                default:
                                    return nil
                                }
                            }()
                            let isDigiCoConsole: Bool = {
                                guard device.kind == .audioConsole,
                                      let modelId = device.consoleModelIdentifier,
                                      AudioConsoleModel.from(identifier: modelId) == .digico else {
                                    return false
                                }
                                return true
                            }()
                            // X32/M32 and WING connectors always send to a fixed OSC port and
                            // never read device.port, so the field is shown read-only here (same
                            // treatment as Allen & Heath below) rather than an editable-but-ignored field.
                            let fixedOSCPort: UInt16? = {
                                guard device.kind == .audioConsole,
                                      let modelId = device.consoleModelIdentifier,
                                      let model = AudioConsoleModel.from(identifier: modelId) else {
                                    return nil
                                }
                                switch model {
                                case .behringerX32, .midasM32:
                                    return 10023
                                case .behringerWing:
                                    return 2223
                                default:
                                    return nil
                                }
                            }()
                            let fixedSennheiserPort: UInt16? = {
                                guard device.kind == .sennheiserWireless,
                                      resolvedSennheiserModel == .specteraBaseStation else {
                                    return nil
                                }
                                return 443
                            }()
                            let fixedAllenHeathPort: UInt16? = {
                                guard let model = allenHeathConsoleModel else { return nil }
                                switch model {
                                case .allenHeathDlive:
                                    let target = normalizedDLiveTargetIdentifier
                                    if target == "dlive_surface" {
                                        return device.consoleUseTLS ? 51329 : 51328
                                    }
                                    return device.consoleUseTLS ? 51327 : 51325
                                case .allenHeathAvantis, .allenHeathSq:
                                    return 51325
                                default:
                                    return nil
                                }
                            }()

                            HStack(spacing: 8) {
                                TextField("Host / IP Address", text: $device.host)
                                    .onChange(of: device.host) { _, _ in onChange() }
                                    .onSubmit {
                                        guard isQuConsole, device.isEnabled else { return }
                                        let trimmed = device.host.trimmingCharacters(in: .whitespacesAndNewlines)
                                        guard !trimmed.isEmpty else { return }
                                        quTestService.test(host: trimmed, port: device.port)
                                    }

                                if isQuConsole {
                                    if quTestService.isTesting {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else if let result = quTestService.lastResult {
                                        Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(result ? Color.green : Color.red)
                                    } else {
                                        Image(systemName: "questionmark.circle")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            if device.kind == .shureWireless {
                                Text("Relay uses the receiver host for Shure devices and manages the command transport automatically.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .onAppear {
                                        syncPrimaryShurePortIfNeeded()
                                    }
                                if shouldShowShureUdpTelemetryControls {
                                    Picker(
                                        "Transport",
                                        selection: Binding(
                                            get: { effectiveShureTransportMode },
                                            set: { setShureTransportMode($0) }
                                        )
                                    ) {
                                        ForEach(ShureTransportMode.allCases) { mode in
                                            Text(mode.displayName).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.menu)

                                    Text(effectiveShureTransportMode.helpText)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)

                                    if effectiveShureTransportMode == .udpPreferred {
                                        DisclosureGroup("Advanced UDP Endpoint") {
                                            VStack(alignment: .leading, spacing: 8) {
                                                HStack(spacing: 8) {
                                                    TextField(
                                                        "UDP Host / IP Address",
                                                        text: Binding(
                                                            get: { device.shureSdtHost ?? "" },
                                                            set: {
                                                                device.shureSdtHost = $0
                                                                onChange()
                                                            }
                                                        )
                                                    )

                                                    TextField(
                                                        "57383",
                                                        value: Binding(
                                                            get: { Int(device.shureSdtPort ?? 57383) },
                                                            set: {
                                                                let clamped = UInt16(max(0, min(65535, $0)))
                                                                device.shureSdtPort = clamped == 0 ? nil : clamped
                                                                onChange()
                                                            }
                                                        ),
                                                        formatter: Self.portFormatter
                                                    )
                                                    .frame(width: 96)
                                                }

                                                Text("TCP 2202 stays enabled for control and detailed device data. This endpoint is only the UDP meter source override.")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                            .padding(.top, 4)
                                        }
                                    }
                                }
                            } else if isQuConsole {
                                HStack {
                                    Text("Port")
                                    Spacer()
                                    Text("51325")
                                        .foregroundStyle(.secondary)
                                }
                                .onAppear {
                                    if device.port != 51325 {
                                        device.port = 51325
                                        onChange()
                                    }
                                }
                            } else if let fixedAllenHeathPort {
                                HStack {
                                    Text("Port")
                                    Spacer()
                                    Text(Self.plainNumberString(fixedAllenHeathPort))
                                        .foregroundStyle(.secondary)
                                }
                                .onAppear {
                                    if device.port != fixedAllenHeathPort {
                                        device.port = fixedAllenHeathPort
                                        onChange()
                                    }
                                }
                                .onChange(of: device.consoleUseTLS) { _, _ in
                                    if device.port != fixedAllenHeathPort {
                                        device.port = fixedAllenHeathPort
                                        onChange()
                                    }
                                }
                                .onChange(of: device.consoleSubmodelIdentifier) { _, _ in
                                    if device.port != fixedAllenHeathPort {
                                        device.port = fixedAllenHeathPort
                                        onChange()
                                    }
                                }
                            } else if let fixedSennheiserPort {
                                HStack {
                                    Text("Port")
                                    Spacer()
                                    Text(Self.plainNumberString(fixedSennheiserPort))
                                        .foregroundStyle(.secondary)
                                }
                                .onAppear {
                                    if device.port != fixedSennheiserPort {
                                        device.port = fixedSennheiserPort
                                        onChange()
                                    }
                                }
                            } else if let fixedOSCPort {
                                HStack {
                                    Text("Port")
                                    Spacer()
                                    Text(Self.plainNumberString(fixedOSCPort))
                                        .foregroundStyle(.secondary)
                                }
                                .onAppear {
                                    if device.port != fixedOSCPort {
                                        device.port = fixedOSCPort
                                        onChange()
                                    }
                                }
                            } else {
                                HStack {
                                    Text(isDigiCoConsole ? "Send Port" : "Port")
                                    DeferredNumberField("Port", value: Binding<Int>(
                                        get: { Int(device.port) },
                                        set: { device.port = UInt16(max(0, min(65535, $0))) }
                                    ), formatter: Self.portFormatter)
                                        .frame(width: 80)
                                        .onChange(of: device.port) { _, _ in onChange() }
                                }
                                if isDigiCoConsole {
                                    HStack {
                                        Text("Receive Port")
                                        TextField(
                                            "8000",
                                            value: Binding(
                                                get: { device.digicoReceivePort ?? 0 },
                                                set: { device.digicoReceivePort = $0 == 0 ? nil : $0 }
                                            ),
                                            formatter: Self.portFormatter
                                        )
                                        .frame(width: 80)
                                        .onChange(of: device.digicoReceivePort) { _, _ in onChange() }
                                    }
                                }
                            }
                            Text(portHint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            if device.kind == .audioConsole,
                               let modelId = device.consoleModelIdentifier,
                               AudioConsoleModel.from(identifier: modelId) == .digico {
                                Button {
                                    showingDiGiCoPadHelp = true
                                } label: {
                                    Label("DiGiCo Pad Help", systemImage: "questionmark.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .disabled(!device.isEnabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var audioConsoleSection: some View {
                // Audio Console settings (mimics legacy panes by console family)
                if device.kind == .audioConsole {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            // Brand selection
                            HStack(spacing: 8) {
                                Text("Brand")
                                    .font(.subheadline)
                                if device.audioConsoleModel?.isBeta == true {
                                    BetaBadgeView(fontSize: 9)
                                }
                                Spacer()
                            }
                            Picker("Brand", selection: $device.consoleModelIdentifier) {
                                Text("Not Set").tag(String?.none)
                                ForEach(AudioConsoleModel.selectionCases) { model in
                                    HStack(spacing: 6) {
                                        Text(model.displayName)
                                        if model.isBeta {
                                            BetaBadgeView(fontSize: 9)
                                        }
                                    }
                                    .tag(Optional(model.rawValue))
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: device.consoleModelIdentifier) { _, newValue in
                                // Apply per-model defaults when selecting a model.
                                let selectedModel: AudioConsoleModel? = {
                                    guard let code = newValue, !code.isEmpty else { return nil }
                                    return AudioConsoleModel.from(identifier: code)
                                }()

                                switch selectedModel {
                                case .some(.behringerX32), .some(.midasM32):
                                    // X32 / M32: OSC destination port is fixed at 10023.
                                    // We store it in `device.port` so connector routing sends to the right port.
                                    if device.port != 10023 { device.port = 10023 }
                                    // Local listen port (if you use it elsewhere) defaults to 8000.
                                    if device.consoleListenPort == nil { device.consoleListenPort = 8000 }
                                    device.consoleSubmodelIdentifier = nil

                                case .some(.allenHeathDlive):
                                    if device.consoleSubmodelIdentifier == nil || device.consoleSubmodelIdentifier == "dlive_avantis" {
                                        device.consoleSubmodelIdentifier = "dlive_mixrack"
                                    }
                                    if device.consoleSubmodelIdentifier == "dlive_surface" {
                                        if device.port == 0 || device.port == 51325 || device.port == 51327 {
                                            device.port = device.consoleUseTLS ? 51329 : 51328
                                        }
                                    } else if device.port == 0 {
                                        device.port = device.consoleUseTLS ? 51327 : 51325
                                    }

                                case .some(.allenHeathAvantis):
                                    if device.port != 51325 { device.port = 51325 }
                                    device.consoleUseTLS = false
                                    device.consoleSubmodelIdentifier = "avantis"

                                case .some(.allenHeathSq):
                                    if device.port != 51325 { device.port = 51325 }
                                    device.consoleUseTLS = false
                                    device.consoleSubmodelIdentifier = "sq"

                                case .some(.allenHeathQu):
                                    if device.port != 51325 { device.port = 51325 }
                                    device.consoleSubmodelIdentifier = "qu"

                                case .some(.digico):
                                    if device.port == 0 { device.port = 9000 }
                                    device.consoleSubmodelIdentifier = nil

                                case .some(.yamahaDm7), .some(.yamahaRivage):
                                    if device.port != 49900 { device.port = 49900 }
                                    if device.yamahaDm7SceneBank.isEmpty { device.yamahaDm7SceneBank = "scene_a" }
                                    device.consoleSubmodelIdentifier = nil

                                case .some(.yamahaClQl):
                                    if device.yamahaDm7SceneBank.isEmpty { device.yamahaDm7SceneBank = "scene_a" }
                                    device.consoleSubmodelIdentifier = nil

                                case .some(.behringerWing):
                                    // WING: OSC destination port is fixed at 2223.
                                    if device.port != 2223 { device.port = 2223 }
                                    device.consoleSubmodelIdentifier = nil

                                case .some(.avidVenueS6L):
                                    // VENUE has no documented default port — seed a starting
                                    // value only if unset; both host and port stay editable
                                    // since the operator assigns them to a connection slot.
                                    if device.port == 0 { device.port = 8000 }
                                    if device.venueTransportMode == nil { device.venueTransportMode = .tcp }
                                    device.consoleSubmodelIdentifier = nil

                                default:
                                    device.consoleSubmodelIdentifier = nil
                                }
                                onChange()
                            }

                            if let modelCode = device.consoleModelIdentifier,
                               let model = AudioConsoleModel.from(identifier: modelCode) {

                                // Enable toggle (console-specific label like old panes)
                                Toggle(isOn: $device.isEnabled) {
                                    Text(device.isEnabled ? "Enabled" : "Disabled")
                                        .foregroundStyle(.secondary)
                                }
                                .toggleStyle(.switch)
                                .onChange(of: device.isEnabled) { _, _ in onChange() }

                                capabilityIndicatorSection(device: device)

                                // Model-specific controls
                                switch model {
                                case .digico:
                                    Divider().padding(.vertical, 4)

                                    // Console model (SD12, Q338, etc.) — below brand picker
                                    HStack(spacing: 8) {
                                        Text("Model")
                                            .font(.subheadline)
                                        Spacer()
                                    }
                                    Picker("Model", selection: Binding(
                                        get: { device.digicoConsoleModel },
                                        set: { newModel in
                                            device.digicoConsoleModel = newModel
                                            // Auto-fill scan counts when a model is chosen
                                            if let m = newModel, device.digicoMaxScanCounts.isEmpty {
                                                device.digicoMaxScanCounts = m.maxScanCounts
                                            }
                                            onChange()
                                        }
                                    )) {
                                        Text("Not specified").tag(Optional<ExternalDeviceConfig.DiGiCoConsoleModel>.none)
                                        ForEach(ExternalDeviceConfig.DiGiCoConsoleModel.allCases) { m in
                                            Text(m.rawValue).tag(Optional(m))
                                        }
                                    }
                                    .pickerStyle(.menu)



                                    HStack {
                                        Button("Import Show RTF…") {
                                            showingDiGiCoRTFImporter = true
                                        }
                                        .disabled(!device.isEnabled)

                                        Button(role: .destructive) {
                                            device.digicoRTFFileName = nil
                                            device.digicoRTFImportedAt = nil
                                            device.digicoInputChannels = []
                                            digicoRTFImportError = nil
                                            onChange()
                                        } label: {
                                            Text("Clear")
                                        }
                                        .disabled(device.digicoInputChannels.isEmpty)

                                        Button("Sync from DiGiCo") {
                                            digicoSyncService.sync(deviceId: device.id)
                                        }
                                        .disabled(!device.isEnabled || device.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || digicoSyncService.isCancellable)

                                        Spacer()

                                        if !device.digicoInputChannels.isEmpty {
                                            Text("\(device.digicoInputChannels.count) channels")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    if let fileName = device.digicoRTFFileName {
                                        let ts = device.digicoRTFImportedAt
                                        Text(ts != nil ? "Imported: \(fileName) • \(ts!.formatted(date: .abbreviated, time: .shortened))" : "Imported: \(fileName)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Import a DiGiCo show RTF to populate available input channels for mapping.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    if let err = digicoRTFImportError {
                                        Text(err)
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    }

                                    Group {
                                        switch digicoSyncService.state {
                                        case .idle:
                                            if device.digicoInputChannels.isEmpty && device.digicoDiscoveredChannels.isEmpty {
                                                Text("Import an RTF or sync from a live console to populate channel names.")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        case .syncing(let progress):
                                            HStack(spacing: 8) {
                                                ProgressView().controlSize(.small)
                                                Text(progress).font(.caption2).foregroundStyle(.secondary)
                                                Spacer()
                                                if digicoSyncService.isCancellable {
                                                    Button("Cancel") { digicoSyncService.cancel() }
                                                        .font(.caption2).buttonStyle(.borderless).foregroundStyle(.red)
                                                }
                                            }
                                        case .succeeded(let inputs, let other, let date):
                                            Text("Synced \(date.formatted(date: .abbreviated, time: .shortened)) · \(inputs) inputs, \(other) aux/group/matrix/CG")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        case .noChannelsFound:
                                            Text("No channels found. Verify console IP and that DiGiCo OSC is enabled (Setup → OSC).")
                                                .font(.caption2).foregroundStyle(.orange)
                                        case .portUnavailable(let port):
                                            Text("Port \(port) is already in use. Change the Receive Port or quit the other app holding it.")
                                                .font(.caption2).foregroundStyle(.red)
                                        case .consoleNotResponding:
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Console not responding. Check:").font(.caption2).foregroundStyle(.red)
                                                ForEach([
                                                    "Console IP address is correct",
                                                    "DiGiCo OSC is enabled (Setup → OSC)",
                                                    "Console Receive Port matches console setting (default 9000)",
                                                    "Receive Port matches the console's OSC send port (default 8000)",
                                                    "Relay has Local Network permission (System Settings → Privacy → Local Network)",
                                                ], id: \.self) { line in
                                                    Text("• \(line)").font(.caption2).foregroundStyle(.secondary)
                                                }
                                            }
                                        case .networkPermissionDenied:
                                            Text("Relay needs Local Network access. Enable it in System Settings → Privacy → Local Network.")
                                                .font(.caption2).foregroundStyle(.red)
                                        case .failed(let msg):
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(msg).font(.caption2).foregroundStyle(.red)
                                                ForEach([
                                                    "Verify Console IP, Send Port, and Receive Port",
                                                    "Check Local Network permission in System Settings → Privacy",
                                                    "Make sure no other app holds the local listen port",
                                                ], id: \.self) { line in
                                                    Text("• \(line)").font(.caption2).foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                    }

                                    // Channel count pill — tap to view full synced channel list
                                    let digicoSyncPillText = digicoChannelCountPill(device: device)
                                    if !digicoSyncPillText.isEmpty {
                                        Button {
                                            showingDiGiCoSyncedChannels = true
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "waveform")
                                                    .imageScale(.small)
                                                Text(digicoSyncPillText)
                                            }
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(.secondary.opacity(0.15), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        .sheet(isPresented: $showingDiGiCoSyncedChannels) {
                                            DiGiCoSyncedChannelsSheet(device: device)
                                        }
                                    }

                                    DisclosureGroup("Advanced") {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text("Max scan count per type")
                                                    .font(.caption).foregroundStyle(.secondary)
                                                Spacer()
                                                if let model = device.digicoConsoleModel {
                                                    Button("Reset to \(model.rawValue) defaults") {
                                                        device.digicoMaxScanCounts = model.maxScanCounts
                                                        onChange()
                                                    }
                                                    .font(.caption2)
                                                    .buttonStyle(.borderless)
                                                    .foregroundStyle(.blue)
                                                }
                                            }
                                            ForEach(DashboardGraph.DiGiCoChannelType.allCases, id: \.self) { type in
                                                HStack {
                                                    Text(type.displayName).font(.caption2)
                                                    Spacer()
                                                    Stepper(
                                                        value: Binding(
                                                            get: { device.digicoMaxScanCounts[type.rawValue] ?? type.defaultMaxScanCount },
                                                            set: { device.digicoMaxScanCounts[type.rawValue] = $0; onChange() }
                                                        ),
                                                        in: 1...512, step: 8
                                                    ) {
                                                        Text("\(device.digicoMaxScanCounts[type.rawValue] ?? type.defaultMaxScanCount)")
                                                            .font(.caption2).monospacedDigit()
                                                    }
                                                    .controlSize(.mini)
                                                }
                                            }
                                        }
                                    }
                                    .font(.caption2)

                                case .allenHeathQu:
                                    Divider().padding(.vertical, 4)

                                    let quMidiChannelBinding = Binding<Int>(
                                        get: { Int(device.consoleBaseMidiChannel ?? 0) + 1 },
                                        set: { newValue in
                                            let clamped = max(1, min(16, newValue))
                                            device.consoleBaseMidiChannel = UInt8(clamped - 1)
                                            onChange()
                                        }
                                    )

                                    HStack {
                                        Text("MIDI Channel")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Stepper("", value: quMidiChannelBinding, in: 1...16)
                                            .labelsHidden()
                                            .disabled(!device.isEnabled)

                                        Text("\(quMidiChannelBinding.wrappedValue)")
                                            .font(.caption)
                                    }

                                    Text("Qu series uses MIDI over TCP/IP (port 51325). Use the network settings below to reach the mixer.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    GroupBox("Qu Connection Test") {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack(spacing: 10) {
                                                Button(quTestService.isTesting ? "Testing…" : "Test Connection") {
                                                    quTestService.test(host: device.host, port: device.port)
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .disabled(!device.isEnabled || quTestService.isTesting)

                                                if quTestService.isTesting {
                                                    ProgressView()
                                                        .controlSize(.small)
                                                }

                                                Spacer()

                                                if let result = quTestService.lastResult {
                                                    Image(systemName: result ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                                        .foregroundStyle(result ? Color.green : Color.red)
                                                    Text(result ? "Response received" : "No response")
                                                        .foregroundStyle(result ? Color.green : Color.secondary)
                                                } else {
                                                    Image(systemName: "questionmark.circle")
                                                        .foregroundStyle(.secondary)
                                                    Text("Not tested")
                                                        .foregroundStyle(.secondary)
                                                }
                                            }

                                            if let last = quTestService.lastResponseAt {
                                                Text("Last response: \(last.formatted(date: .omitted, time: .standard))")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }

                                            if let error = quTestService.lastError {
                                                Text("Error: \(error)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.red)
                                            }
                                            if let debugLog = quTestService.lastDebugLog, !debugLog.isEmpty {
                                                Text(debugLog)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .textSelection(.enabled)
                                            }

                                            Text("Uses MIDI over TCP/IP and sends a MIDI NRPN ‘get’ request, waiting for any response bytes.")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .disabled(!device.isEnabled)

                                case .behringerX32, .midasM32:
                                    Text("X32 / M32 network configuration.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    Divider().padding(.vertical, 4)

                                    GroupBox("Show Control") {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Choose whether Relay creates/renames Cues or Snippets when sending the rundown to this console.")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)

                                            Picker("Send As", selection: $x32ShowSendMode) {
                                                ForEach(X32ShowSendMode.allCases) { mode in
                                                    Text(mode.displayName).tag(mode)
                                                }
                                            }
                                            .pickerStyle(.segmented)
                                            .onChange(of: x32ShowSendMode) { newValue, _ in
                                                persistX32ShowSendMode(newValue)
                                                onChange()
                                            }
                                        }
                                        .onAppear {
                                            x32ShowSendMode = loadPersistedX32ShowSendMode()
                                        }
                                    }
                                    .disabled(!device.isEnabled)

                                    GroupBox("Sync (Channel Names)") {
                                        VStack(alignment: .leading, spacing: 10) {
                                            HStack(spacing: 10) {
                                                Button {
                                                    runX32Sync(deviceId: device.id)
                                                } label: {
                                                    Label(isSyncingX32 ? "Syncing…" : "Sync From Console", systemImage: "arrow.triangle.2.circlepath")
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .disabled(!device.isEnabled || isSyncingX32)

                                                if isSyncingX32 {
                                                    ProgressView()
                                                        .controlSize(.small)
                                                }

                                                Spacer()

                                                if let ts = x32LastSyncAt {
                                                    Text("Last sync: \(ts.formatted(date: .abbreviated, time: .shortened))")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)

                                                    Button(role: .destructive) {
                                                        x32LastSyncAt = nil
                                                        device.lastChannelSyncAt = nil
                                                        x32SyncedChannels = []
                                                        x32SyncError = nil
                                                        clearPersistedX32Sync()
                                                        onChange()
                                                    } label: {
                                                        Text("Clear")
                                                    }
                                                    .buttonStyle(.borderless)
                                                    .font(.caption2)
                                                }
                                            }

                                            if let err = x32SyncError {
                                                Text(err)
                                                    .font(.caption2)
                                                    .foregroundStyle(.red)
                                            }

                                            if !x32SyncedChannels.isEmpty {
                                                HStack {
                                                    Text("Synced \(x32SyncedChannels.count) channels")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                    Spacer()
                                                    Button(showsX32SyncedChannels ? "Hide Channel List" : "Show Channel List") {
                                                        withAnimation(.easeInOut(duration: 0.15)) {
                                                            showsX32SyncedChannels.toggle()
                                                        }
                                                    }
                                                    .buttonStyle(.plain)
                                                    .foregroundStyle(.tint)
                                                    .font(.caption2)
                                                }

                                                if showsX32SyncedChannels {
                                                    ScrollView {
                                                        VStack(alignment: .leading, spacing: 4) {
                                                            ForEach(x32SyncedChannels, id: \.ch) { row in
                                                                Text(String(format: "CH %02d  —  %@", row.ch, row.name))
                                                                    .font(.caption2)
                                                                    .foregroundStyle(.secondary)
                                                            }
                                                        }
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                    }
                                                    .frame(maxHeight: 220)
                                                    .padding(.top, 4)
                                                }
                                            } else {
                                                Text("No synced channel names yet.")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .onAppear {
                                            // Restore persisted sync results into the preview UI.
                                            if x32SyncedChannels.isEmpty {
                                                let saved = loadPersistedX32Sync()
                                                if !saved.map.isEmpty {
                                                    if x32LastSyncAt == nil { x32LastSyncAt = saved.at }
                                                    setSyncedPreview(from: saved.map)
                                                }
                                            }
                                        }
                                        .padding(.top, 4)
                                    }
                                    .disabled(!device.isEnabled)

                                case .allenHeathDlive, .allenHeathAvantis, .allenHeathSq:
                                    Divider().padding(.vertical, 4)

                                    if model == .allenHeathDlive {
                                        HStack(alignment: .center, spacing: 8) {
                                            Text("Connection Target")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)

                                            Button {
                                                showingDLiveHelp = true
                                            } label: {
                                                Image(systemName: "questionmark.circle")
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.borderless)
                                            .help("dLive connection help")

                                            Spacer()
                                        }

                                        Picker("Connection Target", selection: $dLiveTargetSelection) {
                                            Text("MixRack").tag("dlive_mixrack")
                                            Text("Surface").tag("dlive_surface")
                                        }
                                        .pickerStyle(.segmented)
                                        .frame(maxWidth: 320, alignment: .leading)
                                        .disabled(!device.isEnabled)
                                        .onAppear {
                                            syncDLiveTargetSelectionFromDevice()
                                        }
                                        .onChange(of: device.consoleSubmodelIdentifier) { _, _ in
                                            syncDLiveTargetSelectionFromDevice()
                                        }
                                        .onChange(of: dLiveTargetSelection) { _, newValue in
                                            guard device.consoleSubmodelIdentifier != newValue else { return }
                                            device.consoleSubmodelIdentifier = newValue
                                            switch newValue {
                                            case "dlive_surface":
                                                device.port = device.consoleUseTLS ? 51329 : 51328
                                            default:
                                                device.port = device.consoleUseTLS ? 51327 : 51325
                                            }
                                            onChange()
                                        }

                                        Text("Use MixRack for channel-name sync and scene recall. Surface is available for surface-endpoint testing.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text(model == .allenHeathAvantis
                                             ? "Avantis uses Allen & Heath TCP external control."
                                             : "SQ uses Allen & Heath TCP external control.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    if model == .allenHeathDlive {
                                        Toggle("Use TLS", isOn: Binding<Bool>(
                                            get: { device.consoleUseTLS },
                                            set: { newValue in
                                                device.consoleUseTLS = newValue
                                                if (device.consoleSubmodelIdentifier ?? "dlive_mixrack") == "dlive_surface" {
                                                    device.port = newValue ? 51329 : 51328
                                                } else {
                                                    device.port = newValue ? 51327 : 51325
                                                }
                                                onChange()
                                            }
                                        ))
                                        .toggleStyle(.switch)
                                        .disabled(!device.isEnabled)

                                        let tlsProfileBinding = Binding<Int>(
                                            get: { Int(device.consoleTLSUserProfile ?? 1) },
                                            set: { newValue in
                                                let clamped = max(1, min(16, newValue))
                                                device.consoleTLSUserProfile = UInt8(clamped)
                                                onChange()
                                            }
                                        )

                                        HStack {
                                            Text("TLS User Profile")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Stepper("", value: tlsProfileBinding, in: 1...16)
                                                .labelsHidden()
                                                .disabled(!device.isEnabled || !device.consoleUseTLS)
                                            Text("\(tlsProfileBinding.wrappedValue)")
                                                .font(.caption)
                                        }

                                        SecureField("TLS Password", text: Binding<String>(
                                            get: { device.consoleTLSPassword ?? "" },
                                            set: {
                                                device.consoleTLSPassword = $0
                                                onChange()
                                            }
                                        ))
                                        .disabled(!device.isEnabled || !device.consoleUseTLS)

                                        Text("Relay uses dLive TLS profile 1 unless you choose another profile. Leave the password blank if that dLive user profile has no password.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    let midiChannelBinding = Binding<Int>(
                                        get: { Int(device.consoleBaseMidiChannel ?? 0x0B) + 1 },
                                        set: { newValue in
                                            let clamped = max(1, min(16, newValue))
                                            device.consoleBaseMidiChannel = UInt8(clamped - 1)
                                            onChange()
                                        }
                                    )

                                    HStack {
                                        Text("MIDI Channel")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Stepper("", value: midiChannelBinding, in: 1...16)
                                            .labelsHidden()
                                            .disabled(!device.isEnabled)
                                        Text("\(midiChannelBinding.wrappedValue)")
                                            .font(.caption)
                                    }

                                    if model == .allenHeathDlive || model == .allenHeathAvantis || model == .allenHeathSq {
                                        GroupBox("Sync (Channel Names)") {
                                            VStack(alignment: .leading, spacing: 10) {
                                                HStack(spacing: 10) {
                                                    Button {
                                                        runDLiveSync(deviceId: device.id)
                                                    } label: {
                                                        Label(isSyncingDLive ? "Syncing…" : "Sync From Console", systemImage: "arrow.triangle.2.circlepath")
                                                    }
                                                    .buttonStyle(.borderedProminent)
                                                    .disabled(!device.isEnabled || isSyncingDLive)

                                                    if isSyncingDLive {
                                                        ProgressView()
                                                            .controlSize(.small)
                                                    }

                                                    Spacer()

                                                    if let ts = dLiveLastSyncAt {
                                                        Text("Last sync: \(ts.formatted(date: .abbreviated, time: .shortened))")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)

                                                        Button(role: .destructive) {
                                                            dLiveLastSyncAt = nil
                                                            device.lastChannelSyncAt = nil
                                                            dLiveSyncedChannels = []
                                                            dLiveSyncError = nil
                                                            clearPersistedDLiveSync()
                                                            onChange()
                                                        } label: {
                                                            Text("Clear")
                                                        }
                                                        .buttonStyle(.borderless)
                                                        .font(.caption2)
                                                    }
                                                }

                                                if let err = dLiveSyncError {
                                                    Text(err)
                                                        .font(.caption2)
                                                        .foregroundStyle(.red)
                                                }

                                                if !dLiveSyncedChannels.isEmpty {
                                                    HStack {
                                                        Text("Synced \(dLiveSyncedChannels.count) channels")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                        Spacer()
                                                        Button(showsDLiveSyncedChannels ? "Hide Channel List" : "Show Channel List") {
                                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                                showsDLiveSyncedChannels.toggle()
                                                            }
                                                        }
                                                        .buttonStyle(.plain)
                                                        .foregroundStyle(.tint)
                                                        .font(.caption2)
                                                    }

                                                    if showsDLiveSyncedChannels {
                                                        ScrollView {
                                                            VStack(alignment: .leading, spacing: 4) {
                                                                ForEach(dLiveSyncedChannels, id: \.ch) { row in
                                                                    Text(String(format: "CH %03d  —  %@", row.ch, row.name))
                                                                        .font(.caption2)
                                                                        .foregroundStyle(.secondary)
                                                                }
                                                            }
                                                            .frame(maxWidth: .infinity, alignment: .leading)
                                                        }
                                                        .frame(maxHeight: 220)
                                                        .padding(.top, 4)
                                                    }
                                                } else {
                                                    Text("No synced channel names yet.")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            .onAppear {
                                                if dLiveSyncedChannels.isEmpty {
                                                    let saved = loadPersistedDLiveSync()
                                                    if !saved.map.isEmpty {
                                                        if dLiveLastSyncAt == nil { dLiveLastSyncAt = saved.at }
                                                        setAllenHeathSyncedPreview(from: saved.map)
                                                    }
                                                }
                                            }
                                            .padding(.top, 4)
                                        }
                                        .disabled(!device.isEnabled)
                                    }

                                case .yamahaDm7, .yamahaRivage:
                                    if model == .yamahaDm7 {
                                        Picker("Scene Bank", selection: Binding<String>(
                                            get: { device.yamahaDm7SceneBank },
                                            set: { device.yamahaDm7SceneBank = $0; onChange() }
                                        )) {
                                            Text("Scene A").tag("scene_a")
                                            Text("Scene B").tag("scene_b")
                                        }
                                        .pickerStyle(.segmented)
                                        .disabled(!device.isEnabled)
                                    }

                                    yamahaMidiSection
                                    yamahaSceneMappingSection

                                case .yamahaClQl:
                                    Text("MIDI-only Yamaha console. Scene recall uses Program Change mapping.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    yamahaMidiSection
                                    yamahaSceneMappingSection

                                case .behringerWing:
                                    Text("OSC-based console (UDP port 2223). Channel mute, level, pan, and scene recall are available via Standard Console Actions once linked to a trigger.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                case .avidVenueS6L:
                                    Text("VENUE's OSC (software 8.2+) is routed through its own Events system — there's no fixed address scheme. Enter the address template each action should send; it must match an Event you've configured on the console (Control → OSC). Use {channel} for mute/level/pan and {scene} for scene recall.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Picker(
                                        "Transport",
                                        selection: Binding(
                                            get: { device.venueTransportMode ?? .tcp },
                                            set: {
                                                device.venueTransportMode = $0
                                                onChange()
                                            }
                                        )
                                    ) {
                                        ForEach(VenueOSCTransportMode.allCases) { mode in
                                            Text(mode.displayName).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.menu)

                                    TextField(
                                        "Mute address, e.g. /relay/ch/{channel}/mute",
                                        text: Binding(
                                            get: { device.venueMuteAddressTemplate ?? "" },
                                            set: {
                                                device.venueMuteAddressTemplate = $0
                                                onChange()
                                            }
                                        )
                                    )

                                    TextField(
                                        "Level address, e.g. /relay/ch/{channel}/level",
                                        text: Binding(
                                            get: { device.venueLevelAddressTemplate ?? "" },
                                            set: {
                                                device.venueLevelAddressTemplate = $0
                                                onChange()
                                            }
                                        )
                                    )

                                    TextField(
                                        "Pan address, e.g. /relay/ch/{channel}/pan",
                                        text: Binding(
                                            get: { device.venuePanAddressTemplate ?? "" },
                                            set: {
                                                device.venuePanAddressTemplate = $0
                                                onChange()
                                            }
                                        )
                                    )

                                    TextField(
                                        "Scene recall address, e.g. /relay/scene/{scene}/recall",
                                        text: Binding(
                                            get: { device.venueSceneRecallAddressTemplate ?? "" },
                                            set: {
                                                device.venueSceneRecallAddressTemplate = $0
                                                onChange()
                                            }
                                        )
                                    )

                                }

                                if showsRundownSnapshotSettings {
                                    // Shared snapshot-offset controls (legacy parity)
                                    Divider().padding(.vertical, 4)

                                    Toggle(isOn: $device.consoleExistingSnapshots) {
                                        Text("Existing Snapshots")
                                    }
                                    .toggleStyle(.switch)
                                    .disabled(!device.isEnabled)
                                    .onChange(of: device.consoleExistingSnapshots) { _, _ in onChange() }

                                    HStack {
                                        Text("Existing Count")
                                        Spacer()
                                        DeferredNumberField("0", value: $device.consoleExistingSnapshotCount, formatter: Self.portFormatter)
                                            .frame(width: 90)
                                            .disabled(!device.isEnabled || !device.consoleExistingSnapshots)
                                            .onChange(of: device.consoleExistingSnapshotCount) { _, _ in onChange() }
                                    }
                                }

                            } else {
                                Text("Select a console model to configure its settings.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text("Select the closest console family/model. This is used by Graph + ConsoleConnector routing for channel naming.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Text("Audio Console")
                    }
                }
    }

    @ViewBuilder
    private var vistaSection: some View {
        if device.kind == .vistaConsole, RelayLicensingConfig.isVistaIntegrationEnabled {
            GroupBox("Vista") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("OSC Console Target")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            showingVistaOSCHelp = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Vista OSC setup")
                        .popover(isPresented: $showingVistaOSCHelp, arrowEdge: .top) {
                            vistaOSCHelpPopover
                        }
                    }

                    TextField(
                        "EX1",
                        text: Binding(
                            get: { device.vistaConsoleTarget ?? "EX1" },
                            set: { newValue in
                                device.vistaConsoleTarget = newValue
                                onChange()
                            }
                        )
                    )

                    Text("Enable Vista OSC in Preferences > OSC, set the receive port to match this device, and use the External IO Reference target name shown in braces, such as EX1.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var vistaOSCHelpPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vista OSC Setup")
                .font(.headline)

            Text("In Vista, open Preferences > OSC.")
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 8) {
                Text("1. Enable the OSC Server.")
                Text("2. Set Vista Receive Port Number to the same port configured for this Relay device.")
                Text("3. Open External IO Reference and confirm the console target shown in braces, such as EX1.")
                Text("4. Use that exact target in Relay so commands match Vista paths like /v3/console/{EX1}/spbPlay.")
                Text("5. OSC Clients are optional for Relay's outbound control; the server receive port is the important part for this integration.")
            }
            .font(.caption)

            Text("Current commands supported in Relay: Play, Back, Skip Forward, Skip Back, and GM Fader.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 360)
    }

    @ViewBuilder
    private var sennheiserSection: some View {
        if device.kind == .sennheiserWireless {
            GroupBox("Sennheiser Model") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Model")
                            .font(.subheadline)
                        BetaBadgeView(fontSize: 9)
                        Spacer()
                    }
                    Picker("Model", selection: Binding<SennheiserNetworkModel?>(
                        get: {
                            if let explicit = selectedSennheiserModel {
                                return explicit.isSupportedNow ? explicit : nil
                            }
                            if let code = device.sennheiserModelIdentifier,
                               let model = SennheiserNetworkModel(rawValue: code) {
                                return model.isSupportedNow ? model : nil
                            }
                            if let inferred = SennheiserNetworkModel.from(deviceName: device.name),
                               inferred.isSupportedNow {
                                return inferred
                            }
                            return nil
                        },
                        set: { newValue in
                            selectedSennheiserModel = newValue
                            device.sennheiserModelIdentifier = newValue?.rawValue
                            if newValue == .specteraBaseStation, device.port != 443 {
                                device.port = 443
                            }
                            onChange()
                        }
                    )) {
                        ForEach(sennheiserPickerModels) { model in
                            let suffix = model.isSupportedNow ? "" : " (Unsupported)"
                            Text(model.displayName + suffix).tag(Optional(model))
                        }
                    }
                    .pickerStyle(.menu)

                    if let resolved = resolvedSennheiserModel {
                        if resolved == .specteraBaseStation {
                            Text("Uses the Spectera SSCv2 API over HTTPS on port 443. Enter the password configured in LinkDesk or the Spectera WebUI.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            SecureField("Spectera password", text: $specteraPassword)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: specteraPassword) { _, value in
                                    SpecteraKeychainStore.shared.setPassword(value, for: device.id)
                                }
                                .onAppear {
                                    specteraPassword = SpecteraKeychainStore.shared.password(for: device.id) ?? ""
                                }
                        } else {
                            let typeLabel = resolved.category == .iem ? "IEM" : "Mic"
                            Text("Selected type: \(typeLabel). Exposes \(resolved.channelCount) channel(s). \(resolved.supportsNetwork ? "Network monitoring supported." : "Network monitoring may not be available; selection can be used for module assignment.")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Select the closest Sennheiser family. The selected model is used to determine how many channels this device exposes and whether the module should treat it as a Mic or IEM.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if resolvedSennheiserModel?.supportsNetwork ?? true {
                GroupBox("Sennheiser Connection") {
                    VStack(alignment: .leading, spacing: 8) {
                        if resolvedSennheiserModel == .specteraBaseStation {
                            HStack {
                                Button(isTestingSpecteraConnection ? "Testing…" : "Test Connection") {
                                    testSpecteraConnection()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isTestingSpecteraConnection)

                                Spacer()

                                if isTestingSpecteraConnection {
                                    ProgressView()
                                        .controlSize(.small)
                                } else if specteraConnectionSucceeded {
                                    Label("Authenticated", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Text("Not Tested")
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Text("Tests the Spectera SSCv2 API over HTTPS using the password above.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            if let error = specteraConnectionError {
                                Text("Error: \(error)")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }

                            if let fingerprint = specteraCertificateFingerprint {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Spectera uses a self-signed certificate. Verify this fingerprint with the Base Station owner before trusting it. You will need to trust a new certificate after a factory reset or Base Station replacement.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(fingerprint)
                                        .font(.system(.caption2, design: .monospaced))
                                        .textSelection(.enabled)
                                    Button("Trust Certificate and Test Again") {
                                        trustSpecteraCertificate()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        } else {
                            HStack {
                                Button(sennheiserService.isConnected ? "Disconnect" : "Connect") {
                                    if sennheiserService.isConnected {
                                        sennheiserService.disconnect()
                                    } else {
                                        sennheiserService.connect(to: device.host, port: device.port)
                                    }
                                }
                                .buttonStyle(.borderedProminent)

                                Spacer()

                                Text(sennheiserService.isConnected ? "Connected" : "Not Connected")
                                    .foregroundStyle(sennheiserService.isConnected ? Color.green : Color.secondary)
                            }

                            if let last = sennheiserService.lastHeardAt {
                                Text("Last activity: \(last.formatted(date: .omitted, time: .standard))")
                                    .font(.caption2)
                            } else {
                                Text("Last activity: —")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            if let error = sennheiserService.lastError {
                                Text("Error: \(error)")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                basicsSection

                audioConsoleSection

                vistaSection

                sennheiserSection

                // Shure-specific configuration and connection controls
                if device.kind == .shureWireless {
                    GroupBox("Shure Model") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Model", selection: Binding<ShureNetworkModel?>(
                                get: {
                                    if let explicit = selectedShureModel {
                                        return explicit
                                    }
                                    if let code = device.shureModelIdentifier {
                                        let upper = code.uppercased()
                                        if upper.contains("UXLD1") || upper.contains("ULXD1") {
                                            return .ulxd4
                                        }
                                        if let model = ShureNetworkModel(rawValue: upper) {
                                            return model
                                        }
                                    }
                                    return ShureNetworkModel.from(deviceName: device.name)
                                },
                                set: { newValue in
                                    selectedShureModel = newValue
                                    device.shureModelIdentifier = newValue?.rawValue
                                    onChange()
                                }
                            )) {
                                ForEach(ShureNetworkModel.selectionCases) { model in
                                    Text(model.displayName).tag(Optional(model))
                                }
                            }
                            .pickerStyle(.menu)

                            Text("Network-capable Shure receivers (and PSM 900 as an offline placeholder) are listed here. The selected model is used to determine how many channels this device exposes. PSM 900 will not create a network connection; it is used only for module assignment.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let model = resolvedShureModel,
                       model == .anx4 || model == .adtd || model == .adtq {
                        GroupBox("Shure Channel Capacity") {
                            VStack(alignment: .leading, spacing: 8) {
                                if model == .anx4 {
                                    Picker("ANX4 Mode", selection: $localAnx4Mode) {
                                        ForEach(ShureAnx4Mode.allCases) { mode in
                                            Text(mode.displayName).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .onAppear {
                                        let effective = device.shureAnx4Mode ?? .axient
                                        if device.shureAnx4Mode == nil {
                                            device.shureAnx4Mode = effective
                                            onChange()
                                        }
                                        localAnx4Mode = effective
                                    }
                                    .onChange(of: device.shureAnx4Mode) { _, newValue in
                                        if let newValue {
                                            localAnx4Mode = newValue
                                        }
                                    }
                                    .onChange(of: localAnx4Mode) { _, newValue in
                                        device.shureAnx4Mode = newValue
                                        if let current = device.shureChannelCountOverride, current > newValue.maxChannels {
                                            device.shureChannelCountOverride = newValue.maxChannels
                                        }
                                        onChange()
                                    }
                                }
                                Picker("Channel Count", selection: Binding<Int?>(
                                    get: { device.shureChannelCountOverride },
                                    set: { newValue in
                                        device.shureChannelCountOverride = newValue
                                        onChange()
                                    }
                                )) {
                                    let defaultLabel: String = {
                                        if let detected = device.shureDetectedChannelCount, detected > 0 {
                                            return "Auto (Detected: \(detected))"
                                        }
                                        return "Auto (Default: \(model.channelCount))"
                                    }()
                                    Text(defaultLabel).tag(Optional<Int>.none)
                                    ForEach(shureManualChannelCountOptions, id: \.self) { count in
                                        Text("\(count) Channels").tag(Optional(count))
                                    }
                                }
                                .pickerStyle(.menu)

                                Text("Use the licensed channel count for \(model.rawValue). This controls how many channels Relay shows and which channel names are editable.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                HStack {
                                    Button("Detect Channels") {
                                        ExternalDevicesStore.shared.refreshShureDetectedChannelCount(for: device)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(effectiveShureTransportMode == .udpPreferred || device.shureChannelCountOverride != nil)

                                    Spacer()

                                    if device.shureChannelCountOverride != nil {
                                        Text("Manual override in effect — detection is skipped.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    } else if let detected = device.shureDetectedChannelCount, detected > 0 {
                                        Text("Auto-detected \(detected) licensed channels.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Not yet detected.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                if effectiveShureTransportMode == .udpPreferred {
                                    Text("Switch off \"UDP Preferred\" below to enable channel detection (requires TCP command strings enabled on the device).")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                        if resolvedShureModel?.supportsNetwork ?? true {
                        GroupBox("Shure Connection") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Button(shureService.isConnected ? "Disconnect" : "Connect") {
                                        if shureService.isConnected {
                                            shureService.disconnect()
                                        } else {
                                            shureService.connect(device: device) {
                                                guard resolvedShureModel != .psm900 else { return }
                                                ExternalDevicesStore.shared.refreshShureChannelNames(for: device)
                                            }
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Spacer()

                                    Text(
                                        shureService.isConnected
                                            ? "Connected"
                                            : (shureService.lastConnectedAt != nil ? "Last test succeeded" : "Not Connected")
                                    )
                                    .foregroundStyle(
                                        shureService.isConnected || shureService.lastConnectedAt != nil
                                            ? Color.green
                                            : Color.secondary
                                    )
                                }

                                if let last = shureService.lastHeardAt {
                                    Text("Last activity: \(last.formatted(date: .omitted, time: .standard))")
                                        .font(.caption2)
                                } else {
                                    Text("Last activity: —")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                if let lastConnected = shureService.lastConnectedAt {
                                    Text("Last successful connection: \(lastConnected.formatted(date: .abbreviated, time: .standard))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                if let error = shureService.lastError {
                                    Text("Error: \(error)")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }

                                if let model = resolvedShureModel,
                                   model == .anx4 || model == .adtd || model == .adtq {
                                    HStack {
                                        Button("Send Test Command") {
                                            shureService.sendTestCommand()
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(!shureService.isConnected)

                                        Spacer()

                                        if let lastCommand = shureService.lastTestCommand {
                                            Text("Last: \(lastCommand)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    if let packet = shureService.lastRawPacket, !packet.isEmpty {
                                        Text("Last response: \(packet)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onAppear {
                            shureService.loadCachedStatus(for: device)
                        }
                    }

                    if resolvedShureModel != .p10t {
                        let isManual = resolvedShureModel == .anx4 || resolvedShureModel == .adtd || resolvedShureModel == .adtq
                        GroupBox(isManual ? "Shure Channel Names" : "Shure Channel Names (Discovered)") {
                            let names = device.shureChannelNames
                            let manualCount = effectiveShureChannelCount
                            if isManual {
                                if manualCount == 0 {
                                    Text("Set a channel count to enable manual channel names.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(1...manualCount, id: \.self) { channel in
                                            let nameBinding = Binding<String>(
                                                get: { device.shureChannelNames[channel] ?? "" },
                                                set: { newValue in
                                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                                    device.shureChannelNames[channel] = trimmed.isEmpty ? nil : trimmed
                                                    onChange()
                                                }
                                            )
                                            HStack {
                                                Text("CH \(channel)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 52, alignment: .leading)
                                                TextField("Channel Name", text: nameBinding)
                                                Spacer()
                                            }
                                        }
                                    }
                                }
                            } else {
                                if names.isEmpty {
                                    Text("No channel names discovered yet. Use “Refresh Shure Channel Names” or connect to this device to fetch them.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(names.keys.sorted(), id: \.self) { channel in
                                            let nameBinding = Binding<String>(
                                                get: { device.shureChannelNames[channel] ?? "" },
                                                set: { newValue in
                                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                                    device.shureChannelNames[channel] = trimmed.isEmpty ? nil : trimmed
                                                    onChange()
                                                }
                                            )
                                            HStack {
                                                Text("CH \(channel)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 52, alignment: .leading)
                                                TextField("Channel Name", text: nameBinding)
                                                Spacer()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if resolvedShureModel == .p10t {
                        GroupBox("PSM 1000 Channel Names") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("These names are used for the two in-ear channels on this PSM 1000. They will override live channel names in the Shure module when available.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)


                                TextField("Channel 1 Name", text: Binding(
                                    get: { device.psmChannel1Name ?? "" },
                                    set: { newValue in
                                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                        device.psmChannel1Name = trimmed.isEmpty ? nil : trimmed
                                        onChange()
                                    }
                                ))

                                TextField("Channel 2 Name", text: Binding(
                                    get: { device.psmChannel2Name ?? "" },
                                    set: { newValue in
                                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                        device.psmChannel2Name = trimmed.isEmpty ? nil : trimmed
                                        onChange()
                                    }
                                ))
                            }
                        }
                        .onAppear { applyP10TAutoChannelNamesIfNeeded() }
                        .onChange(of: device.shureChannelNames) { _, _ in
                            applyP10TAutoChannelNamesIfNeeded()
                        }
                    }

                    if resolvedShureModel == .psm900 {
                        GroupBox("PSM 900 Channel Name") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("This name is used for the single in-ear channel on this PSM 900. It will override the live channel name in the Shure module when available.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                TextField("Channel Name", text: Binding(
                                    get: { device.psmChannel1Name ?? "" },
                                    set: { newValue in
                                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                        device.psmChannel1Name = trimmed.isEmpty ? nil : trimmed
                                        onChange()
                                    }
                                ))
                            }
                        }
                    }
                }

                if hasSelectedModel {
                    networkSection

                    GroupBox("Notes") {
                    TextEditor(text: Binding(
                        get: { device.notes ?? "" },
                        set: { device.notes = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(minHeight: 80)
                    .onChange(of: device.notes) { _, _ in onChange() }
                }
                }
            }
            .padding(.vertical)
        }
        .onDisappear {
            // Ensure we drop any test connections when the editor is closed.
            shureService.disconnect()
            sennheiserService.disconnect()
        }
        .fileImporter(
            isPresented: $showingDiGiCoRTFImporter,
            allowedContentTypes: [UTType.rtf],
            allowsMultipleSelection: false
        ) { result in
            do {
                let urls = try result.get()
                guard let url = urls.first else { return }

                // macOS sandbox: fileImporter returns a security-scoped URL.
                let didStart = url.startAccessingSecurityScopedResource()
                defer {
                    if didStart {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let parsed = try DiGiCoRTFParser.parseRTFFile(at: url)
                let mapped = parsed.map { ExternalDeviceConfig.DiGiCoInputChannel(channel: $0.channel, stereo: $0.stereo, name: $0.name) }

                device.digicoRTFFileName = url.lastPathComponent
                device.digicoRTFImportedAt = Date()
                device.digicoInputChannels = mapped
                digicoRTFImportError = nil
                onChange()
            } catch {
                digicoRTFImportError = "RTF import failed: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showingDiGiCoPadHelp) {
            DigicoPadHelpView()
        }
        .sheet(isPresented: $showingDLiveHelp) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Allen & Heath dLive")
                            .font(.title3.weight(.semibold))

                        Text("Relay connects to dLive over Allen & Heath TCP external control. For most users, the right target is the MixRack.")
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recommended Setup")
                                .font(.headline)
                            Text("1. Put Relay and the dLive system on the same network.")
                            Text("2. Enter the dLive MixRack IP address in Host / IP Address.")
                            Text("3. Set Connection Target to MixRack.")
                            Text("4. Leave TLS off unless the console is configured for TLS-only remote control.")
                            Text("5. If TLS is required, enter the dLive user profile number and password.")
                            Text("6. Run Sync From Console before assigning people nodes.")
                        }
                        .font(.callout)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ports")
                                .font(.headline)
                            Text("MixRack: 51325 plain TCP, 51327 TLS")
                            Text("Surface: 51328 plain TCP, 51329 TLS")
                        }
                        .font(.callout)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("What Relay Uses")
                                .font(.headline)
                            Text("MixRack is the endpoint Relay expects for channel-name sync, channel renaming, and scene recall.")
                            Text("Surface can be selected for testing a surface-side endpoint, but scene recall should still go through the MixRack.")
                        }
                        .font(.callout)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Troubleshooting")
                                .font(.headline)
                            Text("If the console does not respond, switch back to MixRack and confirm Sync From Console works first.")
                            Text("If sync returns no names, verify the IP address, port, TLS settings, and that external control is enabled on the desk.")
                            Text("If this device was created in an older build, re-save the connection target once so Relay can normalize the endpoint setting.")
                        }
                        .font(.callout)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
                .navigationTitle("dLive Help")
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showingDLiveHelp = false
                        }
                    }
                }
            }
            .frame(minWidth: 420, minHeight: 420)
        }
    }

    private var portHint: String {
        switch device.kind {
        case .audioConsole:
            return "Use the console's OSC or remote control port."
        case .vistaConsole:
            return "Use the Vista OSC host and port reserved for future Relay control."
        case .shureWireless:
            if resolvedShureModel == .psm900 {
                return "Network is not used for PSM 900 placeholders; no IP address or transport settings are required."
            } else if shouldShowShureUdpTelemetryControls {
                return "Relay keeps Shure command/control on TCP and can use UDP fast telemetry for supported ULX-D and AD4 receivers based on the selected transport mode."
            } else {
                return "Relay manages the Shure command transport automatically for this receiver."
            }
        case .sennheiserWireless:
            return "Use the host/IP and control port for your Sennheiser monitoring/control endpoint (e.g., Control Cockpit or receiver API)."
        case .lightingConsole:
            return "Use the console's OSC or remote control port."
        case .genericOsc:
            return "Standard OSC devices often use ports like 8000 or 9000."
        }
    }

    private func testSpecteraConnection() {
        let password = SpecteraKeychainStore.shared.password(for: device.id) ?? specteraPassword
        guard !password.isEmpty else {
            specteraConnectionSucceeded = false
            specteraConnectionError = "Enter the Spectera password first."
            return
        }

        isTestingSpecteraConnection = true
        specteraConnectionSucceeded = false
        specteraConnectionError = nil
        specteraCertificateFingerprint = nil
        let deviceID = device.id
        let deviceName = device.name
        let host = device.host

        Task {
            defer { isTestingSpecteraConnection = false }
            do {
                _ = try await specteraConnectionClient.refresh(
                    deviceID: deviceID,
                    deviceName: deviceName,
                    host: host,
                    password: password
                )
                specteraConnectionSucceeded = true
            } catch {
                if let specteraError = error as? SpecteraClientError,
                   case let .certificateTrustRequired(fingerprint) = specteraError {
                    specteraCertificateFingerprint = fingerprint
                }
                specteraConnectionError = error.localizedDescription
            }
        }
    }

    private func trustSpecteraCertificate() {
        guard specteraConnectionClient.trustPendingCertificate(for: device.id) else {
            specteraConnectionError = "The certificate is no longer available. Test the connection again."
            specteraCertificateFingerprint = nil
            return
        }
        specteraCertificateFingerprint = nil
        testSpecteraConnection()
    }

    private var hasSelectedModel: Bool {
        switch device.kind {
        case .audioConsole:
            return device.consoleModelIdentifier?.isEmpty == false
        case .shureWireless:
            return resolvedShureModel != nil
        case .sennheiserWireless:
            return resolvedSennheiserModel != nil
        default:
            return true
        }
    }
}

private struct DigicoPadHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [String] = [
        "Open Setup > External Control on the console.",
        "Enable External Control.",
        "Add a new device and choose DiGiCo Pad.",
        "Enter this computer's IP address in the iPad IP field.",
        "Set Receive Port and Send Port (use unique ports per device; example 8000/9000).",
        "Load the command set that matches your console model and save."
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DiGiCo Pad Setup")
                .font(.title2.bold())

            Text("Follow these steps on the console so Relay can connect:")
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .leading)
                            Text(step)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Text("Tip: Only one DiGiCo Pad device can be active at a time on some console firmware. Disable other devices if the connection fails.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(maxWidth: 520, maxHeight: 520)
    }
}

// MARK: - Shure Connection Helper

/// Lightweight connection tester for Shure wireless devices so you can
/// connect and see basic status directly from the External Devices settings.
final class ShureConnectionService: ObservableObject {
    private struct CachedStatus {
        var lastConnectedAt: Date?
        var lastHeardAt: Date?
        var lastError: String?
        var lastRawPacket: String?
    }

    @Published var isConnected: Bool = false
    @Published var lastError: String?
    @Published var lastConnectedAt: Date?
    @Published var lastHeardAt: Date?
    @Published var lastRawPacket: String?
    @Published var lastTestCommand: String?
    static let shared = ShureConnectionService()
    private static var cachedStatusByEndpoint: [String: CachedStatus] = [:]

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "ExternalDevices.ShureConnection")
    private var pendingNoResponseWorkItem: DispatchWorkItem?
    private var currentDeviceName: String = ""
    private var currentModel: String = ""
    private var currentHost: String = ""
    private var currentPort: UInt16 = 0
    private var isIntentionalDisconnect = false

    private var currentEndpointKey: String {
        "\(currentModel)|\(currentHost):\(currentPort)"
    }

    func connect(device: ExternalDeviceConfig, onConnected: (() -> Void)? = nil) {
        disconnect()

        currentDeviceName = device.name
        currentModel = device.shureModelIdentifier?.uppercased() ?? ""
        currentHost = device.host
        currentPort = device.port
        let shouldProbeHTTP = isLicensedShureDevice()

        let host = device.host
        let port = device.port

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            lastError = "Invalid port \(port)"
            logDiagnostic("Invalid port \(port)", event: "invalid_port")
            return
        }

        let nwHost = NWEndpoint.Host(host)
        let params = NWParameters.tcp
        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        connection = conn
        isIntentionalDisconnect = false
        loadCachedStatus(for: device)
        lastError = nil
        lastRawPacket = nil
        lastTestCommand = nil

        conn.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.connection === conn else { return }
                switch newState {
                case .ready:
                    print("[Shure] Connection ready to \(host):\(port) model=\(self.currentModel.isEmpty ? "unknown" : self.currentModel)")
                    self.isConnected = true
                    self.lastError = nil
                    self.lastConnectedAt = Date()
                    if self.lastHeardAt == nil {
                        self.lastHeardAt = self.lastConnectedAt
                    }
                    self.persistCachedStatus()
                    self.startReceiveLoop()
                    self.scheduleNoResponseWarning(host: host, port: port)
                    onConnected?()
                case .failed(let error):
                    print("[Shure] Connection failed to \(host):\(port) model=\(self.currentModel.isEmpty ? "unknown" : self.currentModel) error=\(error.localizedDescription)")
                    self.isConnected = false
                    self.lastError = error.localizedDescription
                    self.persistCachedStatus()
                    self.logDiagnostic("Connection failed: \(error.localizedDescription)", event: "connect_failed")
                    if shouldProbeHTTP {
                        ShureHTTPProbe().probe(ip: host)
                    }
                case .cancelled:
                    let wasIntentional = self.isIntentionalDisconnect
                    self.isIntentionalDisconnect = false
                    print("[Shure] Connection cancelled to \(host):\(port) model=\(self.currentModel.isEmpty ? "unknown" : self.currentModel)")
                    self.isConnected = false
                    self.persistCachedStatus()
                    if !wasIntentional {
                        self.logDiagnostic("Connection cancelled", event: "cancelled")
                    }
                default:
                    print("[Shure] Connection state updated: \(newState) to \(host):\(port) model=\(self.currentModel.isEmpty ? "unknown" : self.currentModel)")
                }
            }
        }

        print("[Shure] Starting connection to \(host):\(port) model=\(currentModel.isEmpty ? "unknown" : currentModel)")
        conn.start(queue: queue)
    }

    func disconnect() {
        pendingNoResponseWorkItem?.cancel()
        pendingNoResponseWorkItem = nil
        if let connection {
            isIntentionalDisconnect = true
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
        connection = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.persistCachedStatus()
        }
    }

    private func startReceiveLoop() {
        guard let connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data {
                if data.isEmpty {
                    print("[Shure] Received empty packet from \(self.currentHost):\(self.currentPort)")
                } else {
                    let byteCount = data.count
                    let asString = String(data: data, encoding: .utf8)
                    if let asString {
                        print("[Shure] Received \(byteCount) bytes from \(self.currentHost):\(self.currentPort): \"\(asString)\"")

                        DispatchQueue.main.async {
                            self.lastHeardAt = Date()
                            self.lastRawPacket = asString    // 👈 new
                            self.persistCachedStatus()
                        }
                    } else {
                        print("[Shure] Received \(byteCount) bytes (non-UTF8) from \(self.currentHost):\(self.currentPort): \(data as NSData)")
                        DispatchQueue.main.async {
                            self.lastHeardAt = Date()
                            self.persistCachedStatus()
                        }
                    }
                }
            }

            if let error {
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.lastError = error.localizedDescription
                    self.persistCachedStatus()
                }
                print("[Shure] Receive error from \(self.currentHost):\(self.currentPort): \(error.localizedDescription)")
                logDiagnostic("Receive error: \(error.localizedDescription)", event: "receive_error")
                return
            }

            if isComplete {
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.persistCachedStatus()
                }
                print("[Shure] Connection marked complete by remote \(self.currentHost):\(self.currentPort)")
                return
            }

            // Continue listening
            self.startReceiveLoop()
        }
    }

    func sendTestCommand() {
        guard let connection else {
            lastError = "Not connected"
            logDiagnostic("Test command failed: not connected", event: "test_not_connected")
            return
        }
        let command = "GET 0 ALL"
        let payload = "< \(command) >\r\n"
        lastTestCommand = command
        print("[Shure] Sending test command to \(currentHost):\(currentPort): \(command)")
        connection.send(content: payload.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            if let error {
                DispatchQueue.main.async {
                    self?.lastError = error.localizedDescription
                }
                self?.logDiagnostic("Test command send failed: \(error.localizedDescription)", event: "test_send_failed")
            }
        })
    }

    private func scheduleNoResponseWarning(host: String, port: UInt16) {
        pendingNoResponseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isConnected, self.lastHeardAt == nil {
                print("[Shure] No response yet from \(host):\(port) after 2s model=\(self.currentModel.isEmpty ? "unknown" : self.currentModel)")
                self.logDiagnostic("No response after 2s", event: "no_response")
                if self.isLicensedShureDevice() {
                    ShureHTTPProbe().probe(ip: host)
                }
            }
        }
        pendingNoResponseWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func logDiagnostic(_ message: String, event: String) {
        guard isLicensedShureDevice() else { return }
        let model = currentModel.isEmpty ? "unknown" : currentModel
        let key = "shure_connection_\(model)_\(currentHost):\(currentPort)_\(event)"
        RelayDiagnosticsStore.shared.recordShureTrace("settings \(event) \(currentHost):\(currentPort) model=\(model) message=\(message)")
        RelayDiagnosticsStore.shared.recordThrottledError(
            "Shure \(model) \(currentHost):\(currentPort) — \(message)",
            tag: "Shure",
            key: key,
            minInterval: 30
        )
    }

    private func isLicensedShureDevice() -> Bool {
        let upper = currentModel.uppercased()
        return upper.contains("ANX4") || upper.contains("ADTD") || upper.contains("ADTQ")
    }

    func loadCachedStatus(for device: ExternalDeviceConfig) {
        let model = device.shureModelIdentifier?.uppercased() ?? ""
        let key = "\(model)|\(device.host):\(device.port)"
        let cached = Self.cachedStatusByEndpoint[key]
        lastConnectedAt = cached?.lastConnectedAt
        lastHeardAt = cached?.lastHeardAt
        lastError = cached?.lastError
        lastRawPacket = cached?.lastRawPacket
        isConnected = false
    }

    private func persistCachedStatus() {
        guard !currentHost.isEmpty else { return }
        Self.cachedStatusByEndpoint[currentEndpointKey] = CachedStatus(
            lastConnectedAt: lastConnectedAt,
            lastHeardAt: lastHeardAt,
            lastError: lastError,
            lastRawPacket: lastRawPacket
        )
    }
}


// MARK: - Sennheiser Connection Helper

/// Lightweight connection tester for Sennheiser devices/endpoints so you can
/// connect and see basic status directly from the External Devices settings.
final class SennheiserConnectionService: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var lastError: String?
    @Published var lastHeardAt: Date?
    @Published var lastRawPacket: String?

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "ExternalDevices.SennheiserConnection")

    func connect(to host: String, port: UInt16) {
        disconnect()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            lastError = "Invalid port \(port)"
            return
        }

        let nwHost = NWEndpoint.Host(host)
        let params = NWParameters.tcp
        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        connection = conn
        lastError = nil

        conn.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            DispatchQueue.main.async {
                switch newState {
                case .ready:
                    print("[SennheiserConnectionService] Connection ready to \(host):\(port)")
                    self.isConnected = true
                    self.lastError = nil
                    self.startReceiveLoop()
                case .failed(let error):
                    print("[SennheiserConnectionService] Connection failed: \(error)")
                    self.isConnected = false
                    self.lastError = error.localizedDescription
                case .cancelled:
                    print("[SennheiserConnectionService] Connection cancelled")
                    self.isConnected = false
                default:
                    print("[SennheiserConnectionService] Connection state updated: \(newState)")
                }
            }
        }

        print("[SennheiserConnectionService] Starting connection to \(host):\(port)")
        conn.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }

    private func startReceiveLoop() {
        guard let connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data {
                if data.isEmpty {
                    print("[SennheiserConnectionService] Received empty packet")
                } else {
                    let byteCount = data.count
                    let asString = String(data: data, encoding: .utf8)
                    if let asString {
                        print("[SennheiserConnectionService] Received \(byteCount) bytes: \"\(asString)\"")
                        DispatchQueue.main.async {
                            self.lastHeardAt = Date()
                            self.lastRawPacket = asString
                        }
                    } else {
                        print("[SennheiserConnectionService] Received \(byteCount) bytes (non-UTF8): \(data as NSData)")
                        DispatchQueue.main.async {
                            self.lastHeardAt = Date()
                        }
                    }
                }
            }

            if let error {
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.lastError = error.localizedDescription
                }
                print("[SennheiserConnectionService] Receive error: \(error)")
                return
            }

            if isComplete {
                DispatchQueue.main.async {
                    self.isConnected = false
                }
                print("[SennheiserConnectionService] Connection marked complete by remote")
                return
            }

            // Continue listening
            self.startReceiveLoop()
        }
    }
}


// MARK: - Qu Connection Test Helper

/// Sends a MIDI NRPN "get" request over RTP-MIDI and waits for any response bytes.
final class QuConnectionTestService: ObservableObject {
    @Published var isTesting: Bool = false
    @Published var lastResult: Bool? = nil
    @Published var lastResponseAt: Date? = nil
    @Published var lastError: String? = nil
    @Published var lastDebugLog: String? = nil

    private let queue = DispatchQueue(label: "ExternalDevices.QuConnectionTest")
    private var timeoutWorkItem: DispatchWorkItem?
    private var tcpConnection: NWConnection?
    private var didFinish: Bool = false

    private func appendDebug(_ message: String) {
        let line = "[QuTest] \(message)"
        DispatchQueue.main.async {
            if let existing = self.lastDebugLog, !existing.isEmpty {
                self.lastDebugLog = existing + "\n" + line
            } else {
                self.lastDebugLog = line
            }
        }
        #if DEBUG
        print(line)
        #endif
    }

    func test(host: String, port: UInt16) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            finishFailure("Missing host")
            return
        }
        guard port > 0 else {
            finishFailure("Invalid port")
            return
        }

        isTesting = true
        didFinish = false
        lastResult = nil
        lastError = nil
        lastDebugLog = nil
        appendDebug("Starting test for \(trimmedHost):\(port)")

        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil

        tcpConnection?.cancel()
        tcpConnection = nil

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            finishFailure("Invalid port \(port)")
            return
        }

        let connection = NWConnection(host: NWEndpoint.Host(trimmedHost), port: nwPort, using: .tcp)
        tcpConnection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            DispatchQueue.main.async {
                if self.didFinish { return }
                switch state {
                case .setup:
                    self.appendDebug("TCP setup")
                case .preparing:
                    self.appendDebug("TCP preparing")
                case .ready:
                    self.appendDebug("TCP ready")
                    self.sendGetRequest(over: connection)
                    self.startReceive(on: connection)
                case .waiting(let error):
                    self.appendDebug("TCP waiting: \(error.localizedDescription)")
                case .failed(let error):
                    self.finishFailure("TCP failed: \(error.localizedDescription)")
                case .cancelled:
                    self.appendDebug("TCP cancelled")
                @unknown default:
                    self.appendDebug("TCP state: unknown")
                }
            }
        }
        connection.start(queue: queue)

        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.didFinish { return }
            self.finishFailure("No response")
        }
        timeoutWorkItem = timeout
        queue.asyncAfter(deadline: .now() + 2.0, execute: timeout)
    }

    private func sendGetRequest(over connection: NWConnection) {
        let bytes: [UInt8] = [0xB0, 0x63, 0x00, 0xB0, 0x62, 0x00, 0xB0, 0x60, 0x7F]
        let data = Data(bytes)
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if self.didFinish { return }
            if let error {
                self.finishFailure("Send failed: \(error.localizedDescription)")
            } else {
                self.appendDebug("Sent \(bytes.count) bytes")
            }
        })
    }

    private func startReceive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if self.didFinish { return }
            if let error {
                self.finishFailure("Receive failed: \(error.localizedDescription)")
                return
            }
            if let data, !data.isEmpty {
                self.appendDebug("Received \(data.count) bytes")
                self.finishSuccess()
                return
            }
            if isComplete {
                self.finishFailure("Connection closed by peer")
                return
            }
            self.startReceive(on: connection)
        }
    }

    private func finishSuccess() {
        if didFinish { return }
        didFinish = true
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        tcpConnection?.cancel()
        tcpConnection = nil
        appendDebug("Response received")

        DispatchQueue.main.async {
            self.isTesting = false
            self.lastResult = true
            self.lastResponseAt = Date()
            self.lastError = nil
        }
    }

    private func finishFailure(_ message: String) {
        if didFinish { return }
        didFinish = true
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        tcpConnection?.cancel()
        tcpConnection = nil
        appendDebug("Failure: \(message)")

        DispatchQueue.main.async {
            self.isTesting = false
            self.lastResult = false
            self.lastError = message
        }
    }
}


// MARK: - DiGiCo synced channels sheet

private struct DiGiCoSyncedChannelRow: View {
    let channel: ExternalDeviceConfig.DiGiCoDiscoveredChannel

    private var channelLabel: String {
        "#\(channel.index)"
    }

    var body: some View {
        HStack {
            Text(channelLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
            Text(channel.name)
                .font(.body)
        }
    }
}

private extension View {
    @ViewBuilder
    func conditionalNavigationSubtitle(_ subtitle: String) -> some View {
        if #available(iOS 26.0, *) {
            self.navigationSubtitle(subtitle)
        } else {
            self
        }
    }
}

private struct DiGiCoSyncedChannelsSheet: View {
    let device: ExternalDeviceConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let consoleName = device.digicoOSCConsoleName {
                    Section("Console") {
                        LabeledContent("Name", value: consoleName)
                        if let session = device.digicoOSCSessionFilename {
                            LabeledContent("Session", value: session)
                        }
                        if let date = device.digicoOSCSyncedAt {
                            LabeledContent("Synced", value: date.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }

                if !device.digicoInputChannels.isEmpty {
                    Section("Input Channels (\(device.digicoInputChannels.count))") {
                        ForEach(device.digicoInputChannels) { ch in
                            HStack {
                                Text("#\(ch.channel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .trailing)
                                Text(ch.name)
                                    .font(.body)
                                if ch.stereo {
                                    Text("Stereo")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                                }
                            }
                        }
                    }
                }

                let grouped = Dictionary(grouping: device.digicoDiscoveredChannels, by: \.channelType)
                ForEach(DashboardGraph.DiGiCoChannelType.allCases.filter { $0 != .inputChannel }, id: \.self) { type in
                    if let channels = grouped[type], !channels.isEmpty {
                        let sortedChannels = channels.sorted { $0.index < $1.index }
                        Section("\(type.displayName)s (\(sortedChannels.count))") {
                            ForEach(sortedChannels) { ch in
                                DiGiCoSyncedChannelRow(channel: ch)
                            }
                        }
                    }
                }

                if device.digicoInputChannels.isEmpty && device.digicoDiscoveredChannels.isEmpty {
                    ContentUnavailableView(
                        "No synced channels",
                        systemImage: "waveform.slash",
                        description: Text("Tap \"Sync from DiGiCo\" to discover channels from the console.")
                    )
                }
            }
            .navigationTitle("Synced Channels")
            .conditionalNavigationSubtitle(device.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }
}
