//
//  PersonTileView.swift
//  Relay
//
//  Created by David Bullard on 11/16/25.
//

import SwiftUI
import UniformTypeIdentifiers
import ImageIO
#if os(macOS)
import AppKit

#endif

// MARK: - Environment Keys

private struct IsDraggingTilesOnCanvasKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isDraggingTilesOnCanvas: Bool {
        get { self[IsDraggingTilesOnCanvasKey.self] }
        set { self[IsDraggingTilesOnCanvasKey.self] = newValue }
    }
}


// MARK: - Tile Models

enum PersonTileSource: String, Codable, Equatable {
    case custom      // manually entered in the tile
    case pcoTeam     // driven by a PCO team position
}

struct PersonTileModel: Codable, Equatable {

    var name: String
    var role: String
    var initials: String
    
    var backgroundOffsetX: Double = 0.0
    var backgroundOffsetY: Double = 0.0
    var source: PersonTileSource = .custom

    var pcoPositionName: String? = nil
    var pcoTeamName: String? = nil
    var pcoAssignmentSlot: Int? = nil
    var showPCOTeam: Bool = false
    var backgroundImageName: String? = nil
    /// SHA-256 hash of the explicit background image file, set by the host before pushing a
    /// synced-tab snapshot. Subscribers use this to fetch via GET /localFile/<hash>.
    var relayBackgroundImageHash: String? = nil

    var imageOverlayOpacity: Double
    var showPCOBadge: Bool
    var showPhotoBackground: Bool = true

    /// Where the person's name/role/initials block renders within the tile.
    /// Defaults to `.top`; set to `.bottom` to render the header as a footer.
    var headerPosition: TileHeaderPosition = .top

    init(
        name: String,
        role: String,
        initials: String,
        source: PersonTileSource = .custom,
        pcoPositionName: String? = nil,
        pcoTeamName: String? = nil,
        pcoAssignmentSlot: Int? = nil,
        showPCOTeam: Bool = false,
        backgroundImageName: String? = nil,
        imageOverlayOpacity: Double = 0.4,
        showPCOBadge: Bool = false,
        headerPosition: TileHeaderPosition = .top
    ) {
        self.name = name
        self.role = role
        self.initials = initials
        self.source = source
        self.pcoPositionName = pcoPositionName
        self.pcoTeamName = pcoTeamName
        self.pcoAssignmentSlot = pcoAssignmentSlot
        self.showPCOTeam = showPCOTeam
        self.backgroundImageName = backgroundImageName
        self.imageOverlayOpacity = imageOverlayOpacity
        self.showPCOBadge = showPCOBadge
        self.headerPosition = headerPosition
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case role
        case initials
        case backgroundOffsetX
        case backgroundOffsetY
        case source
        case pcoPositionName
        case pcoTeamName
        case pcoAssignmentSlot
        case showPCOTeam
        case backgroundImageName
        case relayBackgroundImageHash
        case imageOverlayOpacity
        case showPCOBadge
        case headerPosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.role = try container.decode(String.self, forKey: .role)
        self.initials = try container.decode(String.self, forKey: .initials)
        self.backgroundOffsetX = try container.decodeIfPresent(Double.self, forKey: .backgroundOffsetX) ?? 0.0
        self.backgroundOffsetY = try container.decodeIfPresent(Double.self, forKey: .backgroundOffsetY) ?? 0.0
        self.source = try container.decodeIfPresent(PersonTileSource.self, forKey: .source) ?? .custom
        self.pcoPositionName = try container.decodeIfPresent(String.self, forKey: .pcoPositionName)
        self.pcoTeamName = try container.decodeIfPresent(String.self, forKey: .pcoTeamName)
        self.pcoAssignmentSlot = try container.decodeIfPresent(Int.self, forKey: .pcoAssignmentSlot)
        self.showPCOTeam = try container.decodeIfPresent(Bool.self, forKey: .showPCOTeam) ?? false
        self.backgroundImageName = try container.decodeIfPresent(String.self, forKey: .backgroundImageName)
        self.relayBackgroundImageHash = try container.decodeIfPresent(String.self, forKey: .relayBackgroundImageHash)
        self.imageOverlayOpacity = try container.decodeIfPresent(Double.self, forKey: .imageOverlayOpacity) ?? 0.4
        self.showPCOBadge = try container.decodeIfPresent(Bool.self, forKey: .showPCOBadge) ?? true
        self.headerPosition = try container.decodeIfPresent(TileHeaderPosition.self, forKey: .headerPosition) ?? .top
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(role, forKey: .role)
        try container.encode(initials, forKey: .initials)
        try container.encode(backgroundOffsetX, forKey: .backgroundOffsetX)
        try container.encode(backgroundOffsetY, forKey: .backgroundOffsetY)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(pcoPositionName, forKey: .pcoPositionName)
        try container.encodeIfPresent(pcoTeamName, forKey: .pcoTeamName)
        try container.encodeIfPresent(pcoAssignmentSlot, forKey: .pcoAssignmentSlot)
        try container.encode(showPCOTeam, forKey: .showPCOTeam)
        try container.encodeIfPresent(backgroundImageName, forKey: .backgroundImageName)
        try container.encodeIfPresent(relayBackgroundImageHash, forKey: .relayBackgroundImageHash)
        try container.encode(imageOverlayOpacity, forKey: .imageOverlayOpacity)
        try container.encode(showPCOBadge, forKey: .showPCOBadge)
        try container.encode(headerPosition, forKey: .headerPosition)
    }
}

struct PersonTileView: View {
    var model: PersonTileModel
    /// When this tile belongs to a synced tab, pass the group ID so the view can
    /// fetch missing person photos from the host device's `/localPersonPhoto/` endpoint.
    var syncGroupID: String? = nil

    @Environment(\.tileTextFormatting) private var tileTextFormatting
    @EnvironmentObject private var lanService: LANSharedTabsService

