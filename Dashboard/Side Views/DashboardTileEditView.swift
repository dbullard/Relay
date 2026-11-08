//
//  DashboardTileEditView.swift
//  Relay
//
//  Created by David Bullard on 11/20/25.
//


import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import Combine

#if os(iOS)
import UIKit
#endif

#if os(macOS)
import AppKit
import CoreAudio
#endif

// MARK: - Tile Edit View

struct DashboardTileEditView: View {
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif

    /// UI default shown in the Height slider when the module is in Auto mode (moduleHeightPoints == nil).
    private func defaultModuleHeightDisplayPoints(for module: DashboardModuleModel) -> CGFloat {
        let minHeight = minimumHeightPoints(for: module)
        if case .separator = module.kind {
            return max(minHeight, minHeight + 8)
        }
        let padded = minHeight + 40
        return max(minHeight, padded)
    }
    /// Dynamic minimum height per module (pt). This is a UX safeguard to prevent accidental clipping.
    /// Heuristic-based; can be refined or made measurement-driven later.
    private func minimumHeightPoints(for module: DashboardModuleModel) -> CGFloat {
        switch module.kind {
        case .separator:
            return 6
        case .time, .timecode, .dawTransport:
            return 60
        case .rosterPicker:
            return 72
        case .person:
            return 84
        case .pcoRundown, .pcoTeamAssignments, .rosterTeamAssignments:
            return 96
        case .text:
            return 72
        case .shureWireless, .shureOverview, .sennheiserWireless:
            return 110
        case .proPresenter:
            return 88
        case .resolume:
            return 72
        case .liveTranscription:
            return 160
        case .dbReader:
            return 180
        case .image:
            return 120
        case .document:
            return 120
        case .ndi:
            return 120
        case .webpage:
            return 120
        case .youtubeStreamMonitor:
            return 96
        case .button:
            return 64
        case .rta:
            return 120
        case .spectrograph:
            return 120
        }
    }

    #if os(iOS)
    private var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var isIPadRegularWidth: Bool { isIPad && (horizontalSizeClass != .compact) }
    /// Slightly tighter density on iPad so it matches macOS better.
    private var iPadUIScale: CGFloat { isIPadRegularWidth ? 0.9 : 1.0 }
    private var contentHPadding: CGFloat { isIPadRegularWidth ? 16 : 20 }
    private var contentVPadding: CGFloat { isIPadRegularWidth ? 14 : 18 }
    private var groupSpacing: CGFloat { isIPadRegularWidth ? 12 : 16 }
    private var secondaryLabelFont: Font { isIPadRegularWidth ? .footnote : .caption }
    private var tertiaryLabelFont: Font { isIPadRegularWidth ? .caption : .caption2 }
    #endif
    let tileID: UUID
    /// Optional: the current tile height in points (if the parent can provide it).
    /// When present, we can warn if a module's fixed Height exceeds the tile height.
    let tileHeightPoints: CGFloat?
    let isMultiTileEdit: Bool
    let initialPerson: PersonTileModel?
    let hasPCORundown: Bool
    let hasShureWireless: Bool

    let initialBackgroundStyle: TileBackgroundStyle
    let initialBackgroundOpacity: Double
    let initialCornerRadius: CGFloat
    let initialBackgroundColor: CodableColor?
    let initialBackgroundGradient: TileGradientBackground?
    let initialTileContentPaddingValue: CGFloat
    let initialModuleLayout: TileModuleLayout
    let initialShureSelection: ExternalDevicesStore.ShureSelectedChannel?
    let onUpdatePCOModuleConfig: (UUID, PCOModuleConfig) -> Void
    let onUpdateShureModuleConfig: (UUID, ShureModuleConfig) -> Void
    /// Current modules on this tile, in any order. The inspector will sort by
    /// `order` for display.
    let modules: [DashboardModuleModel]

    /// Callback for reordering modules by dragging in the inspector. The closure
    /// is given the module id and the new index in the sorted order.
    let onMoveModule: (UUID, Int) -> Void

    /// Callback for adding a new module of the given kind to this tile.
    let onAddModule: (DashboardModuleKind) -> Void

    /// Callback for removing a module instance by id.
    let onRemoveModule: (UUID) -> Void
    /// Callback for duplicating a module (clone settings).
    let onDuplicateModule: (UUID) -> Void

    /// Callback for updating an existing Text module configuration.
    let onUpdateTextModule: (UUID, TextModuleModel) -> Void
    let onUpdateImageModule: (UUID, ImageModuleModel) -> Void
    let onUpdateDocumentModule: (UUID, DocumentModuleModel) -> Void
    let onUpdateNDIModule: (UUID, NDIModuleModel) -> Void
    let onUpdateWebpageModule: (UUID, WebpageModuleModel) -> Void
    let onUpdateYouTubeStreamMonitorModule: (UUID, YouTubeStreamMonitorModuleModel) -> Void
    /// Callback for updating an existing Button module configuration.
    let onUpdateButtonModule: (UUID, ButtonModuleModel) -> Void
    let onUpdateRosterPickerModule: (UUID, RosterPickerModuleModel) -> Void
    let onUpdateSeparator: (UUID, SeparatorModuleModel) -> Void
    let onOpenPCOTabSettings: () -> Void
    let onUpdateTimeModuleConfig: (UUID, TimeModuleConfig) -> Void
    let onUpdateTimecodeModuleConfig: (UUID, TimecodeModuleConfig) -> Void
    let onUpdateDAWTransportModuleConfig: (UUID, DAWTransportModuleConfiguration) -> Void
    let onUpdateModulePadding: (UUID, CGFloat?, CGFloat?) -> Void
    /// Callback for updating an individual module's scale (1.0 = normal).
    /// Use nil to clear back to default.
    let onUpdateModuleScale: (UUID, CGFloat?) -> Void
    let onPreviewTileAppearance: (TileBackgroundStyle, Double, CGFloat, CodableColor?, TileGradientBackground?) -> Void

    /// Live preview callback for tile content padding (distance between tile
    /// edges and modules inside the tile).
    let onPreviewTileContentPadding: (CGFloat) -> Void

    let onSaveModuleLayout: (TileModuleLayout) -> Void

    let onPreviewTextFormatting: (Double?, PersonFontWeight?, CodableColor?, TextCapitalizationStyle?, TextJustificationStyle?, TextVerticalAlignmentStyle?) -> Void
    let initialTextFontSize: Double?
    let initialTextFontWeight: PersonFontWeight?
    let initialTextColor: CodableColor?
    let initialTextCapitalization: TextCapitalizationStyle?
    let initialTextJustification: TextJustificationStyle?
    let initialTextVerticalAlignment: TextVerticalAlignmentStyle?
    let onSaveTextFormatting: (Double?, PersonFontWeight?, CodableColor?, TextCapitalizationStyle?, TextJustificationStyle?, TextVerticalAlignmentStyle?) -> Void
    let onSaveTileContentPadding: (CGFloat) -> Void
    let initialTileSizeWidthText: String
    let initialTileSizeHeightText: String
    let defaultTileSize: CGSize
    let currentTileSize: CGSize
    let initialTileSize: CGSize?
    let onBeginTileSizeEdit: () -> Void
    let onUpdateTileSizeLive: (Double?, Double?) -> Void

    @Binding var tab: DashboardTab
    let sharedRosters: [DashboardRoster]
    let onSavePerson: (PersonTileModel?) -> Void
    let onSaveTileAppearance: (TileBackgroundStyle, Double, CGFloat, CodableColor?, TileGradientBackground?) -> Void
    let onSaveShureSelection: (ExternalDevicesStore.ShureSelectedChannel?) -> Void
    var allPersonNames: [String]

    let onDismiss: () -> Void
    let initialShowsTitle: Bool
    let onSaveShowsTitle: (Bool) -> Void
    
    let onSaveShureModuleShowsTitle: (Bool) -> Void

    let initialShureShowDeviceName: Bool
    let initialShureShowChannelName: Bool
    let initialShureShowIPPort: Bool
    let initialShureShowFrequency: Bool
    let initialShureShowBattery: Bool
    let initialShureShowRFStrength: Bool

    let onSaveShureDisplayOptions: (Bool, Bool, Bool, Bool, Bool, Bool) -> Void


    @State private var backgroundOpacity: Double = 1.0
    @State private var cornerRadius: Double = 12
    @State private var backgroundColor: Color = .white
    /// User-facing toggle for whether this tile uses a gradient background.
    @State private var useGradientBackground: Bool = false
    @State private var gradientStartColor: Color = .black
    @State private var gradientEndColor: Color = Color.blue.opacity(0.28)
    /// Padding between the tile edges and its internal modules.
    @State private var tileContentPadding: Double = 0
    @State private var moduleLayout: TileModuleLayout = .vertical
    @State private var showsModuleCatalogModal: Bool = false
    @State private var showsTranscriptionLimitAlert: Bool = false
    @Binding var pendingModuleCatalogTileID: UUID?
    /// Set by the canvas when a tile is opened via double-click, requesting that the
    /// first module's settings be shown immediately instead of the empty-selection state.
    @Binding var pendingFirstModuleSelectTileID: UUID?

    // Tile-level text formatting (applies to all modules)
    @State private var textFontSize: Double = 24
    @State private var textFontWeight: PersonFontWeight = .semibold
    @State private var textColor: Color = .white
    @State private var textCapitalization: TextCapitalizationStyle = .normal
    @State private var textJustification: TextJustificationStyle = .leading
    @State private var textVerticalAlignment: TextVerticalAlignmentStyle = .top
    @State private var tileSizeWidthText: String = ""
    @State private var tileSizeHeightText: String = ""
    @State private var hasStartedTileSizeEdit: Bool = false
    @FocusState private var tileSizeFieldFocus: TileSizeField?
    
    @State private var selectedInspectorTab: InspectorTab = .modules

    @State private var showsTitle: Bool = true
    @State var shureModuleShowsTitle: Bool = true
    @State var shureChannelDescriptors: [ShureChannelDescriptor] = []
    /// Currently selected module in the Modules tab. When nil, the first
    /// module (if any) will be treated as the active one for details.
    @State private var selectedModuleID: UUID? = nil

    /// Local mutable copy of `modules` for inspector edits.
    /// The source of truth still lives in the parent; this lets the settings UI update
    /// immediately without attempting to mutate the `let modules` input.
    @State var editableModules: [DashboardModuleModel] = []
    @State var liveTranscriptionInputLevel: Double = 0
    @State var liveTranscriptionProcessedPeak: Double = 0
    @StateObject var liveTranscriptionLevelMonitor = LiveTranscriptionLevelMonitor()
    @StateObject var audioInputDeviceCache = AudioInputDeviceCache.shared
    @State var showsDbReaderCalibration: Bool = false
    @State var dbReaderCalibrationTargetDb: Double = 94
    @State var showsDbReaderAdvanced: Bool = false
    @State var dbReaderLimitWarningText: String = ""
    @State var dbReaderLimitAlertText: String = ""
    @State private var showsTileAppearanceHelp: Bool = false
    @State private var showsModuleAppearanceHelp: Bool = false
    @State private var showsTextFormattingHelp: Bool = false
    @State private var showsTileSizeHelp: Bool = false
    
    /// Local per-module height (pt) cache so the slider can move immediately.
    /// The real persistence still happens via `onUpdateModuleScale` (currently reused as height callback).
    @State private var moduleHeightByID: [UUID: CGFloat] = [:]
    
    @State private var selectedModuleIDs: Set<UUID> = []
    /// Prevents initial state seeding / ColorPicker quirks from immediately saving a default color (e.g. white) on device.
    @State private var hasInitializedInspectorState: Bool = false
    /// True while we are programmatically seeding inspector @State from the selected tile.
    /// Prevents `.onChange` handlers from treating seeded/default values as user edits.
    @State private var isSeedingInspectorState: Bool = false

    // Dirty flags so module settings edits don't inadvertently overwrite tile-level formatting.
    @State private var hasEditedTileAppearance: Bool = false
    @State private var hasEditedTileContentPadding: Bool = false
    @State private var hasEditedModuleLayout: Bool = false
    @State private var hasEditedTextFormatting: Bool = false
    @State private var hasEditedShowsTitle: Bool = false

    #if os(macOS)
    private var inspectorPanelBaseColor: Color { Color(nsColor: .windowBackgroundColor) }
    private var inspectorSectionColor: Color { Color(nsColor: .controlBackgroundColor) }
    #else
    private var inspectorPanelBaseColor: Color { Color(uiColor: .systemBackground) }
    private var inspectorSectionColor: Color { Color(uiColor: .secondarySystemBackground) }
    #endif

    private var inspectorPanelOverlayColor: Color {
        inspectorPanelBaseColor.opacity(colorScheme == .dark ? 0.16 : 0.92)
    }

