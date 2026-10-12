import XCTest
@testable import Relay

final class RosterImportContainmentTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/tmp/RelayRosterImport-TEST/xl", isDirectory: true)

    func testNormalRelativePathAllowed() {
        XCTAssertNotNil(RosterImportPaths.contained("worksheets/sheet1.xml", in: root))
    }
    func testParentTraversalRejected() {
        XCTAssertNil(RosterImportPaths.contained("../../../../etc/passwd", in: root))
        XCTAssertNil(RosterImportPaths.contained("worksheets/../../../x", in: root))
    }
    func testAbsolutePathRejected() {
        XCTAssertNil(RosterImportPaths.contained("/etc/passwd", in: root))
    }
    func testUnzipListingTotalParsed() {
        let listing = """
        Archive:  x.xlsx
          Length      Date    Time    Name
        ---------  ---------- -----   ----
              100  2026-01-01 00:00   a.xml
              200  2026-01-01 00:00   b.xml
        ---------                     -------
              300                     2 files
        """
        XCTAssertEqual(RosterImportPaths.totalUncompressedBytes(fromUnzipListing: listing), 300)
        XCTAssertEqual(RosterImportPaths.totalUncompressedBytes(fromUnzipListing: "garbage"), nil)
    }
}
