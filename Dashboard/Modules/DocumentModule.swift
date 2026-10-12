import SwiftUI
import Foundation
import UniformTypeIdentifiers
import PDFKit
import QuickLookThumbnailing
import CoreText

#if os(macOS)
import AppKit
import QuickLook
import QuickLookUI
#else
import UIKit
import QuickLook
import zlib   // for inflateInit2_ / inflate (raw DEFLATE decompression of .docx ZIP entries)
#endif

extension UTType {
    static var relayDoc: UTType { UTType(filenameExtension: "doc") ?? .data }
    static var relayDocx: UTType { UTType(filenameExtension: "docx") ?? .data }
}

struct DocumentModuleModel: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var displayName: String? = nil
    var fileBookmarkData: Data? = nil
    var cachedFilePath: String? = nil
    var filePath: String? = nil
    var snapshotImageData: Data? = nil
    var snapshotPixelSize: Int? = nil
    var snapshotUpdatedAt: Date? = nil
    var selectedPageIndex: Int = 0
    var pdfPageCount: Int? = nil
}

struct DocumentModuleView: View {
    @Environment(\.dashboardIsLANSnapshotRendering) private var isLANSnapshotRendering
    let model: DocumentModuleModel
    @State private var scopedURL: ScopedDocumentURL? = nil
    private let placeholderColor = Color.white.opacity(0.58)