    private var inspectorPanelStrokeColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08)
    }

    private var inspectorSectionFillColor: Color {
        inspectorSectionColor.opacity(colorScheme == .dark ? 0.55 : 0.9)
    }

    private var inspectorSectionStrokeColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06)
    }

    @ViewBuilder
    private var inspectorPanelBackground: some View {
        let panelShape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let overlayShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        panelShape
            .fill(.ultraThinMaterial)
            .overlay {
                overlayShape.fill(inspectorPanelOverlayColor)
            }
            .liquidGlassIfAvailable()
    }

    @ViewBuilder
    private var inspectorFooterBackground: some View {
        let panelShape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let overlayShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        panelShape
            .fill(.ultraThinMaterial)
            .overlay {
                overlayShape.fill(inspectorPanelOverlayColor)
            }
            .liquidGlassIfAvailable()
    }


    init(
        tileID: UUID,
        tileHeightPoints: CGFloat? = nil,
        isMultiTileEdit: Bool = false,
        initialPerson: PersonTileModel?,
        hasPCORundown: Bool,
        hasShureWireless: Bool,
        initialBackgroundStyle: TileBackgroundStyle,
        initialBackgroundOpacity: Double,
        initialCornerRadius: CGFloat,
        initialBackgroundColor: CodableColor?,
        initialBackgroundGradient: TileGradientBackground?,
        initialModuleLayout: TileModuleLayout,
        initialShureSelection: ExternalDevicesStore.ShureSelectedChannel?,
        modules: [DashboardModuleModel],
        sharedRosters: [DashboardRoster],
        pendingModuleCatalogTileID: Binding<UUID?> = .constant(nil),
        pendingFirstModuleSelectTileID: Binding<UUID?> = .constant(nil),
        onMoveModule: @escaping (UUID, Int) -> Void,
        onAddModule: @escaping (DashboardModuleKind) -> Void,
        onRemoveModule: @escaping (UUID) -> Void,
        onDuplicateModule: @escaping (UUID) -> Void,
        onUpdateTextModule: @escaping (UUID, TextModuleModel) -> Void = { _, _ in },
        onUpdateImageModule: @escaping (UUID, ImageModuleModel) -> Void = { _, _ in },
        onUpdateDocumentModule: @escaping (UUID, DocumentModuleModel) -> Void = { _, _ in },
        onUpdateNDIModule: @escaping (UUID, NDIModuleModel) -> Void = { _, _ in },
        onUpdateWebpageModule: @escaping (UUID, WebpageModuleModel) -> Void = { _, _ in },
        onUpdateYouTubeStreamMonitorModule: @escaping (UUID, YouTubeStreamMonitorModuleModel) -> Void = { _, _ in },
        onUpdateButtonModule: @escaping (UUID, ButtonModuleModel) -> Void = { _, _ in },
        onUpdateRosterPickerModule: @escaping (UUID, RosterPickerModuleModel) -> Void = { _, _ in },
        onUpdateSeparator: @escaping (UUID, SeparatorModuleModel) -> Void = { _, _ in },
        onOpenPCOTabSettings: @escaping () -> Void = {},
        onUpdateTimeModuleConfig: @escaping (UUID, TimeModuleConfig) -> Void = { _, _ in },
        onUpdateTimecodeModuleConfig: @escaping (UUID, TimecodeModuleConfig) -> Void = { _, _ in },
        onUpdateDAWTransportModuleConfig: @escaping (UUID, DAWTransportModuleConfiguration) -> Void = { _, _ in },
        onUpdateModulePadding: @escaping (UUID, CGFloat?, CGFloat?) -> Void,
        onUpdateModuleScale: @escaping (UUID, CGFloat?) -> Void = { _, _ in },
        tab: Binding<DashboardTab>,
        onSavePerson: @escaping (PersonTileModel?) -> Void,
        onSaveTileAppearance: @escaping (TileBackgroundStyle, Double, CGFloat, CodableColor?, TileGradientBackground?) -> Void,
        onPreviewTileAppearance: @escaping (TileBackgroundStyle, Double, CGFloat, CodableColor?, TileGradientBackground?) -> Void,
        // New: tile content padding initial value + callbacks
        initialTileContentPadding: CGFloat = 0,
        onPreviewTileContentPadding: @escaping (CGFloat) -> Void = { _ in },
        onSaveTileContentPadding: @escaping (CGFloat) -> Void = { _ in },
        onSaveModuleLayout: @escaping (TileModuleLayout) -> Void = { _ in },
        onSaveShureSelection: @escaping (ExternalDevicesStore.ShureSelectedChannel?) -> Void,
        onDismiss: @escaping () -> Void,
        onPreviewTextFormatting: @escaping (Double?, PersonFontWeight?, CodableColor?, TextCapitalizationStyle?, TextJustificationStyle?, TextVerticalAlignmentStyle?) -> Void,
        initialTextFontSize: Double?,
        initialTextFontWeight: PersonFontWeight?,
        initialTextColor: CodableColor?,
        initialTextCapitalization: TextCapitalizationStyle?,
        initialTextJustification: TextJustificationStyle?,
        initialTextVerticalAlignment: TextVerticalAlignmentStyle?,
        onSaveTextFormatting: @escaping (Double?, PersonFontWeight?, CodableColor?, TextCapitalizationStyle?, TextJustificationStyle?, TextVerticalAlignmentStyle?) -> Void,
        initialTileSizeWidthText: String = "",
        initialTileSizeHeightText: String = "",
        defaultTileSize: CGSize = CGSize(width: 260, height: 200),
        currentTileSize: CGSize = CGSize(width: 260, height: 200),
        initialTileSize: CGSize? = nil,
        onBeginTileSizeEdit: @escaping () -> Void = {},
        onUpdateTileSizeLive: @escaping (Double?, Double?) -> Void = { _, _ in },
        onUpdatePCOModuleConfig: @escaping (UUID, PCOModuleConfig) -> Void,
        onUpdateShureModuleConfig: @escaping (UUID, ShureModuleConfig) -> Void,
        initialShowsTitle: Bool,
        onSaveShowsTitle: @escaping (Bool) -> Void,
        onSaveShureModuleShowsTitle: @escaping (Bool) -> Void = { _ in },
        initialShureShowDeviceName: Bool = true,
        initialShureShowChannelName: Bool = true,
        initialShureShowIPPort: Bool = true,
        initialShureShowFrequency: Bool = true,
        initialShureShowBattery: Bool = true,
        initialShureShowRFStrength: Bool = true,
        onSaveShureDisplayOptions: @escaping (Bool, Bool, Bool, Bool, Bool, Bool) -> Void = { _, _, _, _, _, _ in },
        allPersonNames: [String] = []
    ) {
        self.tileID = tileID
        self.tileHeightPoints = tileHeightPoints
        self.isMultiTileEdit = isMultiTileEdit
        self.initialPerson = initialPerson
        self.hasPCORundown = hasPCORundown
        self.hasShureWireless = hasShureWireless
        self.initialBackgroundStyle = initialBackgroundStyle
        self.initialBackgroundOpacity = initialBackgroundOpacity
        self.initialCornerRadius = initialCornerRadius
        self.initialBackgroundColor = initialBackgroundColor
        self.initialBackgroundGradient = initialBackgroundGradient
        self.initialTileContentPaddingValue = initialTileContentPadding
        self.initialModuleLayout = initialModuleLayout
        self.initialShureSelection = initialShureSelection
        self.modules = modules
        self.sharedRosters = sharedRosters
        _pendingModuleCatalogTileID = pendingModuleCatalogTileID
        _pendingFirstModuleSelectTileID = pendingFirstModuleSelectTileID
        self.onMoveModule = onMoveModule
        self.onAddModule = onAddModule
        self.onRemoveModule = onRemoveModule
        self.onDuplicateModule = onDuplicateModule
        self.onUpdateTextModule = onUpdateTextModule
        self.onUpdateImageModule = onUpdateImageModule
        self.onUpdateDocumentModule = onUpdateDocumentModule
        self.onUpdateNDIModule = onUpdateNDIModule
        self.onUpdateWebpageModule = onUpdateWebpageModule
        self.onUpdateYouTubeStreamMonitorModule = onUpdateYouTubeStreamMonitorModule
        self.onUpdateButtonModule = onUpdateButtonModule
        self.onUpdateRosterPickerModule = onUpdateRosterPickerModule
        self.onUpdateSeparator = onUpdateSeparator
        self.onOpenPCOTabSettings = onOpenPCOTabSettings
        self.onUpdateTimeModuleConfig = onUpdateTimeModuleConfig
        self.onUpdateTimecodeModuleConfig = onUpdateTimecodeModuleConfig
        self.onUpdateDAWTransportModuleConfig = onUpdateDAWTransportModuleConfig
        self.onUpdateModulePadding = onUpdateModulePadding
        self.onUpdateModuleScale = onUpdateModuleScale
        _tab = tab
        self.onSavePerson = onSavePerson
        self.onSaveTileAppearance = onSaveTileAppearance
        self.onPreviewTileAppearance = onPreviewTileAppearance
        self.onPreviewTileContentPadding = onPreviewTileContentPadding
        self.onSaveTileContentPadding = onSaveTileContentPadding
        self.onSaveModuleLayout = onSaveModuleLayout
        self.onSaveShureSelection = onSaveShureSelection
        self.onDismiss = onDismiss
        self.onPreviewTextFormatting = onPreviewTextFormatting
        self.initialTextFontSize = initialTextFontSize
        self.initialTextFontWeight = initialTextFontWeight
        self.initialTextColor = initialTextColor
        self.initialTextCapitalization = initialTextCapitalization
        self.initialTextJustification = initialTextJustification
        self.initialTextVerticalAlignment = initialTextVerticalAlignment
        self.onSaveTextFormatting = onSaveTextFormatting
        self.initialTileSizeWidthText = initialTileSizeWidthText
        self.initialTileSizeHeightText = initialTileSizeHeightText
        self.defaultTileSize = defaultTileSize
        self.currentTileSize = currentTileSize
        self.initialTileSize = initialTileSize
        self.onBeginTileSizeEdit = onBeginTileSizeEdit
        self.onUpdateTileSizeLive = onUpdateTileSizeLive
        self.onUpdatePCOModuleConfig = onUpdatePCOModuleConfig
        self.onUpdateShureModuleConfig = onUpdateShureModuleConfig
        self.initialShowsTitle = initialShowsTitle
        self.onSaveShowsTitle = onSaveShowsTitle
        self.onSaveShureModuleShowsTitle = onSaveShureModuleShowsTitle
        self.initialShureShowDeviceName = initialShureShowDeviceName
        self.initialShureShowChannelName = initialShureShowChannelName
        self.initialShureShowIPPort = initialShureShowIPPort
        self.initialShureShowFrequency = initialShureShowFrequency
        self.initialShureShowBattery = initialShureShowBattery
        self.initialShureShowRFStrength = initialShureShowRFStrength
        self.onSaveShureDisplayOptions = onSaveShureDisplayOptions
        self.allPersonNames = allPersonNames

        _showsTitle = State(initialValue: initialShowsTitle)
        _shureModuleShowsTitle = State(initialValue: true)
        _backgroundOpacity = State(initialValue: initialBackgroundOpacity)
        _cornerRadius = State(initialValue: Double(initialCornerRadius))
        _backgroundColor = State(initialValue: initialBackgroundColor?.swiftUIColor ?? initialBackgroundStyle.color)
        let seedGradient = initialBackgroundGradient ?? TileGradientBackground.defaultGradient
        _useGradientBackground = State(initialValue: initialBackgroundGradient != nil)
        _gradientStartColor = State(initialValue: seedGradient.startColor.swiftUIColor)
        _gradientEndColor = State(initialValue: seedGradient.endColor.swiftUIColor)
        _tileContentPadding = State(initialValue: Double(initialTileContentPaddingValue))
        _moduleLayout = State(initialValue: initialModuleLayout)

        _textFontSize = State(initialValue: initialTextFontSize ?? 24)
        _textFontWeight = State(initialValue: initialTextFontWeight ?? .semibold)
        _textColor = State(initialValue: initialTextColor?.swiftUIColor ?? .white)
        _textCapitalization = State(initialValue: initialTextCapitalization ?? .normal)
        _textJustification = State(initialValue: initialTextJustification ?? .leading)
        _textVerticalAlignment = State(initialValue: initialTextVerticalAlignment ?? .top)
        _tileSizeWidthText = State(initialValue: initialTileSizeWidthText)
        _tileSizeHeightText = State(initialValue: initialTileSizeHeightText)



        _selectedInspectorTab = State(initialValue: isMultiTileEdit ? .formatting : .modules)
        _editableModules = State(initialValue: modules)
    }
}

final class LiveTranscriptionLevelMonitor: NSObject, ObservableObject {
    @Published var level: Double = 0
    @Published var processedPeak: Double = 0
    private var channelIndex: Int = 0
    private var currentChannelIndex: Int?

#if os(macOS)
    private var captureSession: AVCaptureSession?
    private var captureHAL: DeviceInputCaptureHAL?
    private let captureQueue = DispatchQueue(label: "Relay.LiveTranscription.LevelMonitor")
    private let throttler = TranscriptionThrottler()
    private var currentDeviceUID: String?
#elseif os(iOS)
    private let capture = EngineInputCapture()
    private let throttler = TranscriptionThrottler()
    private var isRunning = false
#endif

    func start(deviceUID: String?, channelIndex: Int = 0) {
        self.channelIndex = max(0, channelIndex)
#if os(macOS)
        if (captureSession != nil || captureHAL != nil),
           currentDeviceUID == deviceUID,
           currentChannelIndex == self.channelIndex {
            return
        }
        stop()
        currentDeviceUID = deviceUID
        currentChannelIndex = self.channelIndex

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard let self, granted else { return }
            self.captureQueue.async {
                self.beginCapture(deviceUID: deviceUID)
            }
        }
#elseif os(iOS)
        if isRunning, currentChannelIndex == self.channelIndex { return }
        if isRunning {
            stop()
        }
        currentChannelIndex = self.channelIndex
        guard hasUsageDescription("NSMicrophoneUsageDescription") else { return }

