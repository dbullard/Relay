import SwiftUI
import Foundation
import UniformTypeIdentifiers
import ImageIO

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ImageModuleView: View {
    let model: ImageModuleModel
    var syncGroupID: String? = nil

    @EnvironmentObject private var lanService: LANSharedTabsService
    @State private var renderedImage: Image? = nil
    @State private var resolvedProxyURL: URL? = nil
    private let placeholderColor = Color.white.opacity(0.58)

    var body: some View {
        ZStack {
            model.backgroundColor.swiftUIColor

            if let renderedImage {
                renderedImage
                    .resizable()
                    .aspectRatio(contentMode: model.contentMode.swiftUIContentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(model.contentMode == .fit ? 12 : 0)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear(perform: loadImage)
        .onChange(of: model.cachedFilePath, initial: false) { _, _ in
            loadImage()
        }
        .onChange(of: resolvedProxyURL, initial: false) { _, newURL in
            guard let newURL else { return }
            loadImageFromURL(newURL)
        }
        .task(id: model.relayFileHash) {
            guard let hash = model.relayFileHash else { return }
            // Only fetch via proxy if local file is missing.
            if let path = model.cachedFilePath, FileManager.default.fileExists(atPath: path) { return }
            guard let groupID = syncGroupID,
                  let baseURL = lanService.peerBaseURL(for: groupID) else { return }
            let remoteURL = baseURL.appendingPathComponent("localFile/\(hash)")
            if let localURL = await SyncedFileCache.shared.localURL(for: hash, remoteURL: remoteURL) {
                resolvedProxyURL = localURL
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(placeholderColor)
            Text("No image selected")
                .font(.callout)
                .foregroundStyle(placeholderColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    private func loadImage() {
        // Try local cached file path first.
        if let path = model.cachedFilePath, !path.isEmpty {
            #if os(macOS)
            if let image = NSImage(contentsOfFile: path) {
                renderedImage = Image(nsImage: image)
                return
            }
            #else
            if let image = UIImage(contentsOfFile: path) {
                renderedImage = Image(uiImage: image)
                return
            }
            #endif
        }
        // Fall back to proxy-resolved URL if available.
        if let proxyURL = resolvedProxyURL {
            loadImageFromURL(proxyURL)
            return
        }
        renderedImage = nil
    }

    private func loadImageFromURL(_ url: URL) {
        #if os(macOS)
        guard let image = NSImage(contentsOf: url) else { return }
        renderedImage = Image(nsImage: image)
        #else
        guard let image = UIImage(contentsOfFile: url.path) else { return }
        renderedImage = Image(uiImage: image)
        #endif
    }
}

struct ImageModuleSettingsView: View {
    @Binding var model: ImageModuleModel
    let onPersist: () -> Void

    @State private var showingPicker = false
    @State private var isImporting = false
    @State private var importErrorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Image")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                Text(displayLabel)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(displayLabel == "No image selected" ? .secondary : .primary)
            }

            HStack(spacing: 10) {
                Button("Choose Image...") {
                    showingPicker = true
                }
                .fileImporter(
                    isPresented: $showingPicker,
                    allowedContentTypes: [.image],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        importSelectedImage(from: url)
                    case .failure(let error):
                        importErrorMessage = error.localizedDescription
                    }
                }

                if model.cachedFilePath != nil {
                    Button("Clear") {
                        clearImageSelection()
                    }
                }

                Spacer(minLength: 0)
            }

            Picker(
                "Scale",
                selection: Binding(
                    get: { model.contentMode },
                    set: { newValue in
                        model.contentMode = newValue
                        onPersist()
                    }
                )
            ) {
                ForEach(ImageModuleContentMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            colorRow(
                title: "Background",
                color: Binding(
                    get: { model.backgroundColor.swiftUIColor },
                    set: { newValue in
                        model.backgroundColor = CodableColor(newValue)
                        onPersist()
                    }
                )
            )

            Text("Imported images are resized to a maximum 1600 px edge to keep dashboard rendering lightweight.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isImporting {
                Text("Importing image…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let importErrorMessage, !importErrorMessage.isEmpty {
                Text(importErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var displayLabel: String {
        if let displayName = model.displayName, !displayName.isEmpty {
            return displayName
        }
        return "No image selected"
    }

    private func importSelectedImage(from url: URL) {
        let previousCachedPath = model.cachedFilePath
        isImporting = true
        importErrorMessage = nil

        Task {
            let imported = ImageModuleImporter.importImage(
                from: url,
                replacingCachedPath: previousCachedPath
            )
            await MainActor.run {
                isImporting = false

                guard let imported else {
                    importErrorMessage = "Unable to import that image."
                    return
                }

                model.displayName = imported.displayName
                model.cachedFilePath = imported.cachedFilePath
                onPersist()
            }
        }
    }

    private func clearImageSelection() {
        if let cachedFilePath = model.cachedFilePath, !cachedFilePath.isEmpty {
            try? FileManager.default.removeItem(atPath: cachedFilePath)
        }
        model.displayName = nil
        model.cachedFilePath = nil
        importErrorMessage = nil
        onPersist()
    }

    @ViewBuilder
    private func colorRow(title: String, color: Binding<Color>) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 0)
            ColorPicker("", selection: color, supportsOpacity: true)
                .labelsHidden()
        }
        .font(.caption)
    }
}

private enum ImageModuleImporter {
    struct Result {
        let displayName: String
        let cachedFilePath: String
    }

    static let maxPixelSize = 1600

    static func importImage(from url: URL, replacingCachedPath oldCachedPath: String?) -> Result? {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var coordinatorError: NSError?
        var importResult: Result?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
            guard
                let cgImage = downsampledImage(from: coordinatedURL, maxPixelSize: maxPixelSize),
                let cacheDirectory = cacheDirectory()
            else {
                return
            }

            do {
                if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
                    try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                }

                let hasAlpha = cgImage.hasAlphaChannel
                let fileExtension = hasAlpha ? "png" : "jpg"
                let destinationURL = cacheDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(fileExtension)

                guard let encodedData = encodedImageData(from: cgImage, preserveAlpha: hasAlpha) else {
                    return
                }

                try encodedData.write(to: destinationURL, options: .atomic)

                if let oldCachedPath, !oldCachedPath.isEmpty, oldCachedPath != destinationURL.path {
                    try? FileManager.default.removeItem(atPath: oldCachedPath)
                }

                importResult = Result(
                    displayName: coordinatedURL.lastPathComponent,
                    cachedFilePath: destinationURL.path
                )
            } catch {
                return
            }
        }

        if coordinatorError != nil {
            return nil
        }

        return importResult
    }

    private static func cacheDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("RelayImageCache", isDirectory: true)
    }

    private static func downsampledImage(from url: URL, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
    }

    private static func encodedImageData(from image: CGImage, preserveAlpha: Bool) -> Data? {
        #if os(macOS)
        let bitmap = NSBitmapImageRep(cgImage: image)
        if preserveAlpha {
            return bitmap.representation(using: .png, properties: [:])
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        #else
        let platformImage = UIImage(cgImage: image)
        if preserveAlpha {
            return platformImage.pngData()
        }
        return platformImage.jpegData(compressionQuality: 0.85)
        #endif
    }
}

private extension CGImage {
    var hasAlphaChannel: Bool {
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }
}

enum ImageModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .image(ImageModuleModel()) }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        let model: ImageModuleModel
        if case .image(let existingModel) = module.wrappedValue.kind {
            model = existingModel
        } else {
            model = ImageModuleModel()
        }
        return AnyView(ImageModuleView(model: model, syncGroupID: tab.wrappedValue.syncGroupID))
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        AnyView(EmptyView())
    }
}
