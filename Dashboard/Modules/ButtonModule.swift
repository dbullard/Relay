//
//  ButtonModule.swift
//  Relay
//
//  Created by Codex on 3/8/26.
//

import SwiftUI

// MARK: - Model

struct ButtonActionEntry: Identifiable, Equatable, Codable {
    var id: UUID
    var action: ButtonModuleAction
    var appControlRefreshDeviceOptions: AppControlRefreshDeviceOptions

    init(
        id: UUID = UUID(),
        action: ButtonModuleAction = .internalCommand(.resetSpl),
        appControlRefreshDeviceOptions: AppControlRefreshDeviceOptions = AppControlRefreshDeviceOptions()
    ) {
        self.id = id
        self.action = action
        self.appControlRefreshDeviceOptions = appControlRefreshDeviceOptions
    }

    enum CodingKeys: String, CodingKey {
        case id
        case action
        case appControlRefreshDeviceOptions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        action = try container.decodeIfPresent(ButtonModuleAction.self, forKey: .action) ?? .internalCommand(.resetSpl)
        appControlRefreshDeviceOptions = try container.decodeIfPresent(AppControlRefreshDeviceOptions.self, forKey: .appControlRefreshDeviceOptions)
            ?? AppControlRefreshDeviceOptions()
    }
}

struct ButtonModuleModel: Identifiable, Equatable, Codable {
    var id: UUID
    var buttons: [ButtonConfig]
    var sharedStyle: ButtonGroupSharedStyle
    var layout: ButtonGroupLayout

    init(
        id: UUID = UUID(),
        buttons: [ButtonConfig] = [ButtonConfig()],
        sharedStyle: ButtonGroupSharedStyle = ButtonGroupSharedStyle(),
        layout: ButtonGroupLayout = ButtonGroupLayout()
    ) {
        self.id = id
        self.buttons = buttons
        self.sharedStyle = sharedStyle
        self.layout = layout
    }

    enum CodingKeys: String, CodingKey {
        case id, buttons, sharedStyle, layout
        // Legacy flat-button keys (pre-multi-button)
        case title, subtitle, actions, action, appControlRefreshDeviceOptions
        case icon, behavior, availability, feedback, statePresentation, style
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sharedStyle = try container.decodeIfPresent(ButtonGroupSharedStyle.self, forKey: .sharedStyle) ?? ButtonGroupSharedStyle()
        layout = try container.decodeIfPresent(ButtonGroupLayout.self, forKey: .layout) ?? ButtonGroupLayout()

        if let decodedButtons = try container.decodeIfPresent([ButtonConfig].self, forKey: .buttons) {
            buttons = decodedButtons
        } else {
            // Legacy migration: decode old flat single-button fields
            let legacyStyle = try container.decodeIfPresent(ButtonModuleStyle.self, forKey: .style) ?? ButtonModuleStyle.default
            // NOTE: legacy ButtonModuleStyle fields useTileTextFormatting, textAlignment,
            // titleFontSize/Weight, subtitleFontSize/Weight, and borderWidth are not migrated —
            // they are superseded by per-button color/behavior settings in the new model.
            let legacyColor = ButtonConfigColor(
                backgroundColor: legacyStyle.backgroundColor,
                borderColor: legacyStyle.borderColor,
                titleColor: legacyStyle.titleColor,
                subtitleColor: legacyStyle.subtitleColor,
                iconColor: nil
            )
            let legacyTitle = try container.decodeIfPresent(String.self, forKey: .title) ?? "Button"
            let legacySubtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
            let legacyIcon = try container.decodeIfPresent(ButtonModuleIcon.self, forKey: .icon) ?? ButtonModuleIcon()
            let legacyBehavior = try container.decodeIfPresent(ButtonModuleBehavior.self, forKey: .behavior) ?? ButtonModuleBehavior()
            let legacyAvailability = try container.decodeIfPresent(ButtonModuleAvailability.self, forKey: .availability) ?? ButtonModuleAvailability()
            let legacyFeedback = try container.decodeIfPresent(ButtonModuleFeedback.self, forKey: .feedback) ?? ButtonModuleFeedback()
            let legacyStatePresentation = try container.decodeIfPresent(ButtonModuleStatePresentation.self, forKey: .statePresentation) ?? ButtonModuleStatePresentation()

            var legacyActions: [ButtonActionEntry]
            if let entries = try container.decodeIfPresent([ButtonActionEntry].self, forKey: .actions) {
                legacyActions = entries
            } else {
                let a = try container.decodeIfPresent(ButtonModuleAction.self, forKey: .action) ?? .internalCommand(.resetSpl)
                let o = try container.decodeIfPresent(AppControlRefreshDeviceOptions.self, forKey: .appControlRefreshDeviceOptions) ?? AppControlRefreshDeviceOptions()
                legacyActions = [ButtonActionEntry(action: a, appControlRefreshDeviceOptions: o)]
            }

            // CRITICAL: use the module's id as the config id to preserve existing canvas wiring
            buttons = [ButtonConfig(
                id: id,
                title: legacyTitle,
                subtitle: legacySubtitle,
                actions: legacyActions,
                icon: legacyIcon,
                behavior: legacyBehavior,
                availability: legacyAvailability,
                feedback: legacyFeedback,
                statePresentation: legacyStatePresentation,
                color: legacyColor
            )]

            // Migrate sharedStyle from legacy style shape fields
            sharedStyle = ButtonGroupSharedStyle(
                cornerRadius: legacyStyle.cornerRadius,
                horizontalPadding: legacyStyle.horizontalPadding,
                verticalPadding: legacyStyle.verticalPadding,
                buttonSpacing: 8
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(buttons, forKey: .buttons)
        try container.encode(sharedStyle, forKey: .sharedStyle)
        try container.encode(layout, forKey: .layout)
    }
}

struct ButtonModuleBehavior: Codable, Equatable {
    var interactionMode: ButtonModuleInteractionMode
    var requiresConfirmation: Bool
    var confirmationTitle: String
    var confirmationMessage: String
    var cooldownSeconds: Double
    var allowsTriggerWhileEditing: Bool
    var commandDelayMilliseconds: Int

    init(
        interactionMode: ButtonModuleInteractionMode = .momentary,
        requiresConfirmation: Bool = false,
        confirmationTitle: String = "",
        confirmationMessage: String = "",
        cooldownSeconds: Double = 0,
        allowsTriggerWhileEditing: Bool = false,
        commandDelayMilliseconds: Int = 0
    ) {
        self.interactionMode = interactionMode
        self.requiresConfirmation = requiresConfirmation
        self.confirmationTitle = confirmationTitle
        self.confirmationMessage = confirmationMessage
        self.cooldownSeconds = cooldownSeconds
        self.allowsTriggerWhileEditing = allowsTriggerWhileEditing
        self.commandDelayMilliseconds = commandDelayMilliseconds
    }
}

enum ButtonModuleInteractionMode: String, CaseIterable, Identifiable, Codable {
    case momentary
    case toggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .momentary: return "Momentary"
        case .toggle: return "Toggle"
        }
    }
}

struct ButtonModuleAvailability: Codable, Equatable {
    var liveModeRequirement: ButtonModuleLiveModeRequirement
    var stateRequirement: ButtonModuleStateRequirement
    var disablesWhileRunning: Bool
    var disablesDuringCooldown: Bool

    init(
        liveModeRequirement: ButtonModuleLiveModeRequirement = .liveOnly,
        stateRequirement: ButtonModuleStateRequirement = .any,
        disablesWhileRunning: Bool = true,
        disablesDuringCooldown: Bool = true
    ) {
        self.liveModeRequirement = liveModeRequirement
        self.stateRequirement = stateRequirement
        self.disablesWhileRunning = disablesWhileRunning
        self.disablesDuringCooldown = disablesDuringCooldown
    }
}

enum ButtonModuleLiveModeRequirement: String, CaseIterable, Identifiable, Codable {
    case liveOnly
    case editOnly
    case always

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liveOnly: return "Live Mode Only"
        case .editOnly: return "Edit Mode Only"
        case .always: return "Always"
        }
    }
}

enum ButtonModuleStateRequirement: String, CaseIterable, Identifiable, Codable {
    case any
    case active
    case inactive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any State"
        case .active: return "Only When Active"
        case .inactive: return "Only When Inactive"
        }
    }
}

struct ButtonModuleFeedback: Codable, Equatable {
    var animatePress: Bool
    var showsRunningIndicator: Bool
    var showsResultBadge: Bool
    var resultBadgeDurationSeconds: Double
    var emitsDetailedEvents: Bool

    init(
        animatePress: Bool = true,
        showsRunningIndicator: Bool = true,
        showsResultBadge: Bool = true,
        resultBadgeDurationSeconds: Double = 1.5,
        emitsDetailedEvents: Bool = true
    ) {
        self.animatePress = animatePress
        self.showsRunningIndicator = showsRunningIndicator
        self.showsResultBadge = showsResultBadge
        self.resultBadgeDurationSeconds = resultBadgeDurationSeconds
        self.emitsDetailedEvents = emitsDetailedEvents
    }
}

struct ButtonConfigColor: Codable, Equatable {
    var backgroundColor: CodableColor
    var borderColor: CodableColor
    var titleColor: CodableColor
    var subtitleColor: CodableColor
    var iconColor: CodableColor?

    static var `default`: ButtonConfigColor {
        ButtonConfigColor(
            backgroundColor: CodableColor(Color.white.opacity(0.12)),
            borderColor: CodableColor(Color.white.opacity(0.18)),
            titleColor: CodableColor(Color.white),
            subtitleColor: CodableColor(Color.white.opacity(0.7)),
            iconColor: nil
        )
    }

    enum CodingKeys: String, CodingKey {
        case backgroundColor, borderColor, titleColor, subtitleColor, iconColor
    }

    init(
        backgroundColor: CodableColor = CodableColor(Color.white.opacity(0.12)),
        borderColor: CodableColor = CodableColor(Color.white.opacity(0.18)),
        titleColor: CodableColor = CodableColor(Color.white),
        subtitleColor: CodableColor = CodableColor(Color.white.opacity(0.7)),
        iconColor: CodableColor? = nil
    ) {
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.titleColor = titleColor
        self.subtitleColor = subtitleColor
        self.iconColor = iconColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backgroundColor = try container.decodeIfPresent(CodableColor.self, forKey: .backgroundColor) ?? CodableColor(Color.white.opacity(0.12))
        borderColor = try container.decodeIfPresent(CodableColor.self, forKey: .borderColor) ?? CodableColor(Color.white.opacity(0.18))
        titleColor = try container.decodeIfPresent(CodableColor.self, forKey: .titleColor) ?? CodableColor(Color.white)
        subtitleColor = try container.decodeIfPresent(CodableColor.self, forKey: .subtitleColor) ?? CodableColor(Color.white.opacity(0.7))
        iconColor = try container.decodeIfPresent(CodableColor.self, forKey: .iconColor)
    }
}