    var body: some View {
        ZStack {
            if isLANSnapshotRendering {
                snapshotFriendlyContent
            } else if let resolvedURL = scopedURL?.url {
                DocumentPreview(url: resolvedURL, selectedPageIndex: model.selectedPageIndex)
                    .id(previewIdentity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snapshot = snapshotImage {
                snapshot
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(10)
            } else {
                emptyState
            }
        }
        .onAppear {
            resolveURL()
        }
        .onChange(of: model.fileBookmarkData, initial: false) { _, _ in
            resolveURL()
        }
        .onChange(of: model.cachedFilePath, initial: false) { _, _ in
            resolveURL()
        }
        .onChange(of: model.filePath, initial: false) { _, _ in
            resolveURL()
        }
    }

    @ViewBuilder
    private var snapshotFriendlyContent: some View {
        if let snapshot = snapshotImage {
            snapshot
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10)
        } else if let label = displayLabelForSnapshot {
            VStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(placeholderColor)
                Text(label)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let pageSummary {
                    Text(pageSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            emptyState
        }
    }

    private var snapshotImage: Image? {
        guard let data = model.snapshotImageData else { return nil }
        #if os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #else
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #endif
    }

    private var previewIdentity: String {
        if let path = model.cachedFilePath {
            return "cache-\(path)"
        }
        if let data = model.fileBookmarkData {
            return "bookmark-\(data.hashValue)"
        }
        if let path = model.filePath {
            return "path-\(path)"
        }
        return "empty"
    }

    private var displayLabelForSnapshot: String? {
        if let label = model.displayName, !label.isEmpty {
            return label
        }
        if let path = model.cachedFilePath, !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if let path = model.filePath, !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return nil
    }

    private var pageSummary: String? {
        guard let pageCount = model.pdfPageCount, pageCount > 0 else { return nil }
        let currentPage = min(max(model.selectedPageIndex + 1, 1), pageCount)
        return "Page \(currentPage) of \(pageCount)"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(placeholderColor)
            Text("No document selected")
                .font(.callout)
                .foregroundStyle(placeholderColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    private func resolveURL() {
        scopedURL = ScopedDocumentURL(bookmarkData: model.fileBookmarkData, cachedPath: model.cachedFilePath, fallbackPath: model.filePath)
    }
}

struct DocumentModuleSettingsView: View {
    @Binding var model: DocumentModuleModel
    let onPersist: () -> Void

    @State private var showingPicker = false
    @State private var isGeneratingSnapshot = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Document")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(displayLabel)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(displayLabel == "No document selected" ? .secondary : .primary)
            }

            HStack(spacing: 10) {
                Button("Choose Document...") {
                    chooseDocument()
                }
#if os(iOS)
                .fileImporter(
                    isPresented: $showingPicker,
                    allowedContentTypes: [.pdf, .relayDoc, .relayDocx],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        handlePickedURL(url)
                    case .failure(let error):
                        print("[DocumentModule] Document pick failed:", error.localizedDescription)
                    }
                }
#endif

                if model.fileBookmarkData != nil || model.cachedFilePath != nil {
                    Button("Clear") {
                        clearDocumentSelection()
                    }
                }

                Spacer(minLength: 0)
            }

            if let pageCount = resolvedPDFPageCount, pageCount >= 1 {
                Picker("Page", selection: selectedPageBinding(pageCount: pageCount)) {
                    ForEach(1...pageCount, id: \.self) { page in
                        Text("Page \(page)")
                            .tag(page)
                    }
                }
                .pickerStyle(.menu)
            }

#if os(iOS)
            // Old-style .doc binary format cannot be parsed on iOS. Advise
            // exporting as .docx or PDF to enable page selection.
            let displayExt = (model.displayName ?? model.cachedFilePath ?? "")
                .split(separator: ".").last.map(String.init)?.lowercased() ?? ""
            if displayExt == "doc", model.cachedFilePath != nil {
                Text("Legacy .doc files cannot be page-navigated on iOS. Re-save as .docx or PDF to enable page selection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
#endif

            if isGeneratingSnapshot {
                Text("Updating preview…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .onChange(of: model.cachedFilePath, initial: false) { _, _ in
            regenerateSnapshotIfNeeded()
        }
        .task(id: model.cachedFilePath ?? model.fileBookmarkData?.base64EncodedString() ?? "") {
            guard model.fileBookmarkData != nil || model.cachedFilePath != nil else { return }
            guard (model.pdfPageCount ?? 0) == 0 else { return }
            guard let scopedURL = ScopedDocumentURL(
                bookmarkData: model.fileBookmarkData,
                cachedPath: model.cachedFilePath,
                fallbackPath: model.filePath
            ) else { return }
            let url = scopedURL.url
            guard url.pathExtension.lowercased() == "pdf" else { return }
            guard let document = PDFDocument(url: url) else { return }
            let count = max(1, document.pageCount)
            await MainActor.run {
                model.pdfPageCount = count
                onPersist()
            }
        }
        .onAppear {
            regenerateSnapshotIfNeeded()
        }
    }

    private var displayLabel: String {
        if let label = model.displayName, !label.isEmpty {
            return label
        }
        if let path = model.cachedFilePath, !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if let path = model.filePath, !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return "No document selected"
    }

    private var resolvedPDFPageCount: Int? {
        if let cached = model.pdfPageCount, cached > 0 {
            return cached
        }
        guard let path = model.cachedFilePath ?? model.filePath else { return nil }
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension.lowercased() == "pdf" else { return nil }
        guard let document = PDFDocument(url: url) else { return nil }
        return max(1, document.pageCount)
    }

    private func selectedPageBinding(pageCount: Int) -> Binding<Int> {
        Binding(
            get: {
                let current = min(max(model.selectedPageIndex, 0), pageCount - 1)
                return current + 1
            },
            set: { newValue in
                let clamped = min(max(newValue - 1, 0), pageCount - 1)
                model.selectedPageIndex = clamped
                onPersist()
            }
        )
    }

    private func chooseDocument() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.pdf, .relayDoc, .relayDocx]

        if panel.runModal() == .OK, let url = panel.url {
            handlePickedURL(url)
        }
#else
        showingPicker = true
#endif
    }

    private func handlePickedURL(_ url: URL) {
        #if os(iOS)
        // On iOS, file picker URLs are security-scoped. Access them directly —
        // NSFileCoordinator is designed for cross-process coordination and can
        // silently fail with file-importer URLs, producing an unreadable
        // coordinatedURL even with the security scope active.
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let bookmark = try url.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let cachedPath = cacheFile(from: url, displayName: url.lastPathComponent)
            let resolvedPath = convertDocToPDFIfPossible(fromCachedPath: cachedPath) ?? cachedPath
            if resolvedPath != cachedPath, let cachedPath {
                try? FileManager.default.removeItem(atPath: cachedPath)
            }
            let pageCount = cachedPDFPageCount(for: resolvedPath)

            Task { @MainActor in
                model.fileBookmarkData = bookmark
                model.displayName = url.lastPathComponent
                model.cachedFilePath = resolvedPath
                model.filePath = nil
                model.selectedPageIndex = 0
                model.pdfPageCount = pageCount
                onPersist()
                regenerateSnapshotIfNeeded(force: true)
            }
        } catch {
            print("[DocumentModule] Failed to handle picked URL (iOS):", error.localizedDescription)
        }
        #else
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var coordinatorError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
            let cachedPath = cacheFile(from: coordinatedURL, displayName: coordinatedURL.lastPathComponent)
            let resolvedPath = convertDocToPDFIfPossible(fromCachedPath: cachedPath) ?? cachedPath
            if resolvedPath != cachedPath, let cachedPath {
                try? FileManager.default.removeItem(atPath: cachedPath)
            }
            let pageCount = cachedPDFPageCount(for: resolvedPath)

            Task { @MainActor in
                model.displayName = coordinatedURL.lastPathComponent
                model.cachedFilePath = resolvedPath
                model.filePath = coordinatedURL.path
                model.selectedPageIndex = 0
                model.pdfPageCount = pageCount

                do {
                    let bookmark = try coordinatedURL.bookmarkData(
                        options: [.withSecurityScope],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    model.fileBookmarkData = bookmark
                } catch {
                    model.fileBookmarkData = nil
                    print("[DocumentModule] Failed to create bookmark:", error.localizedDescription)
                }

                onPersist()
                regenerateSnapshotIfNeeded(force: true)
            }
        }

        if let coordinatorError {
            print("[DocumentModule] Document coordination error:", coordinatorError.localizedDescription)
        }
        #endif
    }

    private func regenerateSnapshotIfNeeded(force: Bool = false) {
        guard !isGeneratingSnapshot else { return }
        guard let cachedPath = model.cachedFilePath, !cachedPath.isEmpty else { return }
        if !force, model.snapshotImageData != nil { return }

        isGeneratingSnapshot = true

        Task {
            let snapshot = await DocumentSnapshotGenerator.thumbnailData(for: URL(fileURLWithPath: cachedPath), maxPixel: 1200)
            await MainActor.run {
                model.snapshotImageData = snapshot
                model.snapshotPixelSize = snapshot == nil ? nil : 1200
                model.snapshotUpdatedAt = Date()
                isGeneratingSnapshot = false
                onPersist()
            }
        }
    }

    private func clearDocumentSelection() {
        if let cachedPath = model.cachedFilePath, !cachedPath.isEmpty {
            try? FileManager.default.removeItem(atPath: cachedPath)
        }
        model.fileBookmarkData = nil
        model.cachedFilePath = nil
        model.filePath = nil
        model.displayName = nil
        model.selectedPageIndex = 0
        model.pdfPageCount = nil
        model.snapshotImageData = nil
        model.snapshotPixelSize = nil
        model.snapshotUpdatedAt = nil
        onPersist()
    }

    private func cacheFile(from url: URL, displayName: String) -> String? {
        let fileManager = FileManager.default
        guard let cacheDirectory = documentCacheDirectory() else { return nil }

        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            do {
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            } catch {
                print("[DocumentModule] Failed to create cache directory:", error.localizedDescription)
                return nil
            }
        }

        let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let destinationURL = cacheDirectory.appendingPathComponent(filename)

        do {
            // Prefer FileManager.copyItem: handles large PDFs without loading them
            // into memory, and works correctly with security-scoped source URLs.
            try FileManager.default.copyItem(at: url, to: destinationURL)
            return destinationURL.path
        } catch {
            print("[DocumentModule] Failed to cache document:", error.localizedDescription)
            return nil
        }
    }

    private func documentCacheDirectory() -> URL? {
        let fileManager = FileManager.default
        guard let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return baseDirectory.appendingPathComponent("RelayDocumentCache", isDirectory: true)
    }

    private func convertDocToPDFIfPossible(fromCachedPath cachedPath: String?) -> String? {
        guard let cachedPath, !cachedPath.isEmpty else { return nil }
        let sourceURL = URL(fileURLWithPath: cachedPath)
        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "doc" || ext == "docx" else { return nil }
        guard let cacheDirectory = documentCacheDirectory() else { return nil }

#if os(macOS)
        let docType: NSAttributedString.DocumentType = (ext == "doc") ? .docFormat : .officeOpenXML
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: docType]
        let attributed: NSAttributedString
        do {
            attributed = try NSAttributedString(url: sourceURL, options: options, documentAttributes: nil)
        } catch {
            print("[DocumentModule] Failed to read Word document:", error.localizedDescription)
            return nil
        }

        let destinationURL = cacheDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        guard renderAttributedStringToPDF(attributed, destinationURL: destinationURL) else {
            return nil
        }
        return destinationURL.path
#elseif os(iOS)
        // .docx (Open XML) files are ZIP archives – extract word/document.xml,
        // parse the paragraph text, and render to PDF using the same
        // UIGraphicsPDFRenderer path so the page picker works on iPad.
        // Old-style .doc (binary format) is not parseable without third-party
        // libraries, so we leave it as-is and fall through to QuickLook display.
        guard ext == "docx" else { return nil }

        guard let attributed = extractAttributedStringFromDocx(at: sourceURL) else {
            print("[DocumentModule] iOS: failed to extract text from .docx")
            return nil
        }

        let destinationURL = cacheDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        guard renderAttributedStringToPDF(attributed, destinationURL: destinationURL) else {
            return nil
        }
        return destinationURL.path
#else
        return nil
#endif
    }

#if os(iOS)
    // MARK: - iOS .docx extraction helpers

