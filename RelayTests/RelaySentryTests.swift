import XCTest
@testable import Relay
#if canImport(Sentry)
import Sentry

@MainActor
final class RelaySentryTests: XCTestCase {
    private func crashEvent() -> Event {
        let event = Event(level: .fatal)
        let exception = Exception(value: "private detail", type: "EXC_BAD_ACCESS")
        let mechanism = Mechanism(type: "mach")
        mechanism.handled = false
        exception.mechanism = mechanism
        event.exceptions = [exception]
        return event
    }

    func test_optionsCollectCrashesWithoutBreadcrumbsOrHangs() {
        let options = Options()
        RelaySentry.configureReportingOptions(options, crashReportingEnabled: true)
        XCTAssertTrue(options.enableCrashHandler)
        XCTAssertFalse(options.enableAppHangTracking)
        XCTAssertFalse(options.enableAutoBreadcrumbTracking)
        XCTAssertFalse(options.enableNetworkBreadcrumbs)
        XCTAssertFalse(options.enableCaptureFailedRequests)
        XCTAssertFalse(options.enableAutoPerformanceTracing)
        XCTAssertFalse(options.enableLogs)
        XCTAssertFalse(options.attachStacktrace)
        XCTAssertEqual(options.maxBreadcrumbs, 0)
        XCTAssertNil(options.beforeBreadcrumb?(Breadcrumb()))
    }

    func test_manualOnlyStartupDisablesCrashCapture() {
        let options = Options()
        RelaySentry.configureReportingOptions(options, crashReportingEnabled: false)
        XCTAssertFalse(options.enableCrashHandler)
        XCTAssertFalse(options.enableAppHangTracking)
    }

    func test_nativeFatalCrashWithoutHandledFlagIsRetained() {
        let event = crashEvent()
        event.exceptions?.first?.mechanism?.handled = nil
        XCTAssertNotNil(RelaySentry.minimizeAutomaticEvent(event))
    }

    func test_beforeSendDropsHandledErrorsEvenWithStacktrace() {
        let event = Event(level: .error)
        let exception = Exception(value: "connection failed", type: "NetworkError")
        let mechanism = Mechanism(type: "NSError")
        mechanism.handled = true
        exception.mechanism = mechanism
        exception.stacktrace = SentryStacktrace(frames: [], registers: [:])
        event.exceptions = [exception]
        XCTAssertNil(RelaySentry.minimizeAutomaticEvent(event))
    }

    func test_beforeSendDropsMessagesWithThreadsAndTransactions() {
        let message = Event(level: .error)
        message.message = SentryMessage(formatted: "connection_failed")
        message.stacktrace = SentryStacktrace(frames: [], registers: [:])
        XCTAssertNil(RelaySentry.minimizeAutomaticEvent(message))
        let transaction = crashEvent()
        transaction.type = "transaction"
        XCTAssertNil(RelaySentry.minimizeAutomaticEvent(transaction))
    }

    func test_crashKeepsStackAndUnhandledClassificationButRemovesBreadcrumbsAndRuntimeContext() throws {
        let event = crashEvent()
        let stack = SentryStacktrace(frames: [], registers: ["x0": "secret"])
        event.exceptions?.first?.stacktrace = stack
        event.breadcrumbs = [Breadcrumb(level: .info, category: "wireless.shure")]
        event.context = ["relay_runtime": ["runtime_tab_count": 3]]
        event.message = SentryMessage(formatted: "timeout")
        event.user = User(userId: "private-id")
        event.tags = ["host": "10.0.1.55"]
        event.fingerprint = ["private-device"]
        event.serverName = "private-host"
        event.extra = ["host": "10.0.1.55"]
        let result = try XCTUnwrap(RelaySentry.minimizeAutomaticEvent(event))
        XCTAssertEqual(result.breadcrumbs?.count ?? 0, 0)
        XCTAssertEqual(result.context?.count ?? 0, 0)
        XCTAssertNil(result.message)
        XCTAssertNil(result.user)
        XCTAssertNil(result.serverName)
        XCTAssertNil(result.fingerprint)
        XCTAssertEqual(result.tags?.count ?? 0, 0)
        XCTAssertEqual(result.extra?.count ?? 0, 0)
        XCTAssertNil(result.exceptions?.first?.value)
        XCTAssertTrue(result.exceptions?.first?.stacktrace === stack)
        XCTAssertEqual(stack.registers, [:])
        XCTAssertEqual(result.exceptions?.first?.mechanism?.handled, false)
    }

    func test_userFeedbackContainsOnlyUserSuppliedText() throws {
        let feedback = try RelaySentry.makeFeedback(message: "  The timer stopped  ", diagnostics: nil)
        let payload = feedback.serialize()
        XCTAssertEqual(payload["message"] as? String, "The timer stopped")
        XCTAssertNil(payload["name"])
        XCTAssertNil(payload["contact_email"])
    }

    func test_diagnosticAttachmentContainsOnlyExplicitlySelectedSummary() throws {
        XCTAssertNil(RelaySentry.makeDiagnosticAttachment(nil))
        let attachment = try XCTUnwrap(RelaySentry.makeDiagnosticAttachment("Reviewed log contents"))
        XCTAssertEqual(attachment.filename, "relay-diagnostics.txt")
        XCTAssertEqual(attachment.data, Data("Reviewed log contents".utf8))
    }

    func test_emptyFeedbackCannotBeSubmitted() {
        XCTAssertThrowsError(try RelaySentry.makeFeedback(message: " \n ", diagnostics: "logs"))
    }
}
#endif
