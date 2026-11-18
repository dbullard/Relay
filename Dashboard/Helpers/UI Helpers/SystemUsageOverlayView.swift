import SwiftUI
import Foundation
import Combine
import Darwin

/// Samples Relay's own CPU and memory use, matching Activity Monitor's row for Relay:
/// CPU is a percent of one core (so it can go past 100% when several threads are busy),
/// and memory is the process footprint (Activity Monitor's "Memory" column).
@MainActor
final class SystemUsageMonitor: ObservableObject {
    /// Average CPU over the last few samples, as a percent of one core.
    @Published var cpuPercent: Double = 0
    /// Highest CPU sample in the same window, as a percent of one core.
    @Published var cpuPeakPercent: Double = 0
    /// Relay's physical memory footprint in bytes.
    @Published var memoryFootprintBytes: UInt64 = 0
    /// The footprint as a share of the Mac's physical RAM (0–100).
    @Published var memoryPercent: Double = 0
    @Published var lastOscActivity: Date? = nil
    @Published var lastMidiActivity: Date? = nil

    private var cpuSamples: [Double] = []
    private let maxSamples: Int = 5

    // Delta-based CPU sampling state (process CPU seconds against a monotonic clock).
    private var lastProcessCPUSeconds: Double = 0
    private var lastCPUSampleUptime: TimeInterval?

    private var updateTask: Task<Void, Never>?
    private var midiObserver: NSObjectProtocol?

    deinit {
        updateTask?.cancel()
        if let midiObserver {
            NotificationCenter.default.removeObserver(midiObserver)
        }
    }

    func start() {
        guard updateTask == nil else { return }

        midiObserver = NotificationCenter.default.addObserver(
            forName: .midiReceiveMessageDidArrive,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lastMidiActivity = Date()
            }
        }

        // Hold self weakly between ticks so the loop never keeps a hidden overlay's
        // monitor alive (and sampling) after its view is gone.
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.updateMetrics()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    func stop() {
        updateTask?.cancel()
        updateTask = nil
        if let midiObserver {
            NotificationCenter.default.removeObserver(midiObserver)
            self.midiObserver = nil
        }
        cpuSamples.removeAll()
        lastCPUSampleUptime = nil
    }

    private func updateMetrics() {
        if let cpu = readAppCpuPercent() {
            cpuSamples.append(max(0, cpu))
            if cpuSamples.count > maxSamples {
                cpuSamples.removeFirst(cpuSamples.count - maxSamples)
            }
            // Publish only visible changes (the overlay shows whole percents). Each publish
            // schedules a SwiftUI transaction, so skipping no-op ones avoids a wakeup every 0.5 s.
            let avg = average(cpuSamples)
            if avg.rounded() != cpuPercent.rounded() { cpuPercent = avg }
            let peak = cpuSamples.max() ?? avg
            if peak.rounded() != cpuPeakPercent.rounded() { cpuPeakPercent = peak }
        }

        if let footprint = readAppMemoryFootprint() {
            // The footprint moves a little on every sample; only publish when the shown text changes.
            if Self.formatMemory(footprint) != Self.formatMemory(memoryFootprintBytes) {
                memoryFootprintBytes = footprint
            }
            let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
            if totalBytes > 0 {
                let percent = Double(footprint) / totalBytes * 100.0
                if percent.rounded() != memoryPercent.rounded() { memoryPercent = percent }
            }
        }

        let oscManager = OSCManager.shared
        let oscLast = maxDate(oscManager.lastReceiveAt, oscManager.lastSendAt)
        if let oscLast, oscLast != lastOscActivity {
            lastOscActivity = oscLast
        }
    }

