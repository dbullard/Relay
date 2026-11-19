import SwiftUI
import XCTest
@testable import Relay

/// Drives recognizer results through the Live Transcription controller's real path (prefix
/// stripping, line segmenting, duplicate suppression) and checks that every word heard shows
/// up once. A repeated line also re-fires every word trigger in it.
@MainActor
final class LiveTranscriptionDuplicateLineTests: XCTestCase {
    private var controller: LiveTranscriptionController!
    private let channel = TranscriptChannel(
        id: UUID(),
        displayName: "COMMS",
        color: CodableColor(.white),
        deviceUID: nil,
        channelIndex: 0
    )

    override func setUp() {
        super.setUp()
        controller = LiveTranscriptionController(
            tabId: UUID(),
            tileId: UUID(),
            settings: LiveTranscriptionModuleModel(),
            tabSnapshot: DashboardTab(name: "Test", tiles: []),
            transcriptionLocaleIdentifier: nil
        )
    }

    override func tearDown() {
        controller = nil
        super.tearDown()
    }

    private func lines(_ steps: [LiveTranscriptionController.ReplayStep]) -> [String] {
        controller.replayForTesting(steps, channel: channel)
            .filter(\.isFinal)
            .map(\.displayText)
    }

    /// The 2026-11-18 comms transcript: one recognizer task stayed open from 18:40 to 18:54
    /// while the board was muted, and three lines re-sent the whole task.
    func testCommsTranscriptShowsEachWordOnce() {
        let base = "Hey Davis hey Davis hey David we got it Bob had it muted on the board here"
        let result = lines([
            .result("Hey Davis", at: 0), .silence(at: 1),
            .result("Hey Davis hey Davis", at: 3), .silence(at: 4),
            .result("Hey Davis hey Davis hey David", at: 819), .silence(at: 820),
            .result(base, at: 833), .silence(at: 834),
            .result("\(base) earlier", at: 839), .silence(at: 840),
            .result("\(base) sorry for Bob's fault", at: 841), .silence(at: 842),
            .result("\(base) sorry for Bob's fault it's bob", at: 843), .silence(at: 843.9),
            .result("\(base) sorry for Bob's fault Bob's fault", at: 845), .silence(at: 846),
        ])
        XCTAssertEqual(result, [
            "Hey Davis",
            "hey Davis",
            "hey David",
            "we got it Bob had it muted on the board here",
            "earlier",
            "sorry for Bob's fault",
            "it's bob",
            "Bob's fault",
        ])
    }

    func testGrowingResultsBecomeOneLine() {
        XCTAssertEqual(
            lines([
                .result("stand", at: 0),
                .result("stand by", at: 0.3),
                .result("stand by for walk in", at: 0.6),
                .silence(at: 1.6),
            ]),
            ["stand by for walk in"]
        )
    }

    func testFinalResultAfterTheLineWasShownAddsNothing() {
        // The recognizer often confirms a line seconds after silence already showed it.
        XCTAssertEqual(
            lines([
                .result("stand by for walk in", at: 0), .silence(at: 1),
                .result("stand by for walk in", isFinal: true, at: 3),
            ]),
            ["stand by for walk in"]
        )
    }

    func testFinalResultWithNewWordsAddsOnlyThem() {
        XCTAssertEqual(
            lines([
                .result("stand by for walk in", at: 0), .silence(at: 1),
                .result("stand by for walk in music", isFinal: true, at: 3),
            ]),
            ["stand by for walk in", "music"]
        )
    }

    func testRepeatedIdenticalResultsAfterTheLineAddNothing() {
        XCTAssertEqual(
            lines([
                .result("we're clear", at: 0), .silence(at: 1),
                .result("we're clear", at: 3), .silence(at: 4),
                .result("we're clear", at: 6), .silence(at: 7),
            ]),
            ["we're clear"]
        )
    }

    func testDroppedWordDoesNotRepeatTheLine() {
        XCTAssertEqual(
            lines([
                .result("we got it Bob had it", at: 0), .silence(at: 1),
                .result("we got it had it", at: 3), .silence(at: 4),
                .result("we got it had it on the board", at: 6), .silence(at: 7),
            ]),
            ["we got it Bob had it", "on the board"]
        )
    }

    func testNextRecognizerTaskAfterAFinalIsShown() {
        XCTAssertEqual(
            lines([
                .result("stand by", at: 0),
                .result("stand by", isFinal: true, at: 0.5),
                .result("go", at: 3), .silence(at: 4),
            ]),
            ["stand by", "go"]
        )
    }

    func testLongQuietTaskNeverRepeatsOlderLines() {
        var task = ""
        var steps: [LiveTranscriptionController.ReplayStep] = []
        let calls = ["mic check one", "mic check two", "copy that", "stand by", "go cue three"]
        for (index, call) in calls.enumerated() {
            task = task.isEmpty ? call : "\(task) \(call)"
            let time = Double(index) * 60
            steps += [.result(task, at: time), .silence(at: time + 1)]
        }
        XCTAssertEqual(lines(steps), calls)
    }
}
