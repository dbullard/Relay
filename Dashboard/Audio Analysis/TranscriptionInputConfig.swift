import Foundation
import SwiftUI

nonisolated struct TranscriptionInputConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var deviceUID: String?
    var channelIndex: Int
    var color: CodableColor
    var autoGainEnabled: Bool
    var sensitivity: Double        // 0.0–1.0
    var enginePreference: TranscriptionEnginePreference
    var wordFilters: [WordReplacementFilter]
    var profanitySettings: LiveTranscriptionProfanitySettings

    private enum CodingKeys: String, CodingKey {
        case id, name, deviceUID, channelIndex, color, autoGainEnabled, sensitivity
        case enginePreference, wordFilters, profanitySettings
    }

    init(
        id: UUID = UUID(),
        name: String,
        deviceUID: String? = nil,
        channelIndex: Int = 0,
        color: CodableColor = CodableColor(.cyan),
        autoGainEnabled: Bool = true,
        sensitivity: Double = 0.4,
        enginePreference: TranscriptionEnginePreference = .auto,
        wordFilters: [WordReplacementFilter] = [],
        profanitySettings: LiveTranscriptionProfanitySettings = LiveTranscriptionProfanitySettings()
    ) {
        self.id = id
        self.name = name
        self.deviceUID = deviceUID
        self.channelIndex = max(0, channelIndex)
        self.color = color
        self.autoGainEnabled = autoGainEnabled
        self.sensitivity = min(1.0, max(0.0, sensitivity))
        self.enginePreference = enginePreference
        self.wordFilters = wordFilters
        self.profanitySettings = profanitySettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        deviceUID = try container.decodeIfPresent(String.self, forKey: .deviceUID)
        channelIndex = try container.decode(Int.self, forKey: .channelIndex)
        color = try container.decode(CodableColor.self, forKey: .color)
        autoGainEnabled = try container.decode(Bool.self, forKey: .autoGainEnabled)
        sensitivity = try container.decode(Double.self, forKey: .sensitivity)
        enginePreference = try container.decode(TranscriptionEnginePreference.self, forKey: .enginePreference)
        wordFilters = try container.decodeIfPresent([WordReplacementFilter].self, forKey: .wordFilters) ?? []
        profanitySettings = try container.decodeIfPresent(
            LiveTranscriptionProfanitySettings.self,
            forKey: .profanitySettings
        ) ?? LiveTranscriptionProfanitySettings()
    }

    /// Maps sensitivity (0.0–1.0) to auto-gain RMS target (0.02–0.12).
    /// Sensitivity 0.4 → target 0.06 (matches the previous hardcoded value).
    var autoGainTarget: Double {
        0.02 + sensitivity * 0.10
    }
}

nonisolated enum TranscriptionEnginePreference: String, Codable, CaseIterable {
    case auto
    case onDevice
    case cloud
}

nonisolated struct WordReplacementFilter: Codable, Identifiable, Equatable {
    let id: UUID
    var from: String
    var to: String

    init(id: UUID = UUID(), from: String = "", to: String = "") {
        self.id = id
        self.from = from
        self.to = to
    }
}
