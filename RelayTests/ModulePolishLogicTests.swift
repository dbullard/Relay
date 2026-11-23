// RelayTests/ModulePolishLogicTests.swift
import XCTest
@testable import Relay

/// Countdown overrun: past zero the countdown keeps counting up from the same end date.
@MainActor
final class TimeModuleCountdownOverrunTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 2_000_000)

    func testOverrunIsZeroUntilTheEndDate() {
        let end = start.addingTimeInterval(60)
        XCTAssertEqual(TimeModuleClock.countdownOverrun(endDate: end, now: start), 0)
        XCTAssertEqual(TimeModuleClock.countdownOverrun(endDate: end, now: end.addingTimeInterval(-0.1)), 0)
        XCTAssertEqual(TimeModuleClock.countdownOverrun(endDate: end, now: end), 0)
    }

    func testOverrunCountsWholeSecondsPastTheEnd() {
        let end = start.addingTimeInterval(60)
        XCTAssertEqual(TimeModuleClock.countdownOverrun(endDate: end, now: end.addingTimeInterval(0.9)), 0)
        XCTAssertEqual(TimeModuleClock.countdownOverrun(endDate: end, now: end.addingTimeInterval(1.0)), 1)
        XCTAssertEqual(TimeModuleClock.countdownOverrun(endDate: end, now: end.addingTimeInterval(125.4)), 125)
    }

    func testDisplayNeverSkipsOrRepeatsASecondAcrossZero() {
        // Remaining rounds up and overrun rounds down, so each wall-clock second shows
        // exactly one value: ... 0:01, 0:00 (the instant of zero), +0:00, +0:01 ...
        let end = start.addingTimeInterval(3)
        var shown: [String] = []
        var t = start.addingTimeInterval(0.5)
        while t < end.addingTimeInterval(3) {
            let remaining = TimeModuleClock.countdownRemaining(endDate: end, now: t)
            let overrun = TimeModuleClock.countdownOverrun(endDate: end, now: t)
            shown.append(remaining > 0 ? "\(remaining)" : "+\(overrun)")
            t = t.addingTimeInterval(1)
        }
        XCTAssertEqual(shown, ["3", "2", "1", "+0", "+1", "+2"])
    }

    func testResumingAPausedOverrunContinuesFromThePausedValue() {
        // Paused at OVER +0:42; resumed later, it carries on from +0:42, not from zero or 5:00.
        let resumeAt = start.addingTimeInterval(1_000)
        let end = TimeModuleClock.countdownEndDate(resumingAt: resumeAt, remainingSeconds: 0, overrunSeconds: 42)
        XCTAssertEqual(TimeModuleClock.countdownRemaining(endDate: end, now: resumeAt), 0)
        XCTAssertEqual(TimeModuleClock.countdownOverrun(endDate: end, now: resumeAt), 42)
        XCTAssertEqual(TimeModuleClock.countdownOverrun(endDate: end, now: resumeAt.addingTimeInterval(8.3)), 50)
    }

    func testResumingBeforeZeroAnchorsAheadByTheTimeLeft() {
        let end = TimeModuleClock.countdownEndDate(resumingAt: start, remainingSeconds: 300, overrunSeconds: 0)
        XCTAssertEqual(TimeModuleClock.countdownRemaining(endDate: end, now: start), 300)
        XCTAssertEqual(TimeModuleClock.countdownOverrun(endDate: end, now: start), 0)
    }

    func testOverrunCatchesUpAfterMissedTicks() {
        let end = start.addingTimeInterval(10)
        XCTAssertEqual(TimeModuleClock.countdownOverrun(endDate: end, now: end.addingTimeInterval(600.2)), 600)
    }
}

/// Button tile: why it can't be pressed, and spoken names for icon-only tiles.
@MainActor
final class ButtonModuleAvailabilityTests: XCTestCase {
    private func reason(
        _ availability: ButtonModuleAvailability,
        live: Bool = true,
        allowsWhileEditing: Bool = false,
        active: Bool = false,
        running: Bool = false,
        coolingDown: Bool = false
    ) -> String? {
        availability.unavailableReason(
            isLiveMode: live,
            allowsTriggerWhileEditing: allowsWhileEditing,
            isStateActive: active,
            isRunning: running,
            isCoolingDown: coolingDown
        )
    }

