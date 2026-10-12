import Foundation
import Combine

struct SharedValueWirelessSnapshot: Equatable {
    var batteryPercent: Int?
    var rf: Double?
    var audio: Double?
    var connected: Bool
}

@MainActor
final class SharedValueWirelessAdapter {
    private let store: SharedValueStore
    private let shureSnapshot: (UUID, Int) -> SharedValueWirelessSnapshot?
    private let sennheiserSnapshot: (UUID, Int) -> SharedValueWirelessSnapshot?

    init(
        store: SharedValueStore = .shared,
        shureSnapshot: @escaping (UUID, Int) -> SharedValueWirelessSnapshot?,
        sennheiserSnapshot: @escaping (UUID, Int) -> SharedValueWirelessSnapshot?
    ) {
        self.store = store
        self.shureSnapshot = shureSnapshot
        self.sennheiserSnapshot = sennheiserSnapshot
    }

    func refresh(now: Date = Date()) async {
        for value in store.snapshot.values {
            let snapshot: SharedValueWirelessSnapshot?
            let field: WirelessSharedValueField
            switch value.binding {
            case let .shure(deviceID, channel, bindingField):
                snapshot = shureSnapshot(deviceID, channel)
                field = bindingField
            case let .sennheiser(deviceID, channel, bindingField):
                snapshot = sennheiserSnapshot(deviceID, channel)
                field = bindingField
            default:
                continue
            }

            guard let snapshot else {
                await store.markDisconnected(binding: value.binding)
                continue
            }
            if !snapshot.connected && field != .connected {
                await store.markDisconnected(binding: value.binding)
                continue
            }
            let payload: SharedValuePayload?
            switch field {
            case .batteryPercent: payload = snapshot.batteryPercent.map { .number(Double($0)) }
            case .rf: payload = snapshot.rf.map(SharedValuePayload.number)
            case .audio: payload = snapshot.audio.map(SharedValuePayload.number)
            case .connected: payload = .boolean(snapshot.connected)
            }
            if let payload {
                _ = await store.update(id: value.id, payload: payload, at: now)
            } else if field != .connected {
                await store.markStale(binding: value.binding)
            }
        }
    }
}

@MainActor
final class SharedValueOSCAdapter {
    private let store: SharedValueStore

    init(store: SharedValueStore = .shared) { self.store = store }

    func receive(address: String, text: String?, number: Double?, boolean: Bool?, at date: Date = Date()) async {
        let observed: SharedValuePayload = number.map(SharedValuePayload.number)
            ?? boolean.map(SharedValuePayload.boolean)
            ?? text.map(SharedValuePayload.text)
            ?? .payload("")
        await store.observeOSC(address: address, payload: observed, at: date)
        for value in store.snapshot.values {
            guard case let .osc(boundAddress, payloadType) = value.binding, boundAddress == address else { continue }
            let payload: SharedValuePayload? = switch payloadType {
            case .number: number.map(SharedValuePayload.number)
            case .boolean: boolean.map(SharedValuePayload.boolean)
            case .text: text.map(SharedValuePayload.text)
            case .payload: text.map(SharedValuePayload.payload)
            }
            if let payload { _ = await store.update(id: value.id, payload: payload, at: date) }
        }
    }
}

@MainActor
final class SharedValueTriggerAdapter {
    private let store: SharedValueStore

    init(store: SharedValueStore = .shared) { self.store = store }

    func receive(triggerID: UUID, text: String?, number: Double?, boolean: Bool?, address: String? = nil, at date: Date = Date()) async {
        if let text { await store.observeTrigger(triggerID: triggerID, field: "text", payload: .text(text), at: date) }
        if let number { await store.observeTrigger(triggerID: triggerID, field: "number", payload: .number(number), at: date) }
        if let boolean { await store.observeTrigger(triggerID: triggerID, field: "boolean", payload: .boolean(boolean), at: date) }
        var fields: [String: Any] = [:]
        if let text { fields["text"] = text }
        if let number { fields["number"] = number }
        if let boolean { fields["boolean"] = boolean }
        if let address { fields["address"] = address }
        if !fields.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            await store.observeTrigger(triggerID: triggerID, field: "data", payload: .payload(json), at: date)
        }
    }
}

@MainActor
final class SharedValueSourceCoordinator {
    static let shared = SharedValueSourceCoordinator()

    private var refreshTask: Task<Void, Never>?
    private var oscCancellable: AnyCancellable?
    private var triggerCancellable: AnyCancellable?
    private var deviceCancellable: AnyCancellable?
    private var transcriptionCancellable: AnyCancellable?
    private var tabs: [DashboardTab] = []
    var syncedTabIDs: Set<UUID> { Set(tabs.filter { $0.syncGroupID != nil && !$0.syncIsOwner }.map(\.id)) }
    private var disconnectedGroupIDs: Set<String> = []
    private var transcriptionPayloads: [UUID: TranscriptOutputPayload] = [:]
    private let wirelessConsumerID = UUID()

    func updateTabs(_ tabs: [DashboardTab], disconnectedGroupIDs: Set<String>) {
        self.tabs = tabs
        self.disconnectedGroupIDs = disconnectedGroupIDs
    }

    func syncedTabName(for value: SharedValue) -> String? {
        guard case let .system(key) = value.binding else { return nil }
        let parts = key.split(separator: ":")
        guard parts.count > 1, (parts[0] == "roster" || parts[0] == "planningcenter"),
              let tabID = UUID(uuidString: String(parts[1])) else { return nil }
        return tabs.first(where: { $0.id == tabID && $0.syncGroupID != nil && !$0.syncIsOwner })?.name
    }

