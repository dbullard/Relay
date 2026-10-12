import XCTest
@testable import Relay

@MainActor
final class DbReaderTests: XCTestCase {

    func testAveragedValuesRollingWindow() {
        // Samples 1 second apart, SPL values 10, 20, 30, 40, 50
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        let samples = (0..<5).map { i in
            DbSample(
                id: UUID(),
                timestamp: now.addingTimeInterval(Double(i)),
                graphTimestamp: now.addingTimeInterval(Double(i)).timeIntervalSinceReferenceDate,
                spl: Double(i + 1) * 10,
                peak: 0,
                rawDbFS: 0,
                rawPeakDbFS: 0
            )
        }

        // 2-second window
        let averaged = DbReaderController.computeAveragedValues(samples: samples, windowSeconds: 2.0)

        XCTAssertEqual(averaged.count, 5)
        XCTAssertEqual(averaged[0], 10.0, accuracy: 0.001)   // only sample[0] = 10
        XCTAssertEqual(averaged[1], 15.0, accuracy: 0.001)   // [10,20]/2 = 15
        // samples are 1s apart; 2s window from sample[2] (t=1002) includes t>=1000: [10,20,30]
        XCTAssertEqual(averaged[2], 20.0, accuracy: 0.001)   // [10,20,30]/3 = 20
        // 2s window from sample[3] (t=1003) includes t>=1001: [20,30,40]
        XCTAssertEqual(averaged[3], 30.0, accuracy: 0.001)
        // 2s window from sample[4] (t=1004) includes t>=1002: [30,40,50]
        XCTAssertEqual(averaged[4], 40.0, accuracy: 0.001)
    }

    func testModelDecodesWithMissingNewFields() throws {
        // JSON from an older saved dashboard — no new fields
        let json = """
        {
          "isEnabled": true,
          "sourceKind": "microphone",
          "weighting": "a",
          "timeWeighting": "fast",
          "averagingEnabled": false,
          "averagingWindowSeconds": 60,
          "showMainValue": true,
          "showGraph": true,
          "graphHeight": 120,
          "graphLineMode": "rawSpl",
          "showGraphUnits": true,
          "publishHz": 10,
          "calibrationOffsetDb": 0,
          "isArmedByUser": false,
          "historyWindowSeconds": 30,
          "historyMaxSeconds": 600,
          "exportIncludeRawDbFS": true,
          "exportIncludePeak": true,
          "autoLogEnabled": false,
          "limitColorEnabled": false,
          "limitWarningDb": 90,
          "limitAlertDb": 100
        }
        """.data(using: .utf8)!

        let model = try JSONDecoder().decode(DbReaderModuleModel.self, from: json)
        XCTAssertEqual(model.showBarMeter, false)
        XCTAssertEqual(model.caUpperLimit, 12.0)
        XCTAssertEqual(model.caLowerLimit, 8.0)
    }
}
