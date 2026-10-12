import XCTest
@testable import Relay

@MainActor
final class AudioAnalysisEngineTests: XCTestCase {

    func testSPLSubscriberReferenceCount() async {
        let engine = AudioAnalysisEngine()
        let config = AudioInputConfig(name: "Test", deviceUID: nil, channelIndex: 0)
        let inputID = config.id

        let (sub1, _) = await engine.subscribeSPL(to: inputID, config: config)
        let count1 = await engine.splSubscriberCount(for: inputID)
        XCTAssertEqual(count1, 1)

        let (sub2, _) = await engine.subscribeSPL(to: inputID, config: config)
        let count2 = await engine.splSubscriberCount(for: inputID)
        XCTAssertEqual(count2, 2)

        await engine.unsubscribeSPL(id: sub1)
        let count3 = await engine.splSubscriberCount(for: inputID)
        XCTAssertEqual(count3, 1)

        await engine.unsubscribeSPL(id: sub2)
        let count4 = await engine.splSubscriberCount(for: inputID)
        XCTAssertEqual(count4, 0)
    }

    func testFFTSubscriberCount() async {
        let engine = AudioAnalysisEngine()
        let config = AudioInputConfig(name: "FFTTest", deviceUID: nil, channelIndex: 0)
        let inputID = config.id

        let (subID, _) = await engine.subscribeFFT(to: inputID, config: config, resolution: .thirdOct)
        let count1 = await engine.fftSubscriberCount(for: inputID)
        XCTAssertEqual(count1, 1)

        await engine.unsubscribeFFT(id: subID)
        let count2 = await engine.fftSubscriberCount(for: inputID)
        XCTAssertEqual(count2, 0)
    }

    func testRemoveInputClearsProcessor() async {
        let engine = AudioAnalysisEngine()
        let config = AudioInputConfig(name: "RemoveTest", deviceUID: nil, channelIndex: 0)
        let inputID = config.id

        let _ = await engine.subscribeSPL(to: inputID, config: config)
        await engine.removeInput(inputID)
        let count = await engine.splSubscriberCount(for: inputID)
        XCTAssertEqual(count, 0)
    }
}