    /// Reads a .docx file (a ZIP archive), decompresses word/document.xml,
    /// parses paragraph text, and returns an NSAttributedString ready for
    /// renderAttributedStringToPDF.
    private func extractAttributedStringFromDocx(at url: URL) -> NSAttributedString? {
        guard let zipData = try? Data(contentsOf: url) else { return nil }
        guard let xmlData = extractZipEntry("word/document.xml", from: zipData) else { return nil }
        return parseWordDocumentXML(xmlData)
    }

    /// Minimal ZIP local-file-header scanner.  Handles stored (method 0) and
    /// deflated (method 8) entries – both of which are used in .docx files.
    private func extractZipEntry(_ target: String, from zipData: Data) -> Data? {
        var bytes = [UInt8](zipData)
        var offset = 0

        while offset + 30 <= bytes.count {
            // Local file header signature: PK\x03\x04
            guard bytes[offset] == 0x50, bytes[offset+1] == 0x4B,
                  bytes[offset+2] == 0x03, bytes[offset+3] == 0x04 else { break }

            let method     = Int(bytes[offset+8]) | (Int(bytes[offset+9]) << 8)
            let cmpSize    = Int(bytes[offset+18]) | (Int(bytes[offset+19]) << 8)
                           | (Int(bytes[offset+20]) << 16) | (Int(bytes[offset+21]) << 24)
            let uncmpSize  = Int(bytes[offset+22]) | (Int(bytes[offset+23]) << 8)
                           | (Int(bytes[offset+24]) << 16) | (Int(bytes[offset+25]) << 24)
            let nameLen    = Int(bytes[offset+26]) | (Int(bytes[offset+27]) << 8)
            let extraLen   = Int(bytes[offset+28]) | (Int(bytes[offset+29]) << 8)

            let headerEnd  = offset + 30 + nameLen + extraLen
            let dataEnd    = headerEnd + cmpSize
            guard dataEnd <= bytes.count else { break }

            let name = String(bytes: bytes[(offset+30)..<(offset+30+nameLen)], encoding: .utf8) ?? ""

            if name == target {
                let compressed = Data(bytes[headerEnd..<dataEnd])
                switch method {
                case 0: return compressed                              // stored
                case 8: return inflateRawDeflate(compressed, expectedSize: uncmpSize)  // deflated
                default: break
                }
            }
            offset = dataEnd
        }
        return nil
    }

