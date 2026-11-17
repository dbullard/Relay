import XCTest
@testable import Relay

final class SharedValueWirelessUsageTests: XCTestCase {
    private let wl1Receiver = UUID()
    private let unusedReceiver = UUID()

    private func suggested(_ name: String, device: UUID, channel: Int = 1) -> SharedValue {
        SharedValue(name: name, binding: .shure(deviceID: device, channel: channel, field: .batteryPercent), origin: .suggested)
    }

    func testTokenNamesAreFound() {
        let names = SharedValueWirelessUsage.referencedNames(in: #"{"text":"Battery: #{mic3_111_wl_1_battery}%"}"#)
        XCTAssertTrue(names.contains("mic3_111_wl_1_battery"))
    }

    func testTokenWithOtherSpacingAndCaseIsFound() {
        let names = SharedValueWirelessUsage.referencedNames(in: "Level #{ MIC3 111 WL 1 Audio.value }")
        XCTAssertTrue(names.contains("mic3_111_wl_1_audio"))
    }

    func testSharedPrefixedTokenIsFound() {
        let names = SharedValueWirelessUsage.referencedNames(in: "{{shared:mic3_111_wl_1_rf}}")
        XCTAssertTrue(names.contains("mic3_111_wl_1_rf"))
    }

    func testOnlyReceiversWithReferencedSuggestedValuesAreUsed() {
        let values = [
            suggested("mic3_111_wl_1_battery", device: wl1Receiver),
            suggested("mic9_ch_1_battery", device: unusedReceiver),
        ]
        let names = SharedValueWirelessUsage.referencedNames(in: "#{mic3_111_wl_1_battery}")

        let devices = SharedValueWirelessUsage.shureDeviceIDs(values: values, referencedNames: names)

        XCTAssertEqual(devices, [wl1Receiver])
    }

    /// A longer name that starts with an unused value's name must not count as a use of it.
    func testPrefixOfAnotherNameIsNotAUse() {
        let values = [suggested("mic3_ch_1_rf", device: unusedReceiver)]
        let names = SharedValueWirelessUsage.referencedNames(in: "#{mic3_ch_1_rf_peak}")

        XCTAssertTrue(SharedValueWirelessUsage.shureDeviceIDs(values: values, referencedNames: names).isEmpty)
    }

    func testCustomValuesAlwaysCount() {
        let custom = SharedValue(name: "lead_vocal_battery", binding: .shure(deviceID: wl1Receiver, channel: 1, field: .batteryPercent))

        let devices = SharedValueWirelessUsage.shureDeviceIDs(values: [custom], referencedNames: [])

        XCTAssertEqual(devices, [wl1Receiver])
    }

    func testComputedExpressionsCountAsReferences() {
        let computed = SharedValue(name: "low_battery", binding: .computed(expression: "mic3_111_wl_1_battery < 20", payloadType: .boolean))
        let values = [suggested("mic3_111_wl_1_battery", device: wl1Receiver), computed]
        let text = SharedValueWirelessUsage.referenceText(tabs: [], universalGraph: nil, values: values)

        let devices = SharedValueWirelessUsage.shureDeviceIDs(values: values, referencedNames: SharedValueWirelessUsage.referencedNames(in: text))

        XCTAssertEqual(devices, [wl1Receiver])
    }

    func testSennheiserNeedsAUsedValue() {
        let value = SharedValue(name: "ewdx_ch_1_rf", binding: .sennheiser(deviceID: unusedReceiver, channel: 1, field: .rf), origin: .suggested)

        XCTAssertFalse(SharedValueWirelessUsage.needsSennheiser(values: [value], referencedNames: []))
        XCTAssertTrue(SharedValueWirelessUsage.needsSennheiser(values: [value], referencedNames: ["ewdx_ch_1_rf"]))
    }
}
