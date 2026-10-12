import XCTest
@testable import Relay

final class ProPresenterPasswordPolicyTests: XCTestCase {
    func testExportNeverIncludesPassword() {
        XCTAssertEqual(ProPresenterPasswordPolicy.exportedPassword("hunter2"), "")
        XCTAssertEqual(ProPresenterPasswordPolicy.exportedPassword(""), "")
    }

    func testImportedEmptyPasswordIsNeverApplied() {
        XCTAssertFalse(ProPresenterPasswordPolicy.shouldApplyImported(""))
    }

    func testImportedNonEmptyPasswordFromLegacyFileStillApplies() {
        // Files saved by older builds contain the password; honor it on open so nothing regresses.
        XCTAssertTrue(ProPresenterPasswordPolicy.shouldApplyImported("hunter2"))
    }
}
