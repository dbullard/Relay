import SwiftUI
import XCTest
@testable import Relay

@MainActor
final class DAWPreviewDataSafetyTests: XCTestCase {
    func test_runtimeUsesHUIWhilePreviewIsOff() {
        XCTAssertEqual(DAWTransportType.runtimeType(stored: .reaperMCU, previewEnabled: false), .proToolsHUI)
        XCTAssertEqual(DAWTransportType.runtimeType(stored: .logicProHUI, previewEnabled: false), .genericHUI)
        XCTAssertEqual(DAWTransportType.runtimeType(stored: .reaperMCU, previewEnabled: true), .reaperMCU)
    }

    func test_displayNormalizationPersistsWithoutReplacingSavedProtocol() throws {
        var stored = DAWTransportModuleConfiguration()
        stored.dawType = .reaperMCU
        stored.commandMode = .mcu
        stored.displayMode = .timecode
        stored.appendMTCToDAWDisplay = true
        var persisted: DAWTransportModuleConfiguration?
        let host = DAWTransportModuleSettingsHost(
            config: Binding(get: { stored }, set: { stored = $0 }),
            onPersist: { persisted = stored }
        )

        // Runtime fallback is separate from the stored configuration, even when Preview is off.
        XCTAssertEqual(DAWTransportType.runtimeType(stored: stored.dawType, previewEnabled: false), .proToolsHUI)
        host.normalizeDisplaySettingsIfNeeded()

        XCTAssertNotNil(persisted, "Exercise the real settings persistence hook")
        XCTAssertEqual(persisted?.dawType, .reaperMCU)
        XCTAssertEqual(persisted?.commandMode, .mcu)
        XCTAssertFalse(stored.appendMTCToDAWDisplay)
        let data = try JSONEncoder().encode(XCTUnwrap(persisted))
        XCTAssertEqual(try JSONDecoder().decode(DAWTransportModuleConfiguration.self, from: data).dawType, .reaperMCU)
    }
}