        let permissionHandler: (Bool) -> Void = { [weak self] granted in
            guard let self, granted else { return }
            self.capture.onBuffer = { [weak self] buffer in
                guard let self else { return }
                let peak = self.processedPeakLevel(from: buffer)
                self.throttler.publish(isFinal: false, targetHz: 60) { [weak self] in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        let current = self.level
                        let target = self.normalizedLevel(from: peak)
                        let attack = max(target, current * 0.7)
                        self.level = attack
                        self.processedPeak = peak
                    }
                }
            }
            do {
                try self.capture.start()
                self.isRunning = true
            } catch { }
        }

        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { permissionHandler($0) }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { permissionHandler($0) }
        }
#else
        _ = deviceUID
#endif
    }

    func stop() {
#if os(macOS)
        captureSession?.stopRunning()
        captureSession = nil
        captureHAL?.stop()
        captureHAL = nil
        currentDeviceUID = nil
        currentChannelIndex = nil
#elseif os(iOS)
        capture.stop()
        isRunning = false
        currentChannelIndex = nil
#endif
    }

#if os(iOS)
    private func hasUsageDescription(_ key: String) -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
#endif

#if os(macOS)
    private func beginCapture(deviceUID: String?) {
        captureSession?.stopRunning()
        captureSession = nil
        captureHAL?.stop()
        captureHAL = nil

        if let device = captureDevice(for: deviceUID) {
            startCaptureSession(device)
        } else {
            startCaptureHAL(deviceUID: deviceUID)
        }
    }

    private func captureDevice(for deviceUID: String?) -> AVCaptureDevice? {
        guard deviceUID == nil || deviceUID?.isEmpty == true else {
            return nil
        }
        return AVCaptureDevice.default(for: .audio)
    }

    private func startCaptureSession(_ device: AVCaptureDevice) {
        let session = AVCaptureSession()
        session.beginConfiguration()

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            session.commitConfiguration()
            return
        }

        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false
        ]
        if session.canAddOutput(output) { session.addOutput(output) }
        output.setSampleBufferDelegate(self, queue: captureQueue)

        session.commitConfiguration()
        session.startRunning()
        captureSession = session
    }

    private func startCaptureHAL(deviceUID: String?) {
        let uid = deviceUID ?? ""
        let deviceId = AudioDeviceEnumerator.deviceId(for: uid) ?? AudioDeviceEnumerator.defaultInputDeviceId()
        guard let resolvedDeviceId = deviceId else { return }

        let hal = DeviceInputCaptureHAL(deviceId: resolvedDeviceId)
        hal.channelIndex = channelIndex
        hal.onBuffer = { [weak self] buffer in
            guard let self else { return }
            let peak = self.processedPeakLevel(from: buffer)
            self.throttler.publish(isFinal: false, targetHz: 60) { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let current = self.level
                    let target = self.normalizedLevel(from: peak)
                    let attack = max(target, current * 0.7)
                    self.level = attack
                    self.processedPeak = peak
                }
            }
        }
        captureHAL = hal
        do {
            try hal.start()
        } catch {
            captureHAL = nil
        }
    }
#endif
}

#if os(macOS)
extension LiveTranscriptionLevelMonitor: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard CMSampleBufferIsValid(sampleBuffer),
              let buffer = pcmBuffer(from: sampleBuffer) else { return }
        let peak = processedPeakLevel(from: buffer)
        throttler.publish(isFinal: false, targetHz: 60) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                let current = self.level
                let target = self.normalizedLevel(from: peak)
                let attack = max(target, current * 0.7)
                self.level = attack
                self.processedPeak = peak
            }
        }
    }

    private func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else {
            return nil
        }

        var streamDesc = asbd
        guard let format = AVAudioFormat(streamDescription: &streamDesc) else { return nil }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 0, mDataByteSize: 0, mData: nil)
        )
        var bufferListSize = MemoryLayout<AudioBufferList>.size

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: &audioBufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let destList = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let srcList = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        for i in 0..<min(destList.count, srcList.count) {
            let src = srcList[i]
            let dst = destList[i]
            guard let srcData = src.mData, let dstData = dst.mData else { continue }
            memcpy(dstData, srcData, Int(min(src.mDataByteSize, dst.mDataByteSize)))
        }
        return buffer
    }

    private func rmsLevel(from buffer: AVAudioPCMBuffer) -> Double {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            if let channelData = buffer.floatChannelData {
                let channelCount = Int(buffer.format.channelCount)
                let idx = min(max(0, channelIndex), max(0, channelCount - 1))
                let channel = channelData[idx]
                var sum: Double = 0
                for i in 0..<frameCount {
                    let sample = Double(channel[i])
                    sum += sample * sample
                }
                return sqrt(sum / Double(frameCount))
            } else if buffer.format.isInterleaved {
                let bufferList = buffer.audioBufferList.pointee.mBuffers
                guard let data = bufferList.mData else { return 0 }
                let channelCount = Int(buffer.format.channelCount)
                let idx = min(max(0, channelIndex), max(0, channelCount - 1))
                let stride = channelCount
                let samples = data.bindMemory(to: Float32.self, capacity: frameCount * stride)
                var sum: Double = 0
                for i in 0..<frameCount {
                    let sample = Double(samples[i * stride + idx])
                    sum += sample * sample
                }
                return sqrt(sum / Double(frameCount))
            }
        case .pcmFormatInt16:
            if let channelData = buffer.int16ChannelData {
                let channelCount = Int(buffer.format.channelCount)
                let idx = min(max(0, channelIndex), max(0, channelCount - 1))
                let channel = channelData[idx]
                var sum: Double = 0
                for i in 0..<frameCount {
                    let sample = Double(channel[i]) / Double(Int16.max)
                    sum += sample * sample
                }
                return sqrt(sum / Double(frameCount))
            }
        case .pcmFormatInt32:
            if let channelData = buffer.int32ChannelData {
                let channelCount = Int(buffer.format.channelCount)
                let idx = min(max(0, channelIndex), max(0, channelCount - 1))
                let channel = channelData[idx]
                var sum: Double = 0
                for i in 0..<frameCount {
                    let sample = Double(channel[i]) / Double(Int32.max)
                    sum += sample * sample
                }
                return sqrt(sum / Double(frameCount))
            }
        default:
            break
        }
        return 0
    }

    private func processedPeakLevel(from buffer: AVAudioPCMBuffer) -> Double {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        let gain = computeAutoGain(from: buffer)
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            if let channelData = buffer.floatChannelData {
                let channelCount = Int(buffer.format.channelCount)
                let idx = min(max(0, channelIndex), max(0, channelCount - 1))
                let channel = channelData[idx]
                var peak: Double = 0
                for i in 0..<frameCount {
                    let sample = abs(Double(softLimit(Float(channel[i]) * gain)))
                    if sample > peak { peak = sample }
                }
                return peak
            } else if buffer.format.isInterleaved {
                let bufferList = buffer.audioBufferList.pointee.mBuffers
                guard let data = bufferList.mData else { return 0 }
                let channelCount = Int(buffer.format.channelCount)
                let idx = min(max(0, channelIndex), max(0, channelCount - 1))
                let stride = channelCount
                let samples = data.bindMemory(to: Float32.self, capacity: frameCount * stride)
                var peak: Double = 0
                for i in 0..<frameCount {
                    let sample = abs(Double(softLimit(samples[i * stride + idx] * gain)))
                    if sample > peak { peak = sample }
                }
                return peak
            }
        case .pcmFormatInt16:
            if let channelData = buffer.int16ChannelData {
                let channelCount = Int(buffer.format.channelCount)
                let idx = min(max(0, channelIndex), max(0, channelCount - 1))
                let channel = channelData[idx]
                var peak: Double = 0
                for i in 0..<frameCount {
                    let sample = abs(Double(softLimit(Float(channel[i]) / Float(Int16.max) * gain)))
                    if sample > peak { peak = sample }
                }
                return peak
            }
        case .pcmFormatInt32:
            if let channelData = buffer.int32ChannelData {
                let channelCount = Int(buffer.format.channelCount)
                let idx = min(max(0, channelIndex), max(0, channelCount - 1))
                let channel = channelData[idx]
                var peak: Double = 0
                for i in 0..<frameCount {
                    let sample = abs(Double(softLimit(Float(channel[i]) / Float(Int32.max) * gain)))
                    if sample > peak { peak = sample }
                }
                return peak
            }
        default:
            break
        }
        return 0
    }

    private func computeAutoGain(from buffer: AVAudioPCMBuffer) -> Float {
        let rms = rmsLevel(from: buffer)
        guard rms > 0 else { return 1.0 }
        let target = 0.06
        let gain = min(8.0, max(0.25, target / rms))
        return Float(gain)
    }

    private func softLimit(_ sample: Float) -> Float {
        let drive: Float = 2.0
        let x = Double(sample * drive)
        let denom = tanh(Double(drive))
        guard denom != 0 else { return sample }
        return Float(tanh(x) / denom)
    }

    private func normalizedLevel(from processedPeak: Double) -> Double {
        let expectedPeak: Double = 0.2
        return min(1.0, processedPeak / expectedPeak)
    }
}
#endif

#if os(iOS)
private extension LiveTranscriptionLevelMonitor {
    func rmsLevel(from buffer: AVAudioPCMBuffer) -> Double {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            if let channelData = buffer.floatChannelData {
                let channel = channelData.pointee
                var sum: Double = 0
                for i in 0..<frameCount {
                    let sample = Double(channel[i])
                    sum += sample * sample
                }
                return sqrt(sum / Double(frameCount))
            } else if buffer.format.isInterleaved {
                let bufferList = buffer.audioBufferList.pointee.mBuffers
                guard let data = bufferList.mData else { return 0 }
                let sampleCount = frameCount * Int(buffer.format.channelCount)
                let samples = data.bindMemory(to: Float32.self, capacity: sampleCount)
                var sum: Double = 0
                for i in 0..<sampleCount {
                    let sample = Double(samples[i])
                    sum += sample * sample
                }
                return sqrt(sum / Double(sampleCount))
            }
        case .pcmFormatInt16:
            if let channelData = buffer.int16ChannelData {
                let channel = channelData.pointee
                var sum: Double = 0
                for i in 0..<frameCount {
                    let sample = Double(channel[i]) / Double(Int16.max)
                    sum += sample * sample
                }
                return sqrt(sum / Double(frameCount))
            }
        case .pcmFormatInt32:
            if let channelData = buffer.int32ChannelData {
                let channel = channelData.pointee
                var sum: Double = 0
                for i in 0..<frameCount {
                    let sample = Double(channel[i]) / Double(Int32.max)
                    sum += sample * sample
                }
                return sqrt(sum / Double(frameCount))
            }
        default:
            break
        }
        return 0
    }

    func processedPeakLevel(from buffer: AVAudioPCMBuffer) -> Double {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        let gain = computeAutoGain(from: buffer)
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            if let channelData = buffer.floatChannelData {
                let channel = channelData.pointee
                var peak: Double = 0
                for i in 0..<frameCount {
                    let sample = abs(Double(softLimit(Float(channel[i]) * gain)))
                    if sample > peak { peak = sample }
                }
                return peak
            } else if buffer.format.isInterleaved {
                let bufferList = buffer.audioBufferList.pointee.mBuffers
                guard let data = bufferList.mData else { return 0 }
                let sampleCount = frameCount * Int(buffer.format.channelCount)
                let samples = data.bindMemory(to: Float32.self, capacity: sampleCount)
                var peak: Double = 0
                for i in 0..<sampleCount {
                    let sample = abs(Double(softLimit(samples[i] * gain)))
                    if sample > peak { peak = sample }
                }
                return peak
            }
        case .pcmFormatInt16:
            if let channelData = buffer.int16ChannelData {
                let channel = channelData.pointee
                var peak: Double = 0
                for i in 0..<frameCount {
                    let sample = abs(Double(softLimit(Float(channel[i]) / Float(Int16.max) * gain)))
                    if sample > peak { peak = sample }
                }
                return peak
            }
        case .pcmFormatInt32:
            if let channelData = buffer.int32ChannelData {
                let channel = channelData.pointee
                var peak: Double = 0
                for i in 0..<frameCount {
                    let sample = abs(Double(softLimit(Float(channel[i]) / Float(Int32.max) * gain)))
                    if sample > peak { peak = sample }
                }
                return peak
            }
        default:
            break
        }
        return 0
    }

    func computeAutoGain(from buffer: AVAudioPCMBuffer) -> Float {
        let rms = rmsLevel(from: buffer)
        guard rms > 0 else { return 1.0 }
        let target = 0.06
        let gain = min(8.0, max(0.25, target / rms))
        return Float(gain)
    }

    func softLimit(_ sample: Float) -> Float {
        let drive: Float = 2.0
        let x = Double(sample * drive)
        let denom = tanh(Double(drive))
        guard denom != 0 else { return sample }
        return Float(tanh(x) / denom)
    }

    func normalizedLevel(from processedPeak: Double) -> Double {
        let expectedPeak: Double = 0.2
        guard expectedPeak > 0 else { return min(1.0, processedPeak) }
        return min(1.0, processedPeak / expectedPeak)
    }
}
#endif