struct ButtonConfig: Identifiable, Equatable, Codable {
    var id: UUID
    var title: String
    var subtitle: String
    var actions: [ButtonActionEntry]
    var icon: ButtonModuleIcon
    var behavior: ButtonModuleBehavior
    var availability: ButtonModuleAvailability
    var feedback: ButtonModuleFeedback
    var statePresentation: ButtonModuleStatePresentation
    var color: ButtonConfigColor

    init(
        id: UUID = UUID(),
        title: String = "Button",
        subtitle: String = "",
        actions: [ButtonActionEntry] = [ButtonActionEntry()],
        icon: ButtonModuleIcon = ButtonModuleIcon(),
        behavior: ButtonModuleBehavior = ButtonModuleBehavior(),
        availability: ButtonModuleAvailability = ButtonModuleAvailability(),
        feedback: ButtonModuleFeedback = ButtonModuleFeedback(),
        statePresentation: ButtonModuleStatePresentation = ButtonModuleStatePresentation(),
        color: ButtonConfigColor = .default
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.actions = actions
        self.icon = icon
        self.behavior = behavior
        self.availability = availability
        self.feedback = feedback
        self.statePresentation = statePresentation
        self.color = color
    }

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, actions
        case icon, behavior, availability, feedback, statePresentation, color
        // Legacy single-action keys (pre-multi-button).
        case action
        case appControlRefreshDeviceOptions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Button"
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        icon = try container.decodeIfPresent(ButtonModuleIcon.self, forKey: .icon) ?? ButtonModuleIcon()
        behavior = try container.decodeIfPresent(ButtonModuleBehavior.self, forKey: .behavior) ?? ButtonModuleBehavior()
        availability = try container.decodeIfPresent(ButtonModuleAvailability.self, forKey: .availability) ?? ButtonModuleAvailability()
        feedback = try container.decodeIfPresent(ButtonModuleFeedback.self, forKey: .feedback) ?? ButtonModuleFeedback()
        statePresentation = try container.decodeIfPresent(ButtonModuleStatePresentation.self, forKey: .statePresentation) ?? ButtonModuleStatePresentation()
        color = try container.decodeIfPresent(ButtonConfigColor.self, forKey: .color) ?? .default
        if let entries = try container.decodeIfPresent([ButtonActionEntry].self, forKey: .actions) {
            actions = entries
        } else {
            let legacyAction = try container.decodeIfPresent(ButtonModuleAction.self, forKey: .action) ?? .internalCommand(.resetSpl)
            let legacyOptions = try container.decodeIfPresent(AppControlRefreshDeviceOptions.self, forKey: .appControlRefreshDeviceOptions) ?? AppControlRefreshDeviceOptions()
            actions = [ButtonActionEntry(action: legacyAction, appControlRefreshDeviceOptions: legacyOptions)]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(actions, forKey: .actions)
        try container.encode(icon, forKey: .icon)
        try container.encode(behavior, forKey: .behavior)
        try container.encode(availability, forKey: .availability)
        try container.encode(feedback, forKey: .feedback)
        try container.encode(statePresentation, forKey: .statePresentation)
        try container.encode(color, forKey: .color)
    }
}

struct ButtonGroupSharedStyle: Codable, Equatable {
    var cornerRadius: Double
    var horizontalPadding: Double
    var verticalPadding: Double
    var buttonSpacing: Double

    init(
        cornerRadius: Double = 12,
        horizontalPadding: Double = 12,
        verticalPadding: Double = 10,
        buttonSpacing: Double = 8
    ) {
        self.cornerRadius = cornerRadius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.buttonSpacing = buttonSpacing
    }

    static var `default`: ButtonGroupSharedStyle {
        ButtonGroupSharedStyle()
    }

    enum CodingKeys: String, CodingKey {
        case cornerRadius, horizontalPadding, verticalPadding, buttonSpacing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 12
        horizontalPadding = try container.decodeIfPresent(Double.self, forKey: .horizontalPadding) ?? 12
        verticalPadding = try container.decodeIfPresent(Double.self, forKey: .verticalPadding) ?? 10
        buttonSpacing = try container.decodeIfPresent(Double.self, forKey: .buttonSpacing) ?? 8
    }
}

struct ButtonGroupLayout: Codable, Equatable {
    var columnsPerRow: Int?  // nil = auto-wrap

    init(columnsPerRow: Int? = nil) {
        self.columnsPerRow = columnsPerRow
    }

    enum CodingKeys: String, CodingKey { case columnsPerRow }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        columnsPerRow = try container.decodeIfPresent(Int.self, forKey: .columnsPerRow)
    }
}

struct ButtonModuleIcon: Codable, Equatable {
    var source: ButtonModuleIconSource
    var preset: ButtonModulePresetIcon
    var systemName: String
    var placement: ButtonModuleIconPlacement
    var size: Double
    var color: CodableColor?

    init(
        source: ButtonModuleIconSource = .none,
        preset: ButtonModulePresetIcon = .play,
        systemName: String = "",
        placement: ButtonModuleIconPlacement = .leading,
        size: Double = 18,
        color: CodableColor? = nil
    ) {
        self.source = source
        self.preset = preset
        self.systemName = systemName
        self.placement = placement
        self.size = size
        self.color = color
    }

    enum CodingKeys: String, CodingKey {
        case source
        case preset
        case systemName
        case placement
        case size
        case color
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacySystemName = try container.decodeIfPresent(String.self, forKey: .systemName) ?? ""
        let rawSource = try container.decodeIfPresent(ButtonModuleIconSource.self, forKey: .source)
        let legacyPreset = try container.decodeIfPresent(ButtonModulePresetIcon.self, forKey: .preset) ?? .play

        switch rawSource {
        case .preset:
            source = .symbol
            systemName = legacyPreset.systemName
        case .customSymbol:
            source = .symbol
            systemName = legacySystemName
        case .symbol:
            source = .symbol
            systemName = legacySystemName
        case .some(.none):
            source = .none
            systemName = legacySystemName
        case nil:
            let trimmed = legacySystemName.trimmingCharacters(in: .whitespacesAndNewlines)
            source = trimmed.isEmpty ? .none : .symbol
            systemName = legacySystemName
        }

        preset = legacyPreset
        placement = try container.decodeIfPresent(ButtonModuleIconPlacement.self, forKey: .placement) ?? .leading
        size = try container.decodeIfPresent(Double.self, forKey: .size) ?? 18
        color = try container.decodeIfPresent(CodableColor.self, forKey: .color)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let writtenSource: ButtonModuleIconSource = (source == .preset || source == .customSymbol) ? .symbol : source
        try container.encode(writtenSource, forKey: .source)
        try container.encode(systemName, forKey: .systemName)
        try container.encode(placement, forKey: .placement)
        try container.encode(size, forKey: .size)
        try container.encodeIfPresent(color, forKey: .color)
        // preset field intentionally not encoded — it is legacy only
    }

    fileprivate var resolvedContent: ButtonModuleResolvedIconContent? {
        switch source {
        case .none:
            return nil
        case .symbol, .customSymbol:
            let trimmed = systemName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .symbol(trimmed)
        case .preset:
            return .symbol(preset.systemName)
        }
    }
}

enum ButtonModuleIconSource: String, CaseIterable, Identifiable, Codable {
    case none
    case symbol
    // Legacy decode-only — never written, never shown in UI
    case preset
    case customSymbol

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .symbol, .preset, .customSymbol: return "Symbol"
        }
    }
}

enum ButtonModulePresetIcon: String, CaseIterable, Identifiable, Codable {
    case play
    case stop
    case pause
    case live
    case record
    case microphone
    case transcript
    case waveform
    case refresh
    case save
    case next
    case previous
    case automation
    case light
    case power
    case warning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .play: return "Play"
        case .stop: return "Stop"
        case .pause: return "Pause"
        case .live: return "Live"
        case .record: return "Record"
        case .microphone: return "Microphone"
        case .transcript: return "Transcript"
        case .waveform: return "Waveform"
        case .refresh: return "Refresh"
        case .save: return "Save"
        case .next: return "Next"
        case .previous: return "Previous"
        case .automation: return "Automation"
        case .light: return "Light"
        case .power: return "Power"
        case .warning: return "Warning"
        }
    }

    var systemName: String {
        switch self {
        case .play: return "play.fill"
        case .stop: return "stop.fill"
        case .pause: return "pause.fill"
        case .live: return "dot.radiowaves.left.and.right"
        case .record: return "record.circle.fill"
        case .microphone: return "mic.fill"
        case .transcript: return "text.bubble.fill"
        case .waveform: return "waveform"
        case .refresh: return "arrow.clockwise"
        case .save: return "square.and.arrow.down.fill"
        case .next: return "forward.fill"
        case .previous: return "backward.fill"
        case .automation: return "bolt.fill"
        case .light: return "lightbulb.fill"
        case .power: return "power"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
}

enum ButtonModuleIconPlacement: String, CaseIterable, Identifiable, Codable {
    case leading
    case top

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leading: return "Leading"
        case .top: return "Top"
        }
    }
}

struct ButtonModuleStatePresentation: Codable, Equatable {
    var source: ButtonModuleStateSource
    var showsBadge: Bool
    var selectedTabIndex: Int
    var activeTitle: String
    var inactiveTitle: String
    var activeSubtitle: String
    var inactiveSubtitle: String
    var activeIconToken: String
    var inactiveIconToken: String

    init(
        source: ButtonModuleStateSource = .none,
        showsBadge: Bool = true,
        selectedTabIndex: Int = 1,
        activeTitle: String = "",
        inactiveTitle: String = "",
        activeSubtitle: String = "",
        inactiveSubtitle: String = "",
        activeIconToken: String = "",
        inactiveIconToken: String = ""
    ) {
        self.source = source
        self.showsBadge = showsBadge
        self.selectedTabIndex = selectedTabIndex
        self.activeTitle = activeTitle
        self.inactiveTitle = inactiveTitle
        self.activeSubtitle = activeSubtitle
        self.inactiveSubtitle = inactiveSubtitle
        self.activeIconToken = activeIconToken
        self.inactiveIconToken = inactiveIconToken
    }

