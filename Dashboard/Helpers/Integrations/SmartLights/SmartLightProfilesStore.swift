import Foundation
import Combine

final class SmartLightProfilesStore: ObservableObject {
    static let shared = SmartLightProfilesStore()

    @Published var profiles: [SmartLightProfile] = [] {
        didSet { scheduleSave() }
    }

    private let storageKey = "Relay.SmartLightProfilesStore.v1"
    private var saveTask: Task<Void, Never>?
    private var isLoadingFromDisk = false

    private init() {
        loadFromDisk()
    }

    func loadFromDisk() {
        isLoadingFromDisk = true
        defer { isLoadingFromDisk = false }
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SmartLightProfile].self, from: data) else {
            profiles = []
            return
        }
        profiles = decoded
    }

    func saveToDisk() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func scheduleSave() {
        guard !isLoadingFromDisk else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            self.saveToDisk()
        }
    }

    func upsert(_ profile: SmartLightProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
    }

    func removeProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        SmartLightKeychainStore.shared.clearSecrets(for: id)
    }

    func profile(id: UUID?) -> SmartLightProfile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }

    var enabledProfiles: [SmartLightProfile] {
        profiles.filter(\.isEnabled)
    }
}