    @AppStorage("dashboard_personImageFolder") private var personImageFolder: String = ""
    @AppStorage("dashboard_personImageFolderBookmark") private var personImageFolderBookmarkData: Data?
    @Environment(\.tileCornerRadius) private var tileCornerRadius
    @Environment(\.isDraggingTilesOnCanvas) private var isDraggingTilesOnCanvas
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dashboardIsLANSnapshotRendering) private var isLANSnapshotRendering

    /// Cached background image so we don't repeatedly hit disk / decode on every render.
    @State private var resolvedBackgroundImage: Image?
    @State private var lastBackgroundSize: CGSize = .zero

    #if os(macOS)
    private typealias PlatformImage = NSImage
    #else
    private typealias PlatformImage = UIImage
    #endif

    private nonisolated(unsafe) static let backgroundImageCache = NSCache<NSString, PlatformImage>()
    private nonisolated static let backgroundImageMissQueue = DispatchQueue(label: "Relay.PersonTileImageMissCache")
    private nonisolated(unsafe) static var backgroundImageMissOrder: [NSString] = []
    private nonisolated(unsafe) static var backgroundImageMissCache: [NSString: TimeInterval] = [:]
    private nonisolated static let backgroundImageMissLimit: Int = 128
    private nonisolated static let backgroundLookupQueue = DispatchQueue(label: "Relay.PersonTileImageLookupCache")
    private nonisolated(unsafe) static var backgroundLookupHitOrder: [NSString] = []
    private nonisolated(unsafe) static var backgroundLookupHitCache: [NSString: URL] = [:]
    private nonisolated(unsafe) static var backgroundLookupMissOrder: [NSString] = []
    private nonisolated(unsafe) static var backgroundLookupMissCache: [NSString: TimeInterval] = [:]
    private nonisolated static let backgroundLookupLimit: Int = 512

    private struct BackgroundImageRequest: Sendable {
        let backgroundImageName: String?
        let baseNames: [String]
        let personImageFolderBookmarkData: Data?
        let personImageFolderPath: String
    }

    @ViewBuilder
    private func backgroundView(using image: Image?) -> some View {
        if model.showPhotoBackground, let image {
            image
                .resizable()
                .scaledToFill()
                .overlay(
                    Color.black.opacity(model.imageOverlayOpacity)
                )
        } else if model.showPhotoBackground {
            // Photos enabled but image hasn't resolved yet — show a neutral
            // placeholder so a flash of the tile background isn't visible.
            Color(.sRGB, white: 0.12, opacity: 1.0)
        } else {
            // Photo background disabled — let the tile's own background
            // (solid color or gradient) show through.
            Color.clear
        }
    }

    private func snapshotBackgroundImage(targetMaxPixel: Int) -> Image? {
        guard isLANSnapshotRendering else { return nil }
        guard model.showPhotoBackground else { return nil }
        guard targetMaxPixel > 0 else { return nil }

        let request = BackgroundImageRequest(
            backgroundImageName: model.backgroundImageName,
            baseNames: imageLookupBaseNames(),
            personImageFolderBookmarkData: personImageFolderBookmarkData,
            personImageFolderPath: personImageFolder
        )

        #if os(macOS)
        if let platformImage = Self.computeBackgroundPlatformImage(
            request: request,
            targetMaxPixel: targetMaxPixel
        ) {
            return makeSwiftUIImage(from: platformImage)
        }
        #else
        if let platformImage = Self.computeBackgroundPlatformImage(
            request: request,
            targetMaxPixel: targetMaxPixel
        ) {
            return makeSwiftUIImage(from: platformImage)
        }
        #endif

        return nil
    }

    /// True when this tile has either an explicit asset-based background
    /// image, or a resolvable image in the configured person image folder.
    private var hasAnyBackgroundImage: Bool {
        // Never touch disk during body evaluation.
        // This is now a simple derived flag.
        guard model.showPhotoBackground else { return false }
        return model.backgroundImageName != nil || resolvedBackgroundImage != nil
    }

    private var backgroundTargetMaxPixel: Int {
        let maxDim = max(lastBackgroundSize.width, lastBackgroundSize.height)
        guard maxDim > 1 else { return 0 }
        let scaled = maxDim * displayScale * 1.2
        let bucket = Int((scaled / 64).rounded(.up)) * 64
        return max(1, bucket)
    }

    private func updateBackgroundSize(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        if abs(lastBackgroundSize.width - size.width) < 0.5,
           abs(lastBackgroundSize.height - size.height) < 0.5 {
            return
        }
        lastBackgroundSize = size
    }

    private nonisolated static func shouldSkipImageLookup(for key: NSString) -> Bool {
        Self.backgroundImageMissQueue.sync {
            guard let last = Self.backgroundImageMissCache[key] else { return false }
            return (Date().timeIntervalSince1970 - last) < 30
        }
    }

    private nonisolated static func recordImageMiss(for key: NSString) {
        Self.backgroundImageMissQueue.sync {
            Self.backgroundImageMissCache[key] = Date().timeIntervalSince1970
            Self.backgroundImageMissOrder.append(key)
            if Self.backgroundImageMissOrder.count > Self.backgroundImageMissLimit {
                let overflow = Self.backgroundImageMissOrder.count - Self.backgroundImageMissLimit
                for _ in 0..<overflow {
                    if let oldest = Self.backgroundImageMissOrder.first {
                        Self.backgroundImageMissOrder.removeFirst()
                        Self.backgroundImageMissCache.removeValue(forKey: oldest)
                    }
                }
            }
        }
    }

    private nonisolated static func candidateCacheKey(baseURL: URL, fileName: String) -> NSString {
        "\(baseURL.path)|\(fileName)" as NSString
    }

    private nonisolated static func cachedCandidateURL(for key: NSString) -> URL? {
        Self.backgroundLookupQueue.sync {
            Self.backgroundLookupHitCache[key]
        }
    }

    private nonisolated static func shouldSkipCandidateLookup(for key: NSString) -> Bool {
        Self.backgroundLookupQueue.sync {
            guard let last = Self.backgroundLookupMissCache[key] else { return false }
            return (Date().timeIntervalSince1970 - last) < 30
        }
    }

    private nonisolated static func recordCandidateHit(key: NSString, url: URL) {
        Self.backgroundLookupQueue.sync {
            Self.backgroundLookupHitCache[key] = url
            Self.backgroundLookupHitOrder.append(key)
            if Self.backgroundLookupHitOrder.count > Self.backgroundLookupLimit {
                let overflow = Self.backgroundLookupHitOrder.count - Self.backgroundLookupLimit
                for _ in 0..<overflow {
                    if let oldest = Self.backgroundLookupHitOrder.first {
                        Self.backgroundLookupHitOrder.removeFirst()
                        Self.backgroundLookupHitCache.removeValue(forKey: oldest)
                    }
                }
            }
        }
    }

    private nonisolated static func recordCandidateMiss(key: NSString) {
        Self.backgroundLookupQueue.sync {
            Self.backgroundLookupMissCache[key] = Date().timeIntervalSince1970
            Self.backgroundLookupMissOrder.append(key)
            if Self.backgroundLookupMissOrder.count > Self.backgroundLookupLimit {
                let overflow = Self.backgroundLookupMissOrder.count - Self.backgroundLookupLimit
                for _ in 0..<overflow {
                    if let oldest = Self.backgroundLookupMissOrder.first {
                        Self.backgroundLookupMissOrder.removeFirst()
                        Self.backgroundLookupMissCache.removeValue(forKey: oldest)
                    }
                }
            }
        }
    }

    private nonisolated static func cachedPlatformImage(for url: URL, targetMaxPixel: Int) -> PlatformImage? {
        let key = "\(url.path)|\(targetMaxPixel)" as NSString
        if let cached = Self.backgroundImageCache.object(forKey: key) {
            return cached
        }
        if shouldSkipImageLookup(for: key) {
            return nil
        }
        guard let image = loadDownsampledImage(from: url, targetMaxPixel: targetMaxPixel) else {
            recordImageMiss(for: key)
            return nil
        }
        Self.backgroundImageCache.setObject(image, forKey: key)
        return image
    }

    private nonisolated static func loadDownsampledImage(from url: URL, targetMaxPixel: Int) -> PlatformImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return nil
        }
        let maxPixel = max(1, targetMaxPixel)
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }
        #if os(macOS)
        return NSImage(cgImage: cgImage, size: .zero)
        #else
        return UIImage(cgImage: cgImage)
        #endif
    }

    /// Resolves the preferred background image for this tile based on the explicit
    /// backgroundImageName (if any) or the person image folder.
    ///
    /// IMPORTANT: This does file I/O and decoding and should be called off the main actor.
