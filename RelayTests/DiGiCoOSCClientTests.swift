import XCTest
@testable import Relay

final class DiGiCoOSCClientTests: XCTestCase {

    // MARK: - OSC packet helpers

    private func paddedCString(_ s: String) -> Data {
        var bytes = Array(s.utf8)
        bytes.append(0)
        while bytes.count % 4 != 0 { bytes.append(0) }
        return Data(bytes)
    }

    private func int32BE(_ val: Int32) -> Data {
        var be = val.bigEndian
        return Data(bytes: &be, count: 4)
    }

    private func float32BE(_ val: Float) -> Data {
        var be = val.bitPattern.bigEndian
        return Data(bytes: &be, count: 4)
    }

    private func makePacket(address: String, typeTags: String, args: Data) -> Data {
        var data = paddedCString(address)
        data += paddedCString("," + typeTags)
        data += args
        return data
    }

    private func makeStringPacket(address: String, value: String) -> Data {
        makePacket(address: address, typeTags: "s", args: paddedCString(value))
    }

    private func makeNoArgPacket(address: String) -> Data {
        paddedCString(address)
    }

    // MARK: - parseOSCResponse

    func testParseConsoleName() {
        let packet = makeStringPacket(address: "/Console/Name", value: "SD12")
        let result = DiGiCoOSCClient.parseOSCResponse(packet)
        XCTAssertEqual(result?.address, "/Console/Name")
        XCTAssertEqual(result?.value, "SD12")
    }

    func testParseInputChannelName() {
        let packet = makeStringPacket(address: "/Input_Channels/1/Channel_Input/name", value: "Kick")
        let result = DiGiCoOSCClient.parseOSCResponse(packet)
        XCTAssertEqual(result?.address, "/Input_Channels/1/Channel_Input/name")
        XCTAssertEqual(result?.value, "Kick")
    }

    func testParseAuxOutputName() {
        let packet = makeStringPacket(address: "/Aux_Outputs/3/Buss_Trim/name", value: "IEM L")
        let result = DiGiCoOSCClient.parseOSCResponse(packet)
        XCTAssertEqual(result?.address, "/Aux_Outputs/3/Buss_Trim/name")
        XCTAssertEqual(result?.value, "IEM L")
    }

    func testParseGroupOutputName() {
        let packet = makeStringPacket(address: "/Group_Outputs/2/Buss_Trim/name", value: "Drums")
        let result = DiGiCoOSCClient.parseOSCResponse(packet)
        XCTAssertEqual(result?.address, "/Group_Outputs/2/Buss_Trim/name")
        XCTAssertEqual(result?.value, "Drums")
    }

    func testParseMatrixOutputName() {
        let packet = makeStringPacket(address: "/Matrix_Outputs/1/Buss_Trim/name", value: "Room L")
        let result = DiGiCoOSCClient.parseOSCResponse(packet)
        XCTAssertEqual(result?.address, "/Matrix_Outputs/1/Buss_Trim/name")
        XCTAssertEqual(result?.value, "Room L")
    }

    func testParseControlGroupName() {
        let packet = makeStringPacket(address: "/Control_Groups/4/name", value: "Vocals")
        let result = DiGiCoOSCClient.parseOSCResponse(packet)
        XCTAssertEqual(result?.address, "/Control_Groups/4/name")
        XCTAssertEqual(result?.value, "Vocals")
    }

    func testParseSessionFilename() {
        let packet = makeStringPacket(address: "/Console/Session/Filename", value: "SundayMorning.session")
        let result = DiGiCoOSCClient.parseOSCResponse(packet)
        XCTAssertEqual(result?.address, "/Console/Session/Filename")
        XCTAssertEqual(result?.value, "SundayMorning.session")
    }

    func testParseEmptyStringArg() {
        let packet = makeStringPacket(address: "/Input_Channels/5/Channel_Input/name", value: "")
        let result = DiGiCoOSCClient.parseOSCResponse(packet)
        XCTAssertEqual(result?.address, "/Input_Channels/5/Channel_Input/name")
        XCTAssertEqual(result?.value, "")
    }

    func testParseNoArgPacketReturnsNil() {
        let packet = makeNoArgPacket(address: "/Console/Name/?")
        let result = DiGiCoOSCClient.parseOSCResponse(packet)
        XCTAssertNil(result)
    }

    func testParseEmptyDataReturnsNil() {
        let result = DiGiCoOSCClient.parseOSCResponse(Data())
        XCTAssertNil(result)
    }

    func testParseTruncatedPacketReturnsNil() {
        let result = DiGiCoOSCClient.parseOSCResponse(Data([0x2F, 0x41, 0x42]))
        XCTAssertNil(result)
    }

    func testParseFirstStringArgWhenMultipleArgs() {
        var args = int32BE(42)
        args += paddedCString("Hello")
        let packet = makePacket(address: "/test", typeTags: "is", args: args)
        let result = DiGiCoOSCClient.parseOSCResponse(packet)
        XCTAssertEqual(result?.value, "Hello")
    }

    // MARK: - parseOSCArguments (layout bank packets)

    func testParseLayoutBankArguments() {
        var args = paddedCString("Inputs A")
        args += paddedCString("L")
        args += int32BE(1)
        args += int32BE(0)
        args += paddedCString("Input_Channels")
        args += int32BE(1)
        args += paddedCString("Aux_Outputs")
        args += int32BE(8)

        let packet = makePacket(address: "/Layout/Layout/Banks",
                                typeTags: "ssiisisi",
                                args: args)

        let result = DiGiCoOSCClient.parseOSCArguments(packet)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.address, "/Layout/Layout/Banks")

        guard case .string(let name) = result?.args[0] else { return XCTFail("args[0] not string") }
        XCTAssertEqual(name, "Inputs A")

        guard case .string(let section) = result?.args[1] else { return XCTFail("args[1] not string") }
        XCTAssertEqual(section, "L")

        guard case .int32(let page) = result?.args[2] else { return XCTFail("args[2] not int32") }
        XCTAssertEqual(page, 1)

        guard case .int32(let layer) = result?.args[3] else { return XCTFail("args[3] not int32") }
        XCTAssertEqual(layer, 0)

        guard case .string(let stripType) = result?.args[4] else { return XCTFail("args[4] not string") }
        XCTAssertEqual(stripType, "Input_Channels")

        guard case .int32(let stripIdx) = result?.args[5] else { return XCTFail("args[5] not int32") }
        XCTAssertEqual(stripIdx, 1)

        guard case .string(let auxType) = result?.args[6] else { return XCTFail("args[6] not string") }
        XCTAssertEqual(auxType, "Aux_Outputs")

        guard case .int32(let auxIdx) = result?.args[7] else { return XCTFail("args[7] not int32") }
        XCTAssertEqual(auxIdx, 8)
    }

    func testParseLayoutBankWithFloatArg() {
        let args = float32BE(1.5)
        let packet = makePacket(address: "/test/float", typeTags: "f", args: args)
        let result = DiGiCoOSCClient.parseOSCArguments(packet)
        XCTAssertNotNil(result)
        guard case .float32(let val) = result?.args.first else { return XCTFail("not float") }
        XCTAssertEqual(val, 1.5, accuracy: 0.001)
    }
}