    /// Decompresses raw DEFLATE data (no zlib/gzip header) via libz.
    private func inflateRawDeflate(_ compressed: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)

        let ok = compressed.withUnsafeBytes { src -> Bool in
            guard let srcPtr = src.baseAddress else { return false }
            return output.withUnsafeMutableBytes { dst -> Bool in
                guard let dstPtr = dst.baseAddress else { return false }
                var stream = z_stream()
                stream.next_in  = UnsafeMutablePointer(mutating: srcPtr.assumingMemoryBound(to: Bytef.self))
                stream.avail_in = uInt(compressed.count)
                stream.next_out = dstPtr.assumingMemoryBound(to: Bytef.self)
                stream.avail_out = uInt(expectedSize)
                // -15 selects raw DEFLATE (no zlib wrapper header)
                guard inflateInit2_(&stream, -15, ZLIB_VERSION,
                                    Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return false }
                let ret = inflate(&stream, Z_FINISH)
                inflateEnd(&stream)
                return ret == Z_STREAM_END || ret == Z_OK
            }
        }
        return ok ? output : nil
    }

    /// Parses word/document.xml and extracts paragraph text while preserving
    /// basic font attributes (bold, italic, size).
    private func parseWordDocumentXML(_ data: Data) -> NSAttributedString? {
        final class WordXMLHandler: NSObject, XMLParserDelegate {
            // Accumulated result
            let result = NSMutableAttributedString()

            // State
            private var inParagraph = false
            private var paraBuffer = NSMutableAttributedString()
            private var currentText = ""

            // Current run attributes
            private var isBold   = false
            private var isItalic = false
            private var fontSize: CGFloat = 12

            // Track nesting so we only capture <w:t> text nodes
            private var inRun = false
            private var collectingText = false

            // ---------- SAX callbacks ----------

            func parser(_ parser: XMLParser, didStartElement el: String,
                        namespaceURI: String?, qualifiedName: String?,
                        attributes: [String: String]) {
                switch el {
                case "w:p":
                    inParagraph = true
                    paraBuffer = NSMutableAttributedString()
                case "w:r":
                    inRun = true; isBold = false; isItalic = false; fontSize = 12
                case "w:b":
                    isBold = true
                case "w:i":
                    isItalic = true
                case "w:sz":           // half-points; 24 = 12 pt
                    if let v = attributes["w:val"], let pts = Double(v) {
                        fontSize = CGFloat(pts / 2)
                    }
                case "w:t":
                    collectingText = true; currentText = ""
                default: break
                }
            }

            func parser(_ parser: XMLParser, foundCharacters string: String) {
                if collectingText { currentText += string }
            }

            func parser(_ parser: XMLParser, didEndElement el: String,
                        namespaceURI: String?, qualifiedName: String?) {
                switch el {
                case "w:t":
                    collectingText = false
                    if !currentText.isEmpty {
                        var traits: UIFontDescriptor.SymbolicTraits = []
                        if isBold   { traits.insert(.traitBold) }
                        if isItalic { traits.insert(.traitItalic) }
                        let descriptor = UIFontDescriptor.preferredFontDescriptor(
                            withTextStyle: .body
                        ).withSymbolicTraits(traits) ??
                            UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                        let font = UIFont(descriptor: descriptor, size: fontSize)
                        let run = NSAttributedString(string: currentText,
                                                     attributes: [.font: font])
                        paraBuffer.append(run)
                        currentText = ""
                    }
                case "w:r":
                    inRun = false
                case "w:p":
                    inParagraph = false
                    if paraBuffer.length > 0 || result.length > 0 {
                        if result.length > 0 {
                            result.append(NSAttributedString(string: "\n"))
                        }
                        result.append(paraBuffer)
                    }
                default: break
                }
            }
        }

        let parser  = XMLParser(data: data)
        let handler = WordXMLHandler()
        parser.delegate = handler
        guard parser.parse(), handler.result.length > 0 else { return nil }
        return handler.result
    }
