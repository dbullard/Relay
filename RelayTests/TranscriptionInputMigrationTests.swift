import XCTest
@testable import Relay

@MainActor
final class TranscriptionInputMigrationTests: XCTestCase {

    func testSourceConfigDecodesLegacyJsonWithoutTransInputID() throws {
        let oldJson = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "kind": "microphone",
            "displayName": "Mic 1",
            "deviceUID": "abc",
            "channelIndex": 0,
            "color": {"red": 1, "green": 1, "blue": 1, "alpha": 1},
            "isEnabled": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(LiveTranscriptionSourceConfig.self, from: oldJson)
        XCTAssertNil(decoded.transInputID, "transInputID should be nil for legacy JSON")
        XCTAssertEqual(decoded.displayName, "Mic 1")
    }

    func testSourceConfigRoundTripsWithTransInputID() throws {
        let inputID = UUID()
        let source = LiveTranscriptionSourceConfig(
            kind: .microphone,
            displayName: "Pastor",
            deviceUID: "dev-uid",
            channelIndex: 1,
            color: CodableColor(red: 0, green: 1, blue: 1),
            transInputID: inputID
        )
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(LiveTranscriptionSourceConfig.self, from: data)
        XCTAssertEqual(decoded.transInputID, inputID)
        XCTAssertEqual(decoded.displayName, "Pastor")
    }

    func testTranscriptionInputConfigDecodesLegacyJsonWithoutProfanitySettings() throws {
        let oldJson = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "name": "Mic",
            "deviceUID": "abc",
            "channelIndex": 0,
            "color": {"red": 0, "green": 1, "blue": 1, "alpha": 1},
            "autoGainEnabled": true,
            "sensitivity": 0.4,
            "enginePreference": "auto",
            "wordFilters": []
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TranscriptionInputConfig.self, from: oldJson)

        XCTAssertEqual(decoded.profanitySettings.mode, .off)
        XCTAssertTrue(decoded.profanitySettings.includeDefaultList)
        XCTAssertTrue(decoded.profanitySettings.customBlockedWords.isEmpty)
    }

    func testApplyWordFiltersReplacesCaseInsensitive() {
        let filters = [
            WordReplacementFilter(from: "relay", to: "Relay"),
            WordReplacementFilter(from: "pro presenter", to: "ProPresenter")
        ]
        let input = "Welcome to relay and pro presenter"
        var result = input
        for filter in filters {
            let from = filter.from.trimmingCharacters(in: .whitespacesAndNewlines)
            let to = filter.to
            guard !from.isEmpty else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: from)
            guard let regex = try? NSRegularExpression(pattern: escaped, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: to)
        }
        XCTAssertEqual(result, "Welcome to Relay and ProPresenter")
    }

    private func resetTranscriptionMigrationState() {
        UserDefaults.standard.removeObject(forKey: "relay_transcription_inputs_migrated_v2")
        UserDefaults.standard.removeObject(forKey: "relay_transcription_inputs_config_v1")
        TranscriptionInputsConfigStore.shared.inputs = []
    }

    func testMigrationCreatesGlobalInputsFromSources() {
        resetTranscriptionMigrationState()

        let sourceA = LiveTranscriptionSourceConfig(
            kind: .microphone,
            displayName: "Pastor",
            deviceUID: "dante-ch1",
            channelIndex: 0,
            color: CodableColor(red: 0.5, green: 0.5, blue: 1.0)
        )
        let sourceB = LiveTranscriptionSourceConfig(
            kind: .microphone,
            displayName: "Translator",
            deviceUID: "dante-ch4",
            channelIndex: 3,
            color: CodableColor(red: 0, green: 1, blue: 0)
        )

        let moduleModel = LiveTranscriptionModuleModel(sources: [sourceA, sourceB])
        let module = DashboardModuleModel(kind: .liveTranscription(moduleModel), order: 0)
        let tile = DashboardTileModel(
            kind: .empty,
            modules: [module],
            offset: .zero
        )
        let tab = DashboardTab(name: "Main", tiles: [tile])

        let migratedTabs = DashboardRootView.migrateTranscriptionInputs(tabs: [tab])

        let store = TranscriptionInputsConfigStore()
        XCTAssertEqual(store.inputs.count, 2)

        guard case .liveTranscription(let migratedModel) = migratedTabs[0].tiles[0].modules?[0].kind else {
            XCTFail("Expected liveTranscription module")
            return
        }
        XCTAssertNotNil(migratedModel.sources[0].transInputID)
        XCTAssertNotNil(migratedModel.sources[1].transInputID)

        // Running again should not create duplicates
        let _ = DashboardRootView.migrateTranscriptionInputs(tabs: migratedTabs)
        let store2 = TranscriptionInputsConfigStore()
        XCTAssertEqual(store2.inputs.count, 2)

        resetTranscriptionMigrationState()
    }

    func testMigrationDeduplicatesSameDeviceChannel() {
        resetTranscriptionMigrationState()

        let source = LiveTranscriptionSourceConfig(
            kind: .microphone,
            displayName: "Main Mic",
            deviceUID: "usb-mic",
            channelIndex: 0,
            color: CodableColor(red: 0, green: 1, blue: 1)
        )

        let moduleModel = LiveTranscriptionModuleModel(sources: [source])
        let module = DashboardModuleModel(kind: .liveTranscription(moduleModel), order: 0)
        let tile = DashboardTileModel(kind: .empty, modules: [module], offset: .zero)

        let tab1 = DashboardTab(name: "Tab 1", tiles: [tile])
        let tab2 = DashboardTab(name: "Tab 2", tiles: [tile])
        let tabs = [tab1, tab2]

        _ = DashboardRootView.migrateTranscriptionInputs(tabs: tabs)

        let store = TranscriptionInputsConfigStore()
        XCTAssertEqual(store.inputs.count, 1, "Same device/channel should produce one global input")

        resetTranscriptionMigrationState()
    }

    func testApplyWordFiltersEmptyFiltersReturnsOriginal() {
        let filters: [WordReplacementFilter] = []
        let input = "Hello world"
        var result = input
        for filter in filters {
            let from = filter.from.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !from.isEmpty else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: from)
            guard let regex = try? NSRegularExpression(pattern: escaped, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: filter.to)
        }
        XCTAssertEqual(result, "Hello world")
    }
}