#if os(macOS)
    private nonisolated static func computeBackgroundPlatformImage(
        request: BackgroundImageRequest,
        targetMaxPixel: Int
    ) -> NSImage? {
        guard targetMaxPixel > 0 else { return nil }

        // 1. Explicit background reference set on the person tile takes precedence.
        if let ref = request.backgroundImageName, !ref.isEmpty {
            let url = URL(fileURLWithPath: ref)
            return cachedPlatformImage(for: url, targetMaxPixel: targetMaxPixel)
        }

        // 2. If no explicit reference is set, try to resolve from the user-selected folder.
        let baseNames = request.baseNames
        guard !baseNames.isEmpty else { return nil }

        let exts = ["png", "jpg", "jpeg", "heic"]
        let candidates: [String] = baseNames.flatMap { base in
            exts.map { "\(base).\($0)" }
        }

        let fm = FileManager.default

        // 1) Bookmark-based folder first.
        if let bookmarkData = request.personImageFolderBookmarkData {
            var isStale = false
            if let baseURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                let scoped = baseURL.startAccessingSecurityScopedResource()
                defer { if scoped { baseURL.stopAccessingSecurityScopedResource() } }

                for fileName in candidates {
                    let url = baseURL.appendingPathComponent(fileName)
                    let candidateKey = candidateCacheKey(baseURL: baseURL, fileName: fileName)
                    if let cachedURL = cachedCandidateURL(for: candidateKey) {
                        if let image = cachedPlatformImage(for: cachedURL, targetMaxPixel: targetMaxPixel) {
                            return image
                        } else {
                            recordCandidateMiss(key: candidateKey)
                        }
                        continue
                    }
                    if shouldSkipCandidateLookup(for: candidateKey) { continue }
                    if fm.fileExists(atPath: url.path),
                       let image = cachedPlatformImage(for: url, targetMaxPixel: targetMaxPixel) {
                        recordCandidateHit(key: candidateKey, url: url)
                        return image
                    } else {
                        recordCandidateMiss(key: candidateKey)
                    }
                }
            }
        }

        // 2) Legacy string-path fallback.
        if !request.personImageFolderPath.isEmpty {
            let baseURL = URL(fileURLWithPath: request.personImageFolderPath, isDirectory: true)
            for fileName in candidates {
                let url = baseURL.appendingPathComponent(fileName)
                let candidateKey = candidateCacheKey(baseURL: baseURL, fileName: fileName)
                if let cachedURL = cachedCandidateURL(for: candidateKey) {
                    if let image = cachedPlatformImage(for: cachedURL, targetMaxPixel: targetMaxPixel) {
                        return image
                    } else {
                        recordCandidateMiss(key: candidateKey)
                    }
                    continue
                }
                if shouldSkipCandidateLookup(for: candidateKey) { continue }
                if fm.fileExists(atPath: url.path),
                   let image = cachedPlatformImage(for: url, targetMaxPixel: targetMaxPixel) {
                    recordCandidateHit(key: candidateKey, url: url)
                    return image
                } else {
                    recordCandidateMiss(key: candidateKey)
                }
            }
        }

        return nil
    }
#else
    private nonisolated static func computeBackgroundPlatformImage(
        request: BackgroundImageRequest,
        targetMaxPixel: Int
    ) -> UIImage? {
        guard targetMaxPixel > 0 else { return nil }

        // 1. Explicit background reference set on the person tile takes precedence.
        if let ref = request.backgroundImageName, !ref.isEmpty {
            let url = URL(fileURLWithPath: ref)
            return cachedPlatformImage(for: url, targetMaxPixel: targetMaxPixel)
        }

        // 2. If no explicit reference is set, try to resolve from the user-selected folder.
        let baseNames = request.baseNames
        guard !baseNames.isEmpty else { return nil }

        let exts = ["png", "jpg", "jpeg", "heic"]
        let candidates: [String] = baseNames.flatMap { base in
            exts.map { "\(base).\($0)" }
        }

        let fm = FileManager.default

        guard let bookmarkData = request.personImageFolderBookmarkData else { return nil }

        var isStale = false
        let baseURL: URL
        do {
            baseURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            return nil
        }

        let scoped = baseURL.startAccessingSecurityScopedResource()
        defer { if scoped { baseURL.stopAccessingSecurityScopedResource() } }

        // Try direct filenames first (fast path)
        for fileName in candidates {
            let url = baseURL.appendingPathComponent(fileName)
            let candidateKey = candidateCacheKey(baseURL: baseURL, fileName: fileName)
            if let cachedURL = cachedCandidateURL(for: candidateKey) {
                if let image = cachedPlatformImage(for: cachedURL, targetMaxPixel: targetMaxPixel) {
                    return image
                } else {
                    recordCandidateMiss(key: candidateKey)
                }
                continue
            }
            if shouldSkipCandidateLookup(for: candidateKey) { continue }
            if fm.fileExists(atPath: url.path),
               let image = cachedPlatformImage(for: url, targetMaxPixel: targetMaxPixel) {
                recordCandidateHit(key: candidateKey, url: url)
                return image
            } else {
                recordCandidateMiss(key: candidateKey)
            }
        }

        return nil
    }
