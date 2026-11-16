import Foundation
import Observation

protocol SharedValueStorage: Sendable {
    func load() async -> Data?
    func save(_ data: Data) async
}

actor InMemorySharedValueStorage: SharedValueStorage {
    private var data: Data?

    func load() -> Data? { data }
    func save(_ data: Data) { self.data = data }
}

/// Stores shared values in a JSON file in Application Support.
///
/// They used to live in `UserDefaults`. Live values (wireless battery/RF/audio, clocks) change
/// constantly, so the store persisted every ~5 s, and every `UserDefaults` write notifies every
/// `@AppStorage` in the app: views that use `@AppStorage`, including the whole Automation graph,
/// re-rendered every 5 s for nothing.
actor FileSharedValueStorage: SharedValueStorage {
    /// The previous `UserDefaults` key. Also what `PreviousRelayImporter` writes on import.
    static let legacyDefaultsKey = "relay_shared_values_v1"

    private let fileURL: URL?
    private let defaults: UserDefaults
    private var lastSaved: Data?

    init(fileURL: URL? = FileSharedValueStorage.defaultFileURL(), defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        self.defaults = defaults
    }

    static func defaultFileURL() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return support.appendingPathComponent("Relay", isDirectory: true)
            .appendingPathComponent("SharedValues.json")
    }

    func load() -> Data? {
        // Values in the legacy key (an older build, or an import from the previous Relay applied
        // at launch) take precedence: move them into the file and clear the key, so a later
        // import is picked up again.
        if let legacy = defaults.data(forKey: Self.legacyDefaultsKey) {
            if write(legacy) {
                defaults.removeObject(forKey: Self.legacyDefaultsKey)
            }
            return legacy
        }
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        lastSaved = data
        return data
    }

    func save(_ data: Data) {
        guard data != lastSaved else { return }
        _ = write(data)
    }

    @discardableResult
    private func write(_ data: Data) -> Bool {
        guard let fileURL else { return false }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            lastSaved = data
            return true
        } catch {
            print("[SharedValues] Failed to save \(fileURL.path): \(error)")
            return false
        }
    }
}

enum SharedValueValidationError: Error, Equatable {
    case emptyName
    case invalidName(String)
    case duplicateName(String)
    case missingValue(UUID)
}

/// One reading from a wireless refresh pass, applied in a batch by `SharedValueStore`.
enum SharedValueWirelessUpdate: Sendable {
    case value(id: UUID, payload: SharedValuePayload)
    case disconnected(id: UUID)
    case stale(id: UUID)
}

struct SharedValueSnapshot: Sendable, Equatable {
    var values: [SharedValue]
    var recentOSCAddresses: [OSCAddressObservation] = []
    var recentTriggerValues: [TriggerValueObservation] = []

    static let empty = SharedValueSnapshot(values: [])
}

