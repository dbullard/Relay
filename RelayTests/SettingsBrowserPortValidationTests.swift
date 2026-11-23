import XCTest
@testable import Relay

final class SettingsBrowserPortValidationTests: XCTestCase {
    func testAcceptsPortsInRange() {
        XCTAssertEqual(try BrowserPortValidation.validate("1024").get(), 1024)
        XCTAssertEqual(try BrowserPortValidation.validate("38475").get(), 38475)
        XCTAssertEqual(try BrowserPortValidation.validate("65535").get(), 65535)
        XCTAssertEqual(try BrowserPortValidation.validate("  8080 \n").get(), 8080)
    }

    func testPartialTypingIsRejectedNotClamped() {
        // "5" is what you have after the first keystroke of "5000"; it must not become 1024.
        XCTAssertEqual(BrowserPortValidation.validate("5"), .failure(.outOfRange))
        XCTAssertEqual(BrowserPortValidation.validate("1023"), .failure(.outOfRange))
        XCTAssertEqual(BrowserPortValidation.validate("65536"), .failure(.outOfRange))
        XCTAssertEqual(BrowserPortValidation.validate("99999999999999999999999"), .failure(.outOfRange))
    }

    func testRejectsEmptyAndNonDigits() {
        XCTAssertEqual(BrowserPortValidation.validate(""), .failure(.empty))
        XCTAssertEqual(BrowserPortValidation.validate("   "), .failure(.empty))
        XCTAssertEqual(BrowserPortValidation.validate("80a0"), .failure(.notANumber))
        XCTAssertEqual(BrowserPortValidation.validate("-8080"), .failure(.notANumber))
        XCTAssertEqual(BrowserPortValidation.validate("8,080"), .failure(.notANumber))
        XCTAssertEqual(BrowserPortValidation.validate("٨٠٨٠"), .failure(.notANumber))
    }

    func testErrorMessagesMentionTheRange() {
        for error in [BrowserPortValidation.ValidationError.empty, .notANumber, .outOfRange] {
            XCTAssertTrue(error.message.contains("1024"), error.message)
            XCTAssertTrue(error.message.contains("65535"), error.message)
        }
    }
}

final class SharedValueReferenceCounterTests: XCTestCase {
    func testMatchesPlainAndSharedPrefixedTokens() {
        XCTAssertTrue(SharedValueReferenceCounter.expression("#{lead_mic} + 1", references: "lead_mic"))
        XCTAssertTrue(SharedValueReferenceCounter.expression("x #{shared:lead_mic}", references: "lead_mic"))
        XCTAssertTrue(SharedValueReferenceCounter.expression("#{Shared:Lead Mic}", references: "lead_mic"))
    }

    func testDoesNotMatchOtherNamesOrPrefixes() {
        XCTAssertFalse(SharedValueReferenceCounter.expression("#{lead_mic_2}", references: "lead_mic"))
        XCTAssertFalse(SharedValueReferenceCounter.expression("lead_mic", references: "lead_mic"))
        XCTAssertFalse(SharedValueReferenceCounter.expression("#{lead_mic", references: "lead_mic"))
        XCTAssertFalse(SharedValueReferenceCounter.expression("#{a} #{b}", references: ""))
    }

    func testFindsLaterTokens() {
        XCTAssertTrue(SharedValueReferenceCounter.expression("#{a} and #{b} and #{c}", references: "c"))
    }

    func testCountsOnlyComputedValues() {
        let values = [
            SharedValue(name: "total", binding: .computed(expression: "#{a} + #{b}", payloadType: .number)),
            SharedValue(name: "label", binding: .computed(expression: "Score: #{shared:a}", payloadType: .text)),
            SharedValue(name: "other", binding: .computed(expression: "#{b}", payloadType: .number)),
            SharedValue(name: "a_manual", binding: .manual),
        ]
        XCTAssertEqual(SharedValueReferenceCounter.computedReferenceCount(to: "a", in: values), 2)
        XCTAssertEqual(SharedValueReferenceCounter.computedReferenceCount(to: "b", in: values), 2)
        XCTAssertEqual(SharedValueReferenceCounter.computedReferenceCount(to: "missing", in: values), 0)
    }
}
