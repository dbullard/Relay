//
//  RosterImportSupport.swift
//  Relay
//
//  Created by OpenAI Codex on 4/14/26.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct RosterImportWorkbook: Identifiable, Equatable {
    struct Sheet: Identifiable, Equatable {
        let id: String
        let name: String
        let rows: [[String]]
    }

    let id = UUID()
    let sourceURL: URL
    let sheets: [Sheet]
}

enum RosterImportParser {
    enum ParserError: LocalizedError {
        case unsupportedFileType
        case unreadableFile
        case missingWorkbookData
        case noSheetsFound

        var errorDescription: String? {
            switch self {
            case .unsupportedFileType:
                return "That file type is not supported for roster import yet."
            case .unreadableFile:
                return "The selected file could not be read."
            case .missingWorkbookData:
                return "The workbook could not be parsed."
            case .noSheetsFound:
                return "No worksheets were found in the imported workbook."
            }
        }
    }

    static var allowedContentTypes: [UTType] {
        #if os(macOS)
        return [.commaSeparatedText, .plainText, UTType(filenameExtension: "xlsx") ?? .data]
        #else
        return [.commaSeparatedText, .plainText]
        #endif
    }

    static func parse(url: URL) throws -> RosterImportWorkbook {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "csv", "txt":
            let data = try Data(contentsOf: url)
            let rows = parseDelimitedText(data: data)
            let sheet = RosterImportWorkbook.Sheet(id: "csv", name: url.deletingPathExtension().lastPathComponent, rows: rows)
            return RosterImportWorkbook(sourceURL: url, sheets: [sheet])
        case "xlsx":
            #if os(macOS)
            return try parseXLSX(url: url)
            #else
            throw ParserError.unsupportedFileType
            #endif
        default:
            throw ParserError.unsupportedFileType
        }
    }

    private static func parseDelimitedText(data: Data) -> [[String]] {
        guard let string = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
            return []
        }
        let delimiter = preferredDelimiter(for: string)
        return CSVScanner(delimiter: delimiter).parse(string: string)
    }

    private static func preferredDelimiter(for string: String) -> Character {
        let firstLine = string.split(whereSeparator: \.isNewline).first.map(String.init) ?? string
        let commaCount = firstLine.filter { $0 == "," }.count
        let tabCount = firstLine.filter { $0 == "\t" }.count
        let semicolonCount = firstLine.filter { $0 == ";" }.count

        if tabCount > commaCount && tabCount >= semicolonCount {
            return "\t"
        }
        if semicolonCount > commaCount {
            return ";"
        }
        return ","
    }

    #if os(macOS)
    private static func parseXLSX(url: URL) throws -> RosterImportWorkbook {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("RelayRosterImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // Refuse zip bombs before extracting anything.
        let listing = Process()
        listing.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        listing.arguments = ["-l", url.path]
        let listingPipe = Pipe()
        listing.standardOutput = listingPipe
        listing.standardError = Pipe()
        try listing.run()
        let listingData = listingPipe.fileHandleForReading.readDataToEndOfFile()
        listing.waitUntilExit()
        guard listing.terminationStatus == 0,
              let totalBytes = RosterImportPaths.totalUncompressedBytes(
                  fromUnzipListing: String(decoding: listingData, as: UTF8.self)),
              totalBytes <= RosterImportPaths.maxUncompressedBytes
        else {
            throw ParserError.missingWorkbookData
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", url.path, "-d", tempRoot.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ParserError.missingWorkbookData
        }

        let workbookURL = tempRoot.appendingPathComponent("xl/workbook.xml")
        let relsURL = tempRoot.appendingPathComponent("xl/_rels/workbook.xml.rels")

        guard FileManager.default.fileExists(atPath: workbookURL.path),
              FileManager.default.fileExists(atPath: relsURL.path)
        else {
            throw ParserError.missingWorkbookData
        }

        let workbookParser = WorkbookXMLParser()
        let workbookSheets = try workbookParser.parse(data: Data(contentsOf: workbookURL))

        let relsParser = WorkbookRelationshipsParser()
        let relationships = try relsParser.parse(data: Data(contentsOf: relsURL))

        let sharedStringsURL = tempRoot.appendingPathComponent("xl/sharedStrings.xml")
        let sharedStrings: [String]
        if FileManager.default.fileExists(atPath: sharedStringsURL.path) {
            sharedStrings = try SharedStringsXMLParser().parse(data: Data(contentsOf: sharedStringsURL))
        } else {
            sharedStrings = []
        }

        let sheets: [RosterImportWorkbook.Sheet] = try workbookSheets.compactMap { workbookSheet in
            guard let target = relationships[workbookSheet.relationshipID] else { return nil }
            let path = target.replacingOccurrences(of: "\\", with: "/")
            let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
            let xlRoot = tempRoot.appendingPathComponent("xl", isDirectory: true)
            let stripped = RosterImportPaths.contained(normalizedPath.replacingOccurrences(of: "worksheets/", with: ""), in: xlRoot)
            let direct = RosterImportPaths.contained(normalizedPath, in: xlRoot)
            guard let resolvedURL = [stripped, direct].compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) })
            else { return nil }

            guard FileManager.default.fileExists(atPath: resolvedURL.path) else { return nil }
            let rows = try WorksheetXMLParser(sharedStrings: sharedStrings).parse(data: Data(contentsOf: resolvedURL))
            return RosterImportWorkbook.Sheet(id: workbookSheet.relationshipID, name: workbookSheet.name, rows: rows)
        }

        guard !sheets.isEmpty else {
            throw ParserError.noSheetsFound
        }

        return RosterImportWorkbook(sourceURL: url, sheets: sheets)
    }
    #endif
}

