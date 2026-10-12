import XCTest
@testable import Relay
#if canImport(Sentry)
import Sentry
#endif

@MainActor
final class UsageDiagnosticsPreferencesTests: XCTestCase {
    func test_newPreferences_defaultToDisabledAndRequirePrompt() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = UsageDiagnosticsPreferences(defaults: defaults)

        XCTAssertFalse(preferences.isEnabled)
        XCTAssertTrue(preferences.shouldPresentPrompt)
    }

    func test_recordingNotNow_marksPromptSeenButKeepsDiagnosticsDisabled() {
        let preferences = UsageDiagnosticsPreferences(defaults: UserDefaults(suiteName: #function)!)
        preferences.recordPromptChoice(enabled: false)

        XCTAssertFalse(preferences.isEnabled)
        XCTAssertFalse(preferences.shouldPresentPrompt)
    }

    func test_promptIsNotShownAgainAfterShareChoice() {
        let preferences = UsageDiagnosticsPreferences(defaults: UserDefaults(suiteName: #function)!)
        preferences.recordPromptChoice(enabled: true)

        XCTAssertFalse(preferences.shouldPresentPrompt)
        XCTAssertTrue(preferences.isEnabled)
    }

    func test_manualFeedbackCannotTransmitFromDebugBuild() {
        XCTAssertThrowsError(try RelaySentry.uploadFeedback(message: "A user report", diagnostics: nil)) { error in
            #if canImport(Sentry)
            guard case RelaySentry.UploadError.dsnNotConfigured = error else {
                return XCTFail("Expected an unconfigured Debug SDK, got \(error)")
            }
            #else
            guard case RelaySentry.UploadError.sdkNotAvailable = error else {
                return XCTFail("Expected unavailable SDK, got \(error)")
            }
            #endif
        }
    }

    #if canImport(Sentry)
    func test_automaticEventRedactsExceptionValueWhileRetainingTypeAndStacktrace() {
        let exception = Exception(value: "user@example.com token=secret", type: "NetworkError")
        let stacktrace = SentryStacktrace(frames: [], registers: [:])
        let eventStacktrace = SentryStacktrace(frames: [], registers: ["x0": "token=secret"])
        exception.stacktrace = stacktrace
        exception.module = "Relay"
        let event = Event(level: .fatal)
        event.exceptions = [exception]
        event.stacktrace = eventStacktrace

        let minimized = RelaySentry.minimizeAutomaticEvent(event)

        XCTAssertNil(minimized?.exceptions?.first?.value)
        XCTAssertEqual(minimized?.exceptions?.first?.type, "NetworkError")
        XCTAssertNil(minimized?.exceptions?.first?.module)
        XCTAssertTrue(minimized?.exceptions?.first?.stacktrace === stacktrace)
        XCTAssertEqual(minimized?.stacktrace?.registers, [:])
    }
    #endif
}
