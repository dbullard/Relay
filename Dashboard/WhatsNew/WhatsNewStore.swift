import Foundation
import Combine

@MainActor
final class WhatsNewStore: ObservableObject {
    static let shared = WhatsNewStore()

    @Published private(set) var releases: [WhatsNewRelease] = []

    private let defaults: UserDefaults
    private let cacheFileURL: URL?
    private let currentAppVersionProvider: () -> String
    private static let lastSeenVersionKey = "relay_whatsnew_last_seen_version"

    init(
        defaults: UserDefaults = .standard,
        cacheFileURL: URL? = WhatsNewStore.defaultCacheFileURL(),
        currentAppVersion: @escaping () -> String = WhatsNewStore.currentAppVersion
    ) {
        self.defaults = defaults
        self.cacheFileURL = cacheFileURL
        self.currentAppVersionProvider = currentAppVersion
        self.releases = Self.loadCachedReleases(from: cacheFileURL) ?? []
    }

    var lastSeenVersion: String {
        get { defaults.string(forKey: Self.lastSeenVersionKey) ?? "" }
        set { defaults.set(newValue, forKey: Self.lastSeenVersionKey) }
    }

    /// Releases the installed build can actually show — excludes anything documenting a version
    /// newer than what's installed, so an older client never displays notes for features it
    /// doesn't have yet just because the feed (shared across all clients on a channel) already
    /// lists them.
    var visibleReleases: [WhatsNewRelease] {
        let installed = currentAppVersionProvider()
        return releases.filter { !$0.version.isNewerRelayVersion(than: installed) }
    }

    /// Visible releases strictly newer than `lastSeenVersion`. Empty until a baseline has been
    /// established, so a fresh install never dumps the entire history into the auto-popup sheet.
    var unseenReleases: [WhatsNewRelease] {
        let seen = lastSeenVersion
        guard !seen.isEmpty else { return [] }
        return visibleReleases.filter { $0.version.isNewerRelayVersion(than: seen) }
    }

    var hasUnseenUpdates: Bool {
        !unseenReleases.isEmpty
    }

    private var hasPresentedAutoPopupThisLaunch = false

    /// Whether the auto-popup sheet should be shown right now. Returns `true` at most once per
    /// process lifetime — the store outlives any single view, so this holds even if the hosting
    /// view is recreated (e.g. navigating away and back) and re-evaluates within the same launch.
    func shouldPresentAutoPopup() -> Bool {
        guard !hasPresentedAutoPopupThisLaunch, hasUnseenUpdates else { return false }
        hasPresentedAutoPopupThisLaunch = true
        return true
    }

    func markSeen(version: String = WhatsNewStore.currentAppVersion()) {
        lastSeenVersion = version
    }

    /// Marks the newest *visible* release as seen. Dismissal must track against actual feed
    /// content, not `Bundle.main`'s own version — the feed can ship updates independently of an
    /// app release, so comparing against the app version can leave `hasUnseenUpdates` permanently
    /// true and cause the auto-popup to reappear on every fresh launch. It must also stop at
    /// `visibleReleases` rather than the raw feed, so dismissing today's popup doesn't silently
    /// mark a not-yet-installed future release as seen too.
    func markLatestReleaseSeen() {
        guard let newest = unseenReleases.max(by: { $1.version.isNewerRelayVersion(than: $0.version) }) else {
            markSeen()
            return
        }
        markSeen(version: newest.version)
    }

    /// First-launch baseline: if we've never recorded a "last seen" version, record the current
    /// app version now without treating existing feed history as unseen.
    func establishBaselineIfNeeded() {
        guard lastSeenVersion.isEmpty else { return }
        markSeen()
    }

    func refresh() async {
        guard let client = WhatsNewClient(baseURL: RelayLicensingConfig.apiBaseURL) else { return }
        do {
            let feed = try await client.fetchFeed(channel: RelayLicensingConfig.whatsNewFeedChannel)
            releases = feed.releases
            persistCache(feed)
        } catch {
            // Silent by design: keep whatever was already cached, don't surface an error UI.
        }
    }

    nonisolated static func currentAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private nonisolated static func defaultCacheFileURL() -> URL? {
        guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = cachesDir.appendingPathComponent("Relay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("whatsnew-feed.json")
    }

    private static func loadCachedReleases(from url: URL?) -> [WhatsNewRelease]? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WhatsNewFeed.self, from: data).releases
    }

    private func persistCache(_ feed: WhatsNewFeed) {
        guard let cacheFileURL, let data = try? JSONEncoder().encode(feed) else { return }
        try? data.write(to: cacheFileURL, options: .atomic)
    }
}