enum RosterImportApplyMode {
    case replace
    case append
}

enum RosterImportMerge {
    static let maxColumns = 12
    static let maxRows = 250

    static func apply(
        mode: RosterImportApplyMode,
        existingColumns: [DashboardRosterColumn],
        existingRows: [DashboardRosterRow],
        importedColumns: [DashboardRosterColumn],
        importedRows: [DashboardRosterRow]
    ) -> (columns: [DashboardRosterColumn], rows: [DashboardRosterRow]) {
        switch mode {
        case .replace:
            return (
                Array(importedColumns.prefix(maxColumns)),
                Array(importedRows.prefix(maxRows))
            )
        case .append:
            let remainingColumnSlots = max(0, maxColumns - existingColumns.count)
            let newColumns = Array(importedColumns.prefix(remainingColumnSlots))
            let mergedColumns = existingColumns + newColumns

            var mergedExistingRows = existingRows
            for rowIndex in mergedExistingRows.indices {
                for column in newColumns {
                    mergedExistingRows[rowIndex].values[column.id.uuidString] = ""
                }
            }

            let remainingRowSlots = max(0, maxRows - mergedExistingRows.count)
            let appendedRows: [DashboardRosterRow] = importedRows.prefix(remainingRowSlots).map { importedRow in
                var values: [String: String] = [:]
                for column in existingColumns {
                    values[column.id.uuidString] = ""
                }
                for (key, value) in importedRow.values {
                    values[key] = value
                }
                return DashboardRosterRow(values: values)
            }

            return (mergedColumns, mergedExistingRows + appendedRows)
        }
    }
}

private struct CSVScanner {
    let delimiter: Character

    func parse(string: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var isInQuotes = false
        var iterator = string.makeIterator()
        var buffered: Character?

        func flushField() {
            currentRow.append(currentField)
            currentField = ""
        }

        func flushRow() {
            flushField()
            if !(currentRow.count == 1 && currentRow[0].isEmpty && rows.isEmpty) {
                rows.append(currentRow)
            }
            currentRow = []
        }

        while true {
            let character: Character?
            if let pending = buffered {
                character = pending
                buffered = nil
            } else {
                character = iterator.next()
            }

            guard let character else { break }

            if isInQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            currentField.append("\"")
                        } else {
                            isInQuotes = false
                            buffered = next
                        }
                    } else {
                        isInQuotes = false
                    }
                } else {
                    currentField.append(character)
                }
                continue
            }

            switch character {
            case "\"":
                isInQuotes = true
            case delimiter:
                flushField()
            case "\n":
                flushRow()
            case "\r":
                if let next = iterator.next(), next != "\n" {
                    buffered = next
                }
                flushRow()
            default:
                currentField.append(character)
            }
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            flushRow()
        }

        return rows
    }
}

#if os(macOS)
private final class XMLDelegateBox: NSObject, XMLParserDelegate {}

private struct WorkbookSheetDescriptor {
    let name: String
    let relationshipID: String
}

private final class WorkbookXMLParser: NSObject, XMLParserDelegate {
    private var sheets: [WorkbookSheetDescriptor] = []

    func parse(data: Data) throws -> [WorkbookSheetDescriptor] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        guard parser.parse() else {
            throw parser.parserError ?? RosterImportParser.ParserError.missingWorkbookData
        }
        return sheets
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let name = qName ?? elementName
        if name.hasSuffix("sheet"),
           let sheetName = attributeDict["name"],
           let relationshipID = attributeDict["r:id"] ?? attributeDict["id"] {
            sheets.append(.init(name: sheetName, relationshipID: relationshipID))
        }
    }
}

private final class WorkbookRelationshipsParser: NSObject, XMLParserDelegate {
    private var relationships: [String: String] = [:]

