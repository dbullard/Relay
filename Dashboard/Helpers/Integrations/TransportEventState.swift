//
//  TransportEventState.swift
//  Relay
//
//  Shared concurrency-safe state owner for NWConnection-backed transport clients.
//

import Foundation

/// Serial owner for `NWConnection` callback state.
///
/// `NWConnection` invokes its handlers on a dispatch queue, so receive buffers
/// and one-shot completion flags are shared mutable state across concurrency
/// domains. Owning them in an actor removes the race without dropping the
/// callback queue that Network framework requires.
actor TransportEventState {
    private var receiveBuffer = Data()
    private var didFinish = false

    func append(_ data: Data) { receiveBuffer.append(data) }

    func bufferedData() -> Data { receiveBuffer }

    /// Returns the buffer and clears it, so a parser cannot re-consume bytes.
    func takeBufferedData() -> Data {
        defer { receiveBuffer.removeAll(keepingCapacity: true) }
        return receiveBuffer
    }

    /// `true` exactly once, for the first caller. Guards continuation resume
    /// and teardown paths that a connection can otherwise reach twice.
    ///
    /// Callers typically reach this from inside a `Task { ... }` spawned off an
    /// `NWConnection` callback (response) racing another spawned off a `DispatchWorkItem`
    /// (timeout). Which one wins is decided by Swift Concurrency's task scheduling order,
    /// not by strict real-time arrival order the way the old single-serial-queue + plain
    /// `var` gate was. In practice this only matters for completions that arrive within
    /// scheduling-jitter of each other, which is far below the multi-second timeouts these
    /// call sites use today -- but a future timeout tightened to a similar order of
    /// magnitude as scheduling jitter could reintroduce a user-visible race here.
    func finishIfNeeded() -> Bool {
        guard !didFinish else { return false }
        didFinish = true
        return true
    }
}
