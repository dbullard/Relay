import XCTest
@testable import Relay

@MainActor
final class WhatsNewStoreTests: XCTestCase {

    private let sampleReleases: [WhatsNewRelease] = [
        WhatsNewRelease(version: "2.4.0", date: "2026-06-28", features: [
            WhatsNewFeature(icon: "waveform", iconColor: "#3498db", title: "Word Trigger Sync", description: "...")
        ]),
        WhatsNewRelease(version: "2.3.0", date: "2026-06-15", features: [
            WhatsNewFeature(icon: "ant", iconColor: "#e74c3c", title: "Bug Fixes", description: "...")
        ])
    ]

    private func makeStore(cacheFileURL: URL? = nil, currentAppVersion: String = "9.9.9") -> WhatsNewStore {
        let defaults = UserDefaults(suiteName: "WhatsNewStoreTests.\(UUID().uuidString)")!
        return WhatsNewStore(defaults: defaults, cacheFileURL: cacheFileURL, currentAppVersion: { currentAppVersion })
    }

    private func writeSampleFeedFixture() throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whatsnew-test-\(UUID().uuidString).json")
        let feed = WhatsNewFeed(releases: sampleReleases)
        try JSONEncoder().encode(feed).write(to: tempURL)
        return tempURL
    }

    func test_init_loadsReleasesFromCachedFeedFile() throws {
        let tempURL = try writeSampleFeedFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let store = makeStore(cacheFileURL: tempURL)

        XCTAssertEqual(store.releases, sampleReleases)
    }

    func test_unseenReleases_isEmpty_whenLastSeenVersionIsEmpty_evenWithCachedReleases() throws {
        let tempURL = try writeSampleFeedFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let store = makeStore(cacheFileURL: tempURL)

        XCTAssertFalse(store.releases.isEmpty)
        XCTAssertEqual(store.lastSeenVersion, "")
        XCTAssertTrue(store.unseenReleases.isEmpty)
        XCTAssertFalse(store.hasUnseenUpdates)
    }

    func test_unseenReleases_returnsOnlyReleasesNewerThanLastSeenVersion() throws {
        let tempURL = try writeSampleFeedFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let store = makeStore(cacheFileURL: tempURL)
        store.markSeen(version: "2.3.0")

        XCTAssertEqual(store.unseenReleases.map(\.version), ["2.4.0"])
        XCTAssertTrue(store.hasUnseenUpdates)
    }

    func test_unseenReleases_isEmpty_whenLastSeenVersionIsCurrent() throws {
        let tempURL = try writeSampleFeedFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let store = makeStore(cacheFileURL: tempURL)
        store.markSeen(version: "2.4.0")

        XCTAssertTrue(store.unseenReleases.isEmpty)
        XCTAssertFalse(store.hasUnseenUpdates)
    }

    func test_unseenReleases_excludesReleasesNewerThanInstalledAppVersion() throws {
        let tempURL = try writeSampleFeedFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let store = makeStore(cacheFileURL: tempURL, currentAppVersion: "2.3.0")
        store.markSeen(version: "2.0.0")

        XCTAssertEqual(
            store.unseenReleases.map(\.version), ["2.3.0"],
            "must not show release notes for a version newer than what's actually installed (2.4.0 isn't installed yet)"
        )
    }

    func test_unseenReleases_isEmpty_whenInstalledVersionOlderThanAllReleases() throws {
        let tempURL = try writeSampleFeedFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let store = makeStore(cacheFileURL: tempURL, currentAppVersion: "2.0.0")
        store.markSeen(version: "1.0.0")

        XCTAssertTrue(store.unseenReleases.isEmpty)
    }

    func test_visibleReleases_excludesReleasesNewerThanInstalledAppVersion() throws {
        let tempURL = try writeSampleFeedFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let store = makeStore(cacheFileURL: tempURL, currentAppVersion: "2.3.0")

        XCTAssertEqual(
            store.visibleReleases.map(\.version), ["2.3.0"],
            "the browsable What's New list must not reveal notes for a version the user doesn't have installed"
        )
    }

    func test_markSeen_updatesLastSeenVersion() {
        let store = makeStore()
        store.markSeen(version: "2.4.0")
        XCTAssertEqual(store.lastSeenVersion, "2.4.0")
    }

    func test_establishBaselineIfNeeded_setsVersion_onlyWhenEmpty() {
        let store = makeStore()
        store.markSeen(version: "2.0.0")
        store.establishBaselineIfNeeded()
        XCTAssertEqual(store.lastSeenVersion, "2.0.0", "must not overwrite an already-established baseline")
    }

    func test_shouldPresentAutoPopup_trueOnceWhenUnseenUpdatesExist() throws {
        let tempURL = try writeSampleFeedFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let store = makeStore(cacheFileURL: tempURL)
        store.markSeen(version: "2.3.0")

        XCTAssertTrue(store.shouldPresentAutoPopup())
    }

    func test_shouldPresentAutoPopup_onlyEverTrueOncePerProcessLifetime() throws {
        let tempURL = try writeSampleFeedFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let store = makeStore(cacheFileURL: tempURL)
        store.markSeen(version: "2.3.0")

        XCTAssertTrue(store.shouldPresentAutoPopup(), "first call should present")
        XCTAssertFalse(
            store.shouldPresentAutoPopup(),
            "must not present again this launch even though hasUnseenUpdates is still true (e.g. a hosting view was recreated and re-checked)"
        )
    }

    func test_shouldPresentAutoPopup_falseWhenNoUnseenUpdates() {
        let store = makeStore()

        XCTAssertFalse(store.shouldPresentAutoPopup())
    }

    func test_markLatestReleaseSeen_usesNewestFeedVersion_notCurrentAppVersion() throws {
        let tempURL = try writeSampleFeedFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let store = makeStore(cacheFileURL: tempURL)
        store.markSeen(version: "2.3.0")
        XCTAssertTrue(store.hasUnseenUpdates)

        store.markLatestReleaseSeen()

        XCTAssertEqual(
            store.lastSeenVersion, "2.4.0",
            "must record the newest release's own version, not Bundle.main's CFBundleShortVersionString"
        )
        XCTAssertFalse(
            store.hasUnseenUpdates,
            "dismissing must actually clear unseen state even when the feed version has no relation to the running app's version"
        )
    }

    func test_markLatestReleaseSeen_doesNotSkipAheadToReleasesNewerThanInstalledVersion() throws {
        let tempURL = try writeSampleFeedFixture()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let store = makeStore(cacheFileURL: tempURL, currentAppVersion: "2.3.0")
        store.markSeen(version: "2.0.0")
        XCTAssertEqual(store.unseenReleases.map(\.version), ["2.3.0"])

        store.markLatestReleaseSeen()

        XCTAssertEqual(
            store.lastSeenVersion, "2.3.0",
            "must not mark 2.4.0 as seen just because it exists in the feed — the user hasn't installed it, so they haven't actually seen it"
        )
    }

    func test_markLatestReleaseSeen_fallsBackToCurrentAppVersion_whenNoReleasesKnown() {
        let store = makeStore()

        store.markLatestReleaseSeen()

        XCTAssertEqual(store.lastSeenVersion, WhatsNewStore.currentAppVersion())
    }
}
