import Foundation
import SwiftUI

@Observable
final class TranscriptionInputsConfigStore {
    static let shared = TranscriptionInputsConfigStore()

    var inputs: [TranscriptionInputConfig] = [] {
        didSet {
            schedulePersist()
            NotificationCenter.default.post(name: .transcriptionInputsConfigChanged, object: nil)
        }
    }

    private let storageKey = "relay_transcription_inputs_config_v1"
    /// Debounce task — cancelled and replaced on every mutation so rapid edits
    /// (e.g. typing a name character-by-character) only write once per 400 ms.
    private var persistTask: Task<Void, Never>?

    init() { load() }

    func add() {
        inputs.append(TranscriptionInputConfig(name: "Input \(inputs.count + 1)"))
    }

    func remove(at offsets: IndexSet) {
        inputs.remove(atOffsets: offsets)
    }

    func input(for id: UUID) -> TranscriptionInputConfig? {
        inputs.first { $0.id == id }
    }

    func forcePersist() {
        persist()
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
              let decoded = try? JSONDecoder().decode([TranscriptionInputConfig].self, from: data) else { return }
        inputs = decoded
    }
}

extension Notification.Name {
    static let showTranscriptionInputsConfigRequested = Notification.Name("Relay.ShowTranscriptionInputsConfig")
    static let transcriptionInputsConfigChanged = Notification.Name("Relay.TranscriptionInputsConfigChanged")
}
