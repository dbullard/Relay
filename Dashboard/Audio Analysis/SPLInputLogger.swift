import Foundation

// MARK: - SPLInputLogger
//
// Writes a CSV log file for a single audio input. One instance per
// active logging session per input. Refactored from DbReaderAutoLogger.
//
// Thread-safe: rows are formatted and written on a private serial queue, so callers on
// any thread (including the main thread) never wait on disk I/O.

nonisolated final class SPLInputLogger: @unchecked Sendable {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()
    private static let fileStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// Levels accumulated over one logging interval.
    struct IntervalStats: Sendable {
        /// Highest Z-weighted fast level seen in the interval (calibrated dB).
        var zFastMax: Double
        /// Equivalent continuous levels over the interval (calibrated dB).
        var leqA: Double
        var leqC: Double
        var leqZ: Double
    }

    private let fileURL: URL
    private let queue = DispatchQueue(label: "Relay.SPLInputLogger", qos: .utility)
    // Everything below is only touched on `queue` after init.
    private var handle: FileHandle?
    private var scopedURL: URL?
    private var didStartAccess = false

    /// Called once (on the logger's queue) if a write fails, e.g. the folder's drive was
    /// unplugged. Logging for this input stops after that.
    var onWriteFailure: (@Sendable (String) -> Void)?

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
                "# One row per second. spl = Z slow at the row time; peak = highest Z fast in the second;",
                "# leq_* = equivalent continuous level over the second. raw_* columns are uncalibrated dBFS.",
                "timestamp_iso,spl,peak,raw_dbfs,raw_peak_dbfs,raw_peak_dbfs_max_hold," +
                "raw_ac_dbfs,raw_dc_dbfs," +
                "calibration_offset_db,sample_rate_hz," +
                "weighting,time_weighting," +
                "a_fast,a_slow,a_slow_max,c_fast,c_slow,z_fast,z_slow,ca_fast,ca_slow," +
                "leq_a,leq_c,leq_z"
            ].joined(separator: "\n") + "\n"
            guard (try? header.write(to: fileURL, atomically: true, encoding: .utf8)) != nil
            else { return nil }
        }

        guard let fh = try? FileHandle(forWritingTo: fileURL) else { return nil }
        guard (try? fh.seekToEnd()) != nil else { return nil }
        handle = fh
    }

    /// Queues one CSV row. `interval` carries the per-interval peak and Leq values; without
    /// it, the peak column falls back to the instantaneous Z fast level.
    func append(payload: SPLPayload, calibrationOffsetDb: Double,
                aSlowMax: Double, rawPeakDbfsMax: Double,
                interval: IntervalStats? = nil) {
        queue.async { [self] in
            guard let handle else { return }
            let ts = Self.isoFormatter.string(from: payload.timestamp)
            let fmt: (Double) -> String = { v in
                v.isFinite ? String(format: "%.2f", v) : ""
            }
            let peak = interval?.zFastMax ?? payload.zFast
            let line = "\(ts),\(fmt(payload.zSlow)),\(fmt(peak))," +
                "\(fmt(payload.rawDbFS)),\(fmt(payload.rawPeakDbFS)),\(fmt(rawPeakDbfsMax))," +
                "\(fmt(payload.cFast - payload.calibrationOffsetDb))," +   // raw_ac_dbfs: C fast, uncalibrated
                "," +                         // raw_dc_dbfs (always empty)
                "\(fmt(calibrationOffsetDb))," +
                "\(fmt(payload.sampleRate)),z,slow," +
                "\(fmt(payload.aFast)),\(fmt(payload.aSlow)),\(fmt(aSlowMax))," +
                "\(fmt(payload.cFast)),\(fmt(payload.cSlow))," +
                "\(fmt(payload.zFast)),\(fmt(payload.zSlow))," +
                "\(fmt(payload.caFast)),\(fmt(payload.caSlow))," +
                "\(fmt(interval?.leqA ?? .nan)),\(fmt(interval?.leqC ?? .nan)),\(fmt(interval?.leqZ ?? .nan))\n"
            do {
                // write(contentsOf:) throws; the old write(_:) raised an Objective-C
                // exception (and crashed the app) when the file became unwritable.
                try handle.write(contentsOf: Data(line.utf8))
            } catch {
                closeOnQueue()
                onWriteFailure?("Couldn't write to \"\(fileURL.lastPathComponent)\": \(error.localizedDescription)")
            }
        }
    }

    deinit {
        // Runs after the last reference is gone, so no queued work can still be pending
        // (each queued block retains self).
        try? handle?.close()
        if let scopedURL, didStartAccess {
            scopedURL.stopAccessingSecurityScopedResource()
        }
    }

    /// Flushes queued rows and closes the file.
    func close() {
        queue.sync { closeOnQueue() }
    }

    private func closeOnQueue() {
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
