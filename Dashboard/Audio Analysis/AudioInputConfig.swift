import Foundation
import SwiftUI

nonisolated struct AudioInputConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var deviceUID: String?
    var channelIndex: Int
    /// Calibration offset applied to all SPL/dB outputs for this input. Default 0.
    var calibrationOffsetDb: Double
    /// Display colour used by RTA / Spectrograph tiles that reference this input.
    var color: CodableColor

    init(id: UUID = UUID(), name: String, deviceUID: String? = nil, channelIndex: Int = 0,
         calibrationOffsetDb: Double = 0, color: CodableColor = CodableColor(red: 1, green: 1, blue: 1)) {
        self.id = id
        self.name = name
        self.deviceUID = deviceUID
        self.channelIndex = max(0, channelIndex)
        self.calibrationOffsetDb = calibrationOffsetDb
        self.color = color
    }
}