#endif

    /// Creates a SwiftUI Image from a decoded platform image.
    private func makeSwiftUIImage(from platformImage: Any) -> Image {
#if os(macOS)
        return Image(nsImage: platformImage as! NSImage)
#else
        return Image(uiImage: platformImage as! UIImage)
#endif
    }

    /// Cache key for when the background image should be recomputed.
    /// Changes in the explicit image name, display name, or image folder/bookmark
    /// will cause the resolution task to run again.
    private struct BackgroundCacheKey: Hashable {
        let explicit: String
        let relayHash: String  // triggers re-fetch when host stamps a proxy hash
        let folder: String
        let bookmarkSize: Int
        let name: String
        let showPhoto: Bool
        let targetMaxPixel: Int
        let syncGroupID: String
    }

    private var backgroundCacheKey: BackgroundCacheKey {
        BackgroundCacheKey(
            explicit: model.backgroundImageName ?? "",
            relayHash: model.relayBackgroundImageHash ?? "",
            folder: personImageFolder,
            bookmarkSize: personImageFolderBookmarkData?.count ?? 0,
            name: displayName,
            showPhoto: model.showPhotoBackground,
            targetMaxPixel: backgroundTargetMaxPixel,
            syncGroupID: syncGroupID ?? ""
        )
    }

    /// Computed display name based on the tile's source.
    /// For now this simply uses the stored name, but when the tile is
    /// configured to follow PCO we can override this with a resolved
    /// name from Planning Center (e.g., via a shared view model).
    private var displayName: String {
        switch model.source {
        case .custom:
            return model.name
        case .pcoTeam:
            // In PCO-driven mode, the stored name may be stale (e.g. user changed positions).
            // When no resolved person is available, show a clear placeholder.
            let trimmed = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Not Assigned" : model.name
        }
    }

    /// Computed display role/assignment based on the tile's source.
    /// When following a PCO team position, we prioritize that position
    /// name as the role label, falling back to the stored role.
    private var displayRole: String {
        switch model.source {
        case .custom:
            return model.role
        case .pcoTeam:
            if let pos = model.pcoPositionName, !pos.isEmpty {
                return pos
            } else {
                return model.role
            }
        }
    }

    /// Computed display PCO team string, if enabled and present.
    private var displayPCOTeam: String? {
        guard model.source == .pcoTeam else { return nil }
        guard model.showPCOTeam else { return nil }
        return model.pcoTeamName
    }

    /// Computed initials to show in the avatar circle.
    /// For custom tiles we use the stored initials field directly.
    /// For PCO-driven tiles we derive initials from the resolved display name
    /// so they match the person coming from Planning Center.
    private var displayInitials: String {
        switch model.source {
        case .custom:
            return model.initials
        case .pcoTeam:
            // If showing "Not Assigned", use initials from that placeholder.
            let trimmed = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let nameForInitials = trimmed.isEmpty ? "Not Assigned" : model.name
            return makeInitials(from: nameForInitials)
        }
    }

    /// Builds simple initials from a full name string.
    private func makeInitials(from name: String) -> String {
        let parts = name
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }

        if parts.count >= 2 {
            let first = parts[0].first.map(String.init) ?? ""
            let second = parts[1].first.map(String.init) ?? ""
            let combined = (first + second)
            return combined.uppercased()
        } else if let firstChar = name.trimmingCharacters(in: .whitespacesAndNewlines).first {
            return String(firstChar).uppercased()
        } else {
            return model.initials
        }
    }

    /// Optional badge text to indicate that this tile is following a
    /// PCO team position rather than a fully custom assignment.
    ///
    /// This will only return a value when the person tile is configured
    /// to show the PCO badge and the source is `.pcoTeam`.
    private var sourceBadgeText: String? {
        // If the user has disabled the PCO badge for this tile, don't show anything.
        guard model.showPCOBadge else { return nil }

        switch model.source {
        case .custom:
            return nil
        case .pcoTeam:
            return "PCO"
        }
    }
    // MARK: - Image Filename Helpers

    /// Trims and collapses internal whitespace runs to single spaces.
    private func normalizedFileBaseName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return parts.joined(separator: " ")
    }

    /// Candidate base names to try when resolving a person image from the folder.
    private func imageLookupBaseNames() -> [String] {
        let raw = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizedFileBaseName(displayName)
        let titleCased = normalized.capitalized

        var names: [String] = []
        for n in [raw, normalized, titleCased] {
            let v = n.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty, !names.contains(v) { names.append(v) }
        }
        return names
    }
    // MARK: - Text Formatting Helpers

    private var resolvedFontSize: CGFloat {
        CGFloat(tileTextFormatting?.fontSize ?? 24)
    }

    private var resolvedFontWeight: Font.Weight {
        (tileTextFormatting?.fontWeight ?? .semibold).swiftUIFontWeight
    }

    private var nameFont: Font {
        .system(size: resolvedFontSize, weight: resolvedFontWeight)
    }

    private var roleFont: Font {
        .system(size: max(12, resolvedFontSize * 0.65), weight: .regular)
    }

    private var resolvedTextColor: Color {
        tileTextFormatting?.textColor?.swiftUIColor ?? Color.white
    }
    
    /// Resolved text alignment based on the tile's justification setting.
    private var resolvedTextAlignment: TextAlignment {
        switch tileTextFormatting?.justification ?? .leading {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    /// Resolved horizontal alignment for frames based on justification.
    private var resolvedHorizontalAlignment: Alignment {
        switch tileTextFormatting?.justification ?? .leading {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    /// Resolved horizontal alignment for VStack/HStack containers.
    private var resolvedStackAlignment: HorizontalAlignment {
        switch tileTextFormatting?.justification ?? .leading {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    private func applyCapitalization(_ string: String) -> String {
        switch tileTextFormatting?.capitalization ?? .normal {
        case .normal:
            return string
        case .uppercase:
            return string.uppercased()
        case .lowercase:
            return string.lowercased()
        case .titlecase:
            return string.capitalized
        }
    }

    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.sRGB, white: 0.26, opacity: 1.0))
                    .frame(width: 40, height: 40)

                Text(displayInitials)
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            VStack(alignment: resolvedStackAlignment, spacing: 4) {
                HStack(spacing: 6) {
                    Text(applyCapitalization(displayName))
                        .font(nameFont)
                        .foregroundStyle(resolvedTextColor)

                    if let badge = sourceBadgeText {
                        Text(badge)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color(.sRGB, white: 0.35, opacity: 1.0))
                            )
                            .foregroundStyle(.white)
                    }
                }

                Text(applyCapitalization(displayRole))
                    .font(roleFont)
                    .foregroundStyle(resolvedTextColor.opacity(0.85))

                if let team = displayPCOTeam, !team.isEmpty {
                    Text(applyCapitalization(team))
                        .font(.caption2)
                        .foregroundStyle(resolvedTextColor.opacity(0.6))
                }
            }
            .multilineTextAlignment(resolvedTextAlignment)
        }
        .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
    }

    var body: some View {
        VStack(alignment: resolvedStackAlignment, spacing: 12) {
            if model.headerPosition == .bottom {
                Spacer()
                headerView
            } else {
                headerView
                Spacer()
            }
        }
        .padding(16)
        .background(
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                let size = proxy.size

                // Normalize offsets: model.backgroundOffsetX/Y are in the range [-1, 1],
                // where -1 moves the image fully left/up, and +1 moves it fully right/down.
                let offsetX = CGFloat(model.backgroundOffsetX) * width * 0.5
                let offsetY = CGFloat(model.backgroundOffsetY) * height * 0.5

                let targetMaxPixel = max(1, Int((max(width, height) * displayScale * 1.2).rounded(.up)))
                let snapshotImage = snapshotBackgroundImage(targetMaxPixel: targetMaxPixel)
                let activeImage = resolvedBackgroundImage ?? snapshotImage

                backgroundView(using: activeImage)
                    // Slightly scale up the image so that small offsets don't expose empty edges.
                    .scaleEffect(1.1)
                    .offset(x: offsetX, y: offsetY)
                    .frame(width: width, height: height)
                    .clipped()
                    .onAppear { updateBackgroundSize(size) }
                    .onChange(of: size, initial: false) { _, newSize in
                        updateBackgroundSize(newSize)
                    }
            }
        )
        .task(id: backgroundCacheKey) {
            // Avoid doing file I/O / image decoding on the main actor.
            guard model.showPhotoBackground, !isDraggingTilesOnCanvas else {
                resolvedBackgroundImage = nil
                return
            }

            let key = backgroundCacheKey
            let targetMaxPixel = key.targetMaxPixel
            guard targetMaxPixel > 0 else {
                resolvedBackgroundImage = nil
                return
            }

            let request = BackgroundImageRequest(
                backgroundImageName: model.backgroundImageName,
                baseNames: imageLookupBaseNames(),
                personImageFolderBookmarkData: personImageFolderBookmarkData,
                personImageFolderPath: personImageFolder
            )

            let platformImage: Any? = await Task.detached(priority: .utility) {
                // Bail out if the task was invalidated.
                if Task.isCancelled { return nil }

#if os(macOS)
                return Self.computeBackgroundPlatformImage(
                    request: request,
                    targetMaxPixel: targetMaxPixel
                )
#else
                return Self.computeBackgroundPlatformImage(
                    request: request,
                    targetMaxPixel: targetMaxPixel
                )
#endif
            }.value

            if let platformImage {
                resolvedBackgroundImage = makeSwiftUIImage(from: platformImage)
            } else {
                resolvedBackgroundImage = nil

                // Proxy fallback: if local load failed and this tab is synced,
                // fetch from the host device.
                if let groupID = syncGroupID,
                   let baseURL = lanService.peerBaseURL(for: groupID) {
                    var fetchedImage: Any? = nil

                    if let hash = model.relayBackgroundImageHash, !hash.isEmpty {
                        // Hash-based fetch via /localFile/<hash> (same path as image modules).
                        let remoteURL = baseURL.appendingPathComponent("localFile/\(hash)")
                        if let localURL = await SyncedFileCache.shared.localURL(for: hash, remoteURL: remoteURL),
                           let data = try? Data(contentsOf: localURL) {
                            #if os(macOS)
                            fetchedImage = NSImage(data: data)
                            #else
                            fetchedImage = UIImage(data: data)
                            #endif
                        }
                    } else {
                        // Fallback: filename-based fetch via /localPersonPhoto/<filename>
                        // (used for folder-based person photos without a hash).
                        let exts = ["png", "jpg", "jpeg", "heic"]
                        let candidates: [String]
                        if let explicit = model.backgroundImageName, !explicit.isEmpty {
                            candidates = [URL(fileURLWithPath: explicit).lastPathComponent]
                        } else {
                            candidates = imageLookupBaseNames().flatMap { base in
                                exts.map { "\(base).\($0)" }
                            }
                        }
                        for filename in candidates {
                            if Task.isCancelled { break }
                            let remoteURL = baseURL.appendingPathComponent("localPersonPhoto/\(filename)")
                            if let localURL = await SyncedFileCache.shared.localURL(for: filename, remoteURL: remoteURL),
                               let data = try? Data(contentsOf: localURL) {
                                #if os(macOS)
                                if let img = NSImage(data: data) { fetchedImage = img; break }
                                #else
                                if let img = UIImage(data: data) { fetchedImage = img; break }
                                #endif
                            }
                        }
                    }

                    if let fetchedImage {
                        resolvedBackgroundImage = makeSwiftUIImage(from: fetchedImage)
                    }
                }
            }
        }
    }
}
// MARK: - Plugin Glue (Person)

