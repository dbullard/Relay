import Foundation
import SwiftUI

struct TranscriptChannel: Identifiable, Equatable {
    let id: UUID
    var displayName: String
    var color: CodableColor
    var deviceUID: String?
    var channelIndex: Int
}

struct TranscriptEvent: Equatable {
    let channelId: UUID
    let timestamp: Date
    let text: String
    let isFinal: Bool
    let confidence: Double?
}