    func testLiveOnlyButtonExplainsItselfWhileEditing() {
        let availability = ButtonModuleAvailability(liveModeRequirement: .liveOnly)
        XCTAssertEqual(reason(availability, live: false), "Live Mode only")
        XCTAssertNil(reason(availability, live: false, allowsWhileEditing: true))
        XCTAssertNil(reason(availability, live: true))
    }

    func testEditOnlyButtonIsUnavailableInLiveMode() {
        let availability = ButtonModuleAvailability(liveModeRequirement: .editOnly)
        XCTAssertEqual(reason(availability, live: true), "Edit mode only")
        XCTAssertNil(reason(availability, live: false))
    }

    func testStateRequirements() {
        XCTAssertEqual(reason(ButtonModuleAvailability(stateRequirement: .active), active: false), "Waiting for active state")
        XCTAssertNil(reason(ButtonModuleAvailability(stateRequirement: .active), active: true))
        XCTAssertEqual(reason(ButtonModuleAvailability(stateRequirement: .inactive), active: true), "Unavailable while active")
    }

    func testRunningAndCooldownOnlyBlockWhenConfigured() {
        XCTAssertEqual(reason(ButtonModuleAvailability(), running: true), "Running")
        XCTAssertEqual(reason(ButtonModuleAvailability(), coolingDown: true), "Cooling down")
        let relaxed = ButtonModuleAvailability(disablesWhileRunning: false, disablesDuringCooldown: false)
        XCTAssertNil(reason(relaxed, running: true, coolingDown: true))
    }

    func testSpokenSymbolNameDropsFillAndDots() {
        XCTAssertEqual(ButtonItemView.spokenSymbolName("play.circle.fill"), "play circle")
        XCTAssertEqual(ButtonItemView.spokenSymbolName("stop.fill"), "stop")
        XCTAssertEqual(ButtonItemView.spokenSymbolName("mic"), "mic")
    }

    func testFirstLineOfMultiLineError() {
        XCTAssertEqual(ButtonItemView.firstLine(of: "  OSC wasn't sent\nMIDI wasn't sent "), "OSC wasn't sent")
        XCTAssertEqual(ButtonItemView.firstLine(of: "Single"), "Single")
    }
}

/// DAW Record needs a second tap within the window to start; stopping is immediate.
@MainActor
final class DAWRecordArmGateTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 3_000_000)

    func testFirstTapArmsAndSecondTapSends() {
        var gate = DAWRecordArmGate()
        XCTAssertFalse(gate.registerTap(at: t0, isRecording: false))
        XCTAssertTrue(gate.isArmed(at: t0.addingTimeInterval(1)))
        XCTAssertTrue(gate.registerTap(at: t0.addingTimeInterval(1.5), isRecording: false))
        XCTAssertFalse(gate.isArmed(at: t0.addingTimeInterval(1.6)))
    }

    func testArmingExpiresAfterTheWindow() {
        var gate = DAWRecordArmGate()
        _ = gate.registerTap(at: t0, isRecording: false)
        XCTAssertFalse(gate.isArmed(at: t0.addingTimeInterval(DAWRecordArmGate.window)))
        // A late second tap just arms again.
        XCTAssertFalse(gate.registerTap(at: t0.addingTimeInterval(DAWRecordArmGate.window + 0.1), isRecording: false))
    }

    func testTapWhileRecordingSendsImmediately() {
        var gate = DAWRecordArmGate()
        XCTAssertTrue(gate.registerTap(at: t0, isRecording: true))
        XCTAssertNil(gate.armedUntil)
    }

    func testResetDisarms() {
        var gate = DAWRecordArmGate()
        _ = gate.registerTap(at: t0, isRecording: false)
        gate.reset()
        XCTAssertFalse(gate.isArmed(at: t0))
    }
}

/// Transcript "Undo Clear" puts cleared lines back in time order without duplicates.
@MainActor
final class LiveTranscriptionUndoClearTests: XCTestCase {
    private let source = UUID()

    private func entry(_ text: String, at seconds: TimeInterval, id: UUID = UUID()) -> TranscriptEntry {
        TranscriptEntry(
            id: id,
            timestamp: Date(timeIntervalSinceReferenceDate: seconds),
            sourceId: source,
            sourceDisplayName: "Mic",
            rawText: text,
            displayText: text,
            isFinal: true,
            confidence: nil
        )
    }

