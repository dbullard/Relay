import Foundation

/// Stores DAWTransportViewModel instances by DashboardModuleModel.id so
/// the DAW module survives remounts without restarting MIDI and its status timer.
final class DAWTransportViewModelStore {
    static let shared = DAWTransportViewModelStore()
    private init() {}

    private var cache: [UUID: DAWTransportViewModel] = [:]

    /// Returns the existing view model for moduleId if one exists, creating it if not.
    /// Always calls updateConfiguration so the stored instance reflects the latest config.
    func model(for moduleId: UUID, configuration: DAWTransportModuleConfiguration) -> DAWTransportViewModel {
        if let existing = cache[moduleId] {
            existing.updateConfiguration(configuration)
            return existing
        }
        let model = DAWTransportViewModel(configuration: configuration)
        cache[moduleId] = model
        return model
    }

    func evict(_ moduleId: UUID) {
        cache.removeValue(forKey: moduleId)
    }
}