    private func average(_ samples: [Double]) -> Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case let (l?, nil):
            return l
        case let (nil, r?):
            return r
        case let (l?, r?):
            return max(l, r)
        }
    }

    /// CPU used since the previous sample, as a percent of one core (Activity Monitor's convention).
    private func readAppCpuPercent() -> Double? {
        // getrusage counts every thread the process has ever run, including ones that have
        // since exited. Summing task_threads() only sees live threads, so time spent on
        // short-lived worker threads (GCD, audio, network) vanished between samples.
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        let cpuSeconds = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
            + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000

        let now = ProcessInfo.processInfo.systemUptime
        defer {
            lastProcessCPUSeconds = cpuSeconds
            lastCPUSampleUptime = now
        }

        // The first sample only sets the baseline.
        guard let last = lastCPUSampleUptime else { return nil }
        let elapsed = now - last
        guard elapsed > 0.05 else { return nil }
        return (cpuSeconds - lastProcessCPUSeconds) / elapsed * 100.0
    }

    /// Relay's physical footprint, the figure Activity Monitor shows in its "Memory" column.
    private func readAppMemoryFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }

    /// Binary units, like Activity Monitor: "212 MB", "1.4 GB".
    nonisolated static func formatMemory(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb < 1024 { return String(format: "%.0f MB", mb) }
        return String(format: "%.1f GB", mb / 1024)
    }
}

struct SystemUsageOverlayView: View {
    @AppStorage("osc.global.enabled") private var oscEnabled: Bool = false
    @AppStorage("midi.global.enabled") private var midiEnabled: Bool = false

    @StateObject private var monitor = SystemUsageMonitor()

    let showsLANConnections: Bool
    let lanPeerCount: Int

    private let activityWindow: TimeInterval = 1.0

    /// CPU is a percent of one core: one full core busy is a warning, two is heavy.
    private var cpuColor: Color {
        if monitor.cpuPercent >= 200 { return .red }
        if monitor.cpuPercent >= 100 { return .yellow }
        return .green
    }

    /// Memory is Relay's share of the Mac's RAM.
    private var memoryColor: Color {
        if monitor.memoryPercent >= 90 { return .red }
        if monitor.memoryPercent >= 75 { return .yellow }
        return .green
    }

    private var healthColor: Color {
        if cpuColor == .red || memoryColor == .red { return .red }
        if cpuColor == .yellow || memoryColor == .yellow { return .yellow }
        return .green
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(healthColor)
                .frame(width: 8, height: 8)
                .accessibilityLabel("App health")

            usageBar(
                label: String(format: "CPU %.0f%%", max(monitor.cpuPercent, 0)),
                fraction: monitor.cpuPercent / 100.0,
                color: cpuColor
            )
            usageBar(
                label: "MEM \(SystemUsageMonitor.formatMemory(monitor.memoryFootprintBytes))",
                fraction: monitor.memoryPercent / 100.0,
                color: memoryColor
            )

            activityIndicator(label: "OSC", enabled: oscEnabled, lastActivity: monitor.lastOscActivity)
            activityIndicator(label: "MIDI", enabled: midiEnabled, lastActivity: monitor.lastMidiActivity)

            if showsLANConnections {
                lanConnectionsPill
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .onAppear {
            monitor.start()
        }
        .onDisappear {
            monitor.stop()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App usage")
    }

    private var lanConnectionsPill: some View {
        HStack(spacing: 5) {
            DashboardSymbolImage("link.icloud.fill")
                .font(.caption2)
            Text("\(lanPeerCount)")
                .font(.caption2)
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cloud connections")
        .accessibilityValue("\(lanPeerCount)")
    }

    /// `fraction` fills the bar (clamped to 0–1).
    @ViewBuilder
    private func usageBar(label: String, fraction: Double, color: Color) -> some View {
        let clamped = min(max(fraction, 0), 1)
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 46, height: 4)

                Capsule()
                    .fill(color)
                    .frame(width: max(2, CGFloat(clamped) * 46.0), height: 4)
            }
        }
    }

    @ViewBuilder
    private func activityIndicator(label: String, enabled: Bool, lastActivity: Date?) -> some View {
        let isActive = enabled && isRecentlyActive(lastActivity)
        let dotColor: Color = {
            if !enabled { return Color.white.opacity(0.25) }
            return isActive ? Color.green : Color.white.opacity(0.35)
        }()

        HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
    }

    private func isRecentlyActive(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Date().timeIntervalSince(date) <= activityWindow
    }
}
