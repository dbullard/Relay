import SwiftUI

private struct ProfileScene: Identifiable {
    var id: String
    var name: String
    var sourceDeviceID: String
}

struct SmartLightNodeSettingsView: View {
    @Binding var config: DashboardGraph.SmartLightActionConfig
    let profiles: [SmartLightProfile]
    let onTestAction: () -> Void

    @State private var isRefreshingDevices: Bool = false
    @State private var statusMessage: String?
    @State private var isExpandingTargetSelector: Bool = false
    /// True only when a scene was chosen from the top-level Scenes list.
    /// False when the user picked "Activate Scene" from the action picker manually.
    @State private var sceneModeActive: Bool = false

    private var enabledProfiles: [SmartLightProfile] {
        profiles.filter(\.isEnabled)
    }

    private var selectedProfile: SmartLightProfile? {
        enabledProfiles.first(where: { $0.id == config.profileID })
    }

    private var availableDevices: [SmartLightDevice] {
        selectedProfile?.lastDiscoveredDevices ?? []
    }

    private var selectedDevices: [SmartLightDevice] {
        let ids = Set(config.effectiveDeviceIDs)
        return availableDevices.filter { ids.contains($0.id) }
    }

    /// True when the node targets a profile-level scene rather than individual devices.
    private var isSceneMode: Bool {
        config.action.kind == .activateScene && !(config.action.sceneID ?? "").isEmpty
            && config.deviceIDs.isEmpty == false
    }

