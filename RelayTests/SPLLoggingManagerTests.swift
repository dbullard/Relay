import XCTest
@testable import Relay

@MainActor
final class SPLLoggingManagerTests: XCTestCase {

    func testSPLLoggingSettings_roundTrip() throws {
        let settings = SPLLoggingSettings(
            isLogging: true,
            folderPath: "/tmp/logs",
            folderBookmarkData: Data([0x01, 0x02])
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(SPLLoggingSettings.self, from: data)
        XCTAssertEqual(decoded.isLogging, true)
        XCTAssertEqual(decoded.folderPath, "/tmp/logs")
        XCTAssertEqual(decoded.folderBookmarkData, Data([0x01, 0x02]))
    }

    func testSPLLoggingSettings_defaults() {
        let settings = SPLLoggingSettings()
        XCTAssertFalse(settings.isLogging)
        XCTAssertEqual(settings.folderPath, "")
        XCTAssertNil(settings.folderBookmarkData)
    }

    func testStartLogging_setsIsLogging() async {
        let manager = SPLLoggingManager()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        manager.settings.folderPath = tempDir.path
        await manager.startLogging()
        XCTAssertTrue(manager.settings.isLogging)
        await manager.stopLogging()
    }

    func testStopLogging_clearsIsLogging() async {
        let manager = SPLLoggingManager()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        manager.settings.folderPath = tempDir.path
        await manager.startLogging()
        await manager.stopLogging()
        XCTAssertFalse(manager.settings.isLogging)
    }

    func testToggleLogging_flipsState() async {
        let manager = SPLLoggingManager()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        manager.settings.folderPath = tempDir.path
        XCTAssertFalse(manager.settings.isLogging)
        await manager.toggleLogging()
        XCTAssertTrue(manager.settings.isLogging)
        await manager.toggleLogging()
        XCTAssertFalse(manager.settings.isLogging)
    }
}
