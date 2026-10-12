import Foundation

// MARK: - SPLInputLogger
//
// Writes a CSV log file for a single audio input. One instance per
// active logging session per input. Refactored from DbReaderAutoLogger.

final class SPLInputLogger {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()
    private static let fileStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    private let fileURL: URL
    private var handle: FileHandle?
    private var scopedURL: URL?
    private var didStartAccess = false

    init?(input: AudioInputConfig, sessionId: UUID, sessionStart: Date,
          folderURL: URL, bookmarkData: Data?) {
        var resolvedFolder = folderURL
        if let bookmarkData {
            var isStale = false
            #if os(macOS)
            if let scoped = try? URL(resolvingBookmarkData: bookmarkData,
                                     options: .withSecurityScope,
                                     relativeTo: nil,
                                     bookmarkDataIsStale: &isStale) {
                didStartAccess = scoped.startAccessingSecurityScopedResource()
                scopedURL = scoped
                resolvedFolder = scoped
            }
            #endif
        }

        do {
            try FileManager.default.createDirectory(
                at: resolvedFolder, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        // Sanitize input name for use in filename (replace non-alphanumeric chars with dashes)
        let safeName = input.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let stamp = Self.fileStampFormatter.string(from: sessionStart)
        let sessionPrefix = sessionId.uuidString.prefix(8)
        let filename = "SPL-\(safeName)-\(stamp)-\(sessionPrefix).csv"
        fileURL = resolvedFolder.appendingPathComponent(filename)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let header = [
                "# SPL Input Log",
                "# Generated: \(Self.isoFormatter.string(from: Date()))",
                "# Input Name: \(input.name)",
                "# Device UID: \(input.deviceUID ?? "")",
                "# Channel Index: \(input.channelIndex)",
                "# Calibration Offset dB: \(String(format: "%.2f", input.calibrationOffsetDb))",
                "timestamp_iso,spl,peak,raw_dbfs,raw_peak_dbfs,raw_peak_dbfs_max_hold," +
                "raw_ac_dbfs,raw_dc_dbfs," +
                "estimated_freq_hz,calibration_offset_db,sample_rate_hz," +
                "weighting,time_weighting," +
                "a_fast,a_slow,a_slow_max,c_fast,c_slow,z_fast,z_slow,ca_fast,ca_slow"
            ].joined(separator: "\n") + "\n"
            guard (try? header.write(to: fileURL, atomically: true, encoding: .utf8)) != nil
            else { return nil }
        }

        guard let fh = try? FileHandle(forWritingTo: fileURL) else { return nil }
        fh.seekToEndOfFile()
        handle = fh
    }

    func append(payload: SPLPayload, calibrationOffsetDb: Double,
                aSlowMax: Double, rawPeakDbfsMax: Double) {
        guard let handle else { return }
        let ts = Self.isoFormatter.string(from: payload.timestamp)
        let fmt: (Double) -> String = { v in
            v.isFinite ? String(format: "%.2f", v) : ""
        }
        let line = "\(ts),\(fmt(payload.zSlow)),\(fmt(payload.zFast))," +
            "\(fmt(payload.rawDbFS)),\(fmt(payload.rawPeakDbFS)),\(fmt(rawPeakDbfsMax))," +
            "\(fmt(payload.cFast))," +   // raw_ac_dbfs
            "," +                         // raw_dc_dbfs (always empty)
            "\(fmt(payload.estimatedFrequencyHz)),\(fmt(calibrationOffsetDb))," +
            "\(fmt(payload.sampleRate)),z,slow," +
            "\(fmt(payload.aFast)),\(fmt(payload.aSlow)),\(fmt(aSlowMax))," +
            "\(fmt(payload.cFast)),\(fmt(payload.cSlow))," +
            "\(fmt(payload.zFast)),\(fmt(payload.zSlow))," +
            "\(fmt(payload.caFast)),\(fmt(payload.caSlow))\n"
        if let data = line.data(using: .utf8) {
            handle.write(data)
        }
    }

    deinit {
        close()
    }

    func close() {
        try? handle?.close()
        handle = nil
        if let scopedURL, didStartAccess {
            scopedURL.stopAccessingSecurityScopedResource()
        }
        scopedURL = nil
        didStartAccess = false
    }

    static func defaultFolderURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("Relay")
                   .appendingPathComponent("SPL Logs")
    }
}
