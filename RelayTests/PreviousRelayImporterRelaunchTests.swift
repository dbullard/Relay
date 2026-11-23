import XCTest
@testable import Relay

/// "Import and Restart" ends the process directly, so with unsaved dashboard changes it
/// must ask first, and a cancel must leave everything as it was.
final class PreviousRelayImporterRelaunchTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "PreviousRelayImporterRelaunchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func test_cleanDocumentRelaunchesWithoutAsking() {
        let defaults = makeDefaults()
        var asked = false
        var relaunched = false

        let proceeded = PreviousRelayImporter.requestImportAndRelaunch(
            defaults: defaults,
            hasUnsavedChanges: false,
            confirmDiscardingUnsavedChanges: { asked = true; return false },
            relaunch: { relaunched = true }
        )

        XCTAssertTrue(proceeded)
        XCTAssertFalse(asked)
        XCTAssertTrue(relaunched)
        XCTAssertTrue(defaults.bool(forKey: PreviousRelayImporter.pendingKey))
        XCTAssertTrue(defaults.bool(forKey: PreviousRelayImporter.promptAnsweredKey))
    }

    func test_unsavedChangesCancelledChangesNothing() {
        let defaults = makeDefaults()
        var relaunched = false

        let proceeded = PreviousRelayImporter.requestImportAndRelaunch(
            defaults: defaults,
            hasUnsavedChanges: true,
            confirmDiscardingUnsavedChanges: { false },
            relaunch: { relaunched = true }
        )

        XCTAssertFalse(proceeded)
        XCTAssertFalse(relaunched)
        XCTAssertFalse(defaults.bool(forKey: PreviousRelayImporter.pendingKey))
        XCTAssertFalse(defaults.bool(forKey: PreviousRelayImporter.promptAnsweredKey))
    }

    func test_unsavedChangesConfirmedRelaunches() {
        let defaults = makeDefaults()
        var asked = false
        var relaunched = false

        let proceeded = PreviousRelayImporter.requestImportAndRelaunch(
            defaults: defaults,
            hasUnsavedChanges: true,
            confirmDiscardingUnsavedChanges: { asked = true; return true },
            relaunch: { relaunched = true }
        )

        XCTAssertTrue(proceeded)
        XCTAssertTrue(asked)
        XCTAssertTrue(relaunched)
        XCTAssertTrue(defaults.bool(forKey: PreviousRelayImporter.pendingKey))
    }
}
