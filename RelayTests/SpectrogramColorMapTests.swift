import XCTest
import SwiftUI
@testable import Relay

final class SpectrogramColorMapTests: XCTestCase {

    func testLUTHas256Entries() {
        let lut = SpectrogramLUT(colorMap: .defaultFirePlasma)
        XCTAssertEqual(lut.table.count, 256)
    }

    func testZeroMapsToBlack() {
        let lut = SpectrogramLUT(colorMap: SpectrogramColorMap(preset: .firePlasma, customStops: []))
        let color = lut.color(normalizedValue: 0)
        let r = (color >> 16) & 0xFF
        let g = (color >> 8) & 0xFF
        let b = color & 0xFF
        XCTAssertEqual(r, 0)
        XCTAssertEqual(g, 0)
        XCTAssertEqual(b, 0)
    }

    func testOutOfRangeClamps() {
        let lut = SpectrogramLUT(colorMap: .defaultFirePlasma)
        let below = lut.color(normalizedValue: -1)
        let above = lut.color(normalizedValue: 2)
        XCTAssertEqual(below, lut.color(normalizedValue: 0))
        XCTAssertEqual(above, lut.color(normalizedValue: 1))
    }

    func testCustomStopsInterpolation() {
        let stops = [
            CodableGradientStop(position: 0, color: CodableColor(red: 0, green: 0, blue: 0)),
            CodableGradientStop(position: 1, color: CodableColor(red: 1, green: 1, blue: 1))
        ]
        let lut = SpectrogramLUT(colorMap: SpectrogramColorMap(preset: .custom, customStops: stops))
        let mid = lut.color(normalizedValue: 0.5)
        let r = Int((mid >> 16) & 0xFF)
        XCTAssertTrue(abs(r - 127) <= 2, "Expected ~127 at midpoint, got \(r)")
    }
}