    func parse(data: Data) throws -> [String: String] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? RosterImportParser.ParserError.missingWorkbookData
        }
        return relationships
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let name = qName ?? elementName
        if name.hasSuffix("Relationship"),
           let id = attributeDict["Id"],
           let target = attributeDict["Target"] {
            relationships[id] = target
        }
    }
}

private final class SharedStringsXMLParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var currentString = ""
    private var currentElement = ""
    private var isInsideSI = false

    func parse(data: Data) throws -> [String] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? RosterImportParser.ParserError.missingWorkbookData
        }
        return strings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let name = qName ?? elementName
        currentElement = name
        if name.hasSuffix("si") {
            isInsideSI = true
            currentString = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideSI, currentElement.hasSuffix("t") {
            currentString.append(string)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = qName ?? elementName
        if name.hasSuffix("si") {
            strings.append(currentString)
            currentString = ""
            isInsideSI = false
        }
        currentElement = ""
    }
}

private final class WorksheetXMLParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]

    private var rows: [[String]] = []
    private var currentRow: [Int: String] = [:]
    private var currentRowIndex: Int = 0
    private var currentCellColumn: Int = 0
    private var currentCellType: String?
    private var currentValue = ""
    private var currentElement = ""
    private var maxColumnIndex = -1

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    func parse(data: Data) throws -> [[String]] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? RosterImportParser.ParserError.missingWorkbookData
        }
        return rows
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let name = qName ?? elementName
        currentElement = name

        if name.hasSuffix("row") {
            currentRow = [:]
            maxColumnIndex = -1
        } else if name.hasSuffix("c") {
            currentCellType = attributeDict["t"]
            currentValue = ""
            let reference = attributeDict["r"] ?? ""
            currentCellColumn = Self.columnIndex(from: reference)
            maxColumnIndex = max(maxColumnIndex, currentCellColumn)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement.hasSuffix("v") || currentElement.hasSuffix("t") {
            currentValue.append(string)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = qName ?? elementName
        if name.hasSuffix("c") {
            let resolvedValue: String
            switch currentCellType {
            case "s":
                if let index = Int(currentValue), sharedStrings.indices.contains(index) {
                    resolvedValue = sharedStrings[index]
                } else {
                    resolvedValue = currentValue
                }
            default:
                resolvedValue = currentValue
            }
            currentRow[currentCellColumn] = resolvedValue
            currentValue = ""
            currentCellType = nil
        } else if name.hasSuffix("row") {
            let width = maxColumnIndex + 1
            if width > 0 {
                var row = Array(repeating: "", count: width)
                for (column, value) in currentRow {
                    if row.indices.contains(column) {
                        row[column] = value
                    }
                }
                rows.append(row)
            } else {
                rows.append([])
            }
            currentRowIndex += 1
        }
        currentElement = ""
    }

    private static func columnIndex(from cellReference: String) -> Int {
        let letters = cellReference.prefix { $0.isLetter }
        guard !letters.isEmpty else { return 0 }
        var value = 0
        for character in letters.uppercased() {
            guard let scalar = character.unicodeScalars.first else { continue }
            value = (value * 26) + Int(scalar.value) - 64
        }
        return max(0, value - 1)
    }
}
#endif

struct RosterImportReviewView: View {
    private static let maxRosterColumns = RosterImportMerge.maxColumns
    private static let maxRosterRows = RosterImportMerge.maxRows

