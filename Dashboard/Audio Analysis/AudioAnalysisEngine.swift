import Foundation

// MARK: - AudioAnalysisEngine

/// Centralized actor that owns one AudioInputProcessor per named input.
/// Handles subscription reference counting — tap starts on first subscriber, stops on last.
actor AudioAnalysisEngine {
    static let shared = AudioAnalysisEngine()

    private var processors: [UUID: AudioInputProcessor] = [:]
    private var splCounts: [UUID: Int] = [:]
    private var fftCounts: [UUID: Int] = [:]
    private var splSubToInput: [UUID: UUID] = [:]
    private var fftSubToInput: [UUID: UUID] = [:]

    // MARK: - Config management

    func updateInputConfig(_ config: AudioInputConfig) {
        processors[config.id]?.updateConfig(config)
    }

    func removeInput(_ inputID: UUID) {
        processors[inputID]?.stop()
        processors.removeValue(forKey: inputID)
        splCounts.removeValue(forKey: inputID)
        fftCounts.removeValue(forKey: inputID)
    }

    // MARK: - SPL subscriptions

    func subscribeSPL(to inputID: UUID, config: AudioInputConfig) -> (id: UUID, stream: SPLStream) {
        let proc = processor(for: inputID, config: config)
        let (subID, stream) = proc.addSPLSubscriber()
        splCounts[inputID, default: 0] += 1
        splSubToInput[subID] = inputID
        if splCounts[inputID] == 1 && fftCounts[inputID, default: 0] == 0 {
            proc.start()
        }
        return (subID, stream)
    }

    func unsubscribeSPL(id subID: UUID) {
        guard let inputID = splSubToInput.removeValue(forKey: subID),
              let proc = processors[inputID] else { return }
        proc.removeSPLSubscriber(id: subID)
        splCounts[inputID, default: 1] -= 1
        if !proc.hasAnySubscribers { proc.stop() }
    }

    // MARK: - FFT subscriptions

    func subscribeFFT(to inputID: UUID, config: AudioInputConfig, resolution: RTABandResolution) -> (id: UUID, stream: FFTStream) {
        let proc = processor(for: inputID, config: config)
        let (subID, stream) = proc.addFFTSubscriber(resolution: resolution)
        fftCounts[inputID, default: 0] += 1
        fftSubToInput[subID] = inputID
        if fftCounts[inputID] == 1 && splCounts[inputID, default: 0] == 0 {
            proc.start()
        }
        return (subID, stream)
    }

    func unsubscribeFFT(id subID: UUID) {
        guard let inputID = fftSubToInput.removeValue(forKey: subID),
              let proc = processors[inputID] else { return }
        proc.removeFFTSubscriber(id: subID)
        fftCounts[inputID, default: 1] -= 1
        if !proc.hasAnySubscribers { proc.stop() }
    }

    // MARK: - Test helpers (internal)

    func splSubscriberCount(for inputID: UUID) -> Int { splCounts[inputID, default: 0] }
    func fftSubscriberCount(for inputID: UUID) -> Int { fftCounts[inputID, default: 0] }

    // MARK: - Private

    private func processor(for inputID: UUID, config: AudioInputConfig) -> AudioInputProcessor {
        if let existing = processors[inputID] { return existing }
        let p = AudioInputProcessor(config: config)
        processors[inputID] = p
        return p
    }
}
