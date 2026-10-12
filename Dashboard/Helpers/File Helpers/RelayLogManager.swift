//
//  RelayLogManager.swift
//  Relay
//
//  Created by David Bullard on 2/11/26.
//

import Foundation

#if canImport(Darwin)
import Darwin
#endif
#if os(iOS)
import UIKit
#endif

final class RelayLogManager {
    static let shared = RelayLogManager()

    private let fileManager = FileManager.default
    private let logDirectoryName = "RelayLogs"
    private let appSupportDirectoryName = "Relay"
    private let logMirrorQueue = DispatchQueue(label: "RelayLogManager.logMirror")
    private var isStarted = false
    private var currentLogURL: URL?
    private var hasInstalledCrashHandlers = false
    private var logFileHandle: FileHandle?
    private var logMirrorReadHandle: FileHandle?
    private var originalStdoutHandle: FileHandle?

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        do {
            let directory = try ensureLogDirectory()
            cleanupOldLogs(in: directory, maxCount: 10, maxTotalBytes: 20 * 1024 * 1024)

            let timestamp = Self.timestampString()
            let fileName = "Relay-\(timestamp).log"
            let logURL = directory.appendingPathComponent(fileName)
            if !fileManager.fileExists(atPath: logURL.path) {
                fileManager.createFile(atPath: logURL.path, contents: nil, attributes: nil)
            }
            currentLogURL = logURL

            try redirectStdoutAndStderr(to: logURL)
            installCrashHandlersIfNeeded()

            print("[Relay] Log capture started: \(logURL.lastPathComponent)")
            print(sessionHeader())
        } catch {
            print("[Relay] Failed to start log capture: \(error.localizedDescription)")
        }
    }

    func makeCombinedLogData() throws -> Data {
        let directory = try ensureLogDirectory()
        cleanupOldLogs(in: directory, maxCount: 10, maxTotalBytes: 20 * 1024 * 1024)

        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let sorted = urls.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        let diagnostics = RelayDiagnosticsStore.shared
        var combined = ""
        let range = logDateRangeText(from: sorted)
        combined.append("===== SUMMARY =====\n")
        combined.append(diagnostics.diagnosticSummary())
        if !range.isEmpty {
            combined.append("\nLog Range: \(range)")
        }
        combined.append("\n\n===== RECENT ERRORS =====\n")
        combined.append(diagnostics.recentErrorsSummary(limit: 50))
        combined.append("\n\n===== SHURE TRACE =====\n")
        combined.append(diagnostics.shureTraceSummary(limit: 400))
        combined.append("\n\n===== SENNHEISER TRACE =====\n")
        combined.append(diagnostics.sennheiserTraceSummary(limit: 400))
        combined.append("\n\n===== CANVAS MOUNT TRACE =====\n")
        combined.append(diagnostics.canvasMountTraceSummary(limit: 500))
        combined.append("\n\n===== PERFORMANCE =====\n")
        combined.append(diagnostics.performanceSummary(limit: 20))
        combined.append("\n\n===== EVENT COUNTERS =====\n")
        combined.append(diagnostics.eventCountersSummary(limit: 40))
        combined.append("\n\n===== LOGS =====\n\n")

        for url in sorted {
            let name = url.lastPathComponent
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let filtered = filterLogContent(content)
            combined.append("===== \(name) =====\n")
            combined.append(filtered)
            if !combined.hasSuffix("\n") {
                combined.append("\n")
            }
            combined.append("\n")
        }

        return combined.data(using: .utf8) ?? Data()
    }

    private func ensureLogDirectory() throws -> URL {
        #if os(macOS)
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        #else
        let base = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        #endif

        let appSupportURL = base.appendingPathComponent(appSupportDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: appSupportURL.path) {
            try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        }

        let logsURL = appSupportURL.appendingPathComponent(logDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: logsURL.path) {
            try fileManager.createDirectory(at: logsURL, withIntermediateDirectories: true)
        }
        return logsURL
    }

    private func cleanupOldLogs(in directory: URL, maxCount: Int, maxTotalBytes: Int) {
        guard let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return
        }

        let sorted = urls.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        var totalBytes = 0
        var retained: [URL] = []

        for url in sorted {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            totalBytes += size
            retained.append(url)
        }

        var toDelete: [URL] = []
        if retained.count > maxCount {
            toDelete.append(contentsOf: retained.suffix(from: maxCount))
        }

        if totalBytes > maxTotalBytes {
            var running = totalBytes
            for url in retained.reversed() {
                guard running > maxTotalBytes else { break }
                if !toDelete.contains(url) {
                    toDelete.append(url)
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    running -= size
                }
            }
        }

        for url in toDelete {
            try? fileManager.removeItem(at: url)
        }
    }

    private func redirectStdoutAndStderr(to url: URL) throws {
        #if canImport(Darwin)
        fflush(stdout)
        fflush(stderr)

        let fileHandle = try FileHandle(forWritingTo: url)
        try fileHandle.seekToEnd()

        let pipe = Pipe()
        let stdoutFD = dup(STDOUT_FILENO)
        let stderrFD = dup(STDERR_FILENO)
        guard stdoutFD >= 0, stderrFD >= 0 else {
            if stdoutFD >= 0 { close(stdoutFD) }
            if stderrFD >= 0 { close(stderrFD) }
            throw NSError(
                domain: "RelayLogManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to duplicate standard output handles."]
            )
        }

        guard dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO) >= 0,
              dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO) >= 0 else {
            close(stdoutFD)
            close(stderrFD)
            throw NSError(
                domain: "RelayLogManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to redirect standard output to the log mirror pipe."]
            )
        }

        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IOLBF, 0)

        close(stderrFD)
        originalStdoutHandle = FileHandle(fileDescriptor: stdoutFD, closeOnDealloc: true)
        logFileHandle = fileHandle
        logMirrorReadHandle = pipe.fileHandleForReading

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.logMirrorQueue.async {
                self.logFileHandle?.write(data)
                self.originalStdoutHandle?.write(data)
            }
        }

        try? pipe.fileHandleForWriting.close()
        #endif
    }

    private func sessionHeader() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let appName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? "Relay"
        let version = info["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info["CFBundleVersion"] as? String ?? "Unknown"

        #if os(iOS)
        let device = UIDevice.current
        let osVersion = "\(device.systemName) \(device.systemVersion)"
        let model = device.model
        #else
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let model = Host.current().localizedName ?? "Mac"
        #endif

        let timestamp = ISO8601DateFormatter().string(from: Date())
        return "[Session] \(appName) v\(version) (\(build)) • \(model) • \(osVersion) • \(timestamp)"
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }

    private func filterLogContent(_ content: String) -> String {
        let allowSubstrings = [
            "[Relay]",
            "[Session]",
            "[AutomationRuntime]",
            "[MIDI]",
            "[OSC]",
            "[NDI]",
            "[LAN",
            "🟦",
            "🧩",
            "✅",
            "❌",
            "[ProPresenter]",
            "[Resolume]",
            "[PCO]",
            "[Shure]",
            "[ShureTrace]",
            "[Sennheiser]",
            "[SennheiserTrace]",
            "[SennheiserConnectionService]",
            "[CanvasMount]",
            "[Dashboard]",
            "[RelaySpeechWorker]",
            "[Perf]"
        ]

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let filtered = lines.filter { line in
            let text = String(line)
            if text.hasPrefix("OSLOG-") { return false }
            return allowSubstrings.contains(where: { text.contains($0) })
        }
        return filtered.joined(separator: "\n")
    }

    private func installCrashHandlersIfNeeded() {
        guard !hasInstalledCrashHandlers else { return }
        hasInstalledCrashHandlers = true

        NSSetUncaughtExceptionHandler { exception in
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let name = exception.name.rawValue
            let reason = exception.reason ?? "Unknown reason"
            let message = "❌ [Crash] Uncaught exception: \(name) — \(reason) @ \(timestamp)\n"
            RelayLogManager.writeCrashMessage(message)
        }

        let handler: @convention(c) (Int32) -> Void = { signal in
            let message = "❌ [Crash] Signal \(signal)\n"
            RelayLogManager.writeCrashMessage(message)
            Darwin.signal(signal, SIG_DFL)
            raise(signal)
        }

        Darwin.signal(SIGABRT, handler)
        Darwin.signal(SIGTRAP, handler)
        Darwin.signal(SIGILL, handler)
        Darwin.signal(SIGSEGV, handler)
        Darwin.signal(SIGBUS, handler)
    }

    private static func writeCrashMessage(_ message: String) {
        message.withCString { ptr in
            _ = write(STDERR_FILENO, ptr, strlen(ptr))
        }
    }

    private func logDateRangeText(from urls: [URL]) -> String {
        guard !urls.isEmpty else { return "" }
        let dates = urls.compactMap { url in
            try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        guard let newest = dates.max(), let oldest = dates.min() else { return "" }
        let formatter = ISO8601DateFormatter()
        return "\(formatter.string(from: oldest)) → \(formatter.string(from: newest))"
    }
}