    func testRestoresClearedEntriesAheadOfNewOnes() {
        let cleared = [entry("one", at: 1), entry("two", at: 2)]
        let current = [entry("three", at: 3)]
        let restored = LiveTranscriptionController.entriesRestoringClear(cleared, into: current)
        XCTAssertEqual(restored.map(\.rawText), ["one", "two", "three"])
    }

    func testDoesNotDuplicateAnEntryThatIsStillPresent() {
        let sharedID = UUID()
        let cleared = [entry("one", at: 1), entry("partial", at: 2, id: sharedID)]
        let current = [entry("partial, now final", at: 2, id: sharedID)]
        let restored = LiveTranscriptionController.entriesRestoringClear(cleared, into: current)
        XCTAssertEqual(restored.map(\.rawText), ["one", "partial, now final"])
    }
}

/// PCO Team Assignments list: readable scale floor and "+N more" count.
@MainActor
final class PCOTeamAssignmentsOverflowTests: XCTestCase {
    func testScaleShrinksToFitButNotBelowTheFloor() {
        XCTAssertEqual(PCOTeamAssignmentsOverflow.scale(availableHeight: 400, contentHeight: 300), 1)
        XCTAssertEqual(PCOTeamAssignmentsOverflow.scale(availableHeight: 360, contentHeight: 400), 0.9, accuracy: 0.0001)
        XCTAssertEqual(PCOTeamAssignmentsOverflow.scale(availableHeight: 100, contentHeight: 400), PCOTeamAssignmentsOverflow.minimumScale)
    }

    func testOverflowsOnlyWhenTheFloorScaleStillDoesNotFit() {
        XCTAssertFalse(PCOTeamAssignmentsOverflow.overflows(availableHeight: 300, contentHeight: 400))
        XCTAssertTrue(PCOTeamAssignmentsOverflow.overflows(availableHeight: 200, contentHeight: 400))
        XCTAssertFalse(PCOTeamAssignmentsOverflow.overflows(availableHeight: 0, contentHeight: 400))
    }

    func testHiddenRowCountIncludesRowsUnderTheFooter() {
        // Rows end every 50pt; at 0.75 scale that's every 37.5pt; 150pt available, 24pt footer.
        let bottoms: [CGFloat] = [50, 100, 150, 200, 250, 300]
        let hidden = PCOTeamAssignmentsOverflow.hiddenRowCount(
            rowBottoms: bottoms, scale: 0.75, availableHeight: 150, footerHeight: 24
        )
        // Visible limit 126pt: rows ending at 37.5, 75, 112.5 fit; 150, 187.5, 225 don't.
        XCTAssertEqual(hidden, 3)
    }

    func testNoFooterWhenEverythingFits() {
        let hidden = PCOTeamAssignmentsOverflow.hiddenRowCount(
            rowBottoms: [50, 100], scale: 1, availableHeight: 120, footerHeight: 24
        )
        XCTAssertEqual(hidden, 0)
    }

    func testClearAllCountsRoleRulesAndPeopleWithAssignments() {
        let extras = PCOTeamAssignmentsExtras(
            byKey: [
                "a": PCOAssignmentMetadata(personID: "1", assignments: [PCOEquipmentAssignment(assignmentTypeID: "mic")]),
                "b": PCOAssignmentMetadata(personID: "2", assignments: [])
            ],
            roleRulesByPosition: [:]
        )
        let counts = extras.clearableAssignmentCounts
        XCTAssertEqual(counts.roleRules, 0)
        XCTAssertEqual(counts.people, 1)
        XCTAssertEqual(counts.total, 1)
    }
}

/// SPL limit level carries a word and symbol, not only a colour.
@MainActor
final class DbReaderLimitLevelTests: XCTestCase {
    func testNoLevelWhenLimitColouringIsOff() {
        XCTAssertNil(DbReaderLimitLevel.level(for: 120, model: DbReaderModuleModel(limitColorEnabled: false)))
    }

    func testThresholds() {
        let model = DbReaderModuleModel(limitColorEnabled: true, limitWarningDb: 90, limitAlertDb: 100)
        XCTAssertEqual(DbReaderLimitLevel.level(for: 80, model: model), .normal)
        XCTAssertEqual(DbReaderLimitLevel.level(for: 90, model: model), .warning)
        XCTAssertEqual(DbReaderLimitLevel.level(for: 100.5, model: model), .alert)
        XCTAssertEqual(DbReaderLimitLevel.alert.title(isCA: false), "Over Limit")
    }
}