// MARK: - Dashboard Tile Defaults

/// App-wide defaults for tile-level formatting.
private enum DashboardTileDefaults {
    static let backgroundOpacity: Double = 1.0
    static let cornerRadius: CGFloat = 12
    static let contentPadding: CGFloat = 0
    static let textFontSize: Double = 24
}

// MARK: - Liquid Glass helpers (iOS 26+)

/// Applies iOS 26+ `backgroundExtensionEffect()` when available. No-op everywhere else.
private struct LiquidGlassExtensionEffectIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            content.backgroundExtensionEffect()
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private extension View {
    /// Convenience wrapper for applying the Liquid Glass extension effect when available.
    func liquidGlassIfAvailable() -> some View {
        self.modifier(LiquidGlassExtensionEffectIfAvailable())
    }
}

struct DbReaderInspectorInputMeter: View {
    let isEnabled: Bool
    let inputID: UUID?

    @StateObject private var levelMonitor = LiveTranscriptionLevelMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Input Level")
                .font(.caption)
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                let width = max(0, geo.size.width)
                let level = CGFloat(min(1.0, max(0.0, levelMonitor.level)))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(meterColor(forPeak: levelMonitor.processedPeak))
                        .frame(width: max(4, width * level), height: 6)
                }
            }
            .frame(height: 6)
        }
        .onAppear(perform: updateMonitor)
        .onChange(of: isEnabled) { _, _ in updateMonitor() }
        .onChange(of: inputID) { _, _ in updateMonitor() }
        .onDisappear {
            levelMonitor.stop()
        }
    }

    private func updateMonitor() {
        if isEnabled {
            let config = inputID.flatMap { AudioInputsConfigStore.shared.input(for: $0) }
            levelMonitor.start(deviceUID: config?.deviceUID, channelIndex: config?.channelIndex ?? 0)
        } else {
            levelMonitor.stop()
        }
    }

    private func meterColor(forPeak peak: Double) -> Color {
        if peak >= 0.30 {
            return Color.red
        }
        if peak >= 0.18 {
            return Color.yellow
        }
        return Color.green
    }
}

// MARK: - Shure Helpers

extension DashboardTileEditView {
    private var isOS26OrNewer: Bool {
        if #available(iOS 26.0, macOS 26.0, *) {
            return true
        } else {
            return false
        }
    }

    func meterColor(forPeak peak: Double) -> Color {
        if peak >= 0.30 {
            return Color.red
        }
        if peak >= 0.18 {
            return Color.yellow
        }
        return Color.green
    }
    /// Persist any settings that need an explicit save callback.
    /// (Used by module plugin settings views.)
    func persistChanges() {
        // Guard against seeding-time calls from module settings `.onAppear`.
        guard hasInitializedInspectorState, !isSeedingInspectorState else { return }

        // Tile title visibility is persisted via this callback.
        if hasEditedShowsTitle {
            onSaveShowsTitle(showsTitle)
        }

        // Tile content padding is persisted via this callback.
        if hasEditedTileContentPadding {
            onSaveTileContentPadding(CGFloat(tileContentPadding))
        }

        // Tile module layout is persisted via this callback.
        if hasEditedModuleLayout {
            onSaveModuleLayout(moduleLayout)
        }

        // Tile-level text formatting persistence.
        if hasEditedTextFormatting {
            onSaveTextFormatting(
                textFontSize,
                textFontWeight,
                CodableColor(textColor),
                textCapitalization,
                textJustification,
                textVerticalAlignment
            )
        }

        // Tile appearance persistence.
        if hasEditedTileAppearance {
            let resolvedColor = CodableColor(backgroundColor)
            let resolvedGradient = useGradientBackground
                ? TileGradientBackground(
                    startColor: CodableColor(gradientStartColor),
                    endColor: CodableColor(gradientEndColor)
                )
                : nil
            onSaveTileAppearance(initialBackgroundStyle, backgroundOpacity, CGFloat(cornerRadius), resolvedColor, resolvedGradient)
        }
    }

    func resetEditorStateFromInitialValues() {
        // Disable change handlers while we seed @State from the model.
        isSeedingInspectorState = true
        hasInitializedInspectorState = false

        // Tile appearance
        backgroundOpacity = initialBackgroundOpacity
        cornerRadius = Double(initialCornerRadius)
        backgroundColor = initialBackgroundColor?.swiftUIColor ?? initialBackgroundStyle.color
        let seedGradient = initialBackgroundGradient ?? TileGradientBackground.defaultGradient
        useGradientBackground = initialBackgroundGradient != nil
        gradientStartColor = seedGradient.startColor.swiftUIColor
        gradientEndColor = seedGradient.endColor.swiftUIColor
        tileContentPadding = Double(initialTileContentPaddingValue)
        moduleLayout = initialModuleLayout

        // Text formatting
        textFontSize = initialTextFontSize ?? DashboardTileDefaults.textFontSize
        textFontWeight = initialTextFontWeight ?? .semibold
        textColor = initialTextColor?.swiftUIColor ?? .white
        textCapitalization = initialTextCapitalization ?? .normal
        textJustification = initialTextJustification ?? .leading
        textVerticalAlignment = initialTextVerticalAlignment ?? .top

        // Tile size
        tileSizeWidthText = initialTileSizeWidthText
        tileSizeHeightText = initialTileSizeHeightText
        hasStartedTileSizeEdit = false
        tileSizeFieldFocus = nil

        // Title visibility
        showsTitle = initialShowsTitle

        // Reset dirty flags whenever we seed from the model.
        hasEditedTileAppearance = false
        hasEditedTileContentPadding = false
        hasEditedModuleLayout = false
        hasEditedTextFormatting = false
        hasEditedShowsTitle = false

        // Re-enable change handlers on the next runloop so SwiftUI state settles.
        DispatchQueue.main.async {
            hasInitializedInspectorState = true
            isSeedingInspectorState = false
        }
    }
}

struct DbReaderCalibrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var targetDb: Double
    let currentSpl: Double
    let currentRawDbFS: Double
    let currentOffset: Double
    let liveSplProvider: (() -> Double)?
    let liveRawDbFSProvider: (() -> Double)?
    let onApply: (Double, Double?, Double?) -> Void
    let onSetOffset: (Double) -> Void

    @State private var targetText: String = ""
    @State private var offsetText: String = ""
    @State private var offsetDisplay: Double
    @State private var isCapturing: Bool = false
    @State private var captureValues: [Double] = []
    @State private var captureRawValues: [Double] = []
    @State private var captureRemaining: TimeInterval = 0
    @State private var capturedSpl: Double? = nil
    @State private var capturedRawDbFS: Double? = nil
    @State private var warningText: String = ""
    @State private var applyAfterCapture: Bool = false
    @State private var captureTask: Task<Void, Never>? = nil

    private let captureDuration: TimeInterval = 5
    private let captureTick: TimeInterval = 0.1

    init(
        targetDb: Binding<Double>,
        currentSpl: Double,
        currentRawDbFS: Double,
        currentOffset: Double,
        liveSplProvider: (() -> Double)? = nil,
        liveRawDbFSProvider: (() -> Double)? = nil,
        onApply: @escaping (Double, Double?, Double?) -> Void,
        onSetOffset: @escaping (Double) -> Void
    ) {
        _targetDb = targetDb
        self.currentSpl = currentSpl
        self.currentRawDbFS = currentRawDbFS
        self.currentOffset = currentOffset
        self.liveSplProvider = liveSplProvider
        self.liveRawDbFSProvider = liveRawDbFSProvider
        self.onApply = onApply
        self.onSetOffset = onSetOffset
        _targetText = State(initialValue: String(format: "%.1f", targetDb.wrappedValue))
        _offsetText = State(initialValue: String(format: "%.1f", currentOffset))
        _offsetDisplay = State(initialValue: currentOffset)
    }

    var body: some View {
        let measuredRawDbFS = capturedRawDbFS
            ?? liveRawDbFSProvider?()
            ?? currentRawDbFS
        let offsetRequired = targetDb - measuredRawDbFS
        let captureProgress = isCapturing
            ? max(0, min(1, 1 - (captureRemaining / max(0.01, captureDuration))))
            : 1.0
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Calibration Progress")
                    .font(.headline)
                ProgressView(value: captureProgress)
                    .progressViewStyle(.linear)
                Text("\(Int(captureProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Measured Level is: \(String(format: "%.1f", measuredRawDbFS)) dBFS RMS")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !warningText.isEmpty {
                Text(warningText)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Text("Set this value to:")
                Spacer()
                TextField("", text: $targetText)
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .onChange(of: targetText) { _, newValue in
                    if let value = Double(newValue) {
                        targetDb = value
                    }
                }
                Text("dB")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Offset required is:")
                Spacer()
                Text(String(format: "%.1f dB", offsetRequired))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Mic sensitivity is:")
                Spacer()
                Text("NA")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Current Offset")
                Spacer()
                Text(String(format: "%.1f dB", offsetDisplay))
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField("Offset dB", text: $offsetText)
                    .frame(width: 90)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)

                Button("Set Offset") {
                    let value = Double(offsetText) ?? offsetDisplay
                    offsetDisplay = value
                    offsetText = String(format: "%.1f", value)
                    onSetOffset(value)
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Spacer()
                Button(isCapturing ? "Capturing…" : (capturedSpl == nil ? "Capture & Apply" : "Apply Calibration")) {
                    handleApplyTap()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCapturing)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Done") {
                    if let value = Double(offsetText) {
                        offsetDisplay = value
                        offsetText = String(format: "%.1f", value)
                        onSetOffset(value)
                    }
                    if let capturedSpl {
                        onApply(targetDb, capturedSpl, capturedRawDbFS)
                    }
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(minWidth: 320)
        .onDisappear {
            captureTask?.cancel()
            captureTask = nil
        }
    }

    private func startCapture() {
        captureTask?.cancel()
        captureValues.removeAll()
        captureRawValues.removeAll()
        capturedSpl = nil
        capturedRawDbFS = nil
        warningText = ""
        let resetOffset = 0.0
        offsetDisplay = resetOffset
        offsetText = String(format: "%.1f", resetOffset)
        onSetOffset(resetOffset)
        captureRemaining = captureDuration
        isCapturing = true
        let start = Date()
        captureTask = Task {
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                await MainActor.run {
                    captureRemaining = max(0, captureDuration - elapsed)
                    if let live = liveSplProvider?() {
                        captureValues.append(live)
                    }
                    if let liveRaw = liveRawDbFSProvider?() {
                        captureRawValues.append(liveRaw)
                    }
                }
                if elapsed >= captureDuration {
                    break
                }
                let sleepNs = UInt64(captureTick * 1_000_000_000)
                try? await Task.sleep(nanoseconds: sleepNs)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                finishCapture()
            }
        }
    }

    private func finishCapture() {
        isCapturing = false
        guard !captureValues.isEmpty else {
            capturedSpl = nil
            capturedRawDbFS = nil
            return
        }
        let minValue = captureValues.min() ?? 0
        let maxValue = captureValues.max() ?? 0
        let variance = maxValue - minValue
        guard variance <= 2.0 else {
            warningText = "Signal varied by \(String(format: "%.1f", variance)) dB. Keep it within ±1 dB."
            capturedSpl = nil
            capturedRawDbFS = nil
            applyAfterCapture = false
            return
        }
        capturedSpl = captureValues.last
        if !captureRawValues.isEmpty {
            let sum = captureRawValues.reduce(0, +)
            capturedRawDbFS = sum / Double(captureRawValues.count)
        }
        if applyAfterCapture {
            applyAfterCapture = false
            applyCalibration(usingCaptured: capturedSpl)
        }
    }

    private func handleApplyTap() {
        warningText = ""
        if capturedSpl == nil {
            applyAfterCapture = true
            startCapture()
            return
        }
        applyCalibration(usingCaptured: capturedSpl)
    }

    private func applyCalibration(usingCaptured captured: Double?) {
        let currentSpl = captured ?? liveSplProvider?() ?? currentSpl
        let currentRawDbFS = capturedRawDbFS ?? liveRawDbFSProvider?() ?? currentRawDbFS
        let resetOffset = 0.0
        offsetDisplay = resetOffset
        offsetText = String(format: "%.1f", resetOffset)
        onSetOffset(resetOffset)

        let preCalibrated = currentRawDbFS.isFinite && currentRawDbFS != 0 ? currentRawDbFS : currentSpl
        let newOffset = targetDb - preCalibrated
        offsetDisplay = newOffset
        offsetText = String(format: "%.1f", newOffset)
        onApply(targetDb, captured, capturedRawDbFS)
    }
}

