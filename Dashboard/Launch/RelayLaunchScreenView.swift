import SwiftUI
#if os(macOS)
import AppKit
#endif

private enum LaunchHomeMainContent {
    case recent
    case whatsNew
}

// MARK: - Main View

struct RelayLaunchScreenView: View {
    let onOpenRecent: (URL) -> Void
    let onNewDashboard: (CGSize) -> Void
    let onOpenFile: () -> Void
    var onOpenSettings: (() -> Void)? = nil
    var onQuit: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    @ObservedObject private var recentDocs = DashboardRecentDocumentsStore.shared
    @ObservedObject private var whatsNewStore = WhatsNewStore.shared
    @ObservedObject private var saveState = DashboardSaveState.shared
    @AppStorage("relay_startup_file_bookmark") private var startupFileBookmarkData: Data = Data()
    @AppStorage("relay_startup_file_name") private var startupFileName: String = ""

    @State private var showingNewDashboardSheet = false
    @State private var mainAreaContent: LaunchHomeMainContent = .recent
    @State private var filterText = ""
    @State private var sortNewest = true

    var body: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            sidebar
            Divider()
            mainArea
        }
        .frame(width: 860, height: 540)
        .sheet(isPresented: $showingNewDashboardSheet) { newDashboardSheetContent }
        .overlay(alignment: .topTrailing) {
            if saveState.hasRealDocument, let onClose {
                closeButton(action: onClose)
            }
        }
        #else
        NavigationSplitView {
            sidebar
                .navigationTitle("")
                .navigationBarHidden(true)
        } detail: {
            mainArea
        }
        .sheet(isPresented: $showingNewDashboardSheet) { newDashboardSheetContent }
        #endif
    }

    private var newDashboardSheetContent: some View {
        LaunchNewDashboardSheet { size in
            showingNewDashboardSheet = false
            onNewDashboard(size)
        }
    }

    #if os(macOS)
    /// Horizontal footprint (button width + its outer padding) that other trailing-edge
    /// content — like the Recent filter field — must yield so the close button below
    /// doesn't overlap it.
    fileprivate static let closeButtonReservedWidth: CGFloat = 40

    /// Closes Home back to the dashboard behind it. Only shown once a real
    /// dashboard exists (see `DashboardSaveState.hasRealDocument`) — closing into
    /// the pristine auto-generated blank dashboard from a fresh launch would be confusing.
    private func closeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(12)
        .help("Close Home")
    }
    #endif


    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarLogo
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 18)

            Button {
                showingNewDashboardSheet = true
            } label: {
                Label("New Dashboard", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(LaunchPrimaryButtonStyle())
            .padding(.horizontal, 12)

            Button(action: onOpenFile) {
                Label("Open File…", systemImage: "arrow.up.doc")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(LaunchSecondaryButtonStyle())
            .padding(.horizontal, 12)
            .padding(.top, 6)

            Divider().padding(.vertical, 14)

            LaunchSidebarNavItem(label: "Home", icon: "house.fill", isActive: mainAreaContent == .recent) {
                mainAreaContent = .recent
            }
            if !whatsNewStore.visibleReleases.isEmpty {
                LaunchSidebarNavItem(label: "What's New", icon: "sparkles", isActive: mainAreaContent == .whatsNew, showsBadge: whatsNewStore.hasUnseenUpdates) {
                    mainAreaContent = .whatsNew
                }
            }
            LaunchSidebarNavItem(label: "Settings", icon: "gearshape") {
                onOpenSettings?()
            }



            Spacer()

            startupFileSection
                .padding(.horizontal, 12)
                .padding(.bottom, 16)

#if os(macOS)
            if let onQuit {
                Divider().padding(.vertical, 14)
                Button(action: onQuit) {
                    Label("Quit Relay", systemImage: "power")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(LaunchSecondaryButtonStyle())
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
#endif
        }
        .frame(width: 200)
        .background(.regularMaterial)
    }

    private var sidebarLogo: some View {
        HStack(spacing: 10) {
            Image("relay_icon_white copy")
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
            Text("Home")
                .font(.headline)
        }
    }

    private var startupFileSection: some View {
        Group {
            if !startupFileName.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                    Text(startupFileName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        startupFileBookmarkData = Data()
                        startupFileName = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove startup file")
                }
                .padding(8)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text(DashboardPlatformCopy.startupFileHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Main area

    private var mainArea: some View {
        Group {
            switch mainAreaContent {
            case .recent:
                VStack(spacing: 0) {
                    recentToolbar
                    Divider()
                    recentGrid
                }
            case .whatsNew:
                WhatsNewFeedView(releases: whatsNewStore.visibleReleases)
            }
        }
    }

    private var recentToolbar: some View {
        HStack(spacing: 10) {
            Text("Recent")
                .font(.title3.weight(.semibold))

            Menu {
                Button("Newest First") { sortNewest = true }
                Button("Oldest First") { sortNewest = false }
            } label: {
                Label(sortNewest ? "Sort: Newest" : "Sort: Oldest",
                      systemImage: "chevron.up.chevron.down")
                    .font(.subheadline)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            TextField("Filter…", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        #if os(macOS)
        // Leave room on the trailing edge for the close button overlaid on top of
        // this row when it's showing -- otherwise it collides with the filter field.
        .padding(.trailing, saveState.hasRealDocument ? Self.closeButtonReservedWidth : 0)
        #endif
    }

    private var recentGrid: some View {
        ScrollView {
            if filteredRecentURLs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("No recent files")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 60)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(filteredRecentURLs, id: \.self) { url in
                        RecentFileCard(url: url, onTap: { onOpenRecent(url) })
                    }
                }
                .padding(24)
            }
        }
    }

    private var filteredRecentURLs: [URL] {
        var urls = recentDocs.recentDocumentURLs
        if !sortNewest { urls = urls.reversed() }
        guard !filterText.isEmpty else { return urls }
        return urls.filter {
            $0.deletingPathExtension().lastPathComponent
                .localizedCaseInsensitiveContains(filterText)
        }
    }
}

// MARK: - Sidebar helpers

private struct LaunchSidebarNavItem: View {
    let label: String
    let icon: String
    var isActive: Bool = false
    var showsBadge: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 5) {
                Label(label, systemImage: icon)
                if showsBadge {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isActive ? Color.primary.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }
}

private struct LaunchPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

private struct LaunchSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundStyle(.primary)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - File metadata

private struct TileLayout {
    var offsetX: Double
    var offsetY: Double
    var width: Double
    var height: Double
}

private struct RelayFileMetadata {
    var tabCount: Int = 0
    var tabNames: [String] = []
    var canvasWidth: Double = 1920
    var canvasHeight: Double = 1080
    var tiles: [TileLayout] = []
}

// MARK: - Recent file card

private struct RecentFileCard: View {
    let url: URL
    let onTap: () -> Void

    @AppStorage("relay_startup_file_name") private var startupFileName: String = ""
    @State private var isHovered = false
    @State private var isLoading = false
    @State private var cachedThumbnail: Image? = nil
    @State private var metadata: RelayFileMetadata? = nil

    private var fileName: String {
        url.deletingPathExtension().lastPathComponent
    }

    private var isPinned: Bool {
        !startupFileName.isEmpty && startupFileName == fileName
    }

    private var modifiedDateString: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else { return "" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        Button {
            isLoading = true
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                thumbnailArea
                infoArea
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isHovered ? Color.accentColor : Color.primary.opacity(0.12),
                    lineWidth: isHovered ? 1.5 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .onHover { isHovered = $0 }
        .task(id: url) {
            // Load thumbnail from app cache (~/Library/Caches/Relay/thumbnails/)
            if let thumbURL = DashboardRootView.thumbnailCacheURL(for: url),
               FileManager.default.fileExists(atPath: thumbURL.path),
               let data = try? Data(contentsOf: thumbURL) {
                #if os(macOS)
                if let nsImage = NSImage(data: data) {
                    cachedThumbnail = Image(nsImage: nsImage)
                }
                #else
                if let uiImage = UIImage(data: data) {
                    cachedThumbnail = Image(uiImage: uiImage)
                }
                #endif
            }
            metadata = await loadMetadata(for: url)
        }
        .contextMenu {
            Button("Open") { onTap() }
            Divider()
            if isPinned {
                Button("Remove as Startup File") {
                    UserDefaults.standard.removeObject(forKey: "relay_startup_file_bookmark")
                    UserDefaults.standard.removeObject(forKey: "relay_startup_file_name")
                }
            } else {
                Button("Set as Startup File") {
                    #if os(macOS)
                    if let data = try? url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    ) {
                        UserDefaults.standard.set(data, forKey: "relay_startup_file_bookmark")
                        UserDefaults.standard.set(
                            url.deletingPathExtension().lastPathComponent,
                            forKey: "relay_startup_file_name"
                        )
                    }
                    #endif
                }
            }
        }
    }

    @ViewBuilder
    private var thumbnailArea: some View {
        ZStack(alignment: .topLeading) {
            Color.primary.opacity(0.05)
            if let thumb = cachedThumbnail {
                thumb
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .allowsHitTesting(false)
            } else {
                // Generic file icon until a real thumbnail is saved
                Image(systemName: "doc.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                    .overlay(alignment: .bottomLeading) {
                        if let meta = metadata, meta.canvasWidth > 0 {
                            Text("\(Int(meta.canvasWidth)) × \(Int(meta.canvasHeight))")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 6)
                                .padding(.bottom, 5)
                        }
                    }
            }

            // Pin badge — top-left when this file is the startup file
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                    .padding(6)
            }

            // Loading overlay
            if isLoading {
                Color.black.opacity(0.35)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
        .clipped()
    }

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(fileName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
            HStack(spacing: 4) {
                if !modifiedDateString.isEmpty {
                    Text(modifiedDateString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let meta = metadata, meta.tabCount > 0 {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(meta.tabCount) tab\(meta.tabCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            // Tab name pills
            if let meta = metadata, !meta.tabNames.isEmpty {
                HStack(spacing: 3) {
                    ForEach(Array(meta.tabNames.prefix(3).enumerated()), id: \.offset) { idx, name in
                        Text(name)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(idx == 0 ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.08))
                            .foregroundStyle(idx == 0 ? Color.accentColor : .secondary)
                            .clipShape(Capsule())
                    }
                    if meta.tabCount > 3 {
                        Text("+\(meta.tabCount - 3)")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.regularMaterial)
    }
}

// MARK: - Async helpers

private func loadMetadata(for url: URL) async -> RelayFileMetadata? {
    return await Task.detached(priority: .utility) { () -> RelayFileMetadata? in
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(DashboardDocument.Payload.self, from: data)
        else { return nil }

        let canvasW = payload.canvasSize?.width ?? 1920
        let canvasH = payload.canvasSize?.height ?? 1080
        let defaultTileW = 260.0
        let defaultTileH = 200.0

        // Use the selected tab's tiles (or first tab) for the layout schematic
        let tabIdx = max(0, min(payload.selectedTabIndex, payload.tabs.count - 1))
        let tiles: [TileLayout] = payload.tabs.isEmpty ? [] : payload.tabs[tabIdx].tiles.map { tile in
            TileLayout(
                offsetX: Double(tile.offset.width),
                offsetY: Double(tile.offset.height),
                width: tile.size.map { Double($0.width) } ?? defaultTileW,
                height: tile.size.map { Double($0.height) } ?? defaultTileH
            )
        }

        return RelayFileMetadata(
            tabCount: payload.tabs.count,
            tabNames: payload.tabs.map { $0.name },
            canvasWidth: canvasW,
            canvasHeight: canvasH,
            tiles: tiles
        )
    }.value
}
