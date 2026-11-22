import XCTest
@testable import Relay

/// A deleted SPL tile must release its microphone subscription even in Live Mode, where
/// the controller otherwise keeps running off-screen.
@MainActor
final class DbReaderEvictionTests: XCTestCase {

    private func waitUntil(timeout: TimeInterval, _ condition: () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return await condition()
    }

    func testEvictingALiveMeterReleasesItsSubscription() async throws {
        // Reads the configured inputs only; nothing is written to settings.
        guard let input = AudioInputsConfigStore.shared.inputs.first else {
            throw XCTSkip("Needs at least one configured audio input")
        }
        let engine = AudioAnalysisEngine.shared
        let baseline = await engine.splSubscriberCount(for: input.id)

        let moduleId = UUID()
        var settings = DbReaderModuleModel()
        settings.inputID = input.id
        settings.isEnabled = true
        settings.isArmedByUser = true
        let controller = DbReaderControllerStore.shared.controller(moduleId: moduleId, tileId: UUID(), settings: settings)
        controller.setLiveMode(true)
        controller.setTileActive(true)

        let subscribed = await waitUntil(timeout: 6) {
            await engine.splSubscriberCount(for: input.id) == baseline + 1
        }
        XCTAssertTrue(subscribed, "Live, armed meter should subscribe to its input")

        DbReaderControllerStore.shared.evict(moduleIds: [moduleId])

        let released = await waitUntil(timeout: 6) {
            await engine.splSubscriberCount(for: input.id) == baseline
        }
        XCTAssertTrue(released, "Evicted meter should release its input")
        XCTAssertFalse(controller.isRunning)
    }

    func testStopDuringSubscribeDoesNotLeakASubscription() async throws {
        guard let input = AudioInputsConfigStore.shared.inputs.first else {
            throw XCTSkip("Needs at least one configured audio input")
        }
        let engine = AudioAnalysisEngine.shared
        let baseline = await engine.splSubscriberCount(for: input.id)

        var settings = DbReaderModuleModel()
        settings.inputID = input.id
        settings.isEnabled = true
        settings.isArmedByUser = true
        let controller = DbReaderController(moduleId: UUID(), tileId: UUID(), settings: settings)
        // Start and immediately stop, before the subscribe call on the engine returns.
        controller.setLiveMode(true)
        controller.setTileActive(true)
        controller.setTileActive(false)

        // Give the in-flight subscribe time to land and clean itself up.
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let count = await engine.splSubscriberCount(for: input.id)
        XCTAssertEqual(count, baseline, "A subscription that completed after stop must release itself")
    }
}