    enum CodingKeys: String, CodingKey {
        case source
        case showsBadge
        case selectedTabIndex
        case activeTitle
        case inactiveTitle
        case activeSubtitle
        case inactiveSubtitle
        case activeIconToken
        case inactiveIconToken
        case activeSystemImage
        case inactiveSystemImage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(ButtonModuleStateSource.self, forKey: .source) ?? .none
        showsBadge = try container.decodeIfPresent(Bool.self, forKey: .showsBadge) ?? true
        selectedTabIndex = max(1, try container.decodeIfPresent(Int.self, forKey: .selectedTabIndex) ?? 1)
        activeTitle = try container.decodeIfPresent(String.self, forKey: .activeTitle) ?? ""
        inactiveTitle = try container.decodeIfPresent(String.self, forKey: .inactiveTitle) ?? ""
        activeSubtitle = try container.decodeIfPresent(String.self, forKey: .activeSubtitle) ?? ""
        inactiveSubtitle = try container.decodeIfPresent(String.self, forKey: .inactiveSubtitle) ?? ""
        activeIconToken = try container.decodeIfPresent(String.self, forKey: .activeIconToken)
            ?? container.decodeIfPresent(String.self, forKey: .activeSystemImage)
            ?? ""
        inactiveIconToken = try container.decodeIfPresent(String.self, forKey: .inactiveIconToken)
            ?? container.decodeIfPresent(String.self, forKey: .inactiveSystemImage)
            ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(showsBadge, forKey: .showsBadge)
        try container.encode(selectedTabIndex, forKey: .selectedTabIndex)
        try container.encode(activeTitle, forKey: .activeTitle)
        try container.encode(inactiveTitle, forKey: .inactiveTitle)
        try container.encode(activeSubtitle, forKey: .activeSubtitle)
        try container.encode(inactiveSubtitle, forKey: .inactiveSubtitle)
        try container.encode(activeIconToken, forKey: .activeIconToken)
        try container.encode(inactiveIconToken, forKey: .inactiveIconToken)
    }
}

enum ButtonModuleStateSource: String, CaseIterable, Identifiable, Codable {
    case none
    case liveMode
    case splLogging
    case toggle
    case running
    case error
    case success
    case failure
    case selectedTab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .liveMode: return "Live Mode"
        case .splLogging: return "SPL Logging"
        case .toggle: return "Toggle State"
        case .running: return "Running"
        case .error: return "Error State"
        case .success: return "Last Result: Success"
        case .failure: return "Last Result: Failure"
        case .selectedTab: return "Selected Tab"
        }
    }
}

struct ButtonModuleStyle: Codable, Equatable {
    var useTileTextFormatting: Bool
    var textAlignment: TextJustificationStyle
    var titleFontSize: Double
    var titleFontWeight: PersonFontWeight
    var titleColor: CodableColor
    var subtitleFontSize: Double
    var subtitleFontWeight: PersonFontWeight
    var subtitleColor: CodableColor
    var backgroundColor: CodableColor
    var borderColor: CodableColor
    var borderWidth: Double
    var cornerRadius: Double
    var horizontalPadding: Double
    var verticalPadding: Double

    static var `default`: ButtonModuleStyle {
        ButtonModuleStyle(
            useTileTextFormatting: true,
            textAlignment: .center,
            titleFontSize: 16,
            titleFontWeight: .semibold,
            titleColor: CodableColor(Color.white),
            subtitleFontSize: 12,
            subtitleFontWeight: .regular,
            subtitleColor: CodableColor(Color.white.opacity(0.7)),
            backgroundColor: CodableColor(Color.white.opacity(0.12)),
            borderColor: CodableColor(Color.white.opacity(0.18)),
            borderWidth: 1,
            cornerRadius: 12,
            horizontalPadding: 12,
            verticalPadding: 10
        )
    }
}

enum ButtonModuleAction: Equatable, Codable {
    case internalCommand(InternalButtonCommand)
    case osc(OSCButtonAction)
    case midi(MIDIButtonAction)

    enum CodingKeys: String, CodingKey {
        case type
        case internalCommand
        case osc
        case midi
    }

    enum Kind: String, Codable {
        case internalCommand
        case osc
        case midi
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .internalCommand:
            let command = try container.decode(InternalButtonCommand.self, forKey: .internalCommand)
            self = .internalCommand(command)
        case .osc:
            let action = try container.decode(OSCButtonAction.self, forKey: .osc)
            self = .osc(action)
        case .midi:
            let action = try container.decode(MIDIButtonAction.self, forKey: .midi)
            self = .midi(action)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .internalCommand(let command):
            try container.encode(Kind.internalCommand, forKey: .type)
            try container.encode(command, forKey: .internalCommand)
        case .osc(let action):
            try container.encode(Kind.osc, forKey: .type)
            try container.encode(action, forKey: .osc)
        case .midi(let action):
            try container.encode(Kind.midi, forKey: .type)
            try container.encode(action, forKey: .midi)
        }
    }
}

enum InternalButtonCommand: String, CaseIterable, Identifiable, Codable {
    case resetSpl
    case clearLiveTranscription
    case selectFirstTab
    case selectPreviousTab
    case selectNextTab
    case selectLastTab
    case refreshPCO
    case resyncDeviceNames
    case switchToCanvasView
    case switchToAutomationView
    case enterLiveMode
    case exitLiveMode
    case toggleLiveMode
    case saveDashboard
    case saveDashboardAs
    case startSplLogging
    case stopSplLogging
    case toggleSplLogging

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resetSpl: return "Clear SPL Meters"
        case .clearLiveTranscription: return "Clear Live Transcript"
        case .selectFirstTab: return "Select First Tab"
        case .selectPreviousTab: return "Select Previous Tab"
        case .selectNextTab: return "Select Next Tab"
        case .selectLastTab: return "Select Last Tab"
        case .refreshPCO: return "Refresh Planning Center"
        case .resyncDeviceNames: return "Resync Console + Wireless Names"
        case .switchToCanvasView: return "Switch to Canvas View"
        case .switchToAutomationView: return "Switch to Automation View"
        case .enterLiveMode: return "Enter Live Mode"
        case .exitLiveMode: return "Exit Live Mode"
        case .toggleLiveMode: return "Toggle Live Mode"
        case .saveDashboard: return "Save Dashboard"
        case .saveDashboardAs: return "Save Dashboard As"
        case .startSplLogging:  return "Start SPL Logging"
        case .stopSplLogging:   return "Stop SPL Logging"
        case .toggleSplLogging: return "Toggle SPL Logging"
        }
    }

    var appControlActionKind: DashboardGraph.AppControlActionConfig.ActionKind {
        switch self {
        case .resetSpl:
            return .clearSplMeters
        case .clearLiveTranscription:
            return .clearLiveTranscript
        case .selectFirstTab:
            return .selectFirstTab
        case .selectPreviousTab:
            return .selectPreviousTab
        case .selectNextTab:
            return .selectNextTab
        case .selectLastTab:
            return .selectLastTab
        case .refreshPCO:
            return .refreshPCO
        case .resyncDeviceNames:
            return .resyncDeviceNames
        case .switchToCanvasView:
            return .switchToCanvasView
        case .switchToAutomationView:
            return .switchToAutomationView
        case .enterLiveMode:
            return .enterLiveMode
        case .exitLiveMode:
            return .exitLiveMode
        case .toggleLiveMode:
            return .toggleLiveMode
        case .saveDashboard:
            return .saveDashboard
        case .saveDashboardAs:
            return .saveDashboardAs
        case .startSplLogging:
            return .startSplLogging
        case .stopSplLogging:
            return .stopSplLogging
        case .toggleSplLogging:
            return .toggleSplLogging
        }
    }
}

struct OSCButtonAction: Equatable, Codable {
    var endpoint: OSCEndpoint
    var address: String
    var argument: OSCButtonArgument?

    init(
        endpoint: OSCEndpoint = OSCEndpoint(host: "127.0.0.1", port: 8000),
        address: String = "/relay/button",
        argument: OSCButtonArgument? = nil
    ) {
        self.endpoint = endpoint
        self.address = address
        self.argument = argument
    }
}

enum OSCButtonArgument: Equatable, Codable {
    case int(Int)
    case float(Double)
    case string(String)
    case bool(Bool)

    enum CodingKeys: String, CodingKey {
        case type
        case int
        case float
        case string
        case bool
    }

    enum Kind: String, Codable {
        case int
        case float
        case string
        case bool
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .int:
            self = .int(try container.decode(Int.self, forKey: .int))
        case .float:
            self = .float(try container.decode(Double.self, forKey: .float))
        case .string:
            self = .string(try container.decode(String.self, forKey: .string))
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .bool))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .int(let value):
            try container.encode(Kind.int, forKey: .type)
            try container.encode(value, forKey: .int)
        case .float(let value):
            try container.encode(Kind.float, forKey: .type)
            try container.encode(value, forKey: .float)
        case .string(let value):
            try container.encode(Kind.string, forKey: .type)
            try container.encode(value, forKey: .string)
        case .bool(let value):
            try container.encode(Kind.bool, forKey: .type)
            try container.encode(value, forKey: .bool)
        }
    }
}

struct MIDIButtonAction: Equatable, Codable {
    var destinationID: Int32?
    var kind: MIDIMessageKind
    var channel: Int
    var note: Int
    var velocity: Int
    var control: Int
    var value: Int
    var program: Int

    init(
        destinationID: Int32? = nil,
        kind: MIDIMessageKind = .noteOn,
        channel: Int = 1,
        note: Int = 60,
        velocity: Int = 100,
        control: Int = 1,
        value: Int = 127,
        program: Int = 0
    ) {
        self.destinationID = destinationID
        self.kind = kind
        self.channel = channel
        self.note = note
        self.velocity = velocity
        self.control = control
        self.value = value
        self.program = program
    }
}

// MARK: - Tile Rendering

struct ButtonItemView: View {
    @Environment(\.tileTextFormatting) private var tileTextFormatting
    @Environment(\.dashboardIsLANSnapshotRendering) private var isLANSnapshotRendering
    let config: ButtonConfig
    let sharedStyle: ButtonGroupSharedStyle
    let moduleNodeId: UUID
    let buttonCount: Int
    let isLiveMode: Bool
    let onInternalCommand: (InternalButtonCommand, AppControlRefreshDeviceOptions, UUID) -> Void

    @State private var splLoggingManager = SPLLoggingManager.shared
    @State private var selectedTabIndex: Int = 0
    @State private var isToggleOn = false
    @State private var runtimeSucceededRecently = false
    @State private var runtimeFailedRecently = false
    @State private var runtimeErrorMessage: String?
    @State private var isRunning = false
    @State private var cooldownUntil: Date?
    @State private var isPressed = false
    @State private var showsConfirmation = false
    @State private var loggingPulseOpacity: Double = 1.0
    @State private var resultResetTask: Task<Void, Never>?