/// Host view that renders a Person tile from a module binding so changes propagate immediately.
private struct PersonModuleTileHostView: View {
    @Binding var tab: DashboardTab
    @Binding var module: DashboardModuleModel

    private var model: PersonTileModel {
        if case .person(let m) = module.kind {
            return m
        }
        return PersonTileModel.empty()
    }

    private var resolvedModel: PersonTileModel {
        // Ensure PCO-driven tiles show resolved person info, but preserve user-controlled settings.
        var resolved = tab.resolvedPersonModel(model)

        // Preserve toggles / appearance from the stored module model.
        resolved.showPCOBadge = model.showPCOBadge
        resolved.showPCOTeam = model.showPCOTeam
        resolved.showPhotoBackground = model.showPhotoBackground
        resolved.imageOverlayOpacity = model.imageOverlayOpacity
        resolved.backgroundOffsetX = model.backgroundOffsetX
        resolved.backgroundOffsetY = model.backgroundOffsetY
        resolved.backgroundImageName = model.backgroundImageName

        // If the resolver didn't populate a team name, keep whatever is stored on the module model.
        if (resolved.pcoTeamName ?? "").isEmpty {
            resolved.pcoTeamName = model.pcoTeamName
        }

        return resolved
    }

    var body: some View {
        PersonTileView(model: resolvedModel, syncGroupID: tab.syncGroupID)
    }
}

