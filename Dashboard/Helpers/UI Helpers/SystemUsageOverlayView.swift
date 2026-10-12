import SwiftUI
import Foundation
import Combine
import Darwin

@MainActor
final class SystemUsageMonitor: ObservableObject {
    @Published var cpuPercent: Double = 0
    @Published var cpuPeakPercent: Double = 0
    @Published var memoryPercent: Double = 0
    @Published var lastOscActivity: Date? = nil
    @Published var lastMidiActivity: Date? = nil

    private var cpuSamples: [Double] = []
    private var memorySamples: [Double] = []
    private let maxSamples: Int = 5

    // Delta-based CPU sampling state
    private var lastTotalThreadCPUSeconds: Double = 0
    private var lastCPUSampleTime: Date = .distantPast

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
        ) { _ in
            Task { @MainActor [weak self] in
                self?.lastMidiActivity = Date()
            }
        }

        updateTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.updateMetrics()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func updateMetrics() {
        if let cpu = readAppCpuPercent() {
            cpuSamples.append(max(0, cpu))
            if cpuSamples.count > maxSamples {
                cpuSamples.removeFirst(cpuSamples.count - maxSamples)
            }
            cpuPercent = average(cpuSamples)
            cpuPeakPercent = cpuSamples.max() ?? cpuPercent
        }

        if let mem = readAppMemoryPercent() {
            memorySamples.append(max(0, mem))
            if memorySamples.count > maxSamples {
                memorySamples.removeFirst(memorySamples.count - maxSamples)
            }
            memoryPercent = average(memorySamples)
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

    private func readAppCpuPercent() -> Double? {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let taskResult = task_threads(mach_task_self_, &threadList, &threadCount)
        guard taskResult == KERN_SUCCESS, let threads = threadList else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads),
                          vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.stride))
        }

        // Sum cumulative user+system time across all live threads.
        // Comparing deltas between samples gives true instantaneous CPU usage,
        // unlike thread_basic_info.cpu_usage which is a kernel decaying average.
        var totalCPUSeconds: Double = 0
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.stride / MemoryLayout<integer_t>.stride)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            guard result == KERN_SUCCESS else { continue }
            totalCPUSeconds += Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
            totalCPUSeconds += Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastCPUSampleTime)
        let delta = totalCPUSeconds - lastTotalThreadCPUSeconds
        lastTotalThreadCPUSeconds = totalCPUSeconds
        lastCPUSampleTime = now

        // Skip the very first sample — delta has no prior baseline
        guard elapsed > 0.05 else { return nil }

        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        return min((delta / elapsed / Double(cores)) * 100.0, 100.0)
    }

    private func readAppMemoryPercent() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let usedBytes = Double(info.phys_footprint)
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        guard totalBytes > 0 else { return nil }
        return (usedBytes / totalBytes) * 100.0
    }
}

struct SystemUsageOverlayView: View {
    @AppStorage("osc.global.enabled") private var oscEnabled: Bool = false
    @AppStorage("midi.global.enabled") private var midiEnabled: Bool = false

    @StateObject private var monitor = SystemUsageMonitor()

    let showsLANConnections: Bool
    let lanPeerCount: Int

    private let activityWindow: TimeInterval = 1.0

    private var healthColor: Color {
        let worst = max(monitor.cpuPercent, monitor.memoryPercent)
        if worst >= 90 { return .red }
        if worst >= 75 { return .yellow }
        return .green
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(healthColor)
                .frame(width: 8, height: 8)
                .accessibilityLabel("App health")

            usageBar(title: "CPU", value: monitor.cpuPercent)
            usageBar(title: "MEM", value: monitor.memoryPercent)

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

    @ViewBuilder
    private func usageBar(title: String, value: Double) -> some View {
        let clamped = min(max(value, 0), 100)
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%@ %.0f%%", title, clamped))
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
                    .fill(barColor(for: clamped))
                    .frame(width: max(2, CGFloat(clamped / 100.0) * 46.0), height: 4)
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

    private func barColor(for value: Double) -> Color {
        if value >= 90 { return .red }
        if value >= 75 { return .yellow }
        return .green
    }
}
