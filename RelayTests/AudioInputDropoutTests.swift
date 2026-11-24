#if os(macOS)
import XCTest
import CoreAudio
@testable import Relay

/// End-to-end checks of what happens when an input disappears, using real CoreAudio
/// capture. The "unplug" test builds a private aggregate device around BlackHole (visible
/// only to this process), meters it, destroys it, then recreates it with the same UID.
final class AudioInputDropoutTests: XCTestCase {

    private actor Recorder {
        private(set) var payloads: [SPLPayload] = []
        private(set) var frames: [FFTFrame] = []
        func add(_ p: SPLPayload) { payloads.append(p) }
        func add(_ f: FFTFrame) { frames.append(f) }
    }

    /// Polls `condition` every 100 ms until it holds or `timeout` passes.
    private func waitUntil(timeout: TimeInterval, _ condition: () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return await condition()
    }

    func testMissingDeviceReportsNoSignalToSPLAndFFTSubscribers() async throws {
        // On a headless CI Mac the first CoreAudio call can take tens of seconds while the
        // audio system starts, and later calls stay slow enough to block this input's start
        // queue past any sensible limit. Pay that cost first, and skip where CoreAudio is
        // that slow: there the test would time the machine, not the processor. On a normal
        // Mac the call returns almost at once and the test runs.
        let warmUpStart = Date()
        _ = AudioDeviceEnumerator.inputDevices()
        let warmUpSeconds = Date().timeIntervalSince(warmUpStart)
        if warmUpSeconds > 3 {
            throw XCTSkip("CoreAudio took \(Int(warmUpSeconds)) s to list devices; too slow on this machine for a timing test")
        }

        let config = AudioInputConfig(name: "Missing", deviceUID: "relay.test.missing.\(UUID().uuidString)")
        let processor = AudioInputProcessor(config: config)
        let (splID, spl) = processor.addSPLSubscriber()
        let (fftID, fft) = processor.addFFTSubscriber(resolution: .thirdOct)
        let recorder = Recorder()
        let splTask = Task { for await p in spl { await recorder.add(p) } }
        let fftTask = Task { for await f in fft { await recorder.add(f) } }
        processor.start()

        // Normally reported about a second after start (the watchdog's first tick); the
        // generous limit absorbs slow CI machines without hiding a real hang.
        let gotStale = await waitUntil(timeout: 15) {
            let p = await recorder.payloads, f = await recorder.frames
            return p.contains(where: \.isStale) && f.contains(where: \.isStale)
        }
        XCTAssertTrue(gotStale, "A device that can't be opened should be reported as no signal")
        // It must not quietly fall back to another device (e.g. the built-in mic).
        let live = await recorder.payloads.contains { !$0.isStale }
        XCTAssertFalse(live, "Missing device must not meter a different input")

        processor.stop()
        processor.removeSPLSubscriber(id: splID)
        processor.removeFFTSubscriber(id: fftID)
        splTask.cancel(); fftTask.cancel()
    }

    func testUnplugAndReplugRecovers() async throws {
        guard let blackHole = AudioDeviceEnumerator.inputDevices().first(where: { $0.name.contains("BlackHole") }) else {
            throw XCTSkip("Needs the BlackHole virtual audio device")
        }
        let uid = "relay.test.aggregate.\(UUID().uuidString)"
        var device = try createPrivateAggregate(uid: uid, subDeviceUID: blackHole.uid)

        let processor = AudioInputProcessor(config: AudioInputConfig(name: "Agg", deviceUID: uid))
        let (subID, stream) = processor.addSPLSubscriber()
        let recorder = Recorder()
        let consumer = Task { for await p in stream { await recorder.add(p) } }
        processor.start()
        defer {
            processor.stop()
            processor.removeSPLSubscriber(id: subID)
            consumer.cancel()
        }

        // 1. Plugged in: live readings arrive.
        let live = await waitUntil(timeout: 4) { await recorder.payloads.contains { !$0.isStale } }
        XCTAssertTrue(live, "Expected live readings from the aggregate device")

        // 2. Unplug: subscribers are told the signal is gone.
        let beforeUnplug = await recorder.payloads.count
        XCTAssertEqual(AudioHardwareDestroyAggregateDevice(device), noErr)
        let stale = await waitUntil(timeout: 5) {
            await recorder.payloads.dropFirst(beforeUnplug).contains(where: \.isStale)
        }
        XCTAssertTrue(stale, "Expected a no-signal payload after the device disappeared")

        // 3. Replug (same UID): capture restarts by itself and live readings resume.
        let beforeReplug = await recorder.payloads.count
        device = try createPrivateAggregate(uid: uid, subDeviceUID: blackHole.uid)
        defer { AudioHardwareDestroyAggregateDevice(device) }
        let recovered = await waitUntil(timeout: 8) {
            await recorder.payloads.dropFirst(beforeReplug).contains { !$0.isStale }
        }
        XCTAssertTrue(recovered, "Expected capture to recover after the device came back")
    }

    private func createPrivateAggregate(uid: String, subDeviceUID: String) throws -> AudioObjectID {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Relay Dropout Test",
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: subDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: subDeviceUID]]
        ]
        var deviceID = AudioObjectID(0)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID)
        guard status == noErr, deviceID != 0 else {
            throw XCTSkip("Couldn't create an aggregate audio device (status \(status))")
        }
        // Give CoreAudio a moment to publish the new device.
        Thread.sleep(forTimeInterval: 0.5)
        return deviceID
    }
}
#endif