actor SharedValueRegistry {
    private let storage: any SharedValueStorage
    private var valuesByID: [UUID: SharedValue] = [:]
    private var recentOSCAddresses: [OSCAddressObservation] = []
    private var recentTriggerValues: [TriggerValueObservation] = []

    init(storage: any SharedValueStorage = FileSharedValueStorage()) {
        self.storage = storage
    }

    func load() async {
        guard let data = await storage.load(),
              let values = try? JSONDecoder().decode([SharedValue].self, from: data) else {
            return
        }
        valuesByID = Dictionary(uniqueKeysWithValues: values.map { original in
            var value = original
            if value.status == .live && value.binding != .manual {
                value.markStale()
            }
            return (value.id, value)
        })
    }

    func create(name: String, binding: SharedValueBinding) throws -> SharedValue {
        let normalized = normalizeSharedValueName(name)
        try validateName(normalized, excluding: nil)
        let value = SharedValue(name: normalized, binding: binding)
        valuesByID[value.id] = value
        return value
    }

    func syncCatalog(_ observations: [SharedValueCatalogObservation], at date: Date = Date()) -> Bool {
        var changed = false
        let keys = Set(observations.map(\.key))
        // Index system values by key once instead of scanning every value per observation.
        var systemIDByKey: [String: UUID] = [:]
        for (id, value) in valuesByID {
            if case let .system(key) = value.binding { systemIDByKey[key] = id }
        }
        for observation in observations {
            let binding = SharedValueBinding.system(key: observation.key)
            let existing = systemIDByKey[observation.key].flatMap { valuesByID[$0] }
            let value = existing ?? createSuggested(baseName: observation.name, binding: binding)
            var updated = value
            updated.origin = .suggested
            if observation.status == .live {
                changed = updated.apply(payload: observation.payload, at: date) || changed
            } else {
                if updated.payload != observation.payload {
                    updated.payload = observation.payload
                    updated.lastUpdatedAt = date
                    changed = true
                }
                if updated.status != observation.status { updated.status = observation.status; changed = true }
            }
            if existing == nil { changed = true }
            valuesByID[updated.id] = updated
        }
        for (id, var value) in valuesByID {
            guard case let .system(key) = value.binding, !keys.contains(key), value.status == .live else { continue }
            value.markStale()
            valuesByID[id] = value
            changed = true
        }
        return changed
    }

    /// Re-evaluates computed values. Returns whether any value changed.
    @discardableResult
    func recomputeComputedValues() -> Bool {
        let computedIDs = valuesByID.compactMap { id, value -> UUID? in
            if case .computed = value.binding { return id }
            return nil
        }
        guard !computedIDs.isEmpty else { return false }
        var idByName: [String: UUID] = [:]
        for (id, value) in valuesByID { idByName[value.name] = id }
        var changed = false
        var visiting: Set<UUID> = []
        var completed: Set<UUID> = []
        func evaluate(_ id: UUID) -> SharedValuePayload? {
            guard let value = valuesByID[id] else { return nil }
            guard case let .computed(expression, type) = value.binding else { return value.payload }
            if completed.contains(id) { return value.payload }
            guard visiting.insert(id).inserted else { return nil }
            let payload = SharedValueExpression.evaluate(expression, type: type) { name in
                guard let dependencyID = idByName[normalizeSharedValueName(name)] else { return nil }
                return evaluate(dependencyID)
            }
            visiting.remove(id)
            completed.insert(id)
            var updated = value
            if let payload { _ = updated.apply(payload: payload, at: Date()) }
            else { updated.payload = nil; updated.status = .neverReceived }
            if updated != value { changed = true }
            valuesByID[id] = updated
            return payload
        }
        for id in computedIDs { _ = evaluate(id) }
        return changed
    }

    func createSuggested(baseName: String, binding: SharedValueBinding) -> SharedValue {
        if let existing = valuesByID.values.first(where: { $0.binding == binding }) {
            return existing
        }
        let base = normalizeSharedValueName(baseName).isEmpty ? "value" : normalizeSharedValueName(baseName)
        var candidate = base
        var suffix = 2
        while valuesByID.values.contains(where: { $0.name == candidate }) {
            candidate = "\(base)_\(suffix)"
            suffix += 1
        }
        let value = SharedValue(name: candidate, binding: binding)
        valuesByID[value.id] = value
        return value
    }

    func syncSuggestedWirelessValues(devices: [ExternalDeviceConfig]) -> Bool {
        var didChange = false
        for device in devices {
            let channelCount: Int
            let makeBinding: (Int, WirelessSharedValueField) -> SharedValueBinding
            switch device.kind {
            case .shureWireless:
                channelCount = device.effectiveShureChannelCount
                makeBinding = { .shure(deviceID: device.id, channel: $0, field: $1) }
            case .sennheiserWireless:
                channelCount = device.sennheiserNetworkModel?.channelCount ?? 1
                makeBinding = { .sennheiser(deviceID: device.id, channel: $0, field: $1) }
            default:
                continue
            }
            let fields: [WirelessSharedValueField] = [.batteryPercent, .rf, .audio, .connected]
            for channel in 1...max(1, channelCount) {
                let channelName: String?
                if device.kind == .shureWireless {
                    channelName = device.shureChannelNames[channel]
                } else {
                    channelName = nil
                }
                for field in fields {
                    let binding = makeBinding(channel, field)
                    guard !valuesByID.values.contains(where: { $0.binding == binding }) else { continue }
                    let baseName = "\(device.name)_\(channelName ?? "ch_\(channel)")_\(field.variableName)"
                    let value = createSuggested(baseName: baseName, binding: binding)
                    valuesByID[value.id] = SharedValue(
                        id: value.id,
                        name: value.name,
                        binding: value.binding,
                        origin: .suggested
                    )
                    didChange = true
                }
            }
        }
        return didChange
    }

    @discardableResult
    func update(id: UUID, payload: SharedValuePayload, at date: Date = Date()) -> Bool {
        guard var value = valuesByID[id] else { return false }
        let changed = value.apply(payload: payload, at: date)
        valuesByID[id] = value
        return changed
    }

    func setManualValue(id: UUID, payload: SharedValuePayload) -> Bool {
        guard let value = valuesByID[id], value.binding == .manual else { return false }
        return update(id: id, payload: payload)
    }

    @discardableResult
    func markDisconnected(binding: SharedValueBinding) -> Bool {
        var changed = false
        for (id, var value) in valuesByID where value.binding == binding {
            guard value.status != .disconnected && value.status != .neverReceived else { continue }
            value.markDisconnected()
            valuesByID[id] = value
            changed = true
        }
        return changed
    }

    /// Applies one wireless refresh pass. Returns whether any value changed.
    func applyWirelessUpdates(_ updates: [SharedValueWirelessUpdate], at date: Date) -> Bool {
        var changed = false
        for update in updates {
            switch update {
            case let .value(id, payload):
                changed = self.update(id: id, payload: payload, at: date) || changed
            case let .disconnected(id):
                // By id: the binding-based variants scan every value per call.
                guard var value = valuesByID[id],
                      value.status != .disconnected && value.status != .neverReceived else { continue }
                value.markDisconnected()
                valuesByID[id] = value
                changed = true
            case let .stale(id):
                guard var value = valuesByID[id], value.status == .live else { continue }
                value.markStale()
                valuesByID[id] = value
                changed = true
            }
        }
        return changed
    }

    @discardableResult
    func markStale(binding: SharedValueBinding) -> Bool {
        var changed = false
        for (id, var value) in valuesByID where value.binding == binding {
            guard value.status == .live else { continue }
            value.markStale()
            valuesByID[id] = value
            changed = true
        }
        return changed
    }

    func markStaleOSCValues(now: Date, timeout: TimeInterval = 30) -> Bool {
        var changed = false
        for (id, var value) in valuesByID {
            guard case .osc = value.binding,
                  value.status == .live,
                  let lastUpdatedAt = value.lastUpdatedAt,
                  now.timeIntervalSince(lastUpdatedAt) >= timeout else { continue }
            value.markStale()
            valuesByID[id] = value
            changed = true
        }
        return changed
    }

    func value(named name: String) -> SharedValue? {
        let normalized = normalizeSharedValueName(name)
        return valuesByID.values.first { $0.name == normalized }
    }

    func value(id: UUID) -> SharedValue? { valuesByID[id] }

    func snapshot() -> SharedValueSnapshot {
        SharedValueSnapshot(
            values: valuesByID.values.sorted { $0.name < $1.name },
            recentOSCAddresses: recentOSCAddresses,
            recentTriggerValues: recentTriggerValues
        )
    }

    func observeOSC(address: String, payload: SharedValuePayload, at date: Date = Date()) {
        recentOSCAddresses.removeAll { $0.address == address }
        recentOSCAddresses.insert(OSCAddressObservation(address: address, payload: payload, receivedAt: date), at: 0)
        recentOSCAddresses = Array(recentOSCAddresses.prefix(100))
    }

    func observeTrigger(triggerID: UUID, field: String, payload: SharedValuePayload, at date: Date = Date()) {
        recentTriggerValues.removeAll { $0.triggerID == triggerID && $0.field == field }
        recentTriggerValues.insert(TriggerValueObservation(triggerID: triggerID, field: field, payload: payload, receivedAt: date), at: 0)
        recentTriggerValues = Array(recentTriggerValues.prefix(100))
        let matchingIDs = valuesByID.compactMap { id, value -> UUID? in
            guard case let .triggerPayload(boundID, boundField, type) = value.binding,
                  boundID == triggerID, boundField == field, type == payload.valueType else { return nil }
            return id
        }
        for id in matchingIDs {
            _ = update(id: id, payload: payload, at: date)
        }
    }

    func bindings() -> [SharedValue] {
        valuesByID.values.sorted { $0.name < $1.name }
    }

    func delete(id: UUID) -> Bool {
        valuesByID.removeValue(forKey: id) != nil
    }

    func persistNow() async {
        let values = valuesByID.values.sorted { $0.name < $1.name }
        guard let data = try? JSONEncoder().encode(values) else { return }
        await storage.save(data)
    }

    private func validateName(_ name: String, excluding id: UUID?) throws {
        guard !name.isEmpty else { throw SharedValueValidationError.emptyName }
        guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            throw SharedValueValidationError.invalidName(name)
        }
        if valuesByID.values.contains(where: { $0.id != id && $0.name == name }) {
            throw SharedValueValidationError.duplicateName(name)
        }
    }
}

