import XCTest
@testable import Relay

@MainActor
final class ProPresenterChangeDetectionTests: XCTestCase {
    func testNoChangeReturnsEmpty() {
        let snapshot = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-1", slideIndex: 0, slideLabel: "Verse 1",
            presentationName: "Sunday Service", arrangementName: "Default",
            activeMessageName: nil, activeMessageText: nil, timerStatesByName: [:]
        )

        let changes = ProPresenterService.detectChanges(before: snapshot, after: snapshot)

        XCTAssertTrue(changes.isEmpty)
    }

    func testSlideChangeDetected() {
        let before = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-1", slideIndex: 0, slideLabel: "Verse 1",
            presentationName: "Sunday Service", arrangementName: "Default",
            activeMessageName: nil, activeMessageText: nil, timerStatesByName: [:]
        )
        let after = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-2", slideIndex: 1, slideLabel: "Verse 2",
            presentationName: "Sunday Service", arrangementName: "Default",
            activeMessageName: nil, activeMessageText: nil, timerStatesByName: [:]
        )

        let changes = ProPresenterService.detectChanges(before: before, after: after)

        XCTAssertEqual(changes.count, 1)
        guard case .slideChanged(let label, let index) = changes.first else {
            return XCTFail("Expected .slideChanged, got \(String(describing: changes.first))")
        }
        XCTAssertEqual(label, "Verse 2")
        XCTAssertEqual(index, 1)
    }

    func testPresentationChangeDetected() {
        let before = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-1", slideIndex: 0, slideLabel: "Verse 1",
            presentationName: "Sunday Service", arrangementName: "Default",
            activeMessageName: nil, activeMessageText: nil, timerStatesByName: [:]
        )
        let after = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-1", slideIndex: 0, slideLabel: "Verse 1",
            presentationName: "Announcements", arrangementName: "Default",
            activeMessageName: nil, activeMessageText: nil, timerStatesByName: [:]
        )

        let changes = ProPresenterService.detectChanges(before: before, after: after)

        XCTAssertEqual(changes.count, 1)
        guard case .presentationChanged(let name) = changes.first else {
            return XCTFail("Expected .presentationChanged, got \(String(describing: changes.first))")
        }
        XCTAssertEqual(name, "Announcements")
    }

    func testMessageChangeDetected() {
        let before = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-1", slideIndex: 0, slideLabel: "Verse 1",
            presentationName: "Sunday Service", arrangementName: "Default",
            activeMessageName: nil, activeMessageText: nil, timerStatesByName: [:]
        )
        let after = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-1", slideIndex: 0, slideLabel: "Verse 1",
            presentationName: "Sunday Service", arrangementName: "Default",
            activeMessageName: "Running Long", activeMessageText: "We are running long today", timerStatesByName: [:]
        )

        let changes = ProPresenterService.detectChanges(before: before, after: after)

        XCTAssertEqual(changes.count, 1)
        guard case .messageChanged(let name, let text) = changes.first else {
            return XCTFail("Expected .messageChanged, got \(String(describing: changes.first))")
        }
        XCTAssertEqual(name, "Running Long")
        XCTAssertEqual(text, "We are running long today")
    }

    func testTimerChangeDetectedForSpecificTimerOnly() {
        let before = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-1", slideIndex: 0, slideLabel: "Verse 1",
            presentationName: "Sunday Service", arrangementName: "Default",
            activeMessageName: nil, activeMessageText: nil,
            timerStatesByName: ["Countdown": "running", "Service Timer": "running"]
        )
        let after = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-1", slideIndex: 0, slideLabel: "Verse 1",
            presentationName: "Sunday Service", arrangementName: "Default",
            activeMessageName: nil, activeMessageText: nil,
            timerStatesByName: ["Countdown": "stopped", "Service Timer": "running"]
        )

        let changes = ProPresenterService.detectChanges(before: before, after: after)

        XCTAssertEqual(changes.count, 1)
        guard case .timerChanged(let name, let value) = changes.first else {
            return XCTFail("Expected .timerChanged, got \(String(describing: changes.first))")
        }
        XCTAssertEqual(name, "Countdown")
        XCTAssertEqual(value, "stopped")
    }

    func testTimerTickingAloneDoesNotTriggerChange() {
        // Regression test: changeSnapshot(from:) must track only timer.state, not the live
        // countdown time string, so a running timer ticking down every poll doesn't fire
        // .timerChanged on nearly every single poll cycle.
        let before = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-1", slideIndex: 0, slideLabel: "Verse 1",
            presentationName: "Sunday Service", arrangementName: "Default",
            activeMessageName: nil, activeMessageText: nil,
            timerStatesByName: ["Countdown": "running"]
        )
        let after = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-1", slideIndex: 0, slideLabel: "Verse 1",
            presentationName: "Sunday Service", arrangementName: "Default",
            activeMessageName: nil, activeMessageText: nil,
            timerStatesByName: ["Countdown": "running"]
        )

        let changes = ProPresenterService.detectChanges(before: before, after: after)

        XCTAssertTrue(changes.isEmpty)
    }

    func testMultipleSimultaneousChangesAllDetected() {
        let before = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-1", slideIndex: 0, slideLabel: "Verse 1",
            presentationName: "Sunday Service", arrangementName: "Default",
            activeMessageName: nil, activeMessageText: nil, timerStatesByName: [:]
        )
        let after = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-9", slideIndex: 8, slideLabel: "Closing",
            presentationName: "Announcements", arrangementName: "Default",
            activeMessageName: nil, activeMessageText: nil, timerStatesByName: [:]
        )

        let changes = ProPresenterService.detectChanges(before: before, after: after)

        XCTAssertEqual(changes.count, 2)
    }

    func testActiveMessageGoingAwayIsDetected() {
        let before = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-1", slideIndex: 0, slideLabel: "Verse 1",
            presentationName: "Sunday Service", arrangementName: "Default",
            activeMessageName: "Running Long", activeMessageText: "We are running long today",
            timerStatesByName: [:]
        )
        let after = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-1", slideIndex: 0, slideLabel: "Verse 1",
            presentationName: "Sunday Service", arrangementName: "Default",
            activeMessageName: nil, activeMessageText: nil,
            timerStatesByName: [:]
        )

        let changes = ProPresenterService.detectChanges(before: before, after: after)

        XCTAssertEqual(changes.count, 1)
        guard case .messageChanged(let name, let text) = changes.first else {
            return XCTFail("Expected .messageChanged, got \(String(describing: changes.first))")
        }
        XCTAssertNil(name)
        XCTAssertNil(text)
    }

    func testTimerAddedIsDetected() {
        let before = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-1", slideIndex: 0, slideLabel: "Verse 1",
            presentationName: "Sunday Service", arrangementName: "Default",
            activeMessageName: nil, activeMessageText: nil,
            timerStatesByName: [:]
        )
        let after = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-1", slideIndex: 0, slideLabel: "Verse 1",
            presentationName: "Sunday Service", arrangementName: "Default",
            activeMessageName: nil, activeMessageText: nil,
            timerStatesByName: ["Countdown": "running"]
        )

        let changes = ProPresenterService.detectChanges(before: before, after: after)

        XCTAssertEqual(changes.count, 1)
        guard case .timerChanged(let name, let value) = changes.first else {
            return XCTFail("Expected .timerChanged, got \(String(describing: changes.first))")
        }
        XCTAssertEqual(name, "Countdown")
        XCTAssertEqual(value, "running")
    }

    func testTimerRemovedIsDetected() {
        let before = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-1", slideIndex: 0, slideLabel: "Verse 1",
            presentationName: "Sunday Service", arrangementName: "Default",
            activeMessageName: nil, activeMessageText: nil,
            timerStatesByName: ["Countdown": "running"]
        )
        let after = ProPresenterService.ChangeSnapshot(
            slideUUID: "slide-1", slideIndex: 0, slideLabel: "Verse 1",
            presentationName: "Sunday Service", arrangementName: "Default",
            activeMessageName: nil, activeMessageText: nil,
            timerStatesByName: [:]
        )

        let changes = ProPresenterService.detectChanges(before: before, after: after)

        XCTAssertEqual(changes.count, 1)
        guard case .timerChanged(let name, let value) = changes.first else {
            return XCTFail("Expected .timerChanged, got \(String(describing: changes.first))")
        }
        XCTAssertEqual(name, "Countdown")
        XCTAssertNil(value)
    }

    func testParseNumericTimerValuePlainInteger() {
        XCTAssertEqual(ProPresenterService.parseNumericTimerValue("300"), 300.0)
    }

    func testParseNumericTimerValuePlainDecimal() {
        XCTAssertEqual(ProPresenterService.parseNumericTimerValue("12.5"), 12.5)
    }

    func testParseNumericTimerValueNilInput() {
        XCTAssertNil(ProPresenterService.parseNumericTimerValue(nil))
    }

    func testParseNumericTimerValueColonFormattedIsNotParsed() {
        XCTAssertNil(ProPresenterService.parseNumericTimerValue("00:05:00"))
    }

    func testParseNumericTimerValueEmptyStringIsNil() {
        XCTAssertNil(ProPresenterService.parseNumericTimerValue(""))
    }
}
