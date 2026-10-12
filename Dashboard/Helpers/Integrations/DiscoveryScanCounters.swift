import Foundation

/// Thread-safe integer counters for cross-thread discovery-scan diagnostics.
///
/// UDP/TCP discovery services do socket I/O and packet parsing on background
/// GCD queues, but are `@MainActor` types. A GCD read-source event handler is
/// invoked directly by libdispatch on its target queue — it never actually
/// hops through the MainActor's executor, even when the closure is written
/// inline inside a `@MainActor` method. Counter increments made there were
/// racing against reads from `stop()`/`stopScan()` on the main actor. This
/// box lives outside actor isolation and serializes access on its own queue
/// so both sides can touch it safely without an async hop.
final class DiscoveryScanCounters {
    private let queue = DispatchQueue(label: "DiscoveryScanCounters")
    private var values: [String: Int] = [:]

    func increment(_ key: String, by amount: Int = 1) {
        queue.sync { values[key, default: 0] += amount }
    }

    func value(_ key: String) -> Int {
        queue.sync { values[key, default: 0] }
    }

    func reset() {
        queue.sync { values.removeAll() }
    }
}