private extension WirelessSharedValueField {
    var variableName: String {
        switch self {
        case .batteryPercent: "battery"
        case .rf: "rf"
        case .audio: "audio"
        case .connected: "connected"
        }
    }
}

@MainActor @Observable
final class SharedValueStore {
    static let shared = SharedValueStore()

    private let registry: SharedValueRegistry
    private(set) var snapshot: SharedValueSnapshot = .empty
    // Bookkeeping, never rendered: excluded from observation. As tracked properties, the
    // 5 s persistence timer setting `pendingPersistence` re-rendered every observer, which
    // included the whole Automation graph (a full ~100–150 ms re-render every ~5 s).
    @ObservationIgnored private var pendingPersistence: Task<Void, Never>?
    @ObservationIgnored private var pendingOSCSnapshotRefresh: Task<Void, Never>?
    @ObservationIgnored private var hasLoaded = false

    init(registry: SharedValueRegistry = SharedValueRegistry()) {
        self.registry = registry
    }

    func load() async {
        guard !hasLoaded else { return }
        await registry.load()
        snapshot = await registry.snapshot()
        hasLoaded = true
    }

    @discardableResult
    func create(name: String, binding: SharedValueBinding) async throws -> SharedValue {
        let value = try await registry.create(name: name, binding: binding)
        await registry.persistNow()
        snapshot = await registry.snapshot()
        return value
    }