struct DbReaderAdvancedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DbReaderModuleModel
    let onApply: (DbReaderModuleModel) -> Void

    init(model: DbReaderModuleModel, onApply: @escaping (DbReaderModuleModel) -> Void) {
        _draft = State(initialValue: model)
        self.onApply = onApply
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Advanced Settings")
                .font(.headline)

            HStack {
                Text("Publish Rate")
                Spacer()
                TextField("", value: $draft.publishHz, formatter: publishRateFormatter)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                Text("Hz")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("History Buffer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Stored for exporting and peak hold.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    Slider(value: $draft.historyMaxSeconds, in: 60...1800, step: 10)
                    TextField("", value: $draft.historyMaxSeconds, formatter: historySecondsFormatter)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Done") {
                    var updated = draft
                    updated.publishHz = max(1, min(20, updated.publishHz))
                    updated.historyWindowSeconds = max(5, min(30, updated.historyWindowSeconds))
                    updated.historyMaxSeconds = max(60, min(1800, updated.historyMaxSeconds))
                    onApply(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 320)
    }

    private var publishRateFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = 1
        formatter.maximum = 60
        formatter.maximumFractionDigits = 0
        return formatter
    }

    var historySecondsFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = 1
        formatter.maximum = 3600
        formatter.maximumFractionDigits = 0
        return formatter
    }
}

// MARK: - Body

