import XCTest
@testable import Relay

@MainActor
final class NDIFrameProcessorTests: XCTestCase {

    func test_initialStateIsIdle() async {
        let processor = NDIFrameProcessor()
        let snapshot = await processor.currentSnapshot()
        XCTAssertEqual(snapshot.state, .idle)
        XCTAssertEqual(snapshot.retryCount, 0)
    }

    func test_connectingEvent_setsConnectingState() async {
        let processor = NDIFrameProcessor()
        await processor.process(.connecting)
        let snapshot = await processor.currentSnapshot()
        XCTAssertEqual(snapshot.state, .connecting)
    }

    func test_connectedEvent_setsConnectedState() async {
        let processor = NDIFrameProcessor()
        let info = NDIReceiverConnectionInfo(sourceName: "Test", interfaceID: nil, resolution: CGSize(width: 1920, height: 1080), frameRate: 30)
        await processor.process(.connected(info))
        let snapshot = await processor.currentSnapshot()
        XCTAssertEqual(snapshot.state, .connected)
        XCTAssertEqual(snapshot.connectionInfo, info)
    }

    func test_frameEvent_incrementsFrameCount() async {
        let processor = NDIFrameProcessor()
        let frame = NDIFrame(frameNumber: 1, width: 1920, height: 1080, pixelFormat: .bgra8, timestamp: Date(), estimatedFPS: 30)
        await processor.process(.frame(frame))
        let snapshot = await processor.currentSnapshot()
        XCTAssertEqual(snapshot.receivedFrameCount, 1)
        XCTAssertEqual(snapshot.latestFrame?.frameNumber, frame.frameNumber)
        XCTAssertEqual(snapshot.latestFrame?.width, frame.width)
        XCTAssertEqual(snapshot.latestFrame?.pixelFormat, frame.pixelFormat)
    }

    func test_failedEvent_setsFailedStateAndIncrementsRetry() async {
        let processor = NDIFrameProcessor()
        await processor.process(.failed("test error"))
        let snapshot = await processor.currentSnapshot()
        XCTAssertEqual(snapshot.state, .failed("test error"))
        XCTAssertEqual(snapshot.retryCount, 1)
    }

    func test_disconnectedEvent_resetsToIdle() async {
        let processor = NDIFrameProcessor()
        await processor.process(.connecting)
        await processor.process(.disconnected(nil))
        let snapshot = await processor.currentSnapshot()
        XCTAssertEqual(snapshot.state, .idle)
    }

    func test_resetRetry_clearsRetryCount() async {
        let processor = NDIFrameProcessor()
        await processor.process(.failed("err"))
        await processor.process(.failed("err"))
        await processor.resetRetry()
        let snapshot = await processor.currentSnapshot()
        XCTAssertEqual(snapshot.retryCount, 0)
    }

    func test_frameEvent_dropDetection_incrementsDropCount() async {
        let processor = NDIFrameProcessor()
        let first = NDIFrame(frameNumber: 1, width: 1920, height: 1080, pixelFormat: .bgra8,
                             timestamp: Date(timeIntervalSinceNow: -2.0), estimatedFPS: 30)
        let second = NDIFrame(frameNumber: 2, width: 1920, height: 1080, pixelFormat: .bgra8,
                              timestamp: Date(), estimatedFPS: 30)
        await processor.process(.frame(first))
        await processor.process(.frame(second))
        let snapshot = await processor.currentSnapshot()
        XCTAssertEqual(snapshot.droppedFrameCount, 1)
        XCTAssertEqual(snapshot.receivedFrameCount, 2)
    }

    func test_setSuspended_setsState() async {
        let processor = NDIFrameProcessor()
        await processor.setSuspended(.hiddenTile)
        let snapshot = await processor.currentSnapshot()
        XCTAssertEqual(snapshot.state, .suspended(.hiddenTile))
    }

    func test_setSuspendedNil_fromSuspended_revertsToIdle() async {
        let processor = NDIFrameProcessor()
        await processor.setSuspended(.hiddenTile)
        await processor.setSuspended(nil)
        let snapshot = await processor.currentSnapshot()
        XCTAssertEqual(snapshot.state, .idle)
    }
}
