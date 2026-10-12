import Foundation
import Combine
#if os(macOS)
import AppKit
#endif

@MainActor
final class DashboardRecentDocumentsStore: ObservableObject {
    static let shared = DashboardRecentDocumentsStore()

    @Published private(set) var recentDocumentURLs: [URL] = []

    private init() {
        refresh()
    }

    func noteDocumentURL(_ url: URL) {
#if os(macOS)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
#else
        storeRecentBookmark(for: url)
#endif
        refresh()
    }

    func clearRecentDocuments() {
#if os(macOS)
        NSDocumentController.shared.clearRecentDocuments(self)
#else
        UserDefaults.standard.removeObject(forKey: Self.iOSRecentItemsKey)
#endif
        refresh()
    }

    func refresh() {
#if os(macOS)
        recentDocumentURLs = NSDocumentController.shared.recentDocumentURLs.filter {
            $0.pathExtension.lowercased() == "relay" || $0.pathExtension.lowercased() == "pld"
        }
#else
        recentDocumentURLs = resolveStoredBookmarks()
#endif
    }

#if !os(macOS)
    private static let iOSRecentItemsKey = "relay_recent_document_items_v1"
    private static let maxRecentCount = 20

    private struct RecentItem: Codable {
        let path: String
        let bookmarkData: Data?
    }

    private func storeRecentBookmark(for url: URL) {
        // Start scope before creating bookmark — required for file provider (Google Drive etc.) URLs.
        let scoped = url.startAccessingSecurityScopedResource()
        let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        if scoped { url.stopAccessingSecurityScopedResource() }

        let newItem = RecentItem(path: url.path, bookmarkData: bookmark)
        var items = loadRecentItems()
        items.removeAll { $0.path == url.path }
        items.insert(newItem, at: 0)
        if items.count > Self.maxRecentCount { items = Array(items.prefix(Self.maxRecentCount)) }
        saveRecentItems(items)
    }

    private func resolveStoredBookmarks() -> [URL] {
        loadRecentItems().compactMap { item -> URL? in
            // Prefer the bookmark-resolved URL — it carries security scope for file providers.
            if let data = item.bookmarkData {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) {
                    let ext = url.pathExtension.lowercased()
                    if ext == "relay" || ext == "pld" { return url }
                }
            }
            // Fallback to path URL — works for iCloud Drive and app sandbox.
            let url = URL(fileURLWithPath: item.path)
            let ext = url.pathExtension.lowercased()
            return (ext == "relay" || ext == "pld") ? url : nil
        }
    }

    private func loadRecentItems() -> [RecentItem] {
        guard let data = UserDefaults.standard.data(forKey: Self.iOSRecentItemsKey),
              let items = try? JSONDecoder().decode([RecentItem].self, from: data) else { return [] }
        return items
    }

    private func saveRecentItems(_ items: [RecentItem]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.iOSRecentItemsKey)
        }
    }
#endif
}

@MainActor
final class DashboardDocumentController: ObservableObject {
    enum Action: Equatable {
        case save
        case saveAs
        case openPicker
        case newDashboard
        case quitApplication
        case openSpecific(URL)
    }

    struct Request: Identifiable, Equatable {
        let id = UUID()
        let action: Action
    }

    static let shared = DashboardDocumentController()

    @Published private(set) var pendingRequest: Request?

    private init() {}

    func saveCurrentDocument() {
        pendingRequest = Request(action: .save)
    }

    func saveCurrentDocumentAs() {
        pendingRequest = Request(action: .saveAs)
    }

    func openDocument(afterHandlingUnsavedChanges _: Bool = true) {
        pendingRequest = Request(action: .openPicker)
    }

    func newDocument(afterHandlingUnsavedChanges _: Bool = true) {
        pendingRequest = Request(action: .newDashboard)
    }

    func quitApplication(afterHandlingUnsavedChanges _: Bool = true) {
        pendingRequest = Request(action: .quitApplication)
    }

    func openSpecificDocument(_ url: URL) {
        pendingRequest = Request(action: .openSpecific(url))
    }

    func consumeRequest(_ request: Request) {
        guard pendingRequest?.id == request.id else { return }
        pendingRequest = nil
    }
}