extension DashboardTileEditView {
    var editorContent: some View {
        VStack(alignment: .leading, spacing: {
            #if os(iOS)
            return groupSpacing
            #else
            return 16
            #endif
        }()) {
            HStack {
                Text("Edit Tile")
                    .font(.title2.bold())
                Spacer()
                Button("Close") {
                    onDismiss()
                }
                #if os(iOS)
                .buttonStyle(.bordered)
                #else
                .buttonStyle(.borderless)
                #endif
            }

            if isMultiTileEdit {
                // When editing multiple tiles at once, only show formatting controls
                // (tile appearance + text formatting) and apply changes to all
                // selected tiles via the callbacks passed in from the root view.
                // Scrollable content for multi-tile edit
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        tileAppearanceSection
                        tileSizeSection
                        moduleAppearanceSection
                        textFormattingSection
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
                .background(Color.clear)
                #if os(iOS)
                .scrollDismissesKeyboard(.immediately)
                #endif
            } else {
                // Tab selector for the inspector content
                Picker("", selection: $selectedInspectorTab) {
                    ForEach(InspectorTab.allCases) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .liquidGlassIfAvailable()
                }

                // Content for the selected tab
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        switch selectedInspectorTab {
                        case .formatting:
                            tileAppearanceSection
                            tileSizeSection
                            moduleAppearanceSection
                            textFormattingSection
                        case .modules:
                            modulesReorderSection
                            selectedModuleDetailSection
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
                .background(Color.clear)
                #if os(iOS)
                .scrollDismissesKeyboard(.immediately)
                #endif
            }

            // Scrollable content below; footer is pinned on iOS.
        }
    }

    var observedEditorContent: some View {
        editorContent
        .onAppear {
            // Seed the inspector state from the tile's current values.
            resetEditorStateFromInitialValues()
            moduleHeightByID = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0.moduleHeightPoints ?? defaultModuleHeightDisplayPoints(for: $0)) })
            syncModuleSelection(with: modules)
            consumePendingFirstModuleSelectionIfNeeded()
            rebuildShureChannelDescriptors()
            if pendingModuleCatalogTileID == tileID {
                showsModuleCatalogModal = true
                pendingModuleCatalogTileID = nil
            }
        }
        .onReceive(ExternalDevicesStore.shared.$devices) { _ in
            rebuildShureChannelDescriptors()
        }
        .onChange(of: tileID, initial: false) { _, _ in
            if pendingModuleCatalogTileID == tileID {
                showsModuleCatalogModal = true
                pendingModuleCatalogTileID = nil
            }
        }
        .onDisappear {
            #if os(macOS)
            NSColorPanel.shared.close()
            #endif
        }
        .onChange(of: modules, initial: false) { _, newValue in
            editableModules = newValue
            moduleHeightByID = Dictionary(uniqueKeysWithValues: newValue.map { ($0.id, $0.moduleHeightPoints ?? defaultModuleHeightDisplayPoints(for: $0)) })
            syncModuleSelection(with: newValue)
        }
        .onChange(of: initialTileSizeWidthText, initial: false) { _, newValue in
            guard tileSizeFieldFocus == nil, !hasStartedTileSizeEdit else { return }
            if !newValue.isEmpty {
                tileSizeWidthText = newValue
            }
        }
        .onChange(of: initialTileSizeHeightText, initial: false) { _, newValue in
            guard tileSizeFieldFocus == nil, !hasStartedTileSizeEdit else { return }
            if !newValue.isEmpty {
                tileSizeHeightText = newValue
            }
        }
        .onChange(of: currentTileSize, initial: false) { _, newValue in
            guard tileSizeFieldFocus == nil else { return }
            tileSizeWidthText = String(Int(newValue.width.rounded()))
            tileSizeHeightText = String(Int(newValue.height.rounded()))
            hasStartedTileSizeEdit = false
        }
        .onChange(of: tileID, initial: false) { _, _ in
            // Switching tiles should re-seed inspector state; reset handles gating.
            resetEditorStateFromInitialValues()
            moduleHeightByID = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0.moduleHeightPoints ?? defaultModuleHeightDisplayPoints(for: $0)) })
            syncModuleSelection(with: modules)
            consumePendingFirstModuleSelectionIfNeeded()
        }
    }

    #if os(iOS)
    private func applyIOSInspectorChrome<Content: View>(to content: Content) -> some View {
        content
            .padding(.horizontal, contentHPadding)
            .padding(.vertical, contentVPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .controlSize(isIPadRegularWidth ? .regular : .small)
            .padding(.bottom, 64)
            .overlay(alignment: .bottom) {
                footerButtons
                    .padding(.horizontal, contentHPadding)
                    .padding(.vertical, 12)
                    .background {
                        inspectorFooterBackground
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
            }
            .background {
                inspectorPanelBackground
            }
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(inspectorPanelStrokeColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(6)
    }
    #endif

    #if os(macOS)
    private func applyMacInspectorChrome<Content: View>(to content: Content) -> some View {
        content
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(minWidth: 420, minHeight: 340)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(inspectorPanelOverlayColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(inspectorPanelStrokeColor, lineWidth: 1)
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(6)
    }
    #endif

    @ViewBuilder
    var coreBody: some View {
        #if os(iOS)
        applyIOSInspectorChrome(to: observedEditorContent)
        #else
        applyMacInspectorChrome(to: observedEditorContent)
            .environment(\.dashboardVariableValues, GraphRuntime.variableValuesByName(tab: tab))
        #endif
    }
}

// Insert main body property into struct
extension DashboardTileEditView {
    var body: some View {
        coreBody
    }
}

// MARK: - DashboardModuleModel Text Model Helper
extension DashboardModuleModel {
    var rosterPickerModel: RosterPickerModuleModel? {
        if case .rosterPicker(let model) = kind { return model }
        return nil
    }

    var textModel: TextModuleModel? {
        if case .text(let model) = kind { return model }
        return nil
    }

    var imageModel: ImageModuleModel? {
        if case .image(let model) = kind { return model }
        return nil
    }

    var documentModel: DocumentModuleModel? {
        if case .document(let model) = kind { return model }
        return nil
    }

    var ndiModel: NDIModuleModel? {
        if case .ndi(let model) = kind { return model }
        return nil
    }

    var webpageModel: WebpageModuleModel? {
        if case .webpage(let model) = kind { return model }
        return nil
    }

    var youtubeStreamMonitorModel: YouTubeStreamMonitorModuleModel? {
        if case .youtubeStreamMonitor(let model) = kind { return model }
        return nil
    }

    var buttonModel: ButtonModuleModel? {
        if case .button(let model) = kind { return model }
        return nil
    }
}

// MARK: - Sections

extension DashboardTileEditView {
    /// True when the active tab's automation graph has at least one outgoing link
    /// from this Button's auto-mirrored trigger node.
    func isButtonLinkedInAutomation(buttonModuleId: UUID) -> Bool {
        guard let links = tab.graph?.links, !links.isEmpty else { return false }
        let portId = "node:\(buttonModuleId.uuidString)"
        return links.contains { link in
            link.fromTileId == buttonModuleId || link.fromPortId == portId
        }
    }

    /// The currently active module for showing details. If an explicit
    /// selection exists and is still in the modules array, that module is
    /// used. Otherwise, the first module in sorted order is used.
    private var activeSelectedModule: DashboardModuleModel? {
        if let id = selectedModuleID,
           let found = sortedModules.first(where: { $0.id == id }) {
            return found
        }
        #if os(iOS)
        return nil
        #else
        return sortedModules.first
        #endif
    }

    /// Detail section for the currently selected module in the Modules tab.
    @ViewBuilder
    var selectedModuleDetailSection: some View {
        if let module = activeSelectedModule {
            let detailModule = editableModules.first(where: { $0.id == module.id }) ?? module
            VStack(alignment: .leading, spacing: 12) {
                moduleSettingsView(for: detailModule)
                    .toggleStyle(.switch)
                modulePaddingSection(for: detailModule)
            }
            .id(moduleDetailIdentity(for: detailModule))
        } else if !sortedModules.isEmpty {
            ContentUnavailableView(
                "Select a Module",
                systemImage: "slider.horizontal.3",
                description: Text("Choose a module above to load its settings.")
            )
        } else {
            // No modules at all; nothing to show.
            EmptyView()
        }
    }

    private func moduleSettingsView(for module: DashboardModuleModel) -> AnyView {
        switch module.kind {
        case .person: AnyView(moduleSettings_person(module: module))
        case .pcoRundown: AnyView(moduleSettings_pcoRundown(module: module))
        case .pcoTeamAssignments: AnyView(moduleSettings_pcoTeamAssignments(module: module))
        case .rosterTeamAssignments: AnyView(moduleSettings_rosterTeamAssignments(module: module))
        case .time: AnyView(moduleSettings_time(module: module))
        case .timecode: AnyView(moduleSettings_timecode(module: module))
        case .dawTransport: AnyView(moduleSettings_dawTransport(module: module))
        case .shureWireless: AnyView(moduleSettings_shureWireless(module: module))
        case .shureOverview: AnyView(moduleSettings_shureOverview(module: module))
        case .sennheiserWireless: AnyView(moduleSettings_sennheiserWireless(module: module))
        case .proPresenter: AnyView(moduleSettings_proPresenter(module: module))
        case .rosterPicker: AnyView(moduleSettings_rosterPicker(module: module))
        case .text: AnyView(moduleSettings_text(module: module))
        case .image: AnyView(moduleSettings_image(module: module))
        case .document: AnyView(moduleSettings_document(module: module))
        case .ndi: AnyView(moduleSettings_ndi(module: module))
        case .webpage: AnyView(moduleSettings_webpage(module: module))
        case .youtubeStreamMonitor: AnyView(moduleSettings_youtubeStreamMonitor(module: module))
        case .button: AnyView(moduleSettings_button(module: module))
        case .separator: AnyView(moduleSettings_separator(module: module))
        case .resolume: AnyView(moduleSettings_resolume(module: module))
        case .dbReader: AnyView(moduleSettings_dbReader(module: module))
        case .liveTranscription: AnyView(moduleSettings_liveTranscription(module: module))
        case .rta: AnyView(moduleSettings_rta(module: module))
        case .spectrograph: AnyView(moduleSettings_spectrograph(module: module))
        }
    }

    var modulesReorderSection: some View {
        GroupBox("Modules in Tile") {
            VStack(alignment: .leading, spacing: 8) {

                if sortedModules.isEmpty {
                    Text("No modules have been added to this tile yet.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    #if os(iOS)
                    VStack(spacing: 8) {
                        ForEach(sortedModules, id: \.id) { module in
                            moduleInspectorRow(module)
                        }
                    }
                    #else
                    List(selection: $selectedModuleIDs) {
                        ForEach(sortedModules, id: \.id) { module in
                            HStack(spacing: 8) {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                                Text(moduleLabel(for: module))
                                    .font(.title3)
                                Spacer()
                            }
                            .tag(module.id)
                            .contextMenu {
                                Button("Duplicate") {
                                    let targets = selectedModuleIDs.contains(module.id)
                                        ? selectedModuleIDs
                                        : Set([module.id])
                                    if !selectedModuleIDs.contains(module.id) {
                                        selectedModuleIDs = targets
                                    }
                                    duplicateModules(targets)
                                }
                                Button("Delete", role: .destructive) {
                                    let targets = selectedModuleIDs.contains(module.id)
                                        ? selectedModuleIDs
                                        : Set([module.id])
                                    if !selectedModuleIDs.contains(module.id) {
                                        selectedModuleIDs = targets
                                    }
                                    deleteModules(targets)
                                }
                            }
#if os(iOS)
                            .listRowSeparator(.visible)
#endif
                        }
                        .onMove { indices, newOffset in
                            let modulesArray = sortedModules
                            guard let source = indices.first,
                                  modulesArray.indices.contains(source) else { return }

                            let fromID = modulesArray[source].id
                            let rawTarget = (newOffset > source) ? (newOffset - 1) : newOffset
                            let maxIndex = max(0, modulesArray.count - 1)
                            let targetIndex = min(max(0, rawTarget), maxIndex)

                            onMoveModule(fromID, targetIndex)
                        }
                        .onDelete { indices in
                            let modulesArray = sortedModules
                            let idsToDelete: [UUID] = indices.compactMap { idx in
                                modulesArray.indices.contains(idx) ? modulesArray[idx].id : nil
                            }
                            deleteModules(Set(idsToDelete))
                        }
                    }
#if os(iOS)
                    .listStyle(.insetGrouped)
#else
                    .listStyle(.inset)
#endif
#if os(iOS)
                    .background(Color.clear)
                    .frame(minHeight: 120, idealHeight: 160, maxHeight: isIPadRegularWidth ? 220 : 200)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, .constant(.active))
#else
                    .frame(minHeight: 140, idealHeight: 200, maxHeight: 280)
#endif
                    .onChange(of: selectedModuleIDs) { _, newValue in
                        if newValue.count == 1 {
                            selectedModuleID = newValue.first
                        } else if newValue.isEmpty {
                            selectedModuleID = nil
                        }
                    }
                    #endif

                    HStack(spacing: 12) {
                        Button {
                            duplicateModules(selectedModuleIDs)
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }
                        .disabled(selectedModuleIDs.isEmpty)

                        Button(role: .destructive) {
                            deleteModules(selectedModuleIDs)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(selectedModuleIDs.isEmpty)
                    }
                    .font(.callout)
                }

                // Add Module button styled like the dashboard "+" menu rows
                Button {
                    showsModuleCatalogModal = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.accentColor.opacity(0.22))
                            DashboardSymbolImage("square.grid.2x2")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(colorScheme == .dark ? Color.white : Color.accentColor)
                        }
                        .frame(width: 36, height: 36)

                        Text("Add Module")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)

                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.70 : 0.16))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(inspectorSectionStrokeColor, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
        .sheet(isPresented: $showsModuleCatalogModal) {
            #if os(macOS)
            DashboardModuleCatalog.modalView(
                title: "Add Module",
                initialPerson: initialPerson,
                tileID: tileID,
                style: .sheet,
                transcriptionAlreadyPresent: tileHasLiveTranscription(),
                ndiModuleCount: NDIStreamRegistry.shared.ndiModuleCount(forTab: tab.id)
            ) { item in
                addModuleFromPalette(identifier: item.id)
            }
            .padding(12)
            .frame(minWidth: 700, minHeight: 640)
            #else
            DashboardModuleCatalog.modalView(
                title: "Add Module",
                initialPerson: initialPerson,
                tileID: tileID,
                style: .sheet,
                transcriptionAlreadyPresent: tabHasLiveTranscription(),
                ndiModuleCount: NDIStreamRegistry.shared.ndiModuleCount(forTab: tab.id)
            ) { item in
                addModuleFromPalette(identifier: item.id)
            }
            #endif
        }
        .alert("Live Transcription Limit", isPresented: $showsTranscriptionLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
#if os(iOS)
            Text("Only one Live Transcription module is allowed per tab on iPad.")
#else
            Text("Only one Live Transcription module is allowed per tile.")
#endif
        }
    }


    private func addModuleFromPalette(identifier: String) {
        switch identifier {
        case "person":
            let basePerson = initialPerson ?? PersonTileModel(
                name: "Person",
                role: "Role",
                initials: "P"
            )
            onAddModule(.person(basePerson))
        case "pcoRundown", "pco":
            onAddModule(.pcoRundown)
        case "pcoTeamAssignments":
            onAddModule(.pcoTeamAssignments)
        case "rosterTeamAssignments":
            onAddModule(.rosterTeamAssignments)
        case "separator":
            let model = SeparatorModuleModel()
            onAddModule(.separator(model))
        case "shure":
            onAddModule(.shureWireless)
        case "shureOverview":
            onAddModule(.shureOverview)
        case "sennheiser":
            onAddModule(.sennheiserWireless)
        case "propresenter":
            onAddModule(.proPresenter)
        case "ndi":
            onAddModule(.ndi(NDIModuleModel()))
        case "resolume":
            let model = ResolumeModuleModel.default()
            onAddModule(.resolume(model))
        case "time":
            onAddModule(.time)
        case "timecode":
            onAddModule(.timecode)
        case "dawTransport", "proToolsTransport":
            onAddModule(.dawTransport)
        case "rosterPicker":
            onAddModule(.rosterPicker(RosterPickerModuleModel()))
        case "text":
            var defaultText = AttributedString("New text module")
            defaultText.foregroundColor = .white
            defaultText.font = .system(size: 16)
            let model = TextModuleModel(
                header: nil,
                content: defaultText
            )
            onAddModule(.text(model))
        case "image":
            onAddModule(.image(ImageModuleModel()))
        case "document":
            onAddModule(.document(DocumentModuleModel()))
        case "webpage":
            onAddModule(.webpage(WebpageModuleModel()))
        case "youtubeStreamMonitor":
            onAddModule(.youtubeStreamMonitor(YouTubeStreamMonitorModuleModel()))
        case "button":
            onAddModule(.button(ButtonModuleModel()))
        case "dbReader":
            onAddModule(.dbReader(DbReaderModuleModel()))
        case "rta":
            onAddModule(.rta(RTAModuleModel()))
        case "spectrograph":
            onAddModule(.spectrograph(SpectrogramModuleModel()))
        case "transcription":
#if os(iOS)
            let transcriptionBlocked = tabHasLiveTranscription()
#else
            let transcriptionBlocked = tileHasLiveTranscription()
#endif
            if transcriptionBlocked {
                showsTranscriptionLimitAlert = true
            } else {
                onAddModule(.liveTranscription(LiveTranscriptionModuleModel()))
            }
        default:
            break
        }
    }

    private func tileHasLiveTranscription() -> Bool {
        guard let tile = tab.tiles.first(where: { $0.id == tileID }),
              let modules = tile.modules else {
            return false
        }
        return modules.contains(where: { if case .liveTranscription = $0.kind { return true } else { return false } })
    }

    private func tabHasLiveTranscription() -> Bool {
        tab.tiles.contains { tile in
            (tile.modules ?? []).contains { if case .liveTranscription = $0.kind { return true } else { return false } }
        }
    }

    func enabledLiveTranscriptionSourceCount(excludingTileId excludedTileId: UUID? = nil) -> Int {
        tab.tiles.reduce(into: 0) { count, tile in
            if let excludedTileId, tile.id == excludedTileId {
                return
            }
            guard let modules = tile.modules else { return }
            for module in modules {
                guard case .liveTranscription(let model) = module.kind else { continue }
                count += model.sources.filter(\.isEnabled).count
            }
        }
    }

    private func isModuleSelected(_ module: DashboardModuleModel) -> Bool {
        if let id = selectedModuleID {
            return module.id == id
        }
        #if os(iOS)
        return false
        #else
        // When nothing is explicitly selected, treat the first module
        // as the active one for highlighting/details.
        return module.id == sortedModules.first?.id
        #endif
    }

    private var sortedModules: [DashboardModuleModel] {
        editableModules.sorted { $0.order < $1.order }
    }

    private func rebuildShureChannelDescriptors() {
        let devices = ExternalDevicesStore.shared.devices.filter { $0.kind == .shureWireless }

        var out: [ShureChannelDescriptor] = []
        for device in devices {
            let count = device.effectiveShureChannelCount
            guard count > 0 else { continue }
            for index in 1...count {
                out.append(
                    ShureChannelDescriptor(
                        deviceID: device.id,
                        deviceName: device.name,
                        channelIndex: index
                    )
                )
            }
        }

        shureChannelDescriptors = out
    }

    private func moveModuleUpInline(_ module: DashboardModuleModel) {
        guard let currentIndex = sortedModules.firstIndex(where: { $0.id == module.id }) else { return }
        let newIndex = max(0, currentIndex - 1)
        guard newIndex != currentIndex else { return }
        onMoveModule(module.id, newIndex)
    }

    private func moveModuleDownInline(_ module: DashboardModuleModel) {
        let modulesArray = sortedModules
        guard let currentIndex = modulesArray.firstIndex(where: { $0.id == module.id }) else { return }
        let newIndex = min(modulesArray.count - 1, currentIndex + 1)
        guard newIndex != currentIndex else { return }
        onMoveModule(module.id, newIndex)
    }

    private func moduleDetailIdentity(for module: DashboardModuleModel) -> String {
        let moduleIDs = sortedModules.map(\.id.uuidString).joined(separator: ",")
        return "\(module.id.uuidString)|\(moduleKindIdentifier(for: module))|\(moduleIDs)"
    }

    private func moduleKindIdentifier(for module: DashboardModuleModel) -> String {
        switch module.kind {
        case .person: return "person"
        case .pcoRundown: return "pcoRundown"
        case .pcoTeamAssignments: return "pcoTeamAssignments"
        case .rosterTeamAssignments: return "rosterTeamAssignments"
        case .shureWireless: return "shureWireless"
        case .shureOverview: return "shureOverview"
        case .sennheiserWireless: return "sennheiserWireless"
        case .proPresenter: return "proPresenter"
        case .resolume: return "resolume"
        case .time: return "time"
        case .timecode: return "timecode"
        case .dawTransport: return "dawTransport"
        case .rosterPicker: return "rosterPicker"
        case .text: return "text"
        case .image: return "image"
        case .document: return "document"
        case .ndi: return "ndi"
        case .webpage: return "webpage"
        case .youtubeStreamMonitor: return "youtubeStreamMonitor"
        case .separator: return "separator"
        case .liveTranscription: return "liveTranscription"
        case .dbReader: return "dbReader"
        case .button: return "button"
        case .rta: return "rta"
        case .spectrograph: return "spectrograph"
        }
    }

    private func syncModuleSelection(with modules: [DashboardModuleModel]) {
        let ids = Set(modules.map(\.id))

        if let selectedModuleID, ids.contains(selectedModuleID) {
            selectedModuleIDs = [selectedModuleID]
            return
        }

        let survivingSelections = selectedModuleIDs.intersection(ids)
        if let survivingSelection = survivingSelections.first {
            selectedModuleID = survivingSelection
            selectedModuleIDs = [survivingSelection]
            return
        }

        #if os(iOS)
        selectedModuleID = nil
        selectedModuleIDs = []
        #else
        selectedModuleID = modules.first?.id
        selectedModuleIDs = modules.first.map { [$0.id] } ?? []
        #endif
    }

    /// Explicitly selects the first module when this tile was opened via double-click.
    /// Runs after `syncModuleSelection`, which otherwise leaves iOS unselected to avoid
    /// eagerly rendering a module's settings before the tile has finished loading.
    private func consumePendingFirstModuleSelectionIfNeeded() {
        guard pendingFirstModuleSelectTileID == tileID else { return }
        pendingFirstModuleSelectTileID = nil
        guard let first = sortedModules.first else { return }
        selectedModuleID = first.id
        selectedModuleIDs = [first.id]
    }

    #if os(iOS)
    @ViewBuilder
    private func moduleInspectorRow(_ module: DashboardModuleModel) -> some View {
        let isSelected = isModuleSelected(module)

        VStack(spacing: 0) {
            Button {
                selectedModuleID = module.id
                selectedModuleIDs = [module.id]
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .font(.callout.weight(.semibold))

                    Text(moduleLabel(for: module))
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 12)

                    HStack(spacing: 6) {
                        Button {
                            moveModuleUpInline(module)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(sortedModules.first?.id == module.id)

                        Button {
                            moveModuleDownInline(module)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(sortedModules.last?.id == module.id)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.14) : inspectorSectionFillColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : inspectorSectionStrokeColor, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Duplicate") {
                    selectedModuleID = module.id
                    selectedModuleIDs = [module.id]
                    duplicateModules(Set([module.id]))
                }
                Button("Delete", role: .destructive) {
                    selectedModuleID = module.id
                    selectedModuleIDs = [module.id]
                    deleteModules(Set([module.id]))
                }
            }
        }
    }
    #endif

    private func moduleLabel(for module: DashboardModuleModel) -> String {
        switch module.kind {
        case .person(let person):
            if person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Person"
            } else {
                return "Person: \(person.name)"
            }
        case .pcoRundown:
            return "PCO Rundown"
        case .pcoTeamAssignments:
            return "PCO Team Assignments"
        case .rosterTeamAssignments:
            return "Roster Team Assignments"
        case .time:
            return "Time"
        case .timecode:
            return "Timecode"
        case .dawTransport:
            return "DAW Transport"
        case .rosterPicker:
            return "Picker"
        case .shureWireless:
            return "Shure Wireless"
        case .shureOverview:
            return "Shure Overview"
        case .sennheiserWireless:
            return "Sennheiser Wireless"
        case .proPresenter:
            return "ProPresenter"
        case .text:
            return "Text"
        case .image(let model):
            let trimmed = (model.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Image"
            }
            return "Image: \(trimmed)"
        case .document:
            return "Document"
        case .ndi(let model):
            let trimmed = model.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "NDI Feed"
            }
            return "NDI: \(trimmed)"
        case .webpage:
            return "Webpage"
        case .youtubeStreamMonitor:
            return "YouTube Stream Monitor"
        case .separator:
            return "Separator"
        case .resolume:
            return "Resolume"
        case .dbReader:
            return "SPL Meter"
        case .button(let model):
            let trimmed = (model.buttons.first?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Button"
            }
            return "Button: \(trimmed)"
        case .liveTranscription(let model):
            let trimmed = model.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Live Transcription"
            }
            return "Live Transcription: \(trimmed)"
        case .rta:
            return "RTA"
        case .spectrograph:
            return "Spectrograph"
        }
    }
    var tileAppearanceSection: some View {
        GroupBox(label: sectionHeader(
            title: "Tile Appearance",
            helpText: "Adjust the tile background, opacity, corner radius, and title visibility.",
            isShowingHelp: $showsTileAppearanceHelp
        )) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Background Color")
                    ColorPicker("", selection: $backgroundColor, supportsOpacity: false)
                        .labelsHidden()
                        .disabled(useGradientBackground)
                }
#if os(macOS)
                .help("Set the tile background color.")
#endif

                Toggle("Use gradient background", isOn: $useGradientBackground)
#if os(macOS)
                    .help("Replace the flat background with a top-to-bottom gradient.")
#endif

                if useGradientBackground {
                    HStack {
                        Text("Gradient Top")
                        ColorPicker("", selection: $gradientStartColor, supportsOpacity: true)
                            .labelsHidden()
                    }
#if os(macOS)
                    .help("Color used at the top of the tile.")
#endif

                    HStack {
                        Text("Gradient Bottom")
                        ColorPicker("", selection: $gradientEndColor, supportsOpacity: true)
                            .labelsHidden()
                    }
#if os(macOS)
                    .help("Color used at the bottom of the tile.")
#endif
                }

                HStack {
                    Text("Opacity")

                    Slider(value: $backgroundOpacity, in: 0.2...1.0)

                    // Editable percentage field (0–100%)
                    let opacityPercentBinding = Binding<Double>(
                        get: { backgroundOpacity * 100.0 },
                        set: { newValue in
                            let clamped = max(0.0, min(100.0, newValue))
                            // Map back into 0.2–1.0 slider range, clamping to that as well.
                            let asFraction = clamped / 100.0
                            backgroundOpacity = max(0.2, min(1.0, asFraction))
                        }
                    )

                    HStack(spacing: 2) {
                        TextField(
                            "",
                            value: opacityPercentBinding,
                            formatter: percentNumberFormatter
                        )
                        .frame(width: 40)
                        .multilineTextAlignment(.trailing)
                        Text("%")
                    }
                    #if os(iOS)
                    .font(tertiaryLabelFont)
                    #else
                    .font(.caption2)
                    #endif
                    .foregroundStyle(.secondary)

                    Button {
                        backgroundOpacity = DashboardTileDefaults.backgroundOpacity
                        pushTileAppearanceLive()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
#if os(macOS)
                    .help("Reset opacity to default")
#endif
                }
#if os(macOS)
                .help("Adjust the tile background opacity.")
#endif

                HStack {
                    Text("Corner Radius")
                    Slider(value: $cornerRadius, in: 0...40)
                    HStack(spacing: 2) {
                        TextField(
                            "",
                            value: $cornerRadius,
                            formatter: dimensionNumberFormatter
                        )
                        .frame(width: 40)
                        .multilineTextAlignment(.trailing)
                        Text("pt")
                    }
                    #if os(iOS)
                    .font(tertiaryLabelFont)
                    #else
                    .font(.caption2)
                    #endif
                    .foregroundStyle(.secondary)
                    Button {
                        cornerRadius = Double(DashboardTileDefaults.cornerRadius)
                        pushTileAppearanceLive()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                        #if os(iOS)
                        .font(tertiaryLabelFont)
                        #else
                        .font(.caption2)
                        #endif
                    }
                    .buttonStyle(.borderless)
#if os(macOS)
                    .help("Reset corner radius to default")
#endif
                }
#if os(macOS)
                .help("Adjust how rounded the tile corners are.")
#endif

                Toggle("Show tile name", isOn: $showsTitle)
                    .onChange(of: showsTitle, initial: false) { _, _ in
                        hasEditedShowsTitle = true
                        onSaveShowsTitle(showsTitle)
                    }
#if os(macOS)
                    .help("Show or hide the tile title in the header.")
#endif
            }
            .toggleStyle(SwitchToggleStyle())
        }
        .onChange(of: backgroundOpacity, initial: false) { _, _ in
            guard hasInitializedInspectorState, !isSeedingInspectorState else { return }
            hasEditedTileAppearance = true
            pushTileAppearanceLive()
        }
        .onChange(of: cornerRadius, initial: false) { _, _ in
            guard hasInitializedInspectorState, !isSeedingInspectorState else { return }
            hasEditedTileAppearance = true
            pushTileAppearanceLive()
        }
        .onChange(of: backgroundColor, initial: false) { _, _ in
            guard hasInitializedInspectorState, !isSeedingInspectorState else { return }
            hasEditedTileAppearance = true
            pushTileAppearanceLive()
        }
        .onChange(of: useGradientBackground, initial: false) { _, _ in
            guard hasInitializedInspectorState, !isSeedingInspectorState else { return }
            hasEditedTileAppearance = true
            pushTileAppearanceLive()
        }
        .onChange(of: gradientStartColor, initial: false) { _, _ in
            guard hasInitializedInspectorState, !isSeedingInspectorState else { return }
            guard useGradientBackground else { return }
            hasEditedTileAppearance = true
            pushTileAppearanceLive()
        }
        .onChange(of: gradientEndColor, initial: false) { _, _ in
            guard hasInitializedInspectorState, !isSeedingInspectorState else { return }
            guard useGradientBackground else { return }
            hasEditedTileAppearance = true
            pushTileAppearanceLive()
        }
        .onChange(of: tileContentPadding, initial: false) { _, _ in
            guard hasInitializedInspectorState, !isSeedingInspectorState else { return }
            hasEditedTileContentPadding = true
            pushTileContentPaddingLive()
        }
        .onChange(of: moduleLayout, initial: false) { _, _ in
            guard hasInitializedInspectorState, !isSeedingInspectorState else { return }
            hasEditedModuleLayout = true
            onSaveModuleLayout(moduleLayout)
        }
    }

    var tileSizeSection: some View {
        GroupBox(label: sectionHeader(
            title: "Tile Size",
            helpText: "Set a fixed height and width for this tile.",
            isShowingHelp: $showsTileSizeHelp
        )) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("W")
                    TextField("Width", text: $tileSizeWidthText)
                        .frame(width: 70)
                        .textFieldStyle(.roundedBorder)
                        .focused($tileSizeFieldFocus, equals: .width)
                        .onChange(of: tileSizeWidthText, initial: false) { _, _ in
                            pushTileSizeLive()
                        }

                    Text("×")
                        .foregroundStyle(.secondary)

                    Text("H")
                    TextField("Height", text: $tileSizeHeightText)
                        .frame(width: 70)
                        .textFieldStyle(.roundedBorder)
                        .focused($tileSizeFieldFocus, equals: .height)
                        .onChange(of: tileSizeHeightText, initial: false) { _, _ in
                            pushTileSizeLive()
                        }

                    Spacer(minLength: 0)

                    Button {
                        tileSizeWidthText = initialTileSizeWidthText
                        tileSizeHeightText = initialTileSizeHeightText
                        applyTileSizeEdits()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                }

                let labelPrefix = (initialTileSize == nil) ? "Default" : "Original"
                let labelSize = initialTileSize ?? defaultTileSize
                Text("\(labelPrefix) \(Int(labelSize.width))×\(Int(labelSize.height)) pt")
                    #if os(iOS)
                    .font(secondaryLabelFont)
                    #else
                    .font(.caption2)
                    #endif
                    .foregroundStyle(.secondary)
            }
        }
    }
    var moduleAppearanceSection: some View {
        GroupBox(label: sectionHeader(
            title: "Module Appearance",
            helpText: "Control padding between the tile border and its modules, and choose the module layout.",
            isShowingHelp: $showsModuleAppearanceHelp
        )) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Module Padding")
                    Slider(value: $tileContentPadding, in: 0...50)
                    HStack(spacing: 2) {
                        TextField(
                            "",
                            value: $tileContentPadding,
                            formatter: paddingNumberFormatter
                        )
                        .frame(width: 40)
                        .multilineTextAlignment(.trailing)
                        Text("pt")
                    }
                    #if os(iOS)
                    .font(tertiaryLabelFont)
                    #else
                    .font(.caption2)
                    #endif
                    .foregroundStyle(.secondary)
                    Button {
                        tileContentPadding = Double(DashboardTileDefaults.contentPadding)
                        pushTileContentPaddingLive()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
    #if os(macOS)
                    .help("Reset padding to default")
    #endif
                }
#if os(macOS)
                .help("Adjust the margin between the tile border and its modules.")
#endif

                VStack(alignment: .leading, spacing: 6) {
                    Picker("Module Layout", selection: $moduleLayout) {
                        ForEach(TileModuleLayout.allCases) { layout in
                            Text(layout.label).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                }
#if os(macOS)
                .help("Choose how modules stack inside the tile.")
#endif
            }
            .toggleStyle(SwitchToggleStyle())
        }
    }

    var textFormattingSection: some View {
        let header = sectionHeader(
            title: "Text Formatting",
            helpText: "Apply font size, weight, color, capitalization, and alignment to all text in this tile's modules.",
            isShowingHelp: $showsTextFormattingHelp
        )
        return GroupBox(label: header) {
            textFormattingControls
        }
    }

    private var textFormattingControls: some View {
        VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Font Size")
                    Slider(value: $textFontSize, in: 12...120)
                    HStack(spacing: 2) {
                        TextField(
                            "",
                            value: $textFontSize,
                            formatter: dimensionNumberFormatter
                        )
                        .frame(width: 40)
                        .multilineTextAlignment(.trailing)
                        Text("pt")
                    }
                    #if os(iOS)
                    .font(tertiaryLabelFont)
                    #else
                    .font(.caption2)
                    #endif
                    .foregroundStyle(.secondary)
                    Button {
                        textFontSize = DashboardTileDefaults.textFontSize
                        pushTextFormattingLive()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                        #if os(iOS)
                        .font(tertiaryLabelFont)
                        #else
                        .font(.caption2)
                        #endif
                    }
                    .buttonStyle(.borderless)
#if os(macOS)
                    .help("Reset font size to default")
#endif
                }