/// Module-owned settings host that edits the live module binding directly.
struct PersonModuleSettingsHostView: View {
    @Binding var module: DashboardModuleModel
    let onPersist: () -> Void

    /// Whether the current dashboard tab has a PCO connection configured.
    let isPCOConfigured: Bool

    /// Available PCO team position names for the current service/tab (legacy flat list).
    let availablePositions: [String]

    /// Optional: full catalog mapping Team name -> ordered array of position names.
    /// When provided, the settings UI can show a Team picker and filter positions by team.
    let availablePositionsByTeamName: [String: [String]]
    let assignmentCandidatesByLookupKey: [String: [String]]

    // Backward-compatible initializer (if availablePositionsByTeamName is omitted, default to [:])
    init(
        module: Binding<DashboardModuleModel>,
        onPersist: @escaping () -> Void,
        isPCOConfigured: Bool,
        availablePositions: [String],
        availablePositionsByTeamName: [String: [String]] = [:],
        assignmentCandidatesByLookupKey: [String: [String]] = [:]
    ) {
        self._module = module
        self.onPersist = onPersist
        self.isPCOConfigured = isPCOConfigured
        self.availablePositions = availablePositions
        self.availablePositionsByTeamName = availablePositionsByTeamName
        self.assignmentCandidatesByLookupKey = assignmentCandidatesByLookupKey
    }

    private var modelBinding: Binding<PersonTileModel> {
        Binding<PersonTileModel>(
            get: {
                if case .person(let m) = module.kind { return m }
                return PersonTileModel.empty()
            },
            set: { newValue in
                // Only update the module model here. Persist is managed by the settings view
                // (debounced for text fields and deferred for sliders/toggles) to avoid UI snap-back.
                module.kind = .person(newValue)
            }
        )
    }

    var body: some View {
        PersonModuleSettingsView(
            model: modelBinding,
            isPCOConfigured: isPCOConfigured,
            availablePositions: availablePositions,
            availablePositionsByTeamName: availablePositionsByTeamName,
            assignmentCandidatesByLookupKey: assignmentCandidatesByLookupKey,
            onPersist: onPersist
        )
    }
}

struct PersonModuleSettingsView: View {
    @Binding var model: PersonTileModel

    let isPCOConfigured: Bool
    let availablePositions: [String]
    let availablePositionsByTeamName: [String: [String]]
    let assignmentCandidatesByLookupKey: [String: [String]]
    let onPersist: () -> Void

    // Backward-compatible initializer
    init(
        model: Binding<PersonTileModel>,
        isPCOConfigured: Bool,
        availablePositions: [String],
        availablePositionsByTeamName: [String: [String]] = [:],
        assignmentCandidatesByLookupKey: [String: [String]] = [:],
        onPersist: @escaping () -> Void
    ) {
        self._model = model
        self.isPCOConfigured = isPCOConfigured
        self.availablePositions = availablePositions
        self.availablePositionsByTeamName = availablePositionsByTeamName
        self.assignmentCandidatesByLookupKey = assignmentCandidatesByLookupKey
        self.onPersist = onPersist
    }

    /// Persist changes on the next run loop tick to avoid "Publishing changes from within view updates" warnings.
    private func persistDeferred() {
        DispatchQueue.main.async {
            onPersist()
        }
    }