#endif

    private func renderAttributedStringToPDF(_ attributed: NSAttributedString, destinationURL: URL) -> Bool {
        let pageSize = CGSize(width: 612, height: 792)
        let margin: CGFloat = 36
        let textRect = CGRect(
            x: margin,
            y: margin,
            width: pageSize.width - (margin * 2),
            height: pageSize.height - (margin * 2)
        )

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var currentRange = CFRange(location: 0, length: 0)

        #if os(iOS)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let data = renderer.pdfData { context in
            while currentRange.location < attributed.length {
                context.beginPage()
                let cgContext = context.cgContext
                cgContext.saveGState()
                cgContext.textMatrix = .identity
                cgContext.translateBy(x: 0, y: pageSize.height)
                cgContext.scaleBy(x: 1, y: -1)

                let path = CGPath(rect: textRect, transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
                CTFrameDraw(frame, cgContext)
                cgContext.restoreGState()

                let visibleRange = CTFrameGetVisibleStringRange(frame)
                if visibleRange.length == 0 { break }
                currentRange.location += visibleRange.length
                currentRange.length = 0
            }
        }
        do {
            try data.write(to: destinationURL)
            return true
        } catch {
            print("[DocumentModule] Failed to write PDF:", error.localizedDescription)
            return false
        }
        #else
        guard let consumer = CGDataConsumer(url: destinationURL as CFURL) else { return false }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return false }

        while currentRange.location < attributed.length {
            context.beginPDFPage(nil)
            context.saveGState()
            context.textMatrix = .identity

            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
            CTFrameDraw(frame, context)
            context.restoreGState()
            context.endPDFPage()

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            if visibleRange.length == 0 { break }
            currentRange.location += visibleRange.length
            currentRange.length = 0
        }

        context.closePDF()
        return true
        #endif
    }

    private func cachedPDFPageCount(for cachedPath: String?) -> Int? {
        guard let cachedPath, !cachedPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: cachedPath)
        guard url.pathExtension.lowercased() == "pdf" else { return nil }
        guard let document = PDFDocument(url: url) else { return nil }
        return max(1, document.pageCount)
    }
}

