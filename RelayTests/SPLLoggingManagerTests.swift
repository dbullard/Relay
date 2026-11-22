import XCTest
@testable import Relay

/// Unit tests run inside a copy of Relay that shares the real app's `UserDefaults` and
/// audio inputs. Every manager here gets a throwaway defaults suite and no inputs, so the
/// tests never change the user's logging folder or on/off state, and never open an audio
/// device.
@MainActor
final class SPLLoggingManagerTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "RelayTests.SPLLogging.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private func makeManager(inputs: [AudioInputConfig] = []) -> SPLLoggingManager {
        let manager = SPLLoggingManager(defaults: defaults,
                                        defaultFolderURL: tempDir.appendingPathComponent("Default"),
                                        inputsProvider: { inputs })
        manager.settings.folderPath = tempDir.path
        return manager
    }

    /// An input whose device doesn't exist, so logging opens a file but no audio hardware.
    private func phantomInput(_ name: String) -> AudioInputConfig {
        AudioInputConfig(name: name, deviceUID: "relay.test.missing.\(UUID().uuidString)")
    }

    private func csvFiles(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "csv" }
    }

    func testUnwritableChosenFolderFallsBackToDefault() async {
        let manager = makeManager(inputs: [phantomInput("Fallback Mic")])
        // Can't be created (system volume), like an unmounted drive.
        manager.settings.folderPath = "/System/RelayTestUnwritable-\(UUID().uuidString)"
        await manager.startLogging()

        XCTAssertTrue(manager.settings.isLogging, "Should still log, just in the default folder")
        XCTAssertNil(manager.folderAccessError)
        XCTAssertNotNil(manager.folderFallbackNotice)
        XCTAssertEqual(manager.activeFolderURL?.path, tempDir.appendingPathComponent("Default").path)
        XCTAssertEqual(csvFiles(in: tempDir.appendingPathComponent("Default")).count, 1)
        // The user's choice is kept for when the drive comes back.
        XCTAssertTrue(manager.settings.folderPath.hasPrefix("/System/RelayTestUnwritable-"))
        await manager.stopLogging()
        XCTAssertNil(manager.folderFallbackNotice)
    }

    func testWritableChosenFolderIsUsed() async {
        let manager = makeManager(inputs: [phantomInput("Chosen Mic")])
        await manager.startLogging()
        XCTAssertEqual(manager.activeFolderURL?.path, tempDir.path)
        XCTAssertNil(manager.folderFallbackNotice)
        XCTAssertEqual(csvFiles(in: tempDir).count, 1)
        await manager.stopLogging()
    }

    func testUseDefaultFolderClearsChoice() {
        let manager = makeManager()
        manager.useDefaultFolder()
        XCTAssertEqual(manager.settings.folderPath, "")
        XCTAssertNil(manager.settings.folderBookmarkData)
        XCTAssertEqual(SPLLoggingSettings.load(from: defaults).folderPath, "")
    }

    func testTemporaryFolderSettingResetsToDefaultOnLaunch() {
        var stale = SPLLoggingSettings()
        stale.folderPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        stale.save(to: defaults)
        let manager = SPLLoggingManager(defaults: defaults, defaultFolderURL: tempDir, inputsProvider: { [] })
        XCTAssertEqual(manager.settings.folderPath, "")
        XCTAssertEqual(SPLLoggingSettings.load(from: defaults).folderPath, "")
    }

    func testTemporaryLocationDetection() {
        XCTAssertTrue(SPLLoggingManager.isTemporaryLocation(NSTemporaryDirectory() + "abc"))
        XCTAssertTrue(SPLLoggingManager.isTemporaryLocation("/tmp/relay"))
        XCTAssertFalse(SPLLoggingManager.isTemporaryLocation(NSHomeDirectory() + "/Documents/Relay/SPL Logs"))
        XCTAssertFalse(SPLLoggingManager.isTemporaryLocation("/Volumes/Media/SPL Logs"))
    }

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
        let manager = makeManager()
        await manager.startLogging()
        XCTAssertTrue(manager.settings.isLogging)
        await manager.stopLogging()
    }

    func testStopLogging_clearsIsLogging() async {
        let manager = makeManager()
        await manager.startLogging()
        await manager.stopLogging()
        XCTAssertFalse(manager.settings.isLogging)
    }

    func testToggleLogging_flipsState() async {
        let manager = makeManager()
        XCTAssertFalse(manager.settings.isLogging)
        await manager.toggleLogging()
        XCTAssertTrue(manager.settings.isLogging)
        await manager.toggleLogging()
        XCTAssertFalse(manager.settings.isLogging)
    }

    func testSettingsPersistToInjectedStore() async {
        let manager = makeManager()
        await manager.startLogging()
        let saved = SPLLoggingSettings.load(from: defaults)
        XCTAssertTrue(saved.isLogging)
        XCTAssertEqual(saved.folderPath, tempDir.path)
        await manager.stopLogging()
        XCTAssertFalse(SPLLoggingSettings.load(from: defaults).isLogging)
    }

    func testDoesNotTouchTheAppsRealSettings() async {
        let realBefore = UserDefaults.standard.data(forKey: SPLLoggingSettings.userDefaultsKey)
        let manager = makeManager()
        await manager.startLogging()
        manager.saveSettings()
        await manager.stopLogging()
        let realAfter = UserDefaults.standard.data(forKey: SPLLoggingSettings.userDefaultsKey)
        XCTAssertEqual(realBefore, realAfter, "Tests must not change the real SPL logging settings")
    }
}