    let workbook: RosterImportWorkbook
    let onCancel: () -> Void
    let onImport: (RosterImportApplyMode, [DashboardRosterColumn], [DashboardRosterRow]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSheetID: String = ""
    @State private var usesFirstRowAsHeaders: Bool = true
    @State private var selectedColumnIndexes: Set<Int> = []
    @State private var selectedMode: RosterImportApplyMode = .append

    private var selectedSheet: RosterImportWorkbook.Sheet? {
        workbook.sheets.first(where: { $0.id == selectedSheetID }) ?? workbook.sheets.first
    }

    private var maximumColumnCount: Int {
        selectedSheet?.rows.map(\.count).max() ?? 0
    }

    private var candidateHeaderRow: [String] {
        guard let rows = selectedSheet?.rows, !rows.isEmpty else { return [] }
        return rows[0]
    }

    private var previewRows: [[String]] {
        guard let rows = selectedSheet?.rows else { return [] }
        return Array(rows.prefix(8))
    }

    private func columnLabel(for index: Int) -> String {
        if usesFirstRowAsHeaders, candidateHeaderRow.indices.contains(index) {
            let header = candidateHeaderRow[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if !header.isEmpty {
                return header
            }
        }
        return "Column \(index + 1)"
    }

    private func toggleColumn(_ index: Int) {
        if selectedColumnIndexes.contains(index) {
            selectedColumnIndexes.remove(index)
        } else if selectedColumnIndexes.count < Self.maxRosterColumns {
            selectedColumnIndexes.insert(index)
        } else {
            // Ignore selections past the supported roster column limit.
        }
    }

    private func performImport() {
        guard let selectedSheet else { return }

        let orderedIndexes = selectedColumnIndexes.sorted()
        let columns = orderedIndexes.map { index in
            DashboardRosterColumn(title: columnLabel(for: index))
        }

        let dataRows: ArraySlice<[String]>
        if usesFirstRowAsHeaders, !selectedSheet.rows.isEmpty {
            dataRows = selectedSheet.rows.dropFirst()
        } else {
            dataRows = ArraySlice(selectedSheet.rows)
        }

        let rows: [DashboardRosterRow] = dataRows.compactMap { sourceRow in
            var values: [String: String] = [:]
            var hasContent = false

            for (offset, columnIndex) in orderedIndexes.enumerated() {
                let value = sourceRow.indices.contains(columnIndex) ? sourceRow[columnIndex] : ""
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    hasContent = true
                }
                values[columns[offset].id.uuidString] = value
            }

            return hasContent ? DashboardRosterRow(values: values) : nil
        }

        onImport(selectedMode, columns, rows)
        dismiss()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Import")
                .font(.title2.bold())

            Text(workbook.sourceURL.lastPathComponent)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Import Mode", selection: $selectedMode) {
                Text("Append to existing data").tag(RosterImportApplyMode.append)
                Text("Replace existing data").tag(RosterImportApplyMode.replace)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            Text("Roster limits: up to \(Self.maxRosterColumns) imported columns and \(Self.maxRosterRows) rows. Extra data will be ignored.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        if workbook.sheets.count > 1 {
                            Picker("Sheet", selection: $selectedSheetID) {
                                ForEach(workbook.sheets) { sheet in
                                    Text(sheet.name).tag(sheet.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Toggle("Use first row as column headers", isOn: $usesFirstRowAsHeaders)
                            .toggleStyle(.switch)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Columns to Import")
                                .font(.headline)

                            ForEach(0..<maximumColumnCount, id: \.self) { index in
                                Button {
                                    toggleColumn(index)
                                } label: {
                                    HStack {
                                        Image(systemName: selectedColumnIndexes.contains(index) ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(selectedColumnIndexes.contains(index) ? Color.accentColor : .secondary)
                                        Text(columnLabel(for: index))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.trailing, 6)
                }
                .frame(width: 280, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.headline)

                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 8) {
                            if !previewRows.isEmpty {
                                ForEach(Array(previewRows.enumerated()), id: \.offset) { rowIndex, row in
                                    HStack(spacing: 8) {
                                        Text("\(rowIndex + 1)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 28, alignment: .center)

                                        ForEach(0..<maximumColumnCount, id: \.self) { columnIndex in
                                            Text(row.indices.contains(columnIndex) ? row[columnIndex] : "")
                                                .font(.caption)
                                                .frame(width: 140, alignment: .leading)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 6)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .fill(Color.primary.opacity(0.05))
                                                )
                                        }
                                    }
                                }
                            } else {
                                Text("No preview rows available.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minWidth: 700, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                Button("Save") {
                    performImport()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedColumnIndexes.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 1040, idealWidth: 1320, maxWidth: 1600, minHeight: 560, idealHeight: 700, maxHeight: 860)
        .onAppear {
            selectedSheetID = workbook.sheets.first?.id ?? ""
            if let maxColumns = workbook.sheets.first?.rows.map(\.count).max() {
                selectedColumnIndexes = Set(0..<min(maxColumns, Self.maxRosterColumns))
            }
        }
        .onChange(of: selectedSheetID, initial: false) { _, _ in
            selectedColumnIndexes = Set(0..<min(maximumColumnCount, Self.maxRosterColumns))
        }
    }
}

enum RosterImportPaths {
    static let maxUncompressedBytes = 200 * 1024 * 1024

    static func contained(_ relativePath: String, in root: URL) -> URL? {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/") else { return nil }
        let base = root.standardizedFileURL
        let candidate = base.appendingPathComponent(normalized).standardizedFileURL
        return candidate.path.hasPrefix(base.path + "/") ? candidate : nil
    }

    /// Reads the grand total from the last line of `unzip -l` output ("  12345  3 files").
    static func totalUncompressedBytes(fromUnzipListing listing: String) -> Int? {
        let lines = listing.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = lines.last(where: { $0.hasSuffix("file") || $0.hasSuffix("files") }),
              let first = last.split(separator: " ").first else { return nil }
        return Int(first)
    }
}
