import XCTest
@testable import Relay

@MainActor
final class DbReaderMigrationTests: XCTestCase {

    func testNewJsonRoundTrips() throws {
        let inputID = UUID()
        let original = DbReaderModuleModel(inputID: inputID)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DbReaderModuleModel.self, from: data)
        XCTAssertEqual(decoded.inputID, inputID)
    }

    func testNewJsonDoesNotContainLegacyKeys() throws {
        let original = DbReaderModuleModel(inputID: UUID())
        let data = try JSONEncoder().encode(original)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        XCTAssertNil(json["deviceUID"], "deviceUID should not be encoded")
        XCTAssertNil(json["channelIndex"], "channelIndex should not be encoded")
        XCTAssertNil(json["sourceKind"], "sourceKind should not be encoded")
    }

    func testOldJsonWithAutoLogFields_decodesWithoutError() throws {
        // Simulate a saved dashboard JSON that still has the old autoLog fields.
        // JSONDecoder should silently ignore unknown keys — no throw expected.
        let oldJson = """
        {
            "isEnabled": true,
            "autoLogEnabled": true,
            "autoLogFolderPath": "/Users/test/logs",
            "autoLogFolderBookmarkData": "AQIDBA=="
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DbReaderModuleModel.self, from: oldJson)
        XCTAssertTrue(decoded.isEnabled)
        // autoLog fields are gone — the model just decodes without crashing
    }
}
