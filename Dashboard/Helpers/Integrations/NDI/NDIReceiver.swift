import Foundation

@MainActor
final class NDIReceiverController {
    let pipeline: NDIFramePipeline

    private let configuration: NDIReceiverConfiguration
    private let processor = NDIFrameProcessor()
    private var connectionTask: Task<Void, Never>?
    private var publishTask: Task<Void, Never>?

    init(configuration: NDIReceiverConfiguration, pipeline: NDIFramePipeline? = nil) {
        self.configuration = configuration
        self.pipeline = pipeline ?? NDIFramePipeline()
    }

    func start() {
        guard connectionTask == nil else { return }
        startPublishing()
        // Apply fps cap to the processor so poster/preview/live actually differ.
        let fps = Double(configuration.fpsCap)
        Task { [processor] in await processor.setFrameRateCap(fps) }
        // Detach the connection loop from the main actor so the frame event loop
        // never competes with or blocks the main thread.
        connectionTask = Task.detached(priority: .userInitiated) { [configuration, processor = self.processor] in
            await NDIReceiverController.runConnectionLoop(configuration: configuration, processor: processor)
        }
    }

    func stop() {
        connectionTask?.cancel()
        connectionTask = nil
        publishTask?.cancel()
        publishTask = nil
    }

    func setSuspended(_ reason: NDIStreamSuspensionReason?) {
        Task { [processor] in
            await processor.setSuspended(reason)
        }
    }

    // MARK: - Private

    private func startPublishing() {
        // Strong capture of pipeline is safe — no retain cycle (pipeline doesn't hold
        // the controller). Avoids the Swift 6 "captured var" error from weak capture.
        publishTask = Task.detached(priority: .userInitiated) { [processor = self.processor, pipeline = self.pipeline] in
            var lastPublishedRevision: UInt64 = .max

            while !Task.isCancelled {
                let snapshot = await processor.currentSnapshot()

                if snapshot.revision != lastPublishedRevision {
                    lastPublishedRevision = snapshot.revision
                    await MainActor.run { pipeline.applySnapshot(snapshot) }
                }

                let sleepNanoseconds: UInt64 = snapshot.latestFrame == nil
                    ? 250_000_000
                    : 66_666_667
                try? await Task.sleep(nanoseconds: sleepNanoseconds)
                guard !Task.isCancelled else { return }
            }
        }
    }

    private nonisolated static func runConnectionLoop(
        configuration: NDIReceiverConfiguration,
        processor: NDIFrameProcessor
    ) async {
        var backoff: Double = 1.0

        while !Task.isCancelled {
            await processor.resetRetry()

            // On each attempt, try to pick up a fresh URL from discovery —
            // the first attempt may have url=nil (source not yet discovered),
            // but subsequent retries can use the URL once discovery has run.
            let latestURL = await MainActor.run {
                NDIDiscoveryService.shared.sources
                    .first(where: { $0.id == configuration.sourceID })?.urlAddress
            }
            let effectiveConfig = latestURL != nil
                ? NDIReceiverConfiguration(
                    sourceID: configuration.sourceID,
                    sourceName: configuration.sourceName,
                    sourceURLAddress: latestURL,
                    interfaceID: configuration.interfaceID,
                    qualityTier: configuration.qualityTier,
                    fpsCap: configuration.fpsCap,
                    audioEnabled: configuration.audioEnabled,
                    preferLowLatency: configuration.preferLowLatency
                  )
                : configuration

            let receiver = NDISDKFactory.makeReceiver(configuration: effectiveConfig)
            receiver.start()

            var shouldRetry = false
            eventLoop: for await event in receiver.events {
                if Task.isCancelled { receiver.stop(); return }
                await processor.process(event)
                switch await processor.currentSnapshot().state {
                case .failed, .disconnected:
                    shouldRetry = true
                    break eventLoop
                case .idle, .connecting, .connected, .suspended:
                    break
                }
            }

            receiver.stop()

            guard shouldRetry && !Task.isCancelled else { return }

            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            backoff = min(backoff * 2, 30.0)
        }
    }
}