struct DocumentPreview: View {
    let url: URL
    let selectedPageIndex: Int

    var body: some View {
        if url.pathExtension.lowercased() == "pdf" {
            PDFDocumentView(url: url, selectedPageIndex: selectedPageIndex)
        } else {
            QuickLookDocumentView(url: url)
        }
    }
}

struct PDFDocumentView: View {
    let url: URL
    let selectedPageIndex: Int

    var body: some View {
        PDFViewRepresentable(url: url, selectedPageIndex: selectedPageIndex)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if os(macOS)
struct PDFViewRepresentable: NSViewRepresentable {
    let url: URL
    let selectedPageIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let view = ReadOnlyPDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        view.displaysPageBreaks = false
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if context.coordinator.lastURL != url {
            context.coordinator.lastURL = url
            nsView.document = PDFDocument(url: url)
        }

        if context.coordinator.lastPageIndex != selectedPageIndex {
            context.coordinator.lastPageIndex = selectedPageIndex
            if let document = nsView.document,
               let page = document.page(at: selectedPageIndex) {
                nsView.go(to: page)
            }
        }
    }

    final class Coordinator {
        var lastURL: URL? = nil
        var lastPageIndex: Int? = nil
    }
}

final class ReadOnlyPDFView: PDFView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func magnify(with event: NSEvent) {}
    override func smartMagnify(with event: NSEvent) {}
    override func swipe(with event: NSEvent) {}
}