    /// All unique scenes across the profile's discovered devices, sorted by name.
    private var allProfileScenes: [ProfileScene] {
        var seen = Set<String>()
        var result: [ProfileScene] = []
        for device in availableDevices {
            for scene in device.scenes {
                if seen.insert(scene.id).inserted {
                    result.append(ProfileScene(id: scene.id, name: scene.name, sourceDeviceID: device.id))
                }
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var activeSceneID: String? {
        isSceneMode ? config.action.sceneID : nil
    }

    /// Intersection of capabilities across all selected devices (falls back to full list when none selected).
    private var intersectedCapabilities: Set<SmartLightCapability> {
        guard !selectedDevices.isEmpty else {
            return Set(SmartLightCapability.allCases)
        }
        return selectedDevices.dropFirst().reduce(into: selectedDevices[0].capabilities) {
            $0.formIntersection($1.capabilities)
        }
    }

    private var actionOptions: [SmartLightActionKind] {
        let caps = intersectedCapabilities
        var options: [SmartLightActionKind] = [.turnOn, .turnOff]
        if caps.contains(.toggle) || caps.contains(.stateRead) { options.append(.toggle) }
        options.append(.flash)
        if caps.contains(.brightness) { options.append(.setBrightness) }
        if caps.contains(.color) { options.append(.setColor) }
        if caps.contains(.colorTemperature) { options.append(.setColorTemperature) }
        // Always offer scene activation — devices that don't report scenes via discovery
        // can still accept scene commands with a manually entered ID.
        options.append(.activateScene)
        return options
    }

    private var selectedSceneName: String {
        selectedDevices.first?.scenes.first(where: { $0.id == config.action.sceneID })?.name
            ?? config.action.sceneID
            ?? "Scene"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Smart Light")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .onAppear {
                    if config.effectiveDeviceIDs.isEmpty {
                        isExpandingTargetSelector = true
                    }
                    // Restore sceneModeActive for nodes saved via the Scenes list.
                    if config.action.kind == .activateScene,
                       let sceneID = config.action.sceneID, !sceneID.isEmpty,
                       allProfileScenes.contains(where: { $0.id == sceneID }) {
                        sceneModeActive = true
                    }
                }

            if enabledProfiles.isEmpty {
                Text("Add a Smart Light profile in Settings > External Connections > Smart Lights before using this node.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Connection", selection: Binding<UUID?>(
                    get: { config.profileID },
                    set: { newValue in
                        config.profileID = newValue
                        if let profile = enabledProfiles.first(where: { $0.id == newValue }) {
                            config.providerType = profile.providerType
                            if !profile.lastDiscoveredDevices.contains(where: { $0.id == config.deviceID }) {
                                config.deviceID = profile.lastDiscoveredDevices.first?.id ?? ""
                            }
                        }
                    }
                )) {
                    Text("Select connection").tag(UUID?.none)
                    ForEach(enabledProfiles) { profile in
                        Text(profile.displayName).tag(Optional(profile.id))
                    }
                }
                .pickerStyle(.menu)

                if let selectedProfile {
                    HStack(spacing: 10) {
                        Label(selectedProfile.providerType.displayName, systemImage: "link")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button(isRefreshingDevices ? "Refreshing..." : "Refresh Devices") {
                            refreshDevices(for: selectedProfile)
                        }
                        .font(.caption)
                        .disabled(isRefreshingDevices)
                    }

                    targetSummaryRow

                    if isExpandingTargetSelector {
                        targetSelector
                    }

                    if !sceneModeActive {
                        Picker("Action", selection: Binding(
                            get: { config.action.kind },
                            set: { newValue in
                                config.action.kind = newValue
                            }
                        )) {
                            ForEach(actionOptions, id: \.self) { action in
                                Text(action.displayName).tag(action)
                            }
                        }
                        .pickerStyle(.menu)

                        actionParameterEditors
                    }

                    Divider()

                    AdvancedSection(config: $config)

                    HStack {
                        if let statusMessage, !statusMessage.isEmpty {
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Button("Test Action", action: onTestAction)
                            .disabled(config.profileID == nil || config.deviceID.isEmpty)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var targetSummaryRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpandingTargetSelector.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSceneMode ? "sparkles" : "lightbulb")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text(targetSummaryLabel)
                    .font(.callout)
                    .foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: isExpandingTargetSelector ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var targetSummaryLabel: String {
        if isSceneMode {
            let sceneName = allProfileScenes.first(where: { $0.id == config.action.sceneID })?.name
                ?? config.action.sceneID ?? "Scene"
            return sceneName
        }
        let ids = config.effectiveDeviceIDs
        if ids.isEmpty { return "No target selected" }
        let names = ids.compactMap { id in availableDevices.first(where: { $0.id == id })?.name }
        if names.isEmpty { return "\(ids.count) device\(ids.count == 1 ? "" : "s")" }
        if names.count == 1 { return names[0] }
        return "\(names[0]) +\(names.count - 1) more"
    }

    @ViewBuilder
    private var targetSelector: some View {
        if availableDevices.isEmpty {
            Text("No devices have been discovered for this connection yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                // Devices section — multi-select, disabled while a scene is active.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Devices & Groups")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(availableDevices) { device in
                        let isSelected = !sceneModeActive && config.effectiveDeviceIDs.contains(device.id)
                        Button { toggleDevice(device.id) } label: {
                            HStack {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                Image(systemName: device.isGroup ? "rectangle.3.group" : "lightbulb")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                                Text(device.name)
                                    .font(.callout)
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                if let isOnline = device.isOnline {
                                    Text(isOnline ? "Online" : "Offline")
                                        .font(.caption2)
                                        .foregroundStyle(isOnline ? Color.green : Color.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if !sceneModeActive && config.effectiveDeviceIDs.count > 1 {
                        if config.providerType == .govee {
                            Text("Govee cloud API may rate-limit rapid multi-device calls. Using a Scene below is more reliable.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Action options are limited to capabilities shared by all selected devices.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Scenes section — shown only when scenes exist.
                if !allProfileScenes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scenes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(allProfileScenes) { scene in
                            let isActive = activeSceneID == scene.id
                            Button { selectScene(scene) } label: {
                                HStack {
                                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                                    Text(scene.name)
                                        .font(.callout)
                                        .foregroundStyle(Color.primary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        if sceneModeActive {
                            Button("Switch to device control") { clearScene() }
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func selectScene(_ scene: ProfileScene) {
        config.deviceIDs = [scene.sourceDeviceID]
        config.deviceID = scene.sourceDeviceID
        config.action.kind = .activateScene
        config.action.sceneID = scene.id
        config.sceneName = scene.name
        sceneModeActive = true
        withAnimation(.easeInOut(duration: 0.15)) { isExpandingTargetSelector = false }
    }

    private func clearScene() {
        config.action.kind = .turnOn
        config.action.sceneID = nil
        config.sceneName = ""
        sceneModeActive = false
    }

    private func toggleDevice(_ deviceID: String) {
        // Switching to device mode clears any active top-level scene.
        if sceneModeActive {
            config.action.kind = .turnOn
            config.action.sceneID = nil
            config.sceneName = ""
            sceneModeActive = false
            config.deviceIDs = [deviceID]
            config.deviceID = deviceID
            return
        }
        var ids = config.effectiveDeviceIDs
        if let idx = ids.firstIndex(of: deviceID) {
            ids.remove(at: idx)
        } else {
            ids.append(deviceID)
        }
        config.deviceIDs = ids
        config.deviceID = ids.first ?? ""
        if !actionOptions.contains(config.action.kind) {
            config.action.kind = .turnOn
        }
    }

    @ViewBuilder
    private var actionParameterEditors: some View {
        switch config.action.kind {
        case .turnOn, .turnOff, .toggle:
            EmptyView()
        case .setBrightness:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Brightness")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((config.action.brightnessPercent ?? 100).rounded()))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { config.action.brightnessPercent ?? 100 },
                        set: { config.action.brightnessPercent = min(max($0, 0), 100) }
                    ),
                    in: 0...100
                )
            }
        case .setColor:
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Hex color (#RRGGBB)", text: Binding(
                    get: { config.action.color?.hexString ?? "" },
                    set: { config.action.color = SmartLightColor.parse($0) }
                ))
                .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorPreview)
                        .frame(width: 40, height: 20)
                    Text(config.action.color?.hexString ?? "Enter a 6-digit hex color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .setColorTemperature:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Color Temperature")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(config.action.colorTemperatureKelvin ?? 3500)K")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { Double(config.action.colorTemperatureKelvin ?? 3500) },
                        set: { config.action.colorTemperatureKelvin = Int($0.rounded()) }
                    ),
                    in: 2000...6500,
                    step: 100
                )
            }
        case .activateScene:
            VStack(alignment: .leading, spacing: 8) {
                Text("Scene")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let primaryDevice = selectedDevices.first
                if let primaryDevice, !primaryDevice.scenes.isEmpty {
                    Picker("Scene", selection: Binding(
                        get: { config.action.sceneID ?? "" },
                        set: { newSceneID in
                            config.action.sceneID = newSceneID
                            config.sceneName = primaryDevice.scenes.first(where: { $0.id == newSceneID })?.name ?? config.sceneName
                        }
                    )) {
                        Text("Select scene").tag("")
                        ForEach(primaryDevice.scenes) { scene in
                            Text(scene.name).tag(scene.id)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    TextField("Scene or effect name / ID", text: Binding(
                        get: { config.action.sceneID ?? "" },
                        set: {
                            config.action.sceneID = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                            config.sceneName = config.action.sceneID ?? ""
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                if selectedDevices.isEmpty || selectedDevices.first?.scenes.isEmpty == true {
                    Group {
                        if config.providerType == .govee {
                            Text("Enter a number — e.g. 1, 2, 3. Govee identifies scenes by integer, not by name. To find a scene's number: open the Govee app, tap the device, go to Effects, and long-press an effect. If you type a discovered scene name it will be resolved automatically.")
                        } else {
                            Text("No scenes were returned for this device. Enter the scene name or ID manually if the device supports scenes.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if !(config.action.sceneID ?? "").isEmpty {
                    Text(selectedSceneName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .flash:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Flashes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Stepper(
                        "\(config.action.flashCount ?? 3)",
                        value: Binding(
                            get: { config.action.flashCount ?? 3 },
                            set: { config.action.flashCount = min(max($0, 1), 10) }
                        ),
                        in: 1...10
                    )
                    .fixedSize()
                }
                Text("Turns the light off then on rapidly. Ends with the light on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .queryState:
            EmptyView()
        }
    }

    private var colorPreview: Color {
        guard let color = config.action.color else { return Color.clear.opacity(0.2) }
        return Color(
            red: color.red,
            green: color.green,
            blue: color.blue
        )
    }

    private func refreshDevices(for profile: SmartLightProfile) {
        isRefreshingDevices = true
        statusMessage = nil

        Task {
            do {
                let provider = SmartLightProviderRegistry.makeProvider(profile: profile)
                let devices = try await provider.listDevices()
                await MainActor.run {
                    var updatedProfile = profile
                    updatedProfile.lastDiscoveredDevices = devices
                    updatedProfile.lastValidatedAt = Date()
                    updatedProfile.lastValidationMessage = "Loaded \(devices.count) device\(devices.count == 1 ? "" : "s")."
                    SmartLightProfilesStore.shared.upsert(updatedProfile)
                    if config.deviceID.isEmpty {
                        config.deviceID = devices.first?.id ?? ""
                    }
                    statusMessage = updatedProfile.lastValidationMessage
                    isRefreshingDevices = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isRefreshingDevices = false
                }
            }
        }
    }
}

struct DashboardSmartLightsSettingsView: View {
    @ObservedObject private var profilesStore = SmartLightProfilesStore.shared

    @State private var editingProfileID: UUID?
    @State private var showingEditor = false
    @State private var draftHueApplicationKey: String = ""
    @State private var draftGoveeAPIKey: String = ""
    @State private var workingMessage: String?
    @State private var workingMessageIsError: Bool = false
    @State private var isBusy: Bool = false

    private var profiles: [SmartLightProfile] {
        profilesStore.profiles.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private var editingProfile: SmartLightProfile? {
        profiles.first(where: { $0.id == editingProfileID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Smart Lights")
                    .font(.title2.bold())
                Text("Manage shared Philips Hue and Govee connections used by Automation Mode nodes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Connections")
                            .font(.headline)
                        Spacer()
                        Button {
                            addConnection()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("Add Connection")
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    if profiles.isEmpty {
                        Text("No Smart Light connections yet. Add a Philips Hue or Govee connection to get started.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        List {
                            ForEach(profiles) { profile in
                                SmartLightConnectionRow(profile: profile)
                                    .contentShape(Rectangle())
                                    .onTapGesture { beginEditing(profile) }
                                    .contextMenu {
                                        Button("Edit") { beginEditing(profile) }
                                        Divider()
                                        Button(role: .destructive) {
                                            deleteProfile(profile)
                                        } label: { Text("Delete") }
                                    }
                                    .padding(.vertical, 4)
                            }
                        }
                        .frame(minHeight: 120)
                    }

                    Text("Tap a connection to edit it.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            if let profile = editingProfile {
                SmartLightEditorSheet(
                    profile: profile,
                    hueApplicationKey: draftHueApplicationKey,
                    goveeAPIKey: draftGoveeAPIKey,
                    onSave: { updated, hueKey, goveeKey in
                        draftHueApplicationKey = hueKey
                        draftGoveeAPIKey = goveeKey
                        profilesStore.upsert(updated)
                        SmartLightKeychainStore.shared.saveSecret(hueKey, profileID: updated.id, kind: .hueApplicationKey)
                        SmartLightKeychainStore.shared.saveSecret(goveeKey, profileID: updated.id, kind: .goveeAPIKey)
                    },
                    onDelete: { deleteProfile(profile) },
                    onPairBridge: { pairHueBridge(for: profile) },
                    onValidate: { validateProfile($0) },
                    onDiscoverDevices: { discoverDevices(for: $0) },
                    isBusy: isBusy,
                    workingMessage: workingMessage,
                    isWorkingMessageError: workingMessageIsError
                )
            }
        }
    }

    private func addConnection() {
        let profile = SmartLightProfile(name: "New Smart Light", providerType: .philipsHue)
        profilesStore.upsert(profile)
        beginEditing(profile)
    }

    private func beginEditing(_ profile: SmartLightProfile) {
        editingProfileID = profile.id
        draftHueApplicationKey = SmartLightKeychainStore.shared.loadSecret(profileID: profile.id, kind: .hueApplicationKey) ?? ""
        draftGoveeAPIKey = SmartLightKeychainStore.shared.loadSecret(profileID: profile.id, kind: .goveeAPIKey) ?? ""
        workingMessage = nil
        workingMessageIsError = false
        isBusy = false
        showingEditor = true
    }

    private func deleteProfile(_ profile: SmartLightProfile) {
        showingEditor = false
        profilesStore.removeProfile(id: profile.id)
    }

    private func pairHueBridge(for profile: SmartLightProfile) {
        workingMessage = nil
        workingMessageIsError = false
        isBusy = true
        Task {
            do {
                let provider = HueSmartLightProvider(profile: profile)
                let applicationKey = try await provider.pairBridge()
                await MainActor.run {
                    SmartLightKeychainStore.shared.saveSecret(applicationKey, profileID: profile.id, kind: .hueApplicationKey)
                    draftHueApplicationKey = applicationKey
                    updateProfile(profile) {
                        $0.lastValidatedAt = Date()
                        $0.lastValidationMessage = "Hue bridge paired successfully."
                    }
                    workingMessage = "Hue bridge paired successfully."
                    workingMessageIsError = false
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    workingMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    workingMessageIsError = true
                    isBusy = false
                }
            }
        }
    }

    private func validateProfile(_ profile: SmartLightProfile) {
        workingMessage = nil
        workingMessageIsError = false
        isBusy = true
        Task {
            do {
                let provider = SmartLightProviderRegistry.makeProvider(profile: profile)
                let devices = try await provider.listDevices()
                let message = validationMessage(for: profile, compatibleDeviceCount: devices.count)
                await MainActor.run {
                    updateProfile(profile) {
                        $0.lastValidatedAt = Date()
                        $0.lastValidationMessage = message
                        $0.lastDiscoveredDevices = devices
                    }
                    workingMessage = message
                    workingMessageIsError = false
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    updateProfile(profile) { $0.lastValidatedAt = Date(); $0.lastValidationMessage = message }
                    workingMessage = message
                    workingMessageIsError = true
                    isBusy = false
                }
            }
        }
    }

    private func discoverDevices(for profile: SmartLightProfile) {
        workingMessage = nil
        workingMessageIsError = false
        isBusy = true
        Task {
            do {
                let provider = SmartLightProviderRegistry.makeProvider(profile: profile)
                let devices = try await provider.discoverDevices()
                let message = discoveryMessage(for: profile, compatibleDeviceCount: devices.count)
                await MainActor.run {
                    updateProfile(profile) {
                        $0.lastValidatedAt = Date()
                        $0.lastValidationMessage = message
                        $0.lastDiscoveredDevices = devices
                    }
                    workingMessage = message
                    workingMessageIsError = false
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    updateProfile(profile) { $0.lastValidatedAt = Date(); $0.lastValidationMessage = message }
                    workingMessage = message
                    workingMessageIsError = true
                    isBusy = false
                }
            }
        }
    }

    private func updateProfile(_ original: SmartLightProfile, mutate: (inout SmartLightProfile) -> Void) {
        guard var profile = profilesStore.profile(id: original.id) else { return }
        mutate(&profile)
        profilesStore.upsert(profile)
    }

    private func validationMessage(for profile: SmartLightProfile, compatibleDeviceCount: Int) -> String {
        if profile.providerType == .govee {
            if compatibleDeviceCount == 0 {
                return "Connected to Govee, but no supported lights or plugs were returned for this account."
            }
            return "Connection validated. Found \(compatibleDeviceCount) compatible Govee device\(compatibleDeviceCount == 1 ? "" : "s")."
        }
        return "Connection validated successfully."
    }

    private func discoveryMessage(for profile: SmartLightProfile, compatibleDeviceCount: Int) -> String {
        if profile.providerType == .govee, compatibleDeviceCount == 0 {
            return "Connected to Govee, but no supported lights or plugs were returned for this account."
        }
        return "Discovered \(compatibleDeviceCount) device\(compatibleDeviceCount == 1 ? "" : "s")."
    }
}

private struct SmartLightConnectionRow: View {
    let profile: SmartLightProfile

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(profile.isEnabled ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.callout)
                Text(profile.providerType.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let msg = profile.lastValidationMessage, !msg.isEmpty {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SmartLightEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var profilesStore = SmartLightProfilesStore.shared

    let profile: SmartLightProfile
    let onSave: (SmartLightProfile, String, String) -> Void
    let onDelete: () -> Void
    let onPairBridge: () -> Void
    let onValidate: (SmartLightProfile) -> Void
    let onDiscoverDevices: (SmartLightProfile) -> Void
    let isBusy: Bool
    let workingMessage: String?
    let isWorkingMessageError: Bool

    @State private var draft: SmartLightProfile
    @State private var hueKey: String
    @State private var goveeKey: String

    private var liveProfile: SmartLightProfile {
        profilesStore.profile(id: draft.id) ?? draft
    }

    init(
        profile: SmartLightProfile,
        hueApplicationKey: String,
        goveeAPIKey: String,
        onSave: @escaping (SmartLightProfile, String, String) -> Void,
        onDelete: @escaping () -> Void,
        onPairBridge: @escaping () -> Void,
        onValidate: @escaping (SmartLightProfile) -> Void,
        onDiscoverDevices: @escaping (SmartLightProfile) -> Void,
        isBusy: Bool,
        workingMessage: String?,
        isWorkingMessageError: Bool
    ) {
        self.profile = profile
        self.onSave = onSave
        self.onDelete = onDelete
        self.onPairBridge = onPairBridge
        self.onValidate = onValidate
        self.onDiscoverDevices = onDiscoverDevices
        self.isBusy = isBusy
        self.workingMessage = workingMessage
        self.isWorkingMessageError = isWorkingMessageError
        _draft = State(initialValue: profile)
        _hueKey = State(initialValue: hueApplicationKey)
        _goveeKey = State(initialValue: goveeAPIKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Edit Connection")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    persistDraft()
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()

            Divider()

            ScrollView {
                SmartLightProfileEditor(
                    profile: $draft,
                    validationProfile: liveProfile,
                    hueApplicationKey: $hueKey,
                    goveeAPIKey: $goveeKey,
                    isBusy: isBusy,
                    workingMessage: workingMessage,
                    isWorkingMessageError: isWorkingMessageError,
                    onDelete: { onDelete(); dismiss() },
                    onPairBridge: onPairBridge,
                    onValidate: {
                        persistDraft()
                        onValidate(draft)
                    },
                    onDiscoverDevices: {
                        persistDraft()
                        onDiscoverDevices(draft)
                    }
                )
                .padding()
            }
        }
        .frame(minWidth: 420, minHeight: 400)
    }

    private func persistDraft() {
        let trimmedHueKey = hueKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGoveeKey = goveeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        hueKey = trimmedHueKey
        goveeKey = trimmedGoveeKey
        onSave(draft, trimmedHueKey, trimmedGoveeKey)
    }
}

private struct AdvancedSection: View {
    @Binding var config: DashboardGraph.SmartLightActionConfig
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text("Advanced")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show output ports (S = Success, F = Failure, T = State)", isOn: $config.showOutputPorts)
                    Toggle("Power input overrides configured action", isOn: $config.powerInputOverridesConfig)
                    Toggle("Brightness input overrides configured value", isOn: $config.brightnessInputOverridesConfig)
                    Toggle("Color input overrides configured value", isOn: $config.colorInputOverridesConfig)
                }
                .font(.caption)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct SmartLightProfileEditor: View {
    @Binding var profile: SmartLightProfile
    let validationProfile: SmartLightProfile
    @Binding var hueApplicationKey: String
    @Binding var goveeAPIKey: String
    let isBusy: Bool
    let workingMessage: String?
    let isWorkingMessageError: Bool
    let onDelete: () -> Void
    let onPairBridge: () -> Void
    let onValidate: () -> Void
    let onDiscoverDevices: () -> Void

    private var hasValidatedConnection: Bool {
        validationProfile.lastValidatedAt != nil || (workingMessage != nil && !isWorkingMessageError)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Connection Name", text: $profile.name)
                .textFieldStyle(.roundedBorder)

            Picker("Provider", selection: $profile.providerType) {
                ForEach(SmartLightProviderType.allCases.filter {
                    $0 != .genericFuture
                }) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.menu)

            Toggle("Enabled", isOn: $profile.isEnabled)

            switch profile.providerType {
            case .philipsHue:
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Bridge IP or Host", text: $profile.host)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Hue Application Key", text: $hueApplicationKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Relay uses the local Hue bridge API over your LAN. Press the bridge link button before pairing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .govee:
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("Govee Developer API Key", text: $goveeAPIKey)
                        .textFieldStyle(.roundedBorder)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Requires your own Govee Developer API key obtained directly from Govee. Relay sends commands using your key on your behalf. Some models expose fewer capabilities than others.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 0) {
                            Link("Get an API key at developer.govee.com", destination: URL(string: "https://developer.govee.com")!)
                                .font(.caption)
                            Text(" · Usage subject to ")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Link("Govee's Terms of Service", destination: URL(string: "https://www.govee.com/terms-of-service")!)
                                .font(.caption)
                            Text(".")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            case .genericFuture:
                Text("This placeholder provider is here so we can add Matter, Home Assistant, Kasa, and other integrations later without changing node logic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if profile.providerType == .philipsHue {
                    Button(isBusy ? "Pairing..." : "Pair Hue Bridge", action: onPairBridge)
                        .disabled(isBusy || profile.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Button(isBusy ? "Working..." : "Validate", action: onValidate)
                    .disabled(isBusy)

                if hasValidatedConnection {
                    Button(isBusy ? "Working..." : "Refresh Devices", action: onDiscoverDevices)
                        .disabled(isBusy)
                }

                Spacer()

                Button("Delete", role: .destructive, action: onDelete)
            }

            if let message = workingMessage ?? profile.lastValidationMessage,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label {
                    Text(message)
                } icon: {
                    Image(systemName: workingMessage != nil && isWorkingMessageError
                        ? "exclamationmark.triangle.fill"
                        : "info.circle.fill")
                }
                .font(.caption)
                .foregroundStyle(workingMessage != nil && isWorkingMessageError ? Color.red : Color.secondary)
            }

            if !validationProfile.lastDiscoveredDevices.isEmpty {
                DiscoveryPill(devices: validationProfile.lastDiscoveredDevices)
            }
        }
        .onChange(of: profile.providerType, initial: false) { _, _ in
            profile.lastDiscoveredDevices = []
        }
    }
}

private struct DiscoveryPill: View {
    let devices: [SmartLightDevice]
    @State private var showSheet = false

    private var individualDevices: [SmartLightDevice] { devices.filter { !$0.isGroup } }
    private var groups: [SmartLightDevice] { devices.filter { $0.isGroup } }
    private var allScenes: [SmartLightSceneSummary] {
        var seen = Set<String>()
        return devices.flatMap(\.scenes).filter { seen.insert($0.id).inserted }
    }

    private var pillLabel: String {
        var parts: [String] = []
        let d = individualDevices.count
        let g = groups.count
        let s = allScenes.count
        if d > 0 { parts.append("\(d) device\(d == 1 ? "" : "s")") }
        if g > 0 { parts.append("\(g) group\(g == 1 ? "" : "s")") }
        if s > 0 { parts.append("\(s) scene\(s == 1 ? "" : "s")") }
        return parts.isEmpty ? "No devices" : parts.joined(separator: " · ")
    }

    var body: some View {
        Button {
            showSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text(pillLabel)
                    .font(.caption)
                    .foregroundStyle(Color.primary)
                Image(systemName: "arrow.up.right.square")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            DiscoveryDetailSheet(
                individualDevices: individualDevices,
                groups: groups,
                scenes: allScenes
            )
        }
    }
}

private struct DiscoveryDetailSheet: View {
    let individualDevices: [SmartLightDevice]
    let groups: [SmartLightDevice]
    let scenes: [SmartLightSceneSummary]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Discovered")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !individualDevices.isEmpty {
                        discoverySection(title: "Devices", systemImage: "lightbulb", items: individualDevices)
                    }
                    if !groups.isEmpty {
                        discoverySection(title: "Groups", systemImage: "rectangle.3.group", items: groups)
                    }
                    if !scenes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Scenes", systemImage: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                            ForEach(scenes) { scene in
                                HStack {
                                    Text(scene.name).font(.callout)
                                    Spacer()
                                    Text(scene.id)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .monospaced()
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .frame(minWidth: 360, minHeight: 300)
    }

    @ViewBuilder
    private func discoverySection(title: String, systemImage: String, items: [SmartLightDevice]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            ForEach(items) { device in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.name).font(.callout)
                        if let model = device.model, !model.isEmpty {
                            Text(model).font(.caption).foregroundStyle(.secondary)
                        }
                        if !device.scenes.isEmpty {
                            Text("\(device.scenes.count) scene\(device.scenes.count == 1 ? "" : "s")")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let isOnline = device.isOnline {
                        Text(isOnline ? "Online" : "Offline")
                            .font(.caption)
                            .foregroundStyle(isOnline ? .green : .secondary)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
