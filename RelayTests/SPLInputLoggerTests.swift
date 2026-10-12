import XCTest
@testable import Relay

final class SPLInputLoggerTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInit_createsFileWithHeader() throws {
        let input = AudioInputConfig(name: "TestMic", channelIndex: 0, calibrationOffsetDb: 6.0)
        let session = UUID()
        let logger = try XCTUnwrap(
            SPLInputLogger(input: input, sessionId: session,
                           sessionStart: Date(), folderURL: tempDir, bookmarkData: nil)
        )
        logger.close()

        let files = try FileManager.default.contentsOfDirectory(at: tempDir,
                     includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        let content = try String(contentsOf: files[0], encoding: .utf8)
        XCTAssertTrue(content.contains("# SPL Input Log"))
        XCTAssertTrue(content.contains("timestamp_iso,spl,peak,raw_dbfs"))
        XCTAssertTrue(content.contains("# Calibration Offset dB: 6.00"))
    }

    func testAppend_writesOneLinePerCall() throws {
        let input = AudioInputConfig(name: "AppendMic", channelIndex: 0, calibrationOffsetDb: 0)
        let logger = try XCTUnwrap(
            SPLInputLogger(input: input, sessionId: UUID(),
                           sessionStart: Date(), folderURL: tempDir, bookmarkData: nil)
        )

        let payload = SPLPayload(
            aFast: -20, aSlow: -21, cFast: -18, cSlow: -19,
            zFast: -17, zSlow: -18, caFast: -20, caSlow: -21,
            rawDbFS: -22, rawPeakDbFS: -20,
            aInstantPower: 0, cInstantPower: 0, zInstantPower: 0,
            estimatedFrequencyHz: 440,
            clippingWarning: false, headroomDb: 2, noiseFloorDbFS: -60,
            sampleRate: 48000, timestamp: Date(), isStale: false
        )

        logger.append(payload: payload, calibrationOffsetDb: 0,
                      aSlowMax: -19, rawPeakDbfsMax: -18)
        logger.append(payload: payload, calibrationOffsetDb: 0,
                      aSlowMax: -19, rawPeakDbfsMax: -18)
        logger.close()

        let files = try FileManager.default.contentsOfDirectory(at: tempDir,
                     includingPropertiesForKeys: nil)
        let content = try String(contentsOf: files[0], encoding: .utf8)
        // Header lines (starting with #) + column header line + 2 data lines
        let dataLines = content.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("#") && !$0.hasPrefix("timestamp") && !$0.isEmpty }
        XCTAssertEqual(dataLines.count, 2)
    }

    func testFilename_containsInputName() throws {
        let input = AudioInputConfig(name: "Stage Left", channelIndex: 1, calibrationOffsetDb: 0)
        let session = UUID()
        let logger = try XCTUnwrap(
            SPLInputLogger(input: input, sessionId: session,
                           sessionStart: Date(), folderURL: tempDir, bookmarkData: nil)
        )
        logger.close()

        let files = try FileManager.default.contentsOfDirectory(at: tempDir,
                     includingPropertiesForKeys: nil)
        XCTAssertTrue(files[0].lastPathComponent.contains("Stage-Left"))
    }
}