struct QuickLookDocumentView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = DocumentPreviewItem(url: url)
    }
}
#else
struct PDFViewRepresentable: UIViewRepresentable {
    let url: URL
    let selectedPageIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        view.displaysPageBreaks = false
        view.isUserInteractionEnabled = false
        if let scrollView = view.subviews.compactMap({ $0 as? UIScrollView }).first {
            scrollView.isScrollEnabled = false
            scrollView.bounces = false
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if context.coordinator.lastURL != url {
            context.coordinator.lastURL = url
            uiView.document = PDFDocument(url: url)
        }

        if context.coordinator.lastPageIndex != selectedPageIndex {
            context.coordinator.lastPageIndex = selectedPageIndex
            if let document = uiView.document,
               let page = document.page(at: selectedPageIndex) {
                uiView.go(to: page)
            }
        }
    }

    final class Coordinator {
        var lastURL: URL? = nil
        var lastPageIndex: Int? = nil
    }
}

struct QuickLookDocumentView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        // Disable interaction so the QL preview doesn't swallow drag gestures
        // used to move tiles on the canvas.  Documents are view-only in tiles.
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.update(url: url)
        uiViewController.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        private var item: DocumentPreviewItem

        init(url: URL) {
            self.item = DocumentPreviewItem(url: url)
        }

        func update(url: URL) {
            item = DocumentPreviewItem(url: url)
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            item
        }
    }
}
#endif

final class DocumentPreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?

    init(url: URL) {
        self.previewItemURL = url
    }
}

final class ScopedDocumentURL {
    let url: URL
    private let didStartAccess: Bool

    init?(bookmarkData: Data?, cachedPath: String?, fallbackPath: String?) {
        if let cachedPath, !cachedPath.isEmpty {
            url = URL(fileURLWithPath: cachedPath)
            didStartAccess = false
            return
        }

        if let bookmarkData {
            var isStale = false
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
            #else
            let options: URL.BookmarkResolutionOptions = [.withoutUI]
            #endif

            guard let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                return nil
            }
            url = resolved
        } else if let fallbackPath, !fallbackPath.isEmpty {
            url = URL(fileURLWithPath: fallbackPath)
        } else {
            return nil
        }

        didStartAccess = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if didStartAccess {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

enum DocumentSnapshotGenerator {
    static func thumbnailData(for url: URL, maxPixel: CGFloat) async -> Data? {
        let size = CGSize(width: maxPixel, height: maxPixel)
        #if os(macOS)
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        #else
        let scale = UIScreen.main.scale
        #endif

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
                guard let cgImage = representation?.cgImage else {
                    if let error {
                        print("[DocumentModule] Thumbnail generation failed:", error.localizedDescription)
                    }
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: cgImage.pngData())
            }
        }
    }
}

private extension CGImage {
    func pngData() -> Data? {
        #if os(macOS)
        let rep = NSBitmapImageRep(cgImage: self)
        return rep.representation(using: .png, properties: [:])
        #else
        return UIImage(cgImage: self).pngData()
        #endif
    }
}

// MARK: - Plugin Glue

enum DocumentModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .document(DocumentModuleModel()) }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        let model: DocumentModuleModel
        if case .document(let m) = module.wrappedValue.kind {
            model = m
        } else {
            model = DocumentModuleModel()
        }
        return AnyView(DocumentModuleView(model: model))
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        AnyView(EmptyView())
    }
}
