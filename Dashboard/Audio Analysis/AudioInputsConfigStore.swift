import Foundation
import SwiftUI
import OSLog

@Observable
final class AudioInputsConfigStore {
    static let shared = AudioInputsConfigStore()
    private static let log = Logger(subsystem: "Relay", category: "AudioInputsConfigStore")

    var inputs: [AudioInputConfig] = [] {
        didSet {
            // Diagnostic: this store is process-local (UserDefaults.standard) with no known
            // code path that should clear it from a non-empty state during normal use. If this
            // fires, the call stack pinpoints the actual trigger — see conversation re: reports
            // of the configured inputs list going empty during LAN pairing/sync testing.
            if !oldValue.isEmpty && inputs.isEmpty {
                Self.log.warning("AudioInputsConfigStore.inputs cleared: \(oldValue.count) -> 0. Stack: \(Thread.callStackSymbols.joined(separator: "\n"), privacy: .public)")
            }
            schedulePersist()
            // Push any config changes (e.g. calibrationOffsetDb, device, channel) to running processors.
            let updatedInputs = inputs
            Task { for config in updatedInputs { await AudioAnalysisEngine.shared.updateInputConfig(config) } }
        }
    }

    private let storageKey = "relay_audio_inputs_config_v1"
    /// Debounce task — cancelled and replaced on every mutation so rapid edits
    /// (e.g. typing a name character-by-character) only write once per 400 ms.
    private var persistTask: Task<Void, Never>?

    init() { load() }

    func add() {
        inputs.append(AudioInputConfig(name: "Input \(inputs.count + 1)"))
    }

    func remove(at offsets: IndexSet) {
        inputs.remove(atOffsets: offsets)
    }

    func input(for id: UUID) -> AudioInputConfig? {
        inputs.first { $0.id == id }
    }

    // MARK: - Persistence

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(inputs) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([AudioInputConfig].self, from: data) else { return }
        inputs = decoded
    }
}

extension Notification.Name {
    static let showAudioInputsConfigRequested = Notification.Name("Relay.ShowAudioInputsConfig")
}
