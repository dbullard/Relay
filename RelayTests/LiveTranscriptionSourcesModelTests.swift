import XCTest
import SwiftUI
@testable import Relay

@MainActor
final class LiveTranscriptionSourcesModelTests: XCTestCase {

    func testLimitsEnabledBindingNormalizesNilToFalse() {
        var model = LiveTranscriptionModuleModel()
        model.retention.limitsEnabled = nil

        let binding = LiveTranscriptionRetentionBindings.limitsEnabled(
            get: { model.retention.limitsEnabled }, set: { model.retention.limitsEnabled = $0 })

        XCTAssertFalse(binding.wrappedValue)          // nil reads as false
        binding.wrappedValue = true
        XCTAssertEqual(model.retention.limitsEnabled, true)
        binding.wrappedValue = false
        XCTAssertEqual(model.retention.limitsEnabled, false)   // writes false, not nil
    }

    func testRemovingFirstSourceKeepsRemainingSourceIdentities() {
        var model = LiveTranscriptionModuleModel()
        model.sources = [.fixture(), .fixture(), .fixture()]
        let survivingIDs = model.sources.dropFirst().map(\.id)
        model.sources.removeFirst()
        XCTAssertEqual(model.sources.map(\.id), Array(survivingIDs))
    }
}

private extension LiveTranscriptionSourceConfig {
    static func fixture(id: UUID = UUID(), displayName: String = "Microphone") -> Self {
        LiveTranscriptionSourceConfig(
            id: id,
            kind: .microphone,
            displayName: displayName,
            deviceUID: nil,
            color: CodableColor(.cyan),
            isEnabled: true
        )
    }
}