    var body: some View {
        let resolvedFontSize: CGFloat = CGFloat(tileTextFormatting?.fontSize ?? 16)
        let resolvedSubtitleFontSize: CGFloat = CGFloat(max(10, (tileTextFormatting?.fontSize ?? 16) * 0.75))
        let titleWeight = (tileTextFormatting?.fontWeight ?? .semibold).swiftUIFontWeight
        let subtitleWeight = Font.Weight.regular
        let titleColor = config.color.titleColor.swiftUIColor
        let subtitleColor = config.color.subtitleColor.swiftUIColor
        let alignment = tileTextFormatting?.justification ?? .center
        let stackAlignment = horizontalAlignment(from: alignment)
        let frameAlignment = alignmentForFrame(from: alignment)
        let hasRuntimeError = runtimeErrorMessage != nil
        let isStateActive = resolvedStateIsActive
        let isInteractionEnabled = resolvedInteractionEnabled
        let titleText = resolvedTitle
        let subtitleText = resolvedSubtitle
        let iconContent = resolvedIconContent
        let badgeStyle = statusBadgeStyle

        let content = Button(action: handlePrimaryAction) {
            ZStack(alignment: .topTrailing) {
                buttonLabel(
                    titleText: titleText,
                    subtitleText: subtitleText,
                    iconContent: iconContent,
                    titleColor: titleColor,
                    subtitleColor: subtitleColor,
                    textAlignment: alignment,
                    stackAlignment: stackAlignment,
                    frameAlignment: frameAlignment,
                    titleWeight: titleWeight,
                    subtitleWeight: subtitleWeight,
                    resolvedFontSize: resolvedFontSize,
                    resolvedSubtitleFontSize: resolvedSubtitleFontSize
                )
                .padding(.vertical, sharedStyle.verticalPadding)
                .padding(.horizontal, sharedStyle.horizontalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
                .scaleEffect(config.feedback.animatePress && isPressed ? 0.97 : 1.0)

                if hasRuntimeError {
                    Button {
                        runtimeErrorMessage = nil
                    } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.red.opacity(0.95))
                            .padding(6)
                            .background(Color.black.opacity(0.22), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(runtimeErrorMessage.map { "\($0)\nClick to dismiss warning." } ?? "Dismiss warning")
                    .padding(6)
                } else if config.feedback.showsRunningIndicator && isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                } else if let badgeStyle {
                    statusBadge(style: badgeStyle, isActive: isStateActive)
                        .padding(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(buttonBackground(hasRuntimeError: hasRuntimeError, isStateActive: isStateActive))
            .contentShape(.rect(cornerRadius: sharedStyle.cornerRadius))
        }

        content
            .buttonStyle(.plain)
            .allowsHitTesting(isInteractionEnabled)
            .opacity(isInteractionEnabled ? 1.0 : 0.5)
            .animation(.easeInOut(duration: 0.18), value: isStateActive)
            .animation(.easeInOut(duration: 0.12), value: isPressed)
            .simultaneousGesture(pressGesture)
            .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.appControlStarted)) { note in
                guard let actionId = note.userInfo?[ActionNodeUserInfoKeys.nodeId] as? UUID, actionId == moduleNodeId else { return }
                guard let buttonId = note.userInfo?["buttonConfigId"] as? UUID, buttonId == config.id else { return }
                runtimeErrorMessage = nil
                runtimeSucceededRecently = false
                runtimeFailedRecently = false
                isRunning = true
            }
            .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.appControlSucceeded)) { note in
                guard let actionId = note.userInfo?[ActionNodeUserInfoKeys.nodeId] as? UUID, actionId == moduleNodeId else { return }
                guard let buttonId = note.userInfo?["buttonConfigId"] as? UUID, buttonId == config.id else { return }
                runtimeErrorMessage = nil
                isRunning = false
                markResult(success: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: ActionNodeNotifications.appControlFailed)) { note in
                guard let actionId = note.userInfo?[ActionNodeUserInfoKeys.nodeId] as? UUID, actionId == moduleNodeId else { return }
                guard let buttonId = note.userInfo?["buttonConfigId"] as? UUID, buttonId == config.id else { return }
                runtimeErrorMessage = (note.userInfo?[ActionNodeUserInfoKeys.errorMessage] as? String) ?? "Action failed"
                isRunning = false
                markResult(success: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .relayTabDidChange)) { note in
                if let index = note.userInfo?["tabIndex"] as? Int {
                    selectedTabIndex = index
                }
            }
            .confirmationDialog(confirmationTitle, isPresented: $showsConfirmation, titleVisibility: .visible) {
                Button("Run") { executeConfiguredAction() }
                Button("Cancel", role: .cancel) {}
            } message: {
                if !confirmationMessage.isEmpty { Text(confirmationMessage) }
            }
    }

    // MARK: - State resolution

    private var resolvedStateIsActive: Bool {
        switch config.statePresentation.source {
        case .none: return false
        case .liveMode: return isLiveMode
        case .splLogging: return splLoggingManager.settings.isLogging
        case .toggle: return isToggleOn
        case .running: return isRunning
        case .error: return runtimeErrorMessage != nil
        case .success: return runtimeSucceededRecently
        case .failure: return runtimeFailedRecently
        case .selectedTab: return (selectedTabIndex + 1) == config.statePresentation.selectedTabIndex
        }
    }

    private var isCoolingDown: Bool {
        if let cooldownUntil { return cooldownUntil > Date() }
        return false
    }

    private var resolvedInteractionEnabled: Bool {
        let liveModeAllowed: Bool = {
            switch config.availability.liveModeRequirement {
            case .liveOnly: return isLiveMode || config.behavior.allowsTriggerWhileEditing
            case .editOnly: return !isLiveMode
            case .always: return true
            }
        }()
        guard liveModeAllowed else { return false }
        switch config.availability.stateRequirement {
        case .any: break
        case .active: guard resolvedStateIsActive else { return false }
        case .inactive: guard !resolvedStateIsActive else { return false }
        }
        if config.availability.disablesWhileRunning && isRunning { return false }
        if config.availability.disablesDuringCooldown && isCoolingDown { return false }
        return true
    }

    private var resolvedTitle: String {
        let override = resolvedStateIsActive ? config.statePresentation.activeTitle : config.statePresentation.inactiveTitle
        let trimmedOverride = override.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOverride.isEmpty { return trimmedOverride }
        return config.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedSubtitle: String {
        let override = resolvedStateIsActive ? config.statePresentation.activeSubtitle : config.statePresentation.inactiveSubtitle
        let trimmedOverride = override.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOverride.isEmpty { return trimmedOverride }
        return config.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedIconContent: ButtonModuleResolvedIconContent? {
        let stateIconToken = resolvedStateIsActive ? config.statePresentation.activeIconToken : config.statePresentation.inactiveIconToken
        if let override = resolvedIconContentFromToken(stateIconToken) { return override }
        return config.icon.resolvedContent
    }

    private var statusBadgeStyle: ButtonModuleStatusBadgeStyle? {
        guard config.statePresentation.showsBadge else { return nil }
        if config.feedback.showsResultBadge && runtimeSucceededRecently { return .success(label: "Done") }
        if config.feedback.showsResultBadge && runtimeFailedRecently { return .failure(label: "Failed") }
        switch config.statePresentation.source {
        case .none: return nil
        case .liveMode: return .capsule(activeLabel: "LIVE", inactiveLabel: "OFF")
        case .splLogging: return .pulse(activeLabel: "REC", inactiveLabel: "IDLE")
        case .toggle: return .capsule(activeLabel: "ON", inactiveLabel: "OFF")
        case .running: return .capsule(activeLabel: "BUSY", inactiveLabel: "IDLE")
        case .error: return .failure(label: "Error")
        case .success: return .success(label: "Done")
        case .failure: return .failure(label: "Failed")
        case .selectedTab: return .capsule(activeLabel: "TAB \(config.statePresentation.selectedTabIndex)", inactiveLabel: "OTHER")
        }
    }

    private var confirmationTitle: String {
        let trimmed = config.behavior.confirmationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Run Button Action?" : trimmed
    }

    private var confirmationMessage: String {
        config.behavior.confirmationMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Layout helpers

    private func horizontalAlignment(from alignment: TextJustificationStyle) -> HorizontalAlignment {
        switch alignment { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
    }

    private func alignmentForFrame(from alignment: TextJustificationStyle) -> Alignment {
        switch alignment { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
    }

    @ViewBuilder
    private func buttonLabel(
        titleText: String, subtitleText: String, iconContent: ButtonModuleResolvedIconContent?,
        titleColor: Color, subtitleColor: Color, textAlignment: TextJustificationStyle,
        stackAlignment: HorizontalAlignment, frameAlignment: Alignment,
        titleWeight: Font.Weight, subtitleWeight: Font.Weight,
        resolvedFontSize: CGFloat, resolvedSubtitleFontSize: CGFloat
    ) -> some View {
        let iconColor = config.color.iconColor?.swiftUIColor ?? titleColor
        let hasText = !titleText.isEmpty || !subtitleText.isEmpty
        Group {
            if config.icon.placement == .top {
                VStack(alignment: stackAlignment, spacing: 8) {
                    if let iconContent { iconView(iconContent, color: iconColor) }
                    if hasText {
                        textContent(titleText: titleText, subtitleText: subtitleText, titleColor: titleColor, subtitleColor: subtitleColor, textAlignment: textAlignment, stackAlignment: stackAlignment, titleWeight: titleWeight, subtitleWeight: subtitleWeight, resolvedFontSize: resolvedFontSize, resolvedSubtitleFontSize: resolvedSubtitleFontSize)
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    if let iconContent { iconView(iconContent, color: iconColor) }
                    if hasText {
                        textContent(titleText: titleText, subtitleText: subtitleText, titleColor: titleColor, subtitleColor: subtitleColor, textAlignment: textAlignment, stackAlignment: stackAlignment, titleWeight: titleWeight, subtitleWeight: subtitleWeight, resolvedFontSize: resolvedFontSize, resolvedSubtitleFontSize: resolvedSubtitleFontSize)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
    }

    @ViewBuilder
    private func iconView(_ content: ButtonModuleResolvedIconContent, color: Color) -> some View {
        switch content {
        case .symbol(let systemName):
            Image(systemName: systemName)
                .font(.system(size: config.icon.size, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    @ViewBuilder
    private func textContent(
        titleText: String, subtitleText: String, titleColor: Color, subtitleColor: Color,
        textAlignment: TextJustificationStyle, stackAlignment: HorizontalAlignment,
        titleWeight: Font.Weight, subtitleWeight: Font.Weight,
        resolvedFontSize: CGFloat, resolvedSubtitleFontSize: CGFloat
    ) -> some View {
        VStack(alignment: stackAlignment, spacing: 6) {
            if !titleText.isEmpty {
                Text(titleText)
                    .font(.system(size: resolvedFontSize, weight: titleWeight))
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(multilineTextAlignment(from: textAlignment))
            }
            if !subtitleText.isEmpty {
                Text(subtitleText)
                    .font(.system(size: resolvedSubtitleFontSize, weight: subtitleWeight))
                    .foregroundStyle(subtitleColor)
                    .multilineTextAlignment(multilineTextAlignment(from: textAlignment))
            }
        }
    }

    private func multilineTextAlignment(from alignment: TextJustificationStyle) -> TextAlignment {
        switch alignment { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
    }

    private func resolvedIconContentFromToken(_ token: String) -> ButtonModuleResolvedIconContent? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return .symbol(trimmed)
    }

    @ViewBuilder
    private func buttonBackground(hasRuntimeError: Bool, isStateActive: Bool) -> some View {
        let fillColor: Color = {
            if hasRuntimeError || runtimeFailedRecently { return Color.red.opacity(0.22) }
            if runtimeSucceededRecently { return Color.green.opacity(0.20) }
            if !resolvedInteractionEnabled { return config.color.backgroundColor.swiftUIColor.opacity(0.45) }
            if isRunning { return Color.orange.opacity(0.18) }
            if isStateActive { return config.color.backgroundColor.swiftUIColor.opacity(0.9) }
            return config.color.backgroundColor.swiftUIColor
        }()
        let borderColor: Color = {
            if hasRuntimeError || runtimeFailedRecently { return Color.red.opacity(0.85) }
            if runtimeSucceededRecently { return Color.green.opacity(0.78) }
            if !resolvedInteractionEnabled { return config.color.borderColor.swiftUIColor.opacity(0.4) }
            if isRunning { return Color.orange.opacity(0.72) }
            if isStateActive { return config.color.borderColor.swiftUIColor.opacity(0.95) }
            return config.color.borderColor.swiftUIColor
        }()
        if !isLANSnapshotRendering, #available(macOS 26.0, iOS 19.0, tvOS 19.0, watchOS 12.0, *) {
            Color.clear
                .glassEffect(
                    Glass.regular.tint(fillColor).interactive(),
                    in: .rect(cornerRadius: sharedStyle.cornerRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: sharedStyle.cornerRadius, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: hasRuntimeError ? max(1, 1.5) : 1)
                }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: sharedStyle.cornerRadius, style: .continuous).fill(fillColor)
                RoundedRectangle(cornerRadius: sharedStyle.cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: hasRuntimeError ? max(1, 1.5) : 1)
            }
        }
    }

    // MARK: - Badges

    @ViewBuilder
    private func statusBadge(style: ButtonModuleStatusBadgeStyle, isActive: Bool) -> some View {
        switch style {
        case .capsule(let activeLabel, let inactiveLabel):
            Text(isActive ? activeLabel : inactiveLabel)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isActive ? Color.white : Color.primary.opacity(0.8))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule(style: .continuous).fill(isActive ? Color.green.opacity(0.78) : Color.black.opacity(0.14)))
        case .pulse(let activeLabel, let inactiveLabel):
            HStack(spacing: 6) {
                Circle().fill(isActive ? Color.red : Color.secondary.opacity(0.45))
                    .frame(width: 8, height: 8).opacity(isActive ? loggingPulseOpacity : 1.0)
                Text(isActive ? activeLabel : inactiveLabel).font(.system(size: 10, weight: .bold)).foregroundStyle(.primary)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.black.opacity(0.14), in: Capsule(style: .continuous))
            .onAppear {
                guard isActive else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { loggingPulseOpacity = 0.3 }
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    loggingPulseOpacity = 1.0
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { loggingPulseOpacity = 0.3 }
                } else { loggingPulseOpacity = 1.0 }
            }
        case .success(let label):
            Label(label, systemImage: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(Color.green)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.black.opacity(0.14), in: Capsule(style: .continuous))
        case .failure(let label):
            Label(label, systemImage: "xmark.octagon.fill")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(Color.red)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.black.opacity(0.14), in: Capsule(style: .continuous))
        }
    }

    // MARK: - Actions

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard config.feedback.animatePress else { return }
                if !isPressed { isPressed = true; emitDetailedEvent(kind: "button.down") }
            }
            .onEnded { _ in
                if isPressed { isPressed = false; emitDetailedEvent(kind: "button.up") }
            }
    }

    private func handlePrimaryAction() {
        guard resolvedInteractionEnabled else { return }
        guard !isCoolingDown else { return }
        if config.behavior.requiresConfirmation { showsConfirmation = true } else { executeConfiguredAction() }
    }

    private func executeConfiguredAction() {
        if config.behavior.interactionMode == .toggle {
            isToggleOn.toggle()
            emitDetailedEvent(kind: isToggleOn ? "button.toggledOn" : "button.toggledOff")
        }
        let delayNs = UInt64(max(0, config.behavior.commandDelayMilliseconds)) * 1_000_000
        let hasInternalAction = config.actions.contains { if case .internalCommand = $0.action { return true }; return false }
        if config.behavior.cooldownSeconds > 0 { cooldownUntil = Date().addingTimeInterval(config.behavior.cooldownSeconds) }
        runtimeErrorMessage = nil
        runtimeSucceededRecently = false
        runtimeFailedRecently = false
        if !hasInternalAction { isRunning = config.feedback.showsRunningIndicator }
        Task {
            for (index, entry) in config.actions.enumerated() {
                await MainActor.run { execute(entry: entry) }
                if delayNs > 0 && index < (config.actions.count - 1) {
                    try? await Task.sleep(nanoseconds: delayNs)
                }
            }
            await MainActor.run {
                if !hasInternalAction { isRunning = false; markResult(success: true) }
                emitPressEvent(kind: "button.press")
            }
        }
    }

    private func execute(entry: ButtonActionEntry) {
        switch entry.action {
        case .internalCommand(let command):
            onInternalCommand(command, entry.appControlRefreshDeviceOptions, config.id)
        case .osc(let action):
            let message = OSCMessage(address: action.address, args: action.argument.map { [$0.oscValue] } ?? [])
            OSCManager.shared.send(to: action.endpoint, message: message)
        case .midi(let action):
            MIDISendManager.shared.send(bytes: action.midiBytes, to: action.destinationID)
        }
    }

    private func markResult(success: Bool) {
        resultResetTask?.cancel()
        runtimeSucceededRecently = success
        runtimeFailedRecently = !success
        if success { runtimeErrorMessage = nil }
        guard config.feedback.showsResultBadge else { return }
        let durationNs = UInt64(max(0.2, config.feedback.resultBadgeDurationSeconds) * 1_000_000_000)
        resultResetTask = Task {
            try? await Task.sleep(nanoseconds: durationNs)
            await MainActor.run { runtimeSucceededRecently = false; runtimeFailedRecently = false }
        }
    }

    private func emitDetailedEvent(kind: String) {
        guard config.feedback.emitsDetailedEvents else { return }
        emitPressEvent(kind: kind)
    }

    private func emitPressEvent(kind: String) {
        var userInfo: [AnyHashable: Any] = [
            TriggerNodeUserInfoKeys.triggerNodeId: moduleNodeId,
            TriggerNodeUserInfoKeys.source: "canvas.button",
            TriggerNodeUserInfoKeys.timestamp: Date(),
            "eventKind": kind
        ]
        // For multi-button modules, include which button fired so the runtime
        // can route to the correct output port.
        if buttonCount > 1 {
            userInfo["buttonConfigId"] = config.id
        }
        NotificationCenter.default.post(
            name: TriggerNodeNotifications.fired,
            object: nil,
            userInfo: userInfo
        )
    }
}

struct ButtonModuleView: View {
    let model: ButtonModuleModel
    let moduleNodeId: UUID
    let isLiveMode: Bool
    let onInternalCommand: (InternalButtonCommand, AppControlRefreshDeviceOptions, UUID) -> Void

    var body: some View {
        if let columnsPerRow = model.layout.columnsPerRow {
            // Fixed columns — grid layout (may not fill full height for partial rows)
            let columns = Array(repeating: GridItem(.flexible(), spacing: model.sharedStyle.buttonSpacing), count: max(1, columnsPerRow))
            LazyVGrid(columns: columns, spacing: model.sharedStyle.buttonSpacing) {
                ForEach(model.buttons) { config in
                    buttonItem(config)
                }
            }
        } else {
            // Auto — single row HStack fills full tile height
            HStack(spacing: model.sharedStyle.buttonSpacing) {
                ForEach(model.buttons) { config in
                    buttonItem(config)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func buttonItem(_ config: ButtonConfig) -> some View {
        ButtonItemView(
            config: config,
            sharedStyle: model.sharedStyle,
            moduleNodeId: moduleNodeId,
            buttonCount: model.buttons.count,
            isLiveMode: isLiveMode,
            onInternalCommand: onInternalCommand
        )
    }
}

fileprivate enum ButtonModuleResolvedIconContent {
    case symbol(String)
}

fileprivate enum ButtonModuleStatusBadgeStyle {
    case capsule(activeLabel: String, inactiveLabel: String)
    case pulse(activeLabel: String, inactiveLabel: String)
    case success(label: String)
    case failure(label: String)
}

// MARK: - Settings

struct ButtonModuleSettingsView: View {
    @Binding var model: ButtonModuleModel
    let onPersist: () -> Void

    @State private var midiDestinations: [MIDIDestinationOption] = []
    @State private var persistDebounceTask: Task<Void, Never>? = nil
    @State private var expandedButtonIDs: Set<UUID> = []
    @State private var expandedCommandIDs: Set<String> = []  // "configId:actionId"
    @State private var expandedStateSectionIDs: Set<UUID> = []
    @State private var expandedBehaviorSectionIDs: Set<UUID> = []
    @State private var expandedAvailabilitySectionIDs: Set<UUID> = []
    @State private var expandedFeedbackSectionIDs: Set<UUID> = []
    @State private var expandedActiveOverrideIDs: Set<UUID> = []
    @State private var expandedInactiveOverrideIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            inspectorCard(title: "Module Layout", subtitle: "Shared shape and spacing for all buttons in this module.") {
                moduleLayoutSection
            }

            inspectorCard(title: "Buttons", subtitle: "Each button can have its own commands, label, style, and behavior.") {
                buttonsSection
            }
        }
        .onAppear {
            midiDestinations = MIDIDestinationDiscovery.currentDestinations()
            if !model.buttons.isEmpty {
                expandedButtonIDs = [model.buttons[0].id]
            }
        }
        .onChange(of: model) { _, _ in
            persistDebounceTask?.cancel()
            persistDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                onPersist()
            }
        }
    }

    // MARK: - Module Layout Section

    private var moduleLayoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Corner Radius")
                Slider(value: $model.sharedStyle.cornerRadius, in: 0...40)
                DeferredNumberField(value: $model.sharedStyle.cornerRadius, formatter: numberFormatter)
                    .frame(width: 48)
            }
            HStack {
                Text("Horizontal Padding")
                Slider(value: $model.sharedStyle.horizontalPadding, in: 0...40)
                DeferredNumberField(value: $model.sharedStyle.horizontalPadding, formatter: numberFormatter)
                    .frame(width: 48)
            }
            HStack {
                Text("Vertical Padding")
                Slider(value: $model.sharedStyle.verticalPadding, in: 0...30)
                DeferredNumberField(value: $model.sharedStyle.verticalPadding, formatter: numberFormatter)
                    .frame(width: 48)
            }
            HStack {
                Text("Button Spacing")
                Slider(value: $model.sharedStyle.buttonSpacing, in: 0...24)
                DeferredNumberField(value: $model.sharedStyle.buttonSpacing, formatter: numberFormatter)
                    .frame(width: 48)
            }

            Divider()

            Toggle("Fixed Columns Per Row", isOn: Binding(
                get: { model.layout.columnsPerRow != nil },
                set: { enabled in
                    model.layout.columnsPerRow = enabled ? 2 : nil
                    onPersist()
                }
            ))

            if let columns = model.layout.columnsPerRow {
                Stepper("Columns: \(columns)", value: Binding(
                    get: { columns },
                    set: { model.layout.columnsPerRow = max(1, $0); onPersist() }
                ), in: 1...8)
            }
        }
        .toggleStyle(.switch)
    }

    // MARK: - Buttons Section

    private var buttonsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(model.buttons.enumerated()), id: \.element.id) { index, _ in
                buttonAccordionCard(at: index)
            }

            Button {
                addButton()
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Add Button")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func buttonAccordionCard(at index: Int) -> some View {
        let entry = buttonBinding(at: index)
        let isExpanded = Binding<Bool>(
            get: { expandedButtonIDs.contains(entry.wrappedValue.id) },
            set: { newValue in
                if newValue { expandedButtonIDs.insert(entry.wrappedValue.id) }
                else { expandedButtonIDs.remove(entry.wrappedValue.id) }
            }
        )
        let titleDisplay = entry.wrappedValue.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let headerLabel = titleDisplay.isEmpty ? "Button \(index + 1)" : "Button \(index + 1) — \(titleDisplay)"

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    isExpanded.wrappedValue.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                        Text(headerLabel)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    Button {
                        moveButton(at: index, direction: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Move up")
                    .disabled(index == 0)

                    Button {
                        moveButton(at: index, direction: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Move down")
                    .disabled(index == model.buttons.count - 1)
                }

                Button {
                    removeButton(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove button")
                .disabled(model.buttons.count <= 1)
            }
            .padding(10)

            if isExpanded.wrappedValue {
                buttonSettingsBody(for: entry)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func buttonBinding(at index: Int) -> Binding<ButtonConfig> {
        Binding(
            get: {
                guard model.buttons.indices.contains(index) else { return ButtonConfig() }
                return model.buttons[index]
            },
            set: { newValue in
                guard model.buttons.indices.contains(index) else { return }
                model.buttons[index] = newValue
            }
        )
    }

    private func addButton() {
        model.buttons.append(ButtonConfig(title: "Button \(model.buttons.count + 1)"))
        onPersist()
    }

    private func moveButton(at index: Int, direction: Int) {
        let target = index + direction
        guard model.buttons.indices.contains(index), model.buttons.indices.contains(target) else { return }
        model.buttons.swapAt(index, target)
        onPersist()
    }

    private func removeButton(at index: Int) {
        guard model.buttons.count > 1, model.buttons.indices.contains(index) else { return }
        model.buttons.remove(at: index)
        onPersist()
    }

    @ViewBuilder
    private func buttonSettingsBody(for entry: Binding<ButtonConfig>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            inspectorCard(title: "Commands", subtitle: "What this button does when pressed.") {
                buttonCommandsSection(for: entry)
            }
            inspectorCard(title: "Label & Icon", subtitle: "The visible label, subtitle, and icon.") {
                buttonBasicsSection(for: entry)
            }
            inspectorCard(title: "Color", subtitle: "Background tint, border, text, and icon colors for this button.") {
                buttonColorSection(for: entry)
            }
            inspectorCard(title: "State Display", subtitle: "Optional live state reflection.") {
                tappableDisclosure(title: "Show State Options", isExpanded: stateExpanded(for: entry)) {
                    buttonStateSection(for: entry)
                }
            }
            inspectorCard(title: "Interaction", subtitle: "Toggle mode, confirmation, cooldowns.") {
                VStack(alignment: .leading, spacing: 10) {
                    tappableDisclosure(title: "Behavior", isExpanded: behaviorExpanded(for: entry)) {
                        buttonBehaviorSection(for: entry)
                    }
                    tappableDisclosure(title: "Availability", isExpanded: availabilityExpanded(for: entry)) {
                        buttonAvailabilitySection(for: entry)
                    }
                }
            }
            inspectorCard(title: "Feedback", subtitle: "Animations and indicators.") {
                tappableDisclosure(title: "Feedback", isExpanded: feedbackExpanded(for: entry)) {
                    buttonFeedbackSection(for: entry)
                }
            }
        }
    }

    // MARK: - Expansion Helpers

    private func stateExpanded(for entry: Binding<ButtonConfig>) -> Binding<Bool> {
        Binding(
            get: { expandedStateSectionIDs.contains(entry.wrappedValue.id) },
            set: { if $0 { expandedStateSectionIDs.insert(entry.wrappedValue.id) } else { expandedStateSectionIDs.remove(entry.wrappedValue.id) } }
        )
    }

    private func behaviorExpanded(for entry: Binding<ButtonConfig>) -> Binding<Bool> {
        Binding(
            get: { expandedBehaviorSectionIDs.contains(entry.wrappedValue.id) },
            set: { if $0 { expandedBehaviorSectionIDs.insert(entry.wrappedValue.id) } else { expandedBehaviorSectionIDs.remove(entry.wrappedValue.id) } }
        )
    }

    private func availabilityExpanded(for entry: Binding<ButtonConfig>) -> Binding<Bool> {
        Binding(
            get: { expandedAvailabilitySectionIDs.contains(entry.wrappedValue.id) },
            set: { if $0 { expandedAvailabilitySectionIDs.insert(entry.wrappedValue.id) } else { expandedAvailabilitySectionIDs.remove(entry.wrappedValue.id) } }
        )
    }

    private func feedbackExpanded(for entry: Binding<ButtonConfig>) -> Binding<Bool> {
        Binding(
            get: { expandedFeedbackSectionIDs.contains(entry.wrappedValue.id) },
            set: { if $0 { expandedFeedbackSectionIDs.insert(entry.wrappedValue.id) } else { expandedFeedbackSectionIDs.remove(entry.wrappedValue.id) } }
        )
    }

    // MARK: - Commands Section

    private func buttonCommandsSection(for entry: Binding<ButtonConfig>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    let count = entry.wrappedValue.actions.count
                    Text(count == 0 ? "No commands configured" : "\(count) command\(count == 1 ? "" : "s") configured")
                        .font(.subheadline.weight(.semibold))
                    Text("You can trigger one action or stack several in order.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { addButtonCommand(entry: entry) } label: {
                    Label("Add Command", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.bordered)
            }

            if entry.wrappedValue.actions.isEmpty {
                Text("No commands. Pressing this button will only fire automations linked in the graph.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
            } else {
                ForEach(Array(entry.wrappedValue.actions.enumerated()), id: \.element.id) { index, _ in
                    buttonCommandEditorCard(entry: entry, at: index)
                }
            }
        }
    }

    private func addButtonCommand(entry: Binding<ButtonConfig>) {
        entry.wrappedValue.actions.append(ButtonActionEntry())
        onPersist()
    }

    private func removeButtonCommand(entry: Binding<ButtonConfig>, at index: Int) {
        guard entry.wrappedValue.actions.indices.contains(index) else { return }
        entry.wrappedValue.actions.remove(at: index)
        onPersist()
    }

    @ViewBuilder
    private func buttonCommandEditorCard(entry: Binding<ButtonConfig>, at index: Int) -> some View {
        let actionEntry = buttonActionBinding(entry: entry, at: index)
        let expandedKey = "\(entry.wrappedValue.id):\(actionEntry.wrappedValue.id)"
        let isExpanded = Binding<Bool>(
            get: { expandedCommandIDs.contains(expandedKey) },
            set: { newValue in
                if newValue { expandedCommandIDs.insert(expandedKey) }
                else { expandedCommandIDs.remove(expandedKey) }
            }
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    isExpanded.wrappedValue.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Command \(index + 1)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(commandSummary(for: actionEntry.wrappedValue))
                                .font(.subheadline).foregroundStyle(.primary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    removeButtonCommand(entry: entry, at: index)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove command")
            }

            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Command Type", selection: buttonCommandKindBinding(for: actionEntry)) {
                        ForEach(ButtonModuleActionKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    buttonActionDetailSection(for: actionEntry)
                }
                .padding(.top, 8)
                .padding(.leading, 22)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func buttonActionBinding(entry: Binding<ButtonConfig>, at index: Int) -> Binding<ButtonActionEntry> {
        Binding(
            get: {
                guard entry.wrappedValue.actions.indices.contains(index) else { return ButtonActionEntry() }
                return entry.wrappedValue.actions[index]
            },
            set: { newValue in
                guard entry.wrappedValue.actions.indices.contains(index) else { return }
                entry.wrappedValue.actions[index] = newValue
                onPersist()
            }
        )
    }

    private func buttonCommandKindBinding(for actionEntry: Binding<ButtonActionEntry>) -> Binding<ButtonModuleActionKind> {
        Binding<ButtonModuleActionKind>(
            get: { actionEntry.wrappedValue.action.kind },
            set: { newValue in
                guard newValue != actionEntry.wrappedValue.action.kind else { return }
                var updated = actionEntry.wrappedValue
                switch newValue {
                case .internalCommand: updated.action = .internalCommand(.resetSpl)
                case .osc: updated.action = .osc(OSCButtonAction())
                case .midi: updated.action = .midi(MIDIButtonAction())
                }
                actionEntry.wrappedValue = updated
            }
        )
    }

    @ViewBuilder
    private func buttonActionDetailSection(for actionEntry: Binding<ButtonActionEntry>) -> some View {
        switch actionEntry.wrappedValue.action {
        case .internalCommand(let command):
            VStack(alignment: .leading, spacing: 10) {
                Picker("Command", selection: buttonInternalCommandBinding(actionEntry)) {
                    ForEach(InternalButtonCommand.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                if command == .resyncDeviceNames {
                    NameRefreshDeviceOptionsEditor(options: buttonRefreshOptionsBinding(actionEntry))
                }
            }
        case .osc:
            buttonOscSettingsSection(actionEntry)
        case .midi:
            buttonMidiSettingsSection(actionEntry)
        }
    }

    private func buttonInternalCommandBinding(_ entry: Binding<ButtonActionEntry>) -> Binding<InternalButtonCommand> {
        Binding(
            get: { if case .internalCommand(let c) = entry.wrappedValue.action { return c }; return .resetSpl },
            set: { var u = entry.wrappedValue; u.action = .internalCommand($0); entry.wrappedValue = u }
        )
    }

    private func buttonRefreshOptionsBinding(_ entry: Binding<ButtonActionEntry>) -> Binding<AppControlRefreshDeviceOptions> {
        Binding(
            get: { entry.wrappedValue.appControlRefreshDeviceOptions },
            set: { var u = entry.wrappedValue; u.appControlRefreshDeviceOptions = $0; entry.wrappedValue = u }
        )
    }

    // MARK: - OSC Settings

    @ViewBuilder
    private func buttonOscSettingsSection(_ entry: Binding<ButtonActionEntry>) -> some View {
        let binding = buttonOscActionBinding(entry)
        VStack(alignment: .leading, spacing: 10) {
            TextField("Host", text: Binding(
                get: { binding.wrappedValue.endpoint.host },
                set: { var u = binding.wrappedValue; u.endpoint.host = $0; binding.wrappedValue = u }
            ))
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                DeferredNumberField("Port", value: Binding<Int>(
                    get: { Int(binding.wrappedValue.endpoint.port) },
                    set: { var u = binding.wrappedValue; u.endpoint.port = UInt16(max(1, min(65535, $0))); binding.wrappedValue = u }
                ), formatter: Self.oscPortFormatter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)

                TextField("Address", text: Binding(
                    get: { binding.wrappedValue.address },
                    set: { var u = binding.wrappedValue; u.address = $0; binding.wrappedValue = u }
                ))
                .textFieldStyle(.roundedBorder)
            }

            Picker("Argument", selection: buttonOscArgumentKindBinding(binding)) {
                ForEach(OSCButtonArgumentKind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            .pickerStyle(.segmented)

            buttonOscArgumentEditor(for: binding)
        }
    }

    private func buttonOscActionBinding(_ entry: Binding<ButtonActionEntry>) -> Binding<OSCButtonAction> {
        Binding(
            get: { if case .osc(let a) = entry.wrappedValue.action { return a }; return OSCButtonAction() },
            set: { var u = entry.wrappedValue; u.action = .osc($0); entry.wrappedValue = u }
        )
    }

    private func buttonOscArgumentKindBinding(_ binding: Binding<OSCButtonAction>) -> Binding<OSCButtonArgumentKind> {
        Binding(
            get: {
                switch binding.wrappedValue.argument {
                case .int: return .int
                case .float: return .float
                case .string: return .string
                case .bool: return .bool
                case .none: return .none
                }
            },
            set: { newKind in
                var u = binding.wrappedValue
                switch newKind {
                case .none: u.argument = nil
                case .int: u.argument = .int(0)
                case .float: u.argument = .float(0)
                case .string: u.argument = .string("")
                case .bool: u.argument = .bool(false)
                }
                binding.wrappedValue = u
            }
        )
    }

    @ViewBuilder
    private func buttonOscArgumentEditor(for binding: Binding<OSCButtonAction>) -> some View {
        switch binding.wrappedValue.argument {
        case .int(let v):
            DeferredNumberField("Value", value: Binding(get: { v }, set: { var u = binding.wrappedValue; u.argument = .int($0); binding.wrappedValue = u }), formatter: Self.oscArgumentIntFormatter).textFieldStyle(.roundedBorder)
        case .float(let v):
            DeferredNumberField("Value", value: Binding(get: { v }, set: { var u = binding.wrappedValue; u.argument = .float($0); binding.wrappedValue = u }), formatter: Self.oscArgumentFloatFormatter).textFieldStyle(.roundedBorder)
        case .string(let v):
            TextField("Value", text: Binding(get: { v }, set: { var u = binding.wrappedValue; u.argument = .string($0); binding.wrappedValue = u })).textFieldStyle(.roundedBorder)
        case .bool(let v):
            Toggle("Value", isOn: Binding(get: { v }, set: { var u = binding.wrappedValue; u.argument = .bool($0); binding.wrappedValue = u }))
        case .none:
            EmptyView()
        }
    }

    // MARK: - MIDI Settings

    @ViewBuilder
    private func buttonMidiSettingsSection(_ entry: Binding<ButtonActionEntry>) -> some View {
        let binding = buttonMidiActionBinding(entry)
        VStack(alignment: .leading, spacing: 10) {
            Picker("Destination", selection: Binding<Int32?>(
                get: { binding.wrappedValue.destinationID },
                set: { var u = binding.wrappedValue; u.destinationID = $0; binding.wrappedValue = u }
            )) {
                Text("Default").tag(Int32?.none)
                ForEach(midiDestinations) { dest in Text(dest.name).tag(Optional(dest.id)) }
            }

            Picker("Message", selection: Binding<MIDIMessageKind>(
                get: { binding.wrappedValue.kind },
                set: { var u = binding.wrappedValue; u.kind = $0; binding.wrappedValue = u }
            )) {
                ForEach(MIDIMessageKind.allCases, id: \.self) { kind in Text(kind.label).tag(kind) }
            }

            HStack(spacing: 12) {
                Text("Channel")
                Stepper(value: Binding<Int>(
                    get: { binding.wrappedValue.channel },
                    set: { var u = binding.wrappedValue; u.channel = $0; binding.wrappedValue = u }
                ), in: 1...16) { Text("\(binding.wrappedValue.channel)") }
            }

            switch binding.wrappedValue.kind {
            case .noteOn, .noteOff:
                HStack(spacing: 12) {
                    Text("Note")
                    Stepper(value: Binding<Int>(get: { binding.wrappedValue.note }, set: { var u = binding.wrappedValue; u.note = $0; binding.wrappedValue = u }), in: 0...127) { Text("\(binding.wrappedValue.note)") }
                }
                HStack(spacing: 12) {
                    Text("Velocity")
                    Stepper(value: Binding<Int>(get: { binding.wrappedValue.velocity }, set: { var u = binding.wrappedValue; u.velocity = $0; binding.wrappedValue = u }), in: 0...127) { Text("\(binding.wrappedValue.velocity)") }
                }
            case .controlChange:
                HStack(spacing: 12) {
                    Text("Control")
                    Stepper(value: Binding<Int>(get: { binding.wrappedValue.control }, set: { var u = binding.wrappedValue; u.control = $0; binding.wrappedValue = u }), in: 0...127) { Text("\(binding.wrappedValue.control)") }
                }
                HStack(spacing: 12) {
                    Text("Value")
                    Stepper(value: Binding<Int>(get: { binding.wrappedValue.value }, set: { var u = binding.wrappedValue; u.value = $0; binding.wrappedValue = u }), in: 0...127) { Text("\(binding.wrappedValue.value)") }
                }
            case .programChange:
                HStack(spacing: 12) {
                    Text("Program")
                    Stepper(value: Binding<Int>(get: { binding.wrappedValue.program }, set: { var u = binding.wrappedValue; u.program = $0; binding.wrappedValue = u }), in: 0...127) { Text("\(binding.wrappedValue.program)") }
                }
            case .sysex:
                Text("Sysex messages are not supported in the button module yet.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func buttonMidiActionBinding(_ entry: Binding<ButtonActionEntry>) -> Binding<MIDIButtonAction> {
        Binding(
            get: { if case .midi(let a) = entry.wrappedValue.action { return a }; return MIDIButtonAction() },
            set: { var u = entry.wrappedValue; u.action = .midi($0); entry.wrappedValue = u }
        )
    }

    // MARK: - Label & Icon Section

    private func buttonBasicsSection(for entry: Binding<ButtonConfig>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Button label", text: entry.title)
                .textFieldStyle(.roundedBorder)
            TextField("Subtitle (optional)", text: entry.subtitle)
                .textFieldStyle(.roundedBorder)

            Picker("Icon", selection: iconSourceBinding(for: entry)) {
                ForEach(visibleIconSources) { source in Text(source.title).tag(source) }
            }
            .pickerStyle(.segmented)

            switch iconSourceBinding(for: entry).wrappedValue {
            case .none:
                Text("No icon will be shown.").font(.caption).foregroundStyle(.secondary)
            default:
                SymbolPickerTrigger(symbolName: entry.wrappedValue.icon.systemName) { name in
                    var updatedIcon = entry.wrappedValue.icon
                    updatedIcon.systemName = name
                    updatedIcon.source = .symbol
                    entry.wrappedValue.icon = updatedIcon
                }
            }

            if entry.wrappedValue.icon.source != .none {
                Picker("Icon Placement", selection: entry.icon.placement) {
                    ForEach(ButtonModuleIconPlacement.allCases) { p in Text(p.title).tag(p) }
                }
                IconSizeSlider(size: entry.icon.size)
            }
        }
    }

    // MARK: - Color Section

    private func buttonColorSection(for entry: Binding<ButtonConfig>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            colorRow(title: "Background Tint", color: Binding(
                get: { entry.wrappedValue.color.backgroundColor.swiftUIColor },
                set: { entry.wrappedValue.color.backgroundColor = CodableColor($0); onPersist() }
            ))
            colorRow(title: "Border", color: Binding(
                get: { entry.wrappedValue.color.borderColor.swiftUIColor },
                set: { entry.wrappedValue.color.borderColor = CodableColor($0); onPersist() }
            ))
            colorRow(title: "Title Text", color: Binding(
                get: { entry.wrappedValue.color.titleColor.swiftUIColor },
                set: { entry.wrappedValue.color.titleColor = CodableColor($0); onPersist() }
            ))
            colorRow(title: "Subtitle Text", color: Binding(
                get: { entry.wrappedValue.color.subtitleColor.swiftUIColor },
                set: { entry.wrappedValue.color.subtitleColor = CodableColor($0); onPersist() }
            ))
            colorRow(title: "Icon", color: Binding(
                get: { entry.wrappedValue.color.iconColor?.swiftUIColor ?? entry.wrappedValue.color.titleColor.swiftUIColor },
                set: { entry.wrappedValue.color.iconColor = CodableColor($0); onPersist() }
            ))
        }
    }

    // MARK: - State Section

    private func buttonStateSection(for entry: Binding<ButtonConfig>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Visual State", selection: entry.statePresentation.source) {
                ForEach(ButtonModuleStateSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.menu)

            if entry.wrappedValue.statePresentation.source != .none {
                if entry.wrappedValue.statePresentation.source == .selectedTab {
                    Stepper(value: entry.statePresentation.selectedTabIndex, in: 1...128) {
                        Text("Tab Index: \(entry.wrappedValue.statePresentation.selectedTabIndex)")
                    }
                }
                Toggle("Show state badge", isOn: entry.statePresentation.showsBadge)

                tappableDisclosure(title: "Customize Active State", isExpanded: Binding(
                    get: { expandedActiveOverrideIDs.contains(entry.wrappedValue.id)
                        || !entry.wrappedValue.statePresentation.activeTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !entry.wrappedValue.statePresentation.activeSubtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !entry.wrappedValue.statePresentation.activeIconToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                    set: { newValue in
                        if newValue {
                            expandedActiveOverrideIDs.insert(entry.wrappedValue.id)
                        } else {
                            expandedActiveOverrideIDs.remove(entry.wrappedValue.id)
                            entry.wrappedValue.statePresentation.activeTitle = ""
                            entry.wrappedValue.statePresentation.activeSubtitle = ""
                            entry.wrappedValue.statePresentation.activeIconToken = ""
                            onPersist()
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Active Overrides").font(.caption).foregroundStyle(.secondary)
                        TextField("Label override", text: entry.statePresentation.activeTitle).textFieldStyle(.roundedBorder)
                        TextField("Subtitle override", text: entry.statePresentation.activeSubtitle).textFieldStyle(.roundedBorder)
                        TextField("Icon override (SF Symbol name)", text: entry.statePresentation.activeIconToken).textFieldStyle(.roundedBorder)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
                }

                tappableDisclosure(title: "Customize Inactive State", isExpanded: Binding(
                    get: { expandedInactiveOverrideIDs.contains(entry.wrappedValue.id)
                        || !entry.wrappedValue.statePresentation.inactiveTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !entry.wrappedValue.statePresentation.inactiveSubtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !entry.wrappedValue.statePresentation.inactiveIconToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                    set: { newValue in
                        if newValue {
                            expandedInactiveOverrideIDs.insert(entry.wrappedValue.id)
                        } else {
                            expandedInactiveOverrideIDs.remove(entry.wrappedValue.id)
                            entry.wrappedValue.statePresentation.inactiveTitle = ""
                            entry.wrappedValue.statePresentation.inactiveSubtitle = ""
                            entry.wrappedValue.statePresentation.inactiveIconToken = ""
                            onPersist()
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Inactive Overrides").font(.caption).foregroundStyle(.secondary)
                        TextField("Label override", text: entry.statePresentation.inactiveTitle).textFieldStyle(.roundedBorder)
                        TextField("Subtitle override", text: entry.statePresentation.inactiveSubtitle).textFieldStyle(.roundedBorder)
                        TextField("Icon override (SF Symbol name)", text: entry.statePresentation.inactiveIconToken).textFieldStyle(.roundedBorder)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
                }
            } else {
                Text("This button will keep the same label and icon all the time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Behavior Section

    private func buttonBehaviorSection(for entry: Binding<ButtonConfig>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Interaction", selection: entry.behavior.interactionMode) {
                ForEach(ButtonModuleInteractionMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented)

            Toggle("Require confirmation", isOn: entry.behavior.requiresConfirmation)
            if entry.wrappedValue.behavior.requiresConfirmation {
                TextField("Confirmation title", text: entry.behavior.confirmationTitle).textFieldStyle(.roundedBorder)
                TextField("Confirmation message", text: entry.behavior.confirmationMessage).textFieldStyle(.roundedBorder)
            }

            Toggle("Allow while editing", isOn: entry.behavior.allowsTriggerWhileEditing)

            HStack {
                Text("Cooldown")
                Slider(value: entry.behavior.cooldownSeconds, in: 0...10, step: 0.25)
                DeferredNumberField(value: entry.behavior.cooldownSeconds, formatter: numberFormatter).frame(width: 48)
                Text("sec").foregroundStyle(.secondary)
            }

            HStack {
                Text("Delay Between Commands")
                Slider(
                    value: Binding(
                        get: { Double(entry.wrappedValue.behavior.commandDelayMilliseconds) },
                        set: { entry.wrappedValue.behavior.commandDelayMilliseconds = Int($0.rounded()) }
                    ),
                    in: 0...2000, step: 50
                )
                Text("\(entry.wrappedValue.behavior.commandDelayMilliseconds) ms")
                    .foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
            }
        }
        .toggleStyle(.switch)
    }

    // MARK: - Availability Section

    private func buttonAvailabilitySection(for entry: Binding<ButtonConfig>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Live Mode Access", selection: entry.availability.liveModeRequirement) {
                ForEach(ButtonModuleLiveModeRequirement.allCases) { r in Text(r.title).tag(r) }
            }
            Picker("State Requirement", selection: entry.availability.stateRequirement) {
                ForEach(ButtonModuleStateRequirement.allCases) { r in Text(r.title).tag(r) }
            }
            Toggle("Disable while running", isOn: entry.availability.disablesWhileRunning)
            Toggle("Disable during cooldown", isOn: entry.availability.disablesDuringCooldown)
        }
        .toggleStyle(.switch)
    }

    // MARK: - Feedback Section

    private func buttonFeedbackSection(for entry: Binding<ButtonConfig>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Animate press", isOn: entry.feedback.animatePress)
            Toggle("Show running indicator", isOn: entry.feedback.showsRunningIndicator)
            Toggle("Show result badge", isOn: entry.feedback.showsResultBadge)
            if entry.wrappedValue.feedback.showsResultBadge {
                HStack {
                    Text("Result Badge Duration")
                    Slider(value: entry.feedback.resultBadgeDurationSeconds, in: 0.25...5, step: 0.25)
                    DeferredNumberField(value: entry.feedback.resultBadgeDurationSeconds, formatter: numberFormatter).frame(width: 48)
                    Text("sec").foregroundStyle(.secondary)
                }
            }
            Toggle("Emit detailed automation events", isOn: entry.feedback.emitsDetailedEvents)
            Text("Detailed events include button down, up, toggled on, toggled off, and press.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
    }

    // MARK: - Command Summary

    private func commandSummary(for entry: ButtonActionEntry) -> String {
        switch entry.action {
        case .internalCommand(let command): return command.title
        case .osc(let action):
            let address = action.address.trimmingCharacters(in: .whitespacesAndNewlines)
            return address.isEmpty ? "OSC Command" : "OSC \(address)"
        case .midi(let action): return "MIDI \(action.kind.label)"
        }
    }

    // MARK: - Helper Views

    private func inspectorCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func tappableDisclosure<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        showsChevron: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if showsChevron {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    if showsChevron {
                        Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                    }
                    Text(title)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !showsChevron || isExpanded.wrappedValue {
                content()
                    .padding(.top, 10)
                    .padding(.leading, showsChevron ? 22 : 0)
            }
        }
    }

    private func colorRow(title: String, color: Binding<Color>) -> some View {
        HStack {
            Text(title)
            Spacer()
            ColorPicker("", selection: color, supportsOpacity: true)
                .labelsHidden()
        }
    }

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.decimalSeparator = "."
        return formatter
    }

    private static let oscPortFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.usesGroupingSeparator = false
        formatter.minimum = 1
        formatter.maximum = 65535
        return formatter
    }()

    private static let oscArgumentIntFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    private static let oscArgumentFloatFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    private var visibleIconSources: [ButtonModuleIconSource] {
        [.none, .symbol]
    }

    private func iconSourceBinding(for entry: Binding<ButtonConfig>) -> Binding<ButtonModuleIconSource> {
        Binding<ButtonModuleIconSource>(
            get: {
                switch entry.wrappedValue.icon.source {
                case .none: return .none
                default: return .symbol
                }
            },
            set: { newValue in
                entry.wrappedValue.icon.source = newValue
            }
        )
    }
}

// MARK: - Symbol Picker Trigger

private struct SymbolPickerTrigger: View {
    var symbolName: String
    var onSelect: (String) -> Void

    @State private var showsPicker = false
    @State private var liveSymbolName: String = ""

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 48, height: 48)
                let displayed = showsPicker ? liveSymbolName : symbolName
                let trimmed = displayed.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: trimmed)
                        .font(.system(size: 32))
                        .foregroundStyle(.primary)
                }
            }

            Button("Change…") {
                liveSymbolName = symbolName
                showsPicker = true
            }
            .buttonStyle(.bordered)
        }
        .popover(isPresented: $showsPicker) {
            SFSymbolPickerView(selectedSymbolName: $liveSymbolName) { name in
                liveSymbolName = name
                onSelect(name)
                showsPicker = false
            }
        }
    }
}

// MARK: - Icon Size Slider

private struct IconSizeSlider: View {
    @Binding var size: Double

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    var body: some View {
        HStack {
            Text("Icon Size")
            Slider(value: $size, in: 8...72)
            DeferredNumberField(value: $size, formatter: Self.formatter)
                .frame(width: 48)
            Button {
                size = 18
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .help("Reset icon size to default")
        }
    }
}

// MARK: - Helpers

enum ButtonModuleActionKind: String, CaseIterable, Identifiable {
    case internalCommand
    case osc
    case midi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .internalCommand: return "Internal"
        case .osc: return "OSC"
        case .midi: return "MIDI"
        }
    }
}

enum OSCButtonArgumentKind: String, CaseIterable, Identifiable {
    case none
    case int
    case float
    case string
    case bool

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .int: return "Int"
        case .float: return "Float"
        case .string: return "String"
        case .bool: return "Bool"
        }
    }
}

extension ButtonModuleAction {
    var kind: ButtonModuleActionKind {
        switch self {
        case .internalCommand:
            return .internalCommand
        case .osc:
            return .osc
        case .midi:
            return .midi
        }
    }
}

extension OSCButtonArgument {
    var oscValue: OSCValue {
        switch self {
        case .int(let value):
            return .int32(Int32(value))
        case .float(let value):
            return .float32(Float(value))
        case .string(let value):
            return .string(value)
        case .bool(let value):
            return .bool(value)
        }
    }
}

extension MIDIMessageKind {
    var label: String {
        switch self {
        case .noteOn: return "Note On"
        case .noteOff: return "Note Off"
        case .programChange: return "Program Change"
        case .controlChange: return "Control Change"
        case .sysex: return "Sysex"
        }
    }
}

extension MIDIButtonAction {
    var midiBytes: [UInt8] {
        let channelByte = UInt8(max(0, min(15, channel - 1)))
        switch kind {
        case .noteOn:
            return [0x90 | channelByte, UInt8(clamp(note)), UInt8(clamp(velocity))]
        case .noteOff:
            return [0x80 | channelByte, UInt8(clamp(note)), UInt8(clamp(velocity))]
        case .controlChange:
            return [0xB0 | channelByte, UInt8(clamp(control)), UInt8(clamp(value))]
        case .programChange:
            return [0xC0 | channelByte, UInt8(clamp(program))]
        case .sysex:
            return []
        }
    }

    private func clamp(_ value: Int) -> Int {
        max(0, min(127, value))
    }
}

// MARK: - Plugin Glue

enum ButtonModulePlugin: DashboardModulePlugin {
    static var kind: DashboardModuleKind { .button(ButtonModuleModel()) }

    static func tileView(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) -> AnyView {
        let model: ButtonModuleModel
        if case .button(let m) = module.wrappedValue.kind {
            model = m
        } else {
            model = ButtonModuleModel()
        }
        let handleInternalCommand: (InternalButtonCommand, AppControlRefreshDeviceOptions, UUID) -> Void = { command, refreshDeviceOptions, buttonConfigId in
            var userInfo: [String: Any] = [
                ActionNodeUserInfoKeys.nodeId: module.wrappedValue.id,
                ActionNodeUserInfoKeys.appActionKind: command.appControlActionKind.rawValue,
                "buttonConfigId": buttonConfigId
            ]
            if command == .resyncDeviceNames {
                userInfo[ActionNodeUserInfoKeys.refreshTargetScope] = refreshDeviceOptions.targetScope.rawValue
                userInfo[ActionNodeUserInfoKeys.selectedDeviceIDs] = refreshDeviceOptions.selectedDeviceIDs.map(\.uuidString)
            }

            NotificationCenter.default.post(
                name: ActionNodeNotifications.appControl,
                object: nil,
                userInfo: userInfo
            )
        }
        return AnyView(
            ButtonModuleView(
                model: model,
                moduleNodeId: module.wrappedValue.id,
                isLiveMode: isLiveMode,
                onInternalCommand: handleInternalCommand
            )
            .id(module.wrappedValue.id)
        )
    }

    static func settingsView(
        showsHeader: Binding<Bool>,
        onPersist: @escaping () -> Void
    ) -> AnyView {
        AnyView(EmptyView())
    }
}