    func syncedComputerName(for value: SharedValue) -> String? {
        guard case let .system(key) = value.binding else { return nil }
        let parts = key.split(separator: ":")
        guard parts.count > 1 else { return nil }
        let tab: DashboardTab?
        switch parts[0] {
        case "computer": tab = tabs.first { $0.syncGroupID == String(parts[1]) }
        case "roster", "planningcenter":
            guard let tabID = UUID(uuidString: String(parts[1])) else { return nil }
            tab = tabs.first { $0.id == tabID && $0.syncGroupID != nil && !$0.syncIsOwner }
        default: return nil
        }
        guard let tab else { return nil }
        return tab.syncOwnerDeviceName.isEmpty ? "Unknown computer" : tab.syncOwnerDeviceName
    }

    func tabName(for id: UUID) -> String? {
        tabs.first(where: { $0.id == id })?.name
    }

    func start() {
        guard refreshTask == nil else { return }
        let store = SharedValueStore.shared
        Task { await store.syncSuggestedWirelessValues(devices: ExternalDevicesStore.shared.devices) }
        deviceCancellable = ExternalDevicesStore.shared.$devices
            .receive(on: RunLoop.main)
            .sink { devices in
                Task { await store.syncSuggestedWirelessValues(devices: devices) }
            }
        let adapter = SharedValueWirelessAdapter(
            shureSnapshot: { deviceID, channel in
                let service = ShureWirelessService.shared(for: deviceID)
                return SharedValueWirelessSnapshot(
                    batteryPercent: service.standardReportBatteryPercentage(for: channel),
                    rf: service.standardReportRfBarCount(for: channel).map(Double.init),
                    audio: service.liveAudioLevel(for: channel),
                    connected: service.isConnected
                )
            },
            sennheiserSnapshot: { deviceID, channel in
                let service = SennheiserWirelessService.shared
                let snapshot = service.channelsByDevice[deviceID]?.first { $0.channelIndex == channel }
                return SharedValueWirelessSnapshot(
                    batteryPercent: snapshot?.batteryPercent,
                    rf: snapshot?.rfLevel01,
                    audio: snapshot?.audioLevel01,
                    connected: service.connectionStateByDevice[deviceID] == .connected
                )
            }
        )
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await store.markStaleOSCValues()
                let statuses = ProPresenterModulePlugin.sharedService.stateByModuleID.mapValues(\.status)
                let observations = SharedValueCatalog.observations(
                    now: Date(), clockFormats: ClockFormatPreferences.load(), tabs: tabs, devices: ExternalDevicesStore.shared.devices,
                    proPresenterStatuses: statuses, disconnectedGroupIDs: disconnectedGroupIDs,
                    transcriptionPayloads: transcriptionPayloads
                )
                await store.syncCatalog(observations)
                await store.recomputeComputedValues()
                let hasWirelessBinding = SubscriptionManager.shared.hasPro && SharedValueStore.shared.snapshot.values.contains { value in
                    switch value.binding {
                    case .shure, .sennheiser: true
                    default: false
                    }
                }
                if hasWirelessBinding {
                    reconcileWirelessServices()
                    await adapter.refresh()
                    try? await Task.sleep(for: .milliseconds(500))
                } else {
                    reconcileWirelessServices()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            self?.refreshTask = nil
        }
        transcriptionCancellable = NotificationCenter.default.publisher(for: .liveTranscriptionDidPublish)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let tileID = note.userInfo?["tileId"] as? UUID,
                      let payload = note.userInfo?["payload"] as? TranscriptOutputPayload else { return }
                self?.transcriptionPayloads[tileID] = payload
            }
        let oscAdapter = SharedValueOSCAdapter()
        oscCancellable = NotificationCenter.default.publisher(for: .oscReceivePacketDidArrive)
            .receive(on: RunLoop.main)
            .sink { note in
                let info = note.userInfo ?? [:]
                guard let address = info["address"] as? String else { return }
                Task { @MainActor in
                    await oscAdapter.receive(
                        address: address,
                        text: info["payloadText"] as? String,
                        number: info["payloadNumber"] as? Double,
                        boolean: info["payloadBoolean"] as? Bool
                    )
                }
            }
        let triggerAdapter = SharedValueTriggerAdapter()
        triggerCancellable = NotificationCenter.default.publisher(for: TriggerNodeNotifications.fired)
            .receive(on: RunLoop.main)
            .sink { note in
                guard let triggerID = note.userInfo?[TriggerNodeUserInfoKeys.triggerNodeId] as? UUID else { return }
                Task { @MainActor in
                    await triggerAdapter.receive(
                        triggerID: triggerID,
                        text: note.userInfo?[TriggerNodeUserInfoKeys.payloadText] as? String,
                        number: note.userInfo?[TriggerNodeUserInfoKeys.payloadNumber] as? Double,
                        boolean: note.userInfo?[TriggerNodeUserInfoKeys.payloadBoolean] as? Bool,
                        address: note.userInfo?[TriggerNodeUserInfoKeys.address] as? String
                    )
                }
            }
    }

    private func reconcileWirelessServices() {
        let isLive = SubscriptionManager.shared.hasPro && UserDefaults.standard.bool(forKey: "dashboard_live_mode_enabled")
        let values = SharedValueStore.shared.snapshot.values
        let shureDeviceIDs = Set(values.compactMap { value -> UUID? in
            guard case let .shure(deviceID, _, _) = value.binding else { return nil }
            return deviceID
        })
        for deviceID in shureDeviceIDs {
            let service = ShureWirelessService.shared(for: deviceID)
            service.setLiveModeEnabled(isLive)
            service.setOverviewConsumerVisible(wirelessConsumerID, visible: isLive)
        }
        if values.contains(where: { if case .sennheiser = $0.binding { true } else { false } }) {
            SennheiserWirelessService.shared.setLiveModeEnabled(isLive)
        }
    }
}
