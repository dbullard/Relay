//
//  TransportStateIsolationTests.swift
//  RelayTests
//
//  Coverage for TransportEventState, the shared actor that owns NWConnection
//  receive-buffer and one-shot-completion state for the ProPresenter and
//  console transport connectors.
//

import XCTest
@testable import Relay

final class TransportStateIsolationTests: XCTestCase {
    func testTransportStateEmitsOneCompletionForRepeatedReadyEvents() async {
        let state = TransportEventState()
        let first = await state.finishIfNeeded()
        let second = await state.finishIfNeeded()
        XCTAssertTrue(first)
        XCTAssertFalse(second)
    }

    func testTransportStateAppendsFragmentsInOrder() async {
        let state = TransportEventState()
        await state.append(Data("one".utf8))
        await state.append(Data("two".utf8))
        let buffered = await state.bufferedData()
        XCTAssertEqual(buffered, Data("onetwo".utf8))
    }

    func testTakeBufferedDataDrainsTheBuffer() async {
        let state = TransportEventState()
        await state.append(Data("payload".utf8))
        let drained = await state.takeBufferedData()
        XCTAssertEqual(drained, Data("payload".utf8))
        let after = await state.bufferedData()
        XCTAssertTrue(after.isEmpty)
    }

    /// Guards against a regression where many concurrent callers of `finishIfNeeded()`
    /// (mirroring `.ready`/`.failed`/timeout racing on a real NWConnection) could ever
    /// observe `true` more than once.
    func testFinishIfNeededIsExactlyOnceUnderConcurrentContention() async {
        let state = TransportEventState()
        let winners = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<50 {
                group.addTask { await state.finishIfNeeded() }
            }
            var results: [Bool] = []
            for await result in group { results.append(result) }
            return results
        }
        XCTAssertEqual(winners.filter { $0 }.count, 1)
    }
}