    @discardableResult
    func createSuggested(baseName: String, binding: SharedValueBinding) async -> SharedValue {
        let value = await registry.createSuggested(baseName: baseName, binding: binding)
        await registry.persistNow()
        snapshot = await registry.snapshot()
        return value
    }

    func delete(id: UUID) async {
        guard await registry.delete(id: id) else { return }
        await registry.persistNow()
        snapshot = await registry.snapshot()
    }

    @discardableResult
    func update(id: UUID, payload: SharedValuePayload, at date: Date = Date()) async -> Bool {
        let changed = await registry.update(id: id, payload: payload, at: date)
        guard changed else { return false }
        snapshot = await registry.snapshot()
        schedulePersistence()
        return true
    }

    @discardableResult
    func setManualValue(id: UUID, payload: SharedValuePayload) async -> Bool {
        let changed = await registry.setManualValue(id: id, payload: payload)
        guard changed else { return false }
        snapshot = await registry.snapshot()
        await registry.persistNow()
        return true
    }

    func markDisconnected(binding: SharedValueBinding) async {
        guard await registry.markDisconnected(binding: binding) else { return }
        snapshot = await registry.snapshot()
        schedulePersistence()
    }

    func markStale(binding: SharedValueBinding) async {
        guard await registry.markStale(binding: binding) else { return }
        snapshot = await registry.snapshot()
        schedulePersistence()
    }

    func markStaleOSCValues(now: Date = Date()) async {
        guard await registry.markStaleOSCValues(now: now) else { return }
        snapshot = await registry.snapshot()
        schedulePersistence()
    }

    func observeOSC(address: String, payload: SharedValuePayload, at date: Date = Date()) async {
        await registry.observeOSC(address: address, payload: payload, at: date)
        // The recent-address list only feeds the Shared Values window, so refresh it at most
        // 4×/s instead of re-sorting and re-publishing the snapshot for every OSC message (a
        // console can send 30–100/s). Bound values still publish immediately via `update`.
        guard pendingOSCSnapshotRefresh == nil else { return }
        let registry = registry
        pendingOSCSnapshotRefresh = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            let next = await registry.snapshot()
            if next != snapshot { snapshot = next }
            pendingOSCSnapshotRefresh = nil
        }
    }

    func observeTrigger(triggerID: UUID, field: String, payload: SharedValuePayload, at date: Date = Date()) async {
        await registry.observeTrigger(triggerID: triggerID, field: field, payload: payload, at: date)
        snapshot = await registry.snapshot()
        schedulePersistence()
    }

    func syncSuggestedWirelessValues(devices: [ExternalDeviceConfig]) async {
        guard await registry.syncSuggestedWirelessValues(devices: devices) else { return }
        await registry.persistNow()
        snapshot = await registry.snapshot()
    }

    func syncCatalog(_ observations: [SharedValueCatalogObservation], at date: Date = Date()) async {
        guard await registry.syncCatalog(observations, at: date) else { return }
        await registry.recomputeComputedValues()
        snapshot = await registry.snapshot()
        schedulePersistence()
    }

    func recomputeComputedValues() async {
        // Runs every refresh tick; only publish (and wake every observing view) on a change.
        guard await registry.recomputeComputedValues() else { return }
        snapshot = await registry.snapshot()
        schedulePersistence()
    }

    /// Applies one wireless refresh pass with a single snapshot rebuild and publish.
    func applyWirelessUpdates(_ updates: [SharedValueWirelessUpdate], at date: Date = Date()) async {
        guard await registry.applyWirelessUpdates(updates, at: date) else { return }
        snapshot = await registry.snapshot()
        schedulePersistence()
    }

    private func schedulePersistence() {
        guard pendingPersistence == nil else { return }
        let registry = registry
        pendingPersistence = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            await registry.persistNow()
            pendingPersistence = nil
        }
    }
}