    private func assignmentLookupKey(teamName: String?, positionName: String?) -> String? {
        let position = (positionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !position.isEmpty else { return nil }
        let team = (teamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !team.isEmpty else { return position }
        return "\(team)||\(position)"
    }

    private var currentAssignmentCandidates: [String] {
        guard let keyed = assignmentLookupKey(teamName: model.pcoTeamName, positionName: model.pcoPositionName) else {
            return []
        }
        let position = (model.pcoPositionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return assignmentCandidatesByLookupKey[keyed]
            ?? assignmentCandidatesByLookupKey[position]
            ?? []
    }

    #if os(macOS)
    @State private var isPresentingImageImporter = false
    #endif

    // Debounced drafts so we don't persist on every keystroke (prevents heavy tab/LAN updates while typing).
    @State private var draftName: String = ""
    @State private var draftRole: String = ""
    @State private var draftInitials: String = ""
    @State private var draftPCOTeam: String = ""
    @State private var draftPCOPosition: String = ""

    @State private var draftPersistTask: Task<Void, Never>?

    private func syncDraftsFromModel() {
        draftName = model.name
        draftRole = model.role
        draftInitials = model.initials
        draftPCOTeam = model.pcoTeamName ?? ""
        draftPCOPosition = model.pcoPositionName ?? ""
    }

    private func scheduleDraftPersist() {
        draftPersistTask?.cancel()
        let name = draftName
        let role = draftRole
        let initials = draftInitials
        let pcoTeam = draftPCOTeam
        let pcoPos = draftPCOPosition

        draftPersistTask = Task {
            // Small debounce window for typing.
            try? await Task.sleep(nanoseconds: 350_000_000)
            await MainActor.run {
                model.name = name
                model.role = role
                model.initials = initials

                let t = pcoTeam.trimmingCharacters(in: .whitespacesAndNewlines)
                model.pcoTeamName = t.isEmpty ? nil : t

                let p = pcoPos.trimmingCharacters(in: .whitespacesAndNewlines)
                model.pcoPositionName = p.isEmpty ? nil : p
                model.pcoAssignmentSlot = nil

                persistDeferred()
            }
        }
    }

    private let percentNumberFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 0
        nf.maximumFractionDigits = 0
        return nf
    }()

    private var backgroundDisplayName: String {
        guard let ref = model.backgroundImageName, !ref.isEmpty else { return "" }
        // If it’s a file path, show last path component; otherwise show the raw ref.
        if ref.contains("/") {
            return URL(fileURLWithPath: ref).lastPathComponent
        }
        return ref
    }

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    var body: some View {
        GroupBox("Person Module") {
            VStack(alignment: .leading, spacing: 8) {

                // MARK: - Source (matches old inspector)
                Picker("Person Source", selection: Binding(
                    get: { model.source },
                    set: { newValue in
                        // Only flip the source here. Persisting immediately can cause the inspector to
                        // reload and snap the segmented control back.
                        model.source = newValue

                        // Keep drafts in sync with the new mode.
                        syncDraftsFromModel()

                        // Persist once the current update pass completes.
                        DispatchQueue.main.async {
                            persistDeferred()
                        }
                    }
                )) {
                    Text("Custom").tag(PersonTileSource.custom)
                    Text("PCO Team").tag(PersonTileSource.pcoTeam)
                }
                .pickerStyle(.segmented)

                if model.source == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Full Name (matches image filename)", text: $draftName)
                            .onChange(of: draftName, initial: false) { _, newValue in
                                scheduleDraftPersist()
                            }

                        TextField("Role / Position", text: $draftRole)
                            .onChange(of: draftRole, initial: false) { _, newValue in
                                scheduleDraftPersist()
                            }

                        TextField("Initials", text: $draftInitials)
                            .onChange(of: draftInitials, initial: false) { _, newValue in
                                scheduleDraftPersist()
                            }
                    }
                } else {
                    if isPCOConfigured {
                        VStack(alignment: .leading, spacing: 6) {
                            // Optional Team picker (when the full catalog is provided)
                            if !availablePositionsByTeamName.isEmpty {
                                let teamNames = Array(availablePositionsByTeamName.keys)
                                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

                                Picker("Team", selection: Binding(
                                    get: { (model.pcoTeamName ?? "") },
                                    set: { newValue in
                                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                        model.pcoTeamName = trimmed.isEmpty ? nil : trimmed

                                        // Changing teams invalidates any previously resolved person.
                                        model.name = ""
                                        model.role = ""
                                        model.initials = ""

                                        // If the current position isn't valid for the new team, clear it.
                                        if let t = model.pcoTeamName,
                                           let positions = availablePositionsByTeamName[t],
                                           !positions.isEmpty,
                                           let current = model.pcoPositionName,
                                           !current.isEmpty,
                                           !positions.contains(current) {
                                            model.pcoPositionName = nil
                                        }
                                        model.pcoAssignmentSlot = nil

                                        persistDeferred()
                                    }
                                )) {
                                    ForEach(teamNames, id: \.self) { team in
                                        Text(team).tag(team)
                                    }
                                }
                                .pickerStyle(.menu)
                                .task(id: teamNames.joined(separator: "|")) {
                                    // Default to the first team when not set.
                                    // Yield once so we don't mutate bindings during the same view update pass.
                                    await Task.yield()

                                    // Only auto-default when we're in PCO mode.
                                    guard model.source == .pcoTeam else { return }

                                    let current = (model.pcoTeamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                    if current.isEmpty, let first = teamNames.first {
                                        await MainActor.run {
                                            model.pcoTeamName = first
                                        }
                                        // Persist on the next tick (separate from the binding mutation).
                                        persistDeferred()
                                    }
                                }
                            }

                            // Position picker
                            Picker("Position", selection: Binding(
                                get: { model.pcoPositionName ?? "" },
                                set: { newValue in
                                    let newPos = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let prior = (model.pcoPositionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                                    model.pcoPositionName = newPos.isEmpty ? nil : newPos

                                    // If the user changed positions, clear any previously resolved person
                                    // so the tile can display "Not Assigned" until a new match resolves.
                                    if newPos != prior {
                                        model.name = ""
                                        model.role = ""
                                        model.initials = ""
                                        model.pcoAssignmentSlot = nil
                                    }

                                    persistDeferred()
                                }
                            )) {
                                let selected = (model.pcoPositionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                                let baseList: [String] = {
                                    // If we have a team catalog, prefer that team's positions.
                                    if !availablePositionsByTeamName.isEmpty,
                                       let team = model.pcoTeamName,
                                       let positions = availablePositionsByTeamName[team],
                                       !positions.isEmpty {
                                        return positions
                                    }
                                    // Fallback: legacy flat list.
                                    return availablePositions
                                }()

                                let merged: [String] = {
                                    // Preserve incoming ordering; append selected if it isn't present.
                                    var ordered: [String] = []
                                    for p in baseList {
                                        if !ordered.contains(p) { ordered.append(p) }
                                    }
                                    if !selected.isEmpty, !ordered.contains(selected) {
                                        ordered.append(selected)
                                    }
                                    return ordered
                                }()

                                ForEach(merged, id: \.self) { position in
                                    Text(position).tag(position)
                                }
                            }
                            .pickerStyle(.menu)

                            if currentAssignmentCandidates.count > 1 {
                                Picker("Assignment", selection: Binding(
                                    get: {
                                        let slot = model.pcoAssignmentSlot ?? 0
                                        return currentAssignmentCandidates.indices.contains(slot) ? slot : 0
                                    },
                                    set: { newValue in
                                        guard currentAssignmentCandidates.indices.contains(newValue) else { return }
                                        model.pcoAssignmentSlot = newValue
                                        model.name = currentAssignmentCandidates[newValue]
                                        model.initials = ""
                                        persistDeferred()
                                    }
                                )) {
                                    ForEach(Array(currentAssignmentCandidates.enumerated()), id: \.offset) { index, personName in
                                        Text(personName).tag(index)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            Toggle("Show PCO badge", isOn: Binding(
                                get: { model.showPCOBadge },
                                set: { newValue in
                                    model.showPCOBadge = newValue
                                    persistDeferred()
                                }
                            ))
                            .toggleStyle(SwitchToggleStyle())

                            Toggle("Show PCO team", isOn: Binding(
                                get: { model.showPCOTeam },
                                set: { newValue in
                                    model.showPCOTeam = newValue
                                    persistDeferred()
                                }
                            ))
                            .toggleStyle(SwitchToggleStyle())
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PCO is not configured for this tab yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("You can still set the Team/Position now; once PCO is configured these will resolve automatically.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            TextField("Team (optional)", text: $draftPCOTeam)
                                .onChange(of: draftPCOTeam, initial: false) { _, newValue in
                                    scheduleDraftPersist()
                                }

                            TextField("Position", text: $draftPCOPosition)
                                .onChange(of: draftPCOPosition, initial: false) { _, newValue in
                                    // Clear any previously resolved person so the tile shows a placeholder
                                    // until PCO data becomes available.
                                    draftName = ""
                                    draftRole = ""
                                    draftInitials = ""
                                    scheduleDraftPersist()
                                }

                            Toggle("Show PCO badge", isOn: Binding(
                                get: { model.showPCOBadge },
                                set: { newValue in
                                    model.showPCOBadge = newValue
                                    persistDeferred()
                                }
                            ))
                            .toggleStyle(SwitchToggleStyle())

                            Toggle("Show PCO team", isOn: Binding(
                                get: { model.showPCOTeam },
                                set: { newValue in
                                    model.showPCOTeam = newValue
                                    persistDeferred()
                                }
                            ))
                            .toggleStyle(SwitchToggleStyle())
                        }
                    }
                }

                Divider()

                // MARK: - Layout
                HStack {
                    Text("Header Position")
                    Spacer()
                    Picker("Header Position", selection: Binding(
                        get: { model.headerPosition },
                        set: { newValue in
                            model.headerPosition = newValue
                            persistDeferred()
                        }
                    )) {
                        ForEach(TileHeaderPosition.allCases) { position in
                            Text(position.label).tag(position)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                }
#if os(macOS)
                .help("Choose whether the name/role/initials block sits at the top or bottom of the tile.")
#endif

                Divider()

                // MARK: - Background Image (matches old inspector)
                Toggle("Show photo background", isOn: Binding(
                    get: { model.showPhotoBackground },
                    set: { newValue in
                        model.showPhotoBackground = newValue
                        persistDeferred()
                    }
                ))
                .toggleStyle(SwitchToggleStyle())

                if model.showPhotoBackground, !backgroundDisplayName.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Background Image")
                            Spacer()
                            Text(backgroundDisplayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Text("This image is currently being used for this person tile.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Background Image: using automatic/default background from your configured folder.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
#if os(macOS)
                    Button("Choose Image…") {
                        model.showPhotoBackground = true
                        isPresentingImageImporter = true
                    }

                    if model.showPhotoBackground, !backgroundDisplayName.isEmpty {
                        Button("Use Default Background") {
                            model.backgroundImageName = nil
                            persistDeferred()
                        }
                    }
#else
                    // iOS: no file picker here yet; still allow clearing.
                    if model.showPhotoBackground, !backgroundDisplayName.isEmpty {
                        Button("Use Default Background") {
                            model.backgroundImageName = nil
                            persistDeferred()
                        }
                    }
#endif
                }
                .font(.caption)

#if os(macOS)
                .fileImporter(
                    isPresented: $isPresentingImageImporter,
                    allowedContentTypes: [UTType.image],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        model.backgroundImageName = url.path
                        model.showPhotoBackground = true
                        persistDeferred()
                    }
                }
#endif

                // Overlay
                HStack {
                    Text("Image Darken Overlay")
                    Slider(value: Binding(
                        get: { model.imageOverlayOpacity },
                        set: { newValue in
                            model.imageOverlayOpacity = newValue
                            persistDeferred()
                        }
                    ), in: 0.0...1.0)

                    let overlayPercentBinding = Binding<Double>(
                        get: { round(model.imageOverlayOpacity * 100.0) },
                        set: { newValue in
                            let rounded = round(newValue)
                            let clamped = max(0.0, min(100.0, rounded))
                            model.imageOverlayOpacity = clamped / 100.0
                            persistDeferred()
                        }
                    )

                    HStack(spacing: 2) {
                        DeferredNumberField(value: overlayPercentBinding, formatter: Self.percentFormatter)
                            .frame(width: 40)
                            .multilineTextAlignment(.trailing)
                        Text("%")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    Button {
                        // Default overlay matches `PersonTileModel` default (0.4)
                        model.imageOverlayOpacity = 0.4
                        persistDeferred()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Reset overlay to default")
                }
                .font(.caption)

                // Offsets
                VStack(alignment: .leading, spacing: 6) {
                    Text("Background Image Position")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Horizontal
                    HStack {
                        Text("Horizontal")
                        Slider(value: Binding(
                            get: { model.backgroundOffsetX },
                            set: { newValue in
                                model.backgroundOffsetX = newValue
                                persistDeferred()
                            }
                        ), in: -1.0...1.0)

                        let horizontalPercentBinding = Binding<Double>(
                            get: { round(model.backgroundOffsetX * 100.0) },
                            set: { newValue in
                                let rounded = round(newValue)
                                let clamped = max(-100.0, min(100.0, rounded))
                                model.backgroundOffsetX = clamped / 100.0
                                persistDeferred()
                            }
                        )

                        HStack(spacing: 2) {
                            DeferredNumberField(value: horizontalPercentBinding, formatter: Self.percentFormatter)
                                .frame(width: 40)
                                .multilineTextAlignment(.trailing)
                            Text("%")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                        Button {
                            model.backgroundOffsetX = 0.0
                            persistDeferred()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help("Reset horizontal offset")
                    }
                    .font(.caption)

                    // Vertical
                    HStack {
                        Text("Vertical")
                        Slider(value: Binding(
                            get: { model.backgroundOffsetY },
                            set: { newValue in
                                model.backgroundOffsetY = newValue
                                persistDeferred()
                            }
                        ), in: -1.0...1.0)

                        let verticalPercentBinding = Binding<Double>(
                            get: { round(model.backgroundOffsetY * 100.0) },
                            set: { newValue in
                                let rounded = round(newValue)
                                let clamped = max(-100.0, min(100.0, rounded))
                                model.backgroundOffsetY = clamped / 100.0
                                persistDeferred()
                            }
                        )

                        HStack(spacing: 2) {
                            DeferredNumberField(value: verticalPercentBinding, formatter: Self.percentFormatter)
                                .frame(width: 40)
                                .multilineTextAlignment(.trailing)
                            Text("%")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                        Button {
                            model.backgroundOffsetY = 0.0
                            persistDeferred()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help("Reset vertical offset")
                    }
                    .font(.caption)
                }
            }
        }
        .toggleStyle(.switch)
        .task(id: "draft-sync-\(model.source.rawValue)-\(model.pcoTeamName ?? "")-\(model.pcoPositionName ?? "")") {
            // Initialize / resync drafts when switching source or when incoming model changes.
            syncDraftsFromModel()
        }
        .onDisappear {
            // Ensure the latest edits are saved when closing the inspector.
            persistDeferred()
        }
    }
}

/// Dashboard module plugin for Person.
/// Note: assumes `DashboardModuleKind` includes `.person(PersonTileModel)`.
enum PersonModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .person(PersonTileModel.empty()) }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        AnyView(
            PersonModuleTileHostView(tab: tab, module: module)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        )
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        // Hosted by DashboardTileEditView via `PersonModuleSettingsHostView`.
        AnyView(EmptyView())
    }
}
private extension PersonTileModel {
    /// Safe default construction even when the type only exposes `init(from:)`.
    static func empty() -> PersonTileModel {
        // If your Decodable implementation supplies defaults, decoding `{}` yields a valid model.
        let data = Data("{}".utf8)
        if let model = try? JSONDecoder().decode(PersonTileModel.self, from: data) {
            return model
        }
        // Last resort: construct a safe default directly.
        let fallback = Data(#"{"name":"","role":"","initials":""}"#.utf8)
        return (try? JSONDecoder().decode(PersonTileModel.self, from: fallback))
            ?? PersonTileModel(name: "", role: "", initials: "")
    }
}