#if os(macOS)
                .help("Change the font size for text in the tile.")
#endif

                HStack {
                    Text("Font Weight")
                    Picker("", selection: $textFontWeight) {
                        ForEach(PersonFontWeight.allCases) { weight in
                            Text(weight.label).tag(weight)
                        }
                    }
                    .pickerStyle(.menu)
                }
#if os(macOS)
                .help("Set the font weight for text in the tile.")
#endif

                HStack {
                    Text("Text Color")
                    ColorPicker("", selection: $textColor, supportsOpacity: true)
                        .labelsHidden()
                }
#if os(macOS)
                .help("Pick the text color used in the tile.")
#endif

                HStack {
                    Text("Capitalization")
                    Picker("", selection: $textCapitalization) {
                        ForEach(TextCapitalizationStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                }
#if os(macOS)
                .help("Control how text is capitalized in the tile.")
#endif

                HStack {
                    Text("Alignment")
                    Picker("", selection: $textJustification) {
                        ForEach(TextJustificationStyle.allCases) { style in
                            DashboardSymbolImage(style.systemImageName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }
#if os(macOS)
                .help("Set the text alignment for the tile.")
#endif

                HStack {
                    Text("Vertical Align")
                    Picker("", selection: $textVerticalAlignment) {
                        ForEach(TextVerticalAlignmentStyle.allCases) { style in
                            DashboardSymbolImage(style.systemImageName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }
#if os(macOS)
                .help("Set the vertical alignment for text in the tile.")
#endif

                Text("These settings apply to all text inside this tile's modules.")
                    #if os(iOS)
                    .font(secondaryLabelFont)
                    #else
                    .font(.caption2)
                    #endif
                    .foregroundStyle(.secondary)
            }.toggleStyle(SwitchToggleStyle())
        .onChange(of: textFontSize, initial: false) { _, _ in
            guard hasInitializedInspectorState, !isSeedingInspectorState else { return }
            hasEditedTextFormatting = true
            pushTextFormattingLive()
        }
        .onChange(of: textFontWeight, initial: false) { _, _ in
            guard hasInitializedInspectorState, !isSeedingInspectorState else { return }
            hasEditedTextFormatting = true
            pushTextFormattingLive()
        }
        .onChange(of: textColor, initial: false) { _, _ in
            guard hasInitializedInspectorState, !isSeedingInspectorState else { return }
            hasEditedTextFormatting = true
            pushTextFormattingLive()
        }
        .onChange(of: textCapitalization, initial: false) { _, _ in
            guard hasInitializedInspectorState, !isSeedingInspectorState else { return }
            hasEditedTextFormatting = true
            pushTextFormattingLive()
        }
        .onChange(of: textJustification, initial: false) { _, _ in
            guard hasInitializedInspectorState, !isSeedingInspectorState else { return }
            hasEditedTextFormatting = true
            pushTextFormattingLive()
        }
        .onChange(of: textVerticalAlignment, initial: false) { _, _ in
            guard hasInitializedInspectorState, !isSeedingInspectorState else { return }
            hasEditedTextFormatting = true
            pushTextFormattingLive()
        }
    }

    private func sectionHeader(
        title: String,
        helpText: String,
        isShowingHelp: Binding<Bool>
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer()
#if os(iOS)
            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            let helpContent = VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                Text(helpText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Close") {
                    isShowingHelp.wrappedValue = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)

            let helpButton = Button {
                isShowingHelp.wrappedValue = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)

            if isPad {
                helpButton
                    .popover(isPresented: isShowingHelp, arrowEdge: .top) {
                        helpContent.frame(width: 320)
                    }
            } else {
                helpButton
                    .sheet(isPresented: isShowingHelp) {
                        helpContent
                    }
            }
#endif
        }
    }

    var productionSection: some View {
        GroupBox("Production Module") {
            Text("No editable settings for this module yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var footerButtons: some View {
        HStack {
            Spacer()
            Button("Close") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        #if os(macOS)
        .padding(.top, 8)
        #endif
    }
}

// MARK: - Live Preview Helpers

extension DashboardTileEditView {
    @ViewBuilder
    private func modulePaddingSection(for module: DashboardModuleModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Module Spacing")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
#if os(macOS)
                    .help("Adjust the height and the extra space above and below this module inside the tile.")
#endif

                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Height")

                    // Height is stored in points. Nil means "auto".
                    let heightBinding = Binding<Double>(
                        get: {
                            Double(moduleHeightByID[module.id] ?? defaultModuleHeightDisplayPoints(for: module))
                        },
                        set: { newValue in
                            let minH = Double(minimumHeightPoints(for: module))
                            let clamped = max(minH, min(2000.0, newValue))

                            // Update local cache immediately so the slider doesn't snap back.
                            moduleHeightByID[module.id] = CGFloat(clamped)

                            // Keep the local editable copy in sync for other UI.
                            if let idx = editableModules.firstIndex(where: { $0.id == module.id }) {
                                editableModules[idx].moduleHeightPoints = CGFloat(clamped)
                            }

                            updateModuleHeightPoints(moduleID: module.id, heightPoints: CGFloat(clamped))
                        }
                    )

                    Slider(
                        value: heightBinding,
                        in: Double(minimumHeightPoints(for: module))...Double(max(moduleHeightSliderMaxPoints(for: module), minimumHeightPoints(for: module) + 40))
                    )

                    HStack(spacing: 2) {
                        TextField(
                            "",
                            value: heightBinding,
                            formatter: moduleHeightNumberFormatter
                        )
                        .frame(width: 54)
                        .multilineTextAlignment(.trailing)
                        Text("pt")
                    }
                    #if os(iOS)
                    .font(tertiaryLabelFont)
                    #else
                    .font(.caption2)
                    #endif
                    .foregroundStyle(.secondary)

                    Button {
                        moduleHeightByID[module.id] = defaultModuleHeightDisplayPoints(for: module)
                        if let idx = editableModules.firstIndex(where: { $0.id == module.id }) {
                            editableModules[idx].moduleHeightPoints = nil
                        }
                        updateModuleHeightPoints(moduleID: module.id, heightPoints: nil)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
#if os(macOS)
                    .help("Reset height to Auto")
#endif
                }

                // Warnings related to fixed heights.
                let requested = moduleHeightByID[module.id] ?? defaultModuleHeightDisplayPoints(for: module)

                // Too tall for the tile.
                if let tileH = tileHeightPoints, requested > tileH {
                    Label(
                        "Height exceeds tile height (\(Int(tileH))pt). Module will be clipped.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    #if os(iOS)
                    .font(secondaryLabelFont)
                    #else
                    .font(.caption2)
                    #endif
                    .foregroundStyle(.orange)
                }

                // At/near minimum height: likely clipping of content.
                let minWarn = minimumHeightPoints(for: module)
                if requested <= (minWarn + 0.5) {
                    Label(
                        "Height is at the minimum (\(Int(minWarn))pt). Content may be clipped.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    #if os(iOS)
                    .font(secondaryLabelFont)
                    #else
                    .font(.caption2)
                    #endif
                    .foregroundStyle(.orange)
                }

                HStack {
                    Text("Top padding")

                    let topBinding = Binding<Double>(
                        get: {
                            Double(editableModules.first(where: { $0.id == module.id })?.paddingTop ?? 0)
                        },
                        set: { newValue in
                            updateModulePadding(moduleID: module.id, top: CGFloat(newValue), bottom: nil)
                        }
                    )

                    Slider(
                        value: topBinding,
                        in: 0...200
                    )

                    HStack(spacing: 2) {
                        TextField(
                            "",
                            value: topBinding,
                            formatter: paddingNumberFormatter
                        )
                        .frame(width: 40)
                        .multilineTextAlignment(.trailing)
                        Text("pt")
                    }
                    #if os(iOS)
                    .font(tertiaryLabelFont)
                    #else
                    .font(.caption2)
                    #endif
                    .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Bottom padding")

                    let bottomBinding = Binding<Double>(
                        get: {
                            Double(editableModules.first(where: { $0.id == module.id })?.paddingBottom ?? 0)
                        },
                        set: { newValue in
                            updateModulePadding(moduleID: module.id, top: nil, bottom: CGFloat(newValue))
                        }
                    )

                    Slider(
                        value: bottomBinding,
                        in: 0...200
                    )

                    HStack(spacing: 2) {
                        TextField(
                            "",
                            value: bottomBinding,
                            formatter: paddingNumberFormatter
                        )
                        .frame(width: 40)
                        .multilineTextAlignment(.trailing)
                        Text("pt")
                    }
                    #if os(iOS)
                    .font(tertiaryLabelFont)
                    #else
                    .font(.caption2)
                    #endif
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(inspectorSectionFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(inspectorSectionStrokeColor, lineWidth: 1)
                )
        )
    }
}
extension DashboardTileEditView {
    private func updateModulePadding(moduleID: UUID, top: CGFloat?, bottom: CGFloat?) {
        onUpdateModulePadding(moduleID, top, bottom)
    }

    private func updateModuleHeightPoints(moduleID: UUID, heightPoints: CGFloat?) {
        // Reuse the existing callback signature for now.
        onUpdateModuleScale(moduleID, heightPoints)
    }

    private func updateModuleScale(moduleID: UUID, scale: CGFloat?) {
        // Back-compat shim: treat scale as "height points" if this is still called.
        onUpdateModuleScale(moduleID, scale)
    }

    private func moduleHeightSliderMaxPoints(for module: DashboardModuleModel) -> CGFloat {
        let minHeight = minimumHeightPoints(for: module)
        let tileCap = tileHeightPoints.map { max($0, minHeight + 40) }
        let preferred = max(minHeight + 120, 320)
        return max(preferred, tileCap ?? 0)
    }
    
    private func sortServiceTimeLabelsChronologically(_ labels: [String]) -> [String] {
        guard !labels.isEmpty else { return labels }

        struct Formatter {
            static let shared: DateFormatter = {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.dateFormat = "h:mm a"
                return df
            }()
        }

        return labels.sorted { lhs, rhs in
            let f = Formatter.shared
            let lDate = f.date(from: lhs)
            let rDate = f.date(from: rhs)

            switch (lDate, rDate) {
            case let (l?, r?):
                return l < r
            case (nil, nil):
                return lhs < rhs
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }
    }

    func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(inspectorSectionFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(inspectorSectionStrokeColor, lineWidth: 1)
                )
        )
    }

    /// Simple formatter for padding values so we can edit them via text fields.
    private var paddingNumberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = 0
        formatter.maximum = 200
        formatter.maximumFractionDigits = 0
        return formatter
    }
    /// Formatter for module height values in points (minimum...2000).
    private var moduleHeightNumberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = 0
        formatter.maximum = 2000
        formatter.maximumFractionDigits = 0
        return formatter
    }
    /// Formatter for percentage-like values (0–100 or -100–100).
    private var percentNumberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = -100
        formatter.maximum = 100
        formatter.maximumFractionDigits = 0
        return formatter
    }

    private var calibrationNumberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = -2000
        formatter.maximum = 2000
        formatter.allowsFloats = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }

    private var thresholdNumberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = 0
        formatter.maximum = 200
        formatter.allowsFloats = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }

    func resolvedDbReaderZSlow(for moduleID: UUID, model: DbReaderModuleModel) -> Double {
        let controller = DbReaderControllerStore.shared.controller(moduleId: moduleID, tileId: tileID, settings: model)
        if controller.currentZSlow.isFinite, controller.currentZSlow != 0 { return controller.currentZSlow }
        let payload = DbReaderOutputStore.shared.payload(for: moduleID)
        return payload.isStale ? 0 : payload.spl
    }

    func resolvedDbReaderRawDbFS(for moduleID: UUID, model: DbReaderModuleModel) -> Double {
        let controller = DbReaderControllerStore.shared.controller(moduleId: moduleID, tileId: tileID, settings: model)
        if controller.rawDbFS.isFinite, controller.rawDbFS != 0 { return controller.rawDbFS }
        let payload = DbReaderOutputStore.shared.payload(for: moduleID)
        return payload.isStale ? 0 : payload.rawDbFS
    }

    private var publishRateNumberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = 1
        formatter.maximum = 60
        formatter.maximumFractionDigits = 0
        return formatter
    }

    var historySecondsFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = 1
        formatter.maximum = 3600
        formatter.maximumFractionDigits = 0
        return formatter
    }

    /// Formatter for general dimension-like values (e.g., font sizes, radii, thickness).
    private var dimensionNumberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = 0
        formatter.maximum = 500
        formatter.maximumFractionDigits = 0
        return formatter
    }

    /// Format an integer number of seconds as m:ss for display.
    private func formattedDuration(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func pushTextFormattingLive() {
        guard hasInitializedInspectorState, !isSeedingInspectorState else { return }
        hasEditedTextFormatting = true
        let codableColor = CodableColor(textColor)
        onPreviewTextFormatting(
            textFontSize,
            textFontWeight,
            codableColor,
            textCapitalization,
            textJustification,
            textVerticalAlignment
        )
        onSaveTextFormatting(
            textFontSize,
            textFontWeight,
            codableColor,
            textCapitalization,
            textJustification,
            textVerticalAlignment
        )
    }

    func pushTileAppearanceLive() {
        guard hasInitializedInspectorState, !isSeedingInspectorState else { return }
        hasEditedTileAppearance = true
        let codableColor = CodableColor(backgroundColor)
        let resolvedGradient = useGradientBackground
            ? TileGradientBackground(
                startColor: CodableColor(gradientStartColor),
                endColor: CodableColor(gradientEndColor)
            )
            : nil
        onPreviewTileAppearance(
            initialBackgroundStyle,
            backgroundOpacity,
            CGFloat(cornerRadius),
            codableColor,
            resolvedGradient
        )
        onSaveTileAppearance(
            initialBackgroundStyle,
            backgroundOpacity,
            CGFloat(cornerRadius),
            codableColor,
            resolvedGradient
        )
    }

    func pushTileContentPaddingLive() {
        guard hasInitializedInspectorState, !isSeedingInspectorState else { return }
        hasEditedTileContentPadding = true
        let padding = CGFloat(tileContentPadding)
        onPreviewTileContentPadding(padding)
        onSaveTileContentPadding(padding)
    }

    private func beginTileSizeEditIfNeeded() {
        guard !hasStartedTileSizeEdit else { return }
        onBeginTileSizeEdit()
        hasStartedTileSizeEdit = true
    }

    private func deleteModules(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        if let current = selectedModuleID, ids.contains(current) {
            selectedModuleID = nil
        }
        ids.forEach { onRemoveModule($0) }
        selectedModuleIDs.subtract(ids)
    }

    private func duplicateModules(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let ordered = sortedModules.filter { ids.contains($0.id) }
        ordered.forEach { onDuplicateModule($0.id) }
    }

    private func pushTileSizeLive() {
        guard hasInitializedInspectorState, !isSeedingInspectorState else { return }

        let trimmedWidth = tileSizeWidthText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHeight = tileSizeHeightText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedWidth.isEmpty, Double(trimmedWidth) == nil { return }
        if !trimmedHeight.isEmpty, Double(trimmedHeight) == nil { return }

        let widthInput = trimmedWidth.isEmpty ? nil : Double(trimmedWidth)
        let heightInput = trimmedHeight.isEmpty ? nil : Double(trimmedHeight)

        guard widthInput != nil || heightInput != nil else { return }

        beginTileSizeEditIfNeeded()
        onUpdateTileSizeLive(widthInput, heightInput)
    }

    private func applyTileSizeEdits() {
        let trimmedWidth = tileSizeWidthText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHeight = tileSizeHeightText.trimmingCharacters(in: .whitespacesAndNewlines)

        let widthInput = trimmedWidth.isEmpty ? nil : Double(trimmedWidth)
        let heightInput = trimmedHeight.isEmpty ? nil : Double(trimmedHeight)

        if !trimmedWidth.isEmpty, widthInput == nil { return }
        if !trimmedHeight.isEmpty, heightInput == nil { return }

        guard widthInput != nil || heightInput != nil else { return }

        beginTileSizeEditIfNeeded()
        onUpdateTileSizeLive(widthInput, heightInput)
    }


}
// MARK: - Text Justification Style

enum TextJustificationStyle: String, CaseIterable, Identifiable, Codable {
    case leading
    case center
    case trailing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .leading: return "Left"
        case .center: return "Center"
        case .trailing: return "Right"
        }
    }
    var systemImageName: String {
        switch self {
        case .leading: return "distribute.horizontal.left"
        case .center: return "distribute.horizontal.center"
        case .trailing: return "distribute.horizontal.right"
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

// MARK: - Inspector Tabs

private enum InspectorTab: String, CaseIterable, Identifiable {
    case modules
    case formatting

    var id: String { rawValue }

    var label: String {
        switch self {
        case .modules: return "Modules"
        case .formatting: return "Formatting"
        }
    }
}

private enum TileSizeField: Hashable {
    case width
    case height
}
