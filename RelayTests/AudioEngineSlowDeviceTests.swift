import XCTest
@testable import Relay

/// One input whose device is slow to open must not hold up any other input's meters.
final class AudioEngineSlowDeviceTests: XCTestCase {

    private actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    private func missingDeviceConfig(_ name: String) -> AudioInputConfig {
        // A device UID that doesn't exist: start fails fast on its own, so the only delay
        // in these tests is the simulated one.
        AudioInputConfig(name: name, deviceUID: "relay.test.missing.\(UUID().uuidString)")
    }

    func testSlowDeviceDoesNotBlockOtherInputs() async {
        let engine = AudioAnalysisEngine()
        let slow = missingDeviceConfig("Slow")
        let other = missingDeviceConfig("Other")

        let slowProcessor = await engine.processorForTesting(inputID: slow.id, config: slow)
        slowProcessor.captureStartHookForTesting = { Thread.sleep(forTimeInterval: 3) }

        var clock = Date()
        let (slowSub, _) = await engine.subscribeSPL(to: slow.id, config: slow)
        XCTAssertLessThan(Date().timeIntervalSince(clock), 0.5, "Subscribing must not wait for the device to open")

        // While the slow device is still opening, another input subscribes and unsubscribes.
        clock = Date()
        let (otherSub, _) = await engine.subscribeSPL(to: other.id, config: other)
        let (otherFFT, _) = await engine.subscribeFFT(to: other.id, config: other, resolution: .thirdOct)
        await engine.unsubscribeSPL(id: otherSub)
        await engine.unsubscribeFFT(id: otherFFT)
        XCTAssertLessThan(Date().timeIntervalSince(clock), 0.5, "Other inputs must not wait behind a slow device")

        await engine.unsubscribeSPL(id: slowSub)
        let remaining = await engine.splSubscriberCount(for: slow.id)
        XCTAssertEqual(remaining, 0)
    }

    func testStartThenStopStillEndsStoppedAfterSlowOpen() async {
        let config = missingDeviceConfig("Ordered")
        let processor = AudioInputProcessor(config: config)
        let opened = expectation(description: "start attempt ran")
        processor.captureStartHookForTesting = {
            Thread.sleep(forTimeInterval: 0.5)
            opened.fulfill()
        }
        let (subID, stream) = processor.addSPLSubscriber()
        let clock = Date()
        processor.start()
        processor.stop()
        XCTAssertLessThan(Date().timeIntervalSince(clock), 0.2, "start/stop must return immediately")
        await fulfillment(of: [opened], timeout: 2)

        // After stop, the watchdog must not keep reporting or retrying.
        let counter = Counter()
        let consumer = Task { for await _ in stream { await counter.increment() } }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        consumer.cancel()
        let received = await counter.value
        XCTAssertEqual(received, 0, "A stopped input must stay quiet")
        processor.removeSPLSubscriber(id: subID)
    }
}
