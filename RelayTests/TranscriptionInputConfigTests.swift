import XCTest
@testable import Relay

@MainActor
final class TranscriptionInputConfigTests: XCTestCase {

    func testDefaultSensitivityMapsToLegacyTarget() {
        let config = TranscriptionInputConfig(name: "Mic")
        XCTAssertEqual(config.autoGainTarget, 0.06, accuracy: 0.0001)
    }

    func testSensitivityClampedToRange() {
        let low = TranscriptionInputConfig(name: "Low", sensitivity: -5.0)
        XCTAssertEqual(low.sensitivity, 0.0)
        let high = TranscriptionInputConfig(name: "High", sensitivity: 99.0)
        XCTAssertEqual(high.sensitivity, 1.0)
    }

    func testAutoGainTargetRange() {
        let minConfig = TranscriptionInputConfig(name: "Min", sensitivity: 0.0)
        XCTAssertEqual(minConfig.autoGainTarget, 0.02, accuracy: 0.0001)
        let maxConfig = TranscriptionInputConfig(name: "Max", sensitivity: 1.0)
        XCTAssertEqual(maxConfig.autoGainTarget, 0.12, accuracy: 0.0001)
    }

    func testRoundTrip() throws {
        let id = UUID()
        let filter = WordReplacementFilter(from: "relay", to: "Relay")
        let config = TranscriptionInputConfig(
            id: id,
            name: "Pastor Mic",
            deviceUID: "abc-123",
            channelIndex: 2,
            autoGainEnabled: false,
            sensitivity: 0.7,
            enginePreference: .onDevice,
            wordFilters: [filter]
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(TranscriptionInputConfig.self, from: data)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.name, "Pastor Mic")
        XCTAssertEqual(decoded.deviceUID, "abc-123")
        XCTAssertEqual(decoded.channelIndex, 2)
        XCTAssertEqual(decoded.autoGainEnabled, false)
        XCTAssertEqual(decoded.sensitivity, 0.7, accuracy: 0.0001)
        XCTAssertEqual(decoded.enginePreference, .onDevice)
        XCTAssertEqual(decoded.wordFilters.count, 1)
        XCTAssertEqual(decoded.wordFilters[0].from, "relay")
        XCTAssertEqual(decoded.wordFilters[0].to, "Relay")
    }

    func testWordReplacementFilterRoundTrip() throws {
        let filter = WordReplacementFilter(id: UUID(), from: "pro presenter", to: "ProPresenter")
        let data = try JSONEncoder().encode(filter)
        let decoded = try JSONDecoder().decode(WordReplacementFilter.self, from: data)
        XCTAssertEqual(decoded.from, "pro presenter")
        XCTAssertEqual(decoded.to, "ProPresenter")
    }

    func testStorePersistsToUserDefaults() {
        let key = "relay_transcription_inputs_config_v1"
        UserDefaults.standard.removeObject(forKey: key)

        let config = TranscriptionInputConfig(name: "Test Mic")
        let data = try! JSONEncoder().encode([config])
        UserDefaults.standard.set(data, forKey: key)

        let store2 = TranscriptionInputsConfigStore()
        XCTAssertEqual(store2.inputs.count, 1)
        XCTAssertEqual(store2.inputs[0].name, "Test Mic")

        UserDefaults.standard.removeObject(forKey: key)
    }
}
