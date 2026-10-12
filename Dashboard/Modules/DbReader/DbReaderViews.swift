import SwiftUI
import UniformTypeIdentifiers

// MARK: - SwiftUI Views

struct AveragingProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            let width = max(0, geo.size.width)
            let clamped = min(1.0, max(0.0, progress))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.15))
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.65))
                    .frame(width: max(2, width * clamped))
            }
        }
    }
}

struct SplBarMeterView: View {
    let spl: Double
    let range: ClosedRange<Double>
    let limitColorEnabled: Bool
    let limitWarningDb: Double
    let limitAlertDb: Double
    let normalColor: Color
    let warningColor: Color
    let alertColor: Color

    private let segmentCount = 15

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: max(1, geo.size.width * 0.015)) {
                ForEach(0..<segmentCount, id: \.self) { index in
                    let segmentDb = range.lowerBound +
                        (range.upperBound - range.lowerBound) * Double(index) / Double(segmentCount)
                    let isLit = !spl.isNaN && spl > segmentDb
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isLit ? segmentColor(for: segmentDb) : Color.white.opacity(0.1))
                }
            }
        }
    }

    private func segmentColor(for db: Double) -> Color {
        guard limitColorEnabled else { return Color.white.opacity(0.8) }
        if db >= limitAlertDb { return alertColor }
        if db >= limitWarningDb { return warningColor }
        return normalColor
    }
}

struct DbReaderTileView: View {
    @Binding var tab: DashboardTab
    @Binding var tile: DashboardTileModel
    @Binding var module: DashboardModuleModel
    var isLiveMode: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.tileTextFormatting) private var tileTextFormatting
    @Environment(\.dashboardIsLANSnapshotRendering) private var isLANSnapshotRendering
    @AppStorage("dashboard_live_mode_enabled") private var liveModeEnabled: Bool = false

    @StateObject private var controller: DbReaderController
    private var effectiveLiveMode: Bool {
        isLiveMode || liveModeEnabled
    }

    init(
        tab: Binding<DashboardTab>,
        tile: Binding<DashboardTileModel>,
        module: Binding<DashboardModuleModel>,
        isLiveMode: Bool
    ) {
        self._tab = tab
        self._tile = tile
        self._module = module
        self.isLiveMode = isLiveMode

        let model = DbReaderTileView.resolveModel(module: module.wrappedValue)
        let controller = DbReaderControllerStore.shared.controller(moduleId: module.wrappedValue.id, tileId: tile.wrappedValue.id, settings: model)
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some View {
        let model = Self.resolveModel(module: module)
        if isLANSnapshotRendering {
            lanSnapshotView(model: model)
        } else {
            let isLiveDisplay = effectiveLiveMode && model.isArmedByUser
            let displayHistory = controller.frozenHistory
            let graphHistory = controller.frozenGraphHistory.isEmpty ? displayHistory : controller.frozenGraphHistory
            let displaySpl = isLiveDisplay ? controller.displaySpl : controller.frozenPayload.spl
            let displaySlowSpl = isLiveDisplay
                ? controller.currentSplSlow
                : (controller.frozenPayload.caSlow ?? Double.nan)
            let displayHold = isLiveDisplay
                ? controller.formattedPeakHold()
                : formattedHold(from: displayHistory)
            let displayAveragingProgress = isLiveDisplay ? controller.averagingProgress : controller.frozenAveragingProgress
            dbReaderBody(
                model: model,
                isLiveDisplay: isLiveDisplay,
                displaySpl: displaySpl,
                displaySlowSpl: displaySlowSpl,
                displayHold: displayHold,
                displayHistory: displayHistory,
                displayGraphHistory: graphHistory,
                displayAveragingProgress: displayAveragingProgress
            )
        }
    }

    private func dbReaderBody(
        model: DbReaderModuleModel,
        isLiveDisplay: Bool,
        displaySpl: Double,
        displaySlowSpl: Double,
        displayHold: String,
        displayHistory: [DbSample],
        displayGraphHistory: [DbSample],
        displayAveragingProgress: Double
    ) -> some View {
        ZStack {
            VStack(alignment: resolvedVStackAlignment, spacing: 10) {
                header(model: model)

                if model.showMainValue {
                    if model.weighting == .ca {
                        let timeLabel = model.timeWeighting == .fast ? "Fast" : "Slow"
                        VStack(alignment: resolvedVStackAlignment, spacing: 2) {
                            Text(formatSpl(displaySpl))
                                .font(.system(size: baseFontSize * 1.8, weight: primaryFontWeight, design: .rounded))
                                .foregroundStyle(splTextColor(model: model, spl: displaySpl))
                                .monospacedDigit()

                            Text("C-A \(timeLabel)")
                                .font(.system(size: baseFontSize * 0.65, weight: primaryFontWeight))
                                .foregroundStyle(secondaryTextColor)

                            if model.averagingEnabled && (isLiveDisplay || displayAveragingProgress > 0) {
                                AveragingProgressBar(progress: displayAveragingProgress)
                                    .frame(width: 90, height: 6)
                            }
                        }
                    } else {
                        VStack(alignment: resolvedVStackAlignment, spacing: 0) {
                            Text(formatSpl(displaySpl))
                                .font(.system(size: baseFontSize * 1.8, weight: primaryFontWeight, design: .rounded))
                                .foregroundStyle(splTextColor(model: model, spl: displaySpl))
                                .monospacedDigit()

                            Text(applyCapitalization(weightingLabel(model: model)))
                                .font(.system(size: baseFontSize * 0.65, weight: primaryFontWeight))
                                .foregroundStyle(secondaryTextColor)

                            if model.averagingEnabled && (isLiveDisplay || displayAveragingProgress > 0) {
                                AveragingProgressBar(progress: displayAveragingProgress)
                                    .frame(width: 90, height: 6)
                            }
                        }
                    }
                }


                if model.showMainValue {
                    VStack(alignment: resolvedVStackAlignment, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(applyCapitalization("Max") + ":")
                                .font(.system(size: baseFontSize * 0.62, weight: primaryFontWeight))
                                .foregroundStyle(secondaryTextColor)
                            Text(displayHold)
                                .font(.system(size: baseFontSize * 0.62, weight: primaryFontWeight))
                                .foregroundStyle(secondaryTextColor)
                                .monospacedDigit()
                                .frame(width: baseFontSize * 2.2, alignment: .trailing)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
                }

                if model.showMainValue && model.showBarMeter {
                    SplBarMeterView(
                        spl: displaySpl,
                        range: graphRange(model: model, displayHistory: displayHistory),
                        limitColorEnabled: model.limitColorEnabled,
                        limitWarningDb: model.limitWarningDb,
                        limitAlertDb: model.limitAlertDb,
                        normalColor: model.limitColorNormal.swiftUIColor,
                        warningColor: model.limitColorWarning.swiftUIColor,
                        alertColor: model.limitColorAlert.swiftUIColor
                    )
                    .frame(height: 10)
                }

                if model.showGraph {
                    splGraphView(model: model, displayHistory: displayHistory, graphHistory: displayGraphHistory)
                        .frame(height: max(20, model.graphHeight))
                }
            }
            .padding(10)
            .multilineTextAlignment(resolvedTextAlignment)
            .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)

            if !isLiveDisplay {
                VStack(spacing: 6) {
                    Text(applyCapitalization(effectiveLiveMode ? "Paused" : (model.isEnabled ? "Paused: Enable Live Mode to start" : "SPL Disabled")))
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.72))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .opacity(model.isEnabled ? 1.0 : 0.45)
        .saturation(model.isEnabled ? 1.0 : 0.2)
        .onAppear {
            controller.setSettingsChangeHandler { updated in
                updateModuleModel(updated)
            }
            controller.updateSettings(model)
            controller.setLiveMode(effectiveLiveMode)
            controller.setTileActive(effectiveLiveMode)
        }
        .onChange(of: module) { oldValue, newValue in
            let updated = Self.resolveModel(module: newValue)
            controller.updateSettings(updated)
            let oldModel = Self.resolveModel(module: oldValue)
            if oldModel.isEnabled && !updated.isEnabled {
                resetDisplay(keepHistoryAll: true)
            }
        }
        .onChange(of: isLiveMode) { _, newValue in
            let updatedLiveMode = newValue || liveModeEnabled
            if updatedLiveMode && !model.isArmedByUser {
                var updated = model
                updated.isArmedByUser = true
                updateModuleModel(updated)
                controller.updateSettings(updated)
            }
            controller.setTileActive(updatedLiveMode)
            controller.setLiveMode(updatedLiveMode)
        }
        .onChange(of: liveModeEnabled) { _, newValue in
            let updatedLiveMode = isLiveMode || newValue
            if updatedLiveMode && !model.isArmedByUser {
                var updated = model
                updated.isArmedByUser = true
                updateModuleModel(updated)
                controller.updateSettings(updated)
            }
            controller.setTileActive(updatedLiveMode)
            controller.setLiveMode(updatedLiveMode)
        }
        .onChange(of: scenePhase) { _, phase in
            #if os(iOS)
            controller.setLiveMode(effectiveLiveMode && phase == .active)
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .dbReaderClearRequested)) { note in
            guard let moduleId = note.userInfo?["moduleId"] as? UUID, moduleId == module.id else { return }
            guard let clearTileId = note.userInfo?["tileId"] as? UUID, clearTileId == tile.id else { return }
            resetDisplay(keepHistoryAll: false)
        }
        .onDisappear {
            if !effectiveLiveMode {
                controller.setTileActive(false)
            }
        }
    }

    private func graphRange(model: DbReaderModuleModel, displayHistory: [DbSample]) -> ClosedRange<Double> {
        if model.weighting == .ca {
            return 0...25
        } else {
            return 40...120
        }
    }

    private func splGraphView(model: DbReaderModuleModel, displayHistory: [DbSample], graphHistory: [DbSample]) -> some View {
        let alertThreshold = model.limitColorEnabled && model.weighting != .ca ? model.limitAlertDb : nil
        let isLiveGraph = effectiveLiveMode
        return DbMiniTrendView(
            samples: graphHistory,
            range: graphRange(model: model, displayHistory: displayHistory),
            lineMode: model.graphLineMode,
            averageWindowSeconds: model.averagingWindowSeconds,
            historyWindowSeconds: model.historyWindowSeconds,
            alertThreshold: alertThreshold,
            thresholdLineColor: model.limitColorAlert.swiftUIColor,
            showUnits: model.showGraphUnits,
            isLiveMode: isLiveGraph,
            limitColorEnabled: model.limitColorEnabled,
            normalColor: model.limitColorNormal.swiftUIColor,
            warningColor: model.limitColorWarning.swiftUIColor,
            alertColor: model.limitColorAlert.swiftUIColor,
            warningThreshold: model.limitWarningDb,
            alertThresholdValue: model.limitAlertDb,
            caUpperLimit: model.weighting == .ca ? model.caUpperLimit : nil,
            caLowerLimit: model.weighting == .ca ? model.caLowerLimit : nil
        )
    }

    private func lanSnapshotView(model: DbReaderModuleModel) -> some View {
        let payload = DbReaderOutputStore.shared.payload(for: module.id)
        let snapshotSpl = payload.isStale ? Double.nan : payload.spl
        let snapshotSlow = payload.isStale ? Double.nan : (payload.caSlow ?? Double.nan)
        let peakText = payload.isStale ? "--.-" : String(format: "%.1f", payload.peak)
        let lastUpdateText = Self.snapshotTimeFormatter.string(from: payload.timestamp)

        return VStack(alignment: resolvedVStackAlignment, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if model.showsTitle {
                    Text(applyCapitalization("SPL Meter"))
                        .font(.system(size: baseFontSize * 0.7, weight: primaryFontWeight))
                        .foregroundStyle(primaryTextColor)
                }
                Spacer()
            }

            Text("LAN Snapshot")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: resolvedVStackAlignment, spacing: 0) {
                Text(formatSpl(snapshotSpl))
                    .font(.system(size: baseFontSize * 1.8, weight: primaryFontWeight, design: .rounded))
                    .foregroundStyle(splTextColor(model: model, spl: snapshotSpl))
                    .monospacedDigit()

                if model.weighting == .ca {
                    Text("C-A Fast")
                        .font(.system(size: baseFontSize * 0.65, weight: primaryFontWeight))
                        .foregroundStyle(secondaryTextColor)

                    Text(formatSpl(snapshotSlow))
                        .font(.system(size: baseFontSize * 1.2, weight: primaryFontWeight, design: .rounded))
                        .foregroundStyle(secondaryTextColor)
                        .monospacedDigit()

                    Text("C-A Slow")
                        .font(.system(size: baseFontSize * 0.6, weight: primaryFontWeight))
                        .foregroundStyle(secondaryTextColor)
                } else {
                    Text(applyCapitalization(weightingLabel(model: model)))
                        .font(.system(size: baseFontSize * 0.65, weight: primaryFontWeight))
                        .foregroundStyle(secondaryTextColor)
                }
            }

            VStack(alignment: resolvedVStackAlignment, spacing: 2) {
                HStack(spacing: 4) {
                    Text(applyCapitalization("Peak") + ":")
                        .font(.system(size: baseFontSize * 0.62, weight: primaryFontWeight))
                        .foregroundStyle(secondaryTextColor)
                    Text(peakText)
                        .font(.system(size: baseFontSize * 0.62, weight: primaryFontWeight))
                        .foregroundStyle(secondaryTextColor)
                        .monospacedDigit()
                        .frame(width: baseFontSize * 2.2, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)

            Text("Last update: \(lastUpdateText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .multilineTextAlignment(resolvedTextAlignment)
        .frame(maxWidth: .infinity, alignment: resolvedHorizontalAlignment)
        .opacity(model.isEnabled ? 1.0 : 0.45)
        .saturation(model.isEnabled ? 1.0 : 0.2)
    }

    private var baseFontSize: CGFloat {
        CGFloat(tileTextFormatting?.fontSize ?? 24)
    }

    private var primaryFontWeight: Font.Weight {
        (tileTextFormatting?.fontWeight ?? .semibold).swiftUIFontWeight
    }

    private var primaryTextColor: Color {
        tileTextFormatting?.textColor?.swiftUIColor ?? Color.white
    }

    private var secondaryTextColor: Color {
        primaryTextColor.opacity(0.7)
    }

    private var resolvedTextAlignment: TextAlignment {
        switch tileTextFormatting?.justification ?? .leading {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private var resolvedHorizontalAlignment: Alignment {
        switch tileTextFormatting?.justification ?? .leading {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private var resolvedVStackAlignment: HorizontalAlignment {
        switch tileTextFormatting?.justification ?? .leading {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func applyCapitalization(_ string: String) -> String {
        switch tileTextFormatting?.capitalization ?? .normal {
        case .normal:
            return string
        case .uppercase:
            return string.uppercased()
        case .lowercase:
            return string.lowercased()
        case .titlecase:
            return string.capitalized
        }
    }

    private func splTextColor(model: DbReaderModuleModel, spl: Double) -> Color {
        guard model.limitColorEnabled else { return primaryTextColor }
        if model.weighting == .ca {
            return caLimitColor(for: spl, model: model)
        }
        if spl >= model.limitAlertDb {
            return model.limitColorAlert.swiftUIColor
        }
        if spl >= model.limitWarningDb {
            return model.limitColorWarning.swiftUIColor
        }
        return model.limitColorNormal.swiftUIColor
    }

    private func caLimitColor(for value: Double, model: DbReaderModuleModel) -> Color {
        guard value.isFinite else { return primaryTextColor }
        let upper = max(model.caUpperLimit, model.caLowerLimit)
        let lower = min(model.caUpperLimit, model.caLowerLimit)
        let boundaryTolerance = 0.05

        if value < lower - boundaryTolerance || value > upper + boundaryTolerance {
            return model.limitColorAlert.swiftUIColor
        }
        if abs(value - lower) <= boundaryTolerance || abs(value - upper) <= boundaryTolerance {
            return model.limitColorWarning.swiftUIColor
        }
        return model.limitColorNormal.swiftUIColor
    }

    private func resetDisplay(keepHistoryAll: Bool) {
        controller.resetDisplay(keepHistoryAll: keepHistoryAll)
    }

    private func formattedHold(from history: [DbSample]) -> String {
        guard let maxValue = history.map(\.spl).max() else { return "--.-" }
        return String(format: "%.1f", maxValue)
    }


    private func header(model: DbReaderModuleModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                if model.showsTitle {
                    Text(applyCapitalization("SPL Meter"))
                        .font(.system(size: baseFontSize * 0.7, weight: primaryFontWeight))
                        .foregroundStyle(primaryTextColor)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Menu {
                    Button("Reset") { resetDisplay(keepHistoryAll: false) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func updateModuleModel(_ model: DbReaderModuleModel) {
        if case .dbReader = module.kind {
            module.kind = .dbReader(model)
        }
    }

    private func weightingSuffix(_ weighting: DbWeighting) -> String {
        switch weighting {
        case .a: return "dBA"
        case .c: return "dBC"
        case .z: return "dBZ"
        case .ca: return "C-A"
        }
    }

    private func weightingLabel(model: DbReaderModuleModel) -> String {
        let timeLabel: String
        switch model.timeWeighting {
        case .fast:
            timeLabel = "Fast"
        case .slow:
            timeLabel = "Slow"
        }

        if model.weighting == .ca {
            return "C-A \(timeLabel)"
        }

        var label = "\(weightingSuffix(model.weighting)) \(timeLabel)"
        if model.averagingEnabled {
            let seconds = max(1, model.averagingWindowSeconds)
            if seconds >= 60 {
                let minutes = Int(round(seconds / 60.0))
                label += " • Avg \(minutes)m"
            } else {
                let rounded = Int(round(seconds))
                label += " • Avg \(rounded)s"
            }
        }
        return label
    }

    private func formatSpl(_ value: Double) -> String {
        if value.isNaN || value.isInfinite { return "--.-" }
        return String(format: "%.1f", value)
    }

    private func exportCSV(model: DbReaderModuleModel) {
        let string = DbReaderCSVBuilder.build(
            samples: controller.historyAll,
            includeRaw: model.exportIncludeRawDbFS,
            includePeak: model.exportIncludePeak
        )
        let defaultName = "SPLMeter-\(DateFormatter.dbReaderFileStamp.string(from: Date())).csv"

        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = defaultName
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? string.write(to: url, atomically: true, encoding: .utf8)
        }
        #else
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(defaultName)
        try? string.write(to: tempURL, atomically: true, encoding: .utf8)
        DispatchQueue.main.async {
            let exporter = DbReaderFileExporter(url: tempURL)
            exporter.present()
        }
        #endif
    }

    private static func resolveModel(module: DashboardModuleModel) -> DbReaderModuleModel {
        if case .dbReader(let model) = module.kind { return model }
        return DbReaderModuleModel()
    }

    private static let snapshotTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

struct DbMiniTrendView: View {
    let samples: [DbSample]
    let range: ClosedRange<Double>
    let lineMode: DbReaderGraphLineMode
    let averageWindowSeconds: Double
    let historyWindowSeconds: Double
    let alertThreshold: Double?
    let thresholdLineColor: Color
    let showUnits: Bool
    let isLiveMode: Bool
    let limitColorEnabled: Bool
    let normalColor: Color
    let warningColor: Color
    let alertColor: Color
    let warningThreshold: Double
    let alertThresholdValue: Double
    let caUpperLimit: Double?
    let caLowerLimit: Double?

    private struct TrendPoint {
        var sample: DbSample
        var value: Double
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(1, Int(geo.size.width))
            let sampleTime: (DbSample) -> TimeInterval = { $0.graphTimestamp }
            let sampleStart = samples.first.map(sampleTime) ?? 0
            let sampleEnd = samples.last.map(sampleTime) ?? sampleStart
            let sampleElapsedSeconds = max(0, sampleEnd - sampleStart)
            let currentTimestamp = isLiveMode ? sampleEnd : Date().timeIntervalSinceReferenceDate
            let elapsedSeconds = max(0, currentTimestamp - sampleStart)
            let renderElapsedSeconds = min(elapsedSeconds, sampleElapsedSeconds)
            let isWindowFilled: Bool = {
                guard let first = samples.first else { return false }
                let windowStart = currentTimestamp - historyWindowSeconds
                return first.graphTimestamp <= (windowStart + 0.25)
            }()
            let renderDuration = isWindowFilled
                ? max(1, historyWindowSeconds)
                : max(0.001, renderElapsedSeconds)
            let renderStartTime = sampleEnd - renderDuration
            let sourceValues: [Double] = {
                switch lineMode {
                case .rawSpl:
                    return samples.map(\.spl)
                case .averageSpl:
                    return DbReaderController.computeAveragedValues(
                        samples: samples,
                        windowSeconds: averageWindowSeconds
                    )
                }
            }()
            let clippedPoints = Self.clipPointsToWindow(
                samples: samples,
                values: sourceValues,
                startTime: renderStartTime
            )
            let renderPoints = downsample(
                points: clippedPoints,
                maxPoints: min(400, width),
                historyWindowSeconds: historyWindowSeconds,
                elapsedSeconds: renderElapsedSeconds,
                currentTimestamp: sampleEnd,
                windowFilled: isWindowFilled
            )
            let points = renderPoints.map(\.sample)
            let splValues = renderPoints.map(\.value)

            let labelInset: CGFloat = showUnits ? 22 : 0
            ZStack(alignment: .topTrailing) {
                Canvas { context, size in
                    guard points.count > 1 else { return }

                    drawGrid(
                        in: size,
                        context: &context,
                        trailingInset: labelInset,
                        historyWindowSeconds: historyWindowSeconds,
                        elapsedSeconds: renderElapsedSeconds,
                        currentTimestamp: sampleEnd,
                        windowFilled: isWindowFilled
                    )

                    // C-A target band — drawn before the line so line renders on top
                    if let upper = caUpperLimit, let lower = caLowerLimit {
                        let (effectiveUpper, effectiveLower) = upper >= lower ? (upper, lower) : (lower, upper)
                        let upperY = map(value: effectiveUpper, size: size)
                        let lowerY = map(value: effectiveLower, size: size)
                        let clampedUpperY = max(0, min(size.height, upperY))
                        let clampedLowerY = max(0, min(size.height, lowerY))
                        let bandWidth = max(0, size.width - labelInset)

                        // Shaded band
                        var bandRect = Path()
                        bandRect.addRect(CGRect(x: 0, y: clampedUpperY,
                                                width: bandWidth,
                                                height: clampedLowerY - clampedUpperY))
                        context.fill(bandRect, with: .color(normalColor.opacity(0.08)))

                        // Upper dashed line
                        var upperLine = Path()
                        upperLine.move(to: CGPoint(x: 0, y: clampedUpperY))
                        upperLine.addLine(to: CGPoint(x: bandWidth, y: clampedUpperY))
                        context.stroke(upperLine, with: .color(warningColor.opacity(0.7)),
                                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                        // Lower dashed line
                        var lowerLine = Path()
                        lowerLine.move(to: CGPoint(x: 0, y: clampedLowerY))
                        lowerLine.addLine(to: CGPoint(x: bandWidth, y: clampedLowerY))
                        context.stroke(lowerLine, with: .color(warningColor.opacity(0.7)),
                                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }

                    let path = buildPath(
                        samples: points,
                        values: splValues,
                        size: size,
                        trailingInset: labelInset,
                        historyWindowSeconds: historyWindowSeconds,
                        elapsedSeconds: renderElapsedSeconds,
                        currentTimestamp: sampleEnd,
                        windowFilled: isWindowFilled
                    )
                    if limitColorEnabled {
                        let segments = buildColoredSegments(
                            samples: points, values: splValues, size: size,
                            trailingInset: labelInset, historyWindowSeconds: historyWindowSeconds,
                            elapsedSeconds: renderElapsedSeconds, currentTimestamp: sampleEnd,
                            windowFilled: isWindowFilled
                        )
                        for (segPath, segColor) in segments {
                            context.stroke(segPath, with: .color(segColor.opacity(0.85)), lineWidth: 1.5)
                        }
                        if let lastColor = segments.last?.1 {
                            let fillPath = buildFillPath(
                                samples: points, values: splValues, size: size,
                                trailingInset: labelInset, historyWindowSeconds: historyWindowSeconds,
                                elapsedSeconds: renderElapsedSeconds, currentTimestamp: sampleEnd,
                                windowFilled: isWindowFilled
                            )
                            context.fill(fillPath, with: .color(lastColor.opacity(0.15)))
                        }
                    } else {
                        context.stroke(path, with: .color(Color.white.opacity(0.85)), lineWidth: 1.5)
                    }

                    if let alertThreshold {
                        let y = map(value: alertThreshold, size: size)
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: y))
                        line.addLine(to: CGPoint(x: max(0, size.width - labelInset), y: y))
                        context.stroke(line, with: .color(thresholdLineColor.opacity(0.7)), lineWidth: 1.0)

                        let alertPath = buildThresholdPath(
                            samples: points,
                            values: splValues,
                            threshold: alertThreshold,
                            size: size,
                            trailingInset: labelInset,
                            historyWindowSeconds: historyWindowSeconds,
                            elapsedSeconds: renderElapsedSeconds,
                            currentTimestamp: sampleEnd,
                            windowFilled: isWindowFilled
                        )
                        context.stroke(alertPath, with: .color(thresholdLineColor), lineWidth: 1.7)
                    }
                }

                graphUnitsOverlay(size: geo.size, showDbUnits: showUnits, trailingInset: labelInset)
                    .padding(.trailing, 2)
                    .padding(.top, 1)
            }
        }
    }

    private func zoneColor(for value: Double) -> Color {
        guard limitColorEnabled else { return Color.white.opacity(0.85) }
        if let upper = caUpperLimit, let lower = caLowerLimit {
            let effectiveUpper = max(upper, lower)
            let effectiveLower = min(upper, lower)
            let boundaryTolerance = 0.05

            if value < effectiveLower - boundaryTolerance || value > effectiveUpper + boundaryTolerance {
                return alertColor
            }
            if abs(value - effectiveLower) <= boundaryTolerance || abs(value - effectiveUpper) <= boundaryTolerance {
                return warningColor
            }
            return normalColor
        }
        if value >= alertThresholdValue { return alertColor }
        if value >= warningThreshold { return warningColor }
        return normalColor
    }

    private func buildColoredSegments(
        samples: [DbSample],
        values: [Double],
        size: CGSize,
        trailingInset: CGFloat,
        historyWindowSeconds: Double,
        elapsedSeconds: Double,
        currentTimestamp: Double,
        windowFilled: Bool
    ) -> [(Path, Color)] {
        let count = min(samples.count, values.count)
        guard count > 1 else { return [] }
        let width = max(0, size.width - trailingInset)

        var segments: [(Path, Color)] = []
        var currentPath = Path()
        var currentColor = zoneColor(for: values[0])

        let x0 = xPosition(sampleTime: samples[0].graphTimestamp, currentTimestamp: currentTimestamp,
                            elapsedSeconds: elapsedSeconds, historyWindowSeconds: historyWindowSeconds,
                            width: width, windowFilled: windowFilled)
        currentPath.move(to: CGPoint(x: x0, y: map(value: values[0], size: size)))

        for i in 1..<count {
            let xi = xPosition(sampleTime: samples[i].graphTimestamp, currentTimestamp: currentTimestamp,
                               elapsedSeconds: elapsedSeconds, historyWindowSeconds: historyWindowSeconds,
                               width: width, windowFilled: windowFilled)
            let yi = map(value: values[i], size: size)
            let newColor = zoneColor(for: values[i])
            if newColor != currentColor {
                currentPath.addLine(to: CGPoint(x: xi, y: yi))   // close old segment at boundary
                segments.append((currentPath, currentColor))
                currentPath = Path()
                currentPath.move(to: CGPoint(x: xi, y: yi))
                currentColor = newColor
            } else {
                currentPath.addLine(to: CGPoint(x: xi, y: yi))
            }
        }
        segments.append((currentPath, currentColor))
        return segments
    }

    private func buildFillPath(
        samples: [DbSample],
        values: [Double],
        size: CGSize,
        trailingInset: CGFloat,
        historyWindowSeconds: Double,
        elapsedSeconds: Double,
        currentTimestamp: Double,
        windowFilled: Bool
    ) -> Path {
        var path = buildPath(
            samples: samples, values: values, size: size,
            trailingInset: trailingInset, historyWindowSeconds: historyWindowSeconds,
            elapsedSeconds: elapsedSeconds, currentTimestamp: currentTimestamp,
            windowFilled: windowFilled
        )
        let width = max(0, size.width - trailingInset)
        if let lastSample = samples.last {
            let lastX = xPosition(sampleTime: lastSample.graphTimestamp,
                                  currentTimestamp: currentTimestamp,
                                  elapsedSeconds: elapsedSeconds,
                                  historyWindowSeconds: historyWindowSeconds,
                                  width: width, windowFilled: windowFilled)
            path.addLine(to: CGPoint(x: lastX, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
        }
        return path
    }

    private func buildPath(
        samples: [DbSample],
        values: [Double],
        size: CGSize,
        trailingInset: CGFloat,
        historyWindowSeconds: Double,
        elapsedSeconds: Double,
        currentTimestamp: Double,
        windowFilled: Bool
    ) -> Path {
        var path = Path()
        let count = min(samples.count, values.count)
        let width = max(0, size.width - trailingInset)
        guard count > 0 else { return path }

            for i in 0..<count {
                let x = xPosition(
                    sampleTime: samples[i].graphTimestamp,
                    currentTimestamp: currentTimestamp,
                    elapsedSeconds: elapsedSeconds,
                    historyWindowSeconds: historyWindowSeconds,
                    width: width,
                windowFilled: windowFilled
            )
            let y = map(value: values[i], size: size)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    private func buildThresholdPath(
        samples: [DbSample],
        values: [Double],
        threshold: Double,
        size: CGSize,
        trailingInset: CGFloat,
        historyWindowSeconds: Double,
        elapsedSeconds: Double,
        currentTimestamp: Double,
        windowFilled: Bool
    ) -> Path {
        var path = Path()
        let count = min(samples.count, values.count)
        guard count > 1 else { return path }

        let width = max(0, size.width - trailingInset)
        var hasMoved = false

        for i in 0..<(count - 1) {
            let v0 = values[i]
            let v1 = values[i + 1]
            guard v0.isFinite, v1.isFinite else {
                hasMoved = false
                continue
            }
            let x0 = xPosition(
                sampleTime: samples[i].graphTimestamp,
                currentTimestamp: currentTimestamp,
                elapsedSeconds: elapsedSeconds,
                historyWindowSeconds: historyWindowSeconds,
                width: width,
                windowFilled: windowFilled
            )
            let x1 = xPosition(
                sampleTime: samples[i + 1].graphTimestamp,
                currentTimestamp: currentTimestamp,
                elapsedSeconds: elapsedSeconds,
                historyWindowSeconds: historyWindowSeconds,
                width: width,
                windowFilled: windowFilled
            )
            let y0 = map(value: v0, size: size)
            let y1 = map(value: v1, size: size)

            let above0 = v0 >= threshold
            let above1 = v1 >= threshold

            if above0 && above1 {
                if !hasMoved {
                    path.move(to: CGPoint(x: x0, y: y0))
                    hasMoved = true
                }
                path.addLine(to: CGPoint(x: x1, y: y1))
                continue
            }

            if above0 != above1 {
                let denom = (v1 - v0)
                let t = denom == 0 ? 0 : (threshold - v0) / denom
                let xCross = x0 + (x1 - x0) * CGFloat(t)
                let yCross = map(value: threshold, size: size)

                if above0 {
                    if !hasMoved {
                        path.move(to: CGPoint(x: x0, y: y0))
                        hasMoved = true
                    }
                    path.addLine(to: CGPoint(x: xCross, y: yCross))
                    hasMoved = false
                } else {
                    path.move(to: CGPoint(x: xCross, y: yCross))
                    hasMoved = true
                }
            }
        }

        return path
    }

    private func xPosition(
        sampleTime: Double,
        currentTimestamp: Double,
        elapsedSeconds: Double,
        historyWindowSeconds: Double,
        width: CGFloat,
        windowFilled: Bool
    ) -> CGFloat {
        let windowSeconds = max(1, historyWindowSeconds)
        let duration = windowFilled ? windowSeconds : max(0.001, elapsedSeconds)
        let startTime = currentTimestamp - duration
        let t = (sampleTime - startTime) / max(0.001, duration)
        return max(0, min(width, CGFloat(t) * width))
    }

    private func drawGrid(
        in size: CGSize,
        context: inout GraphicsContext,
        trailingInset: CGFloat,
        historyWindowSeconds: Double,
        elapsedSeconds: Double,
        currentTimestamp: Double,
        windowFilled: Bool
    ) {
        let width = max(0, size.width - trailingInset)
        let height = max(0, size.height)
        guard width > 0, height > 0 else { return }

        let windowSeconds = max(1, historyWindowSeconds)
        let verticalStep: Double = 1
        let verticalCount = max(1, Int((windowSeconds / verticalStep).rounded(.down)))
        let horizontalCount = 6
        let lineColor = Color.white.opacity(0.14)

        if !windowFilled {
            let scaleSeconds = max(1, elapsedSeconds)
            let visibleCount = max(1, Int((scaleSeconds / verticalStep).rounded(.down)))
            for i in 0...visibleCount {
                let x = CGFloat(i) / CGFloat(scaleSeconds / verticalStep) * width
                guard x >= 0, x <= width else { continue }
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
            }
        } else {
            let phase = (currentTimestamp.truncatingRemainder(dividingBy: verticalStep)) / verticalStep
            for i in 0...(verticalCount + 1) {
                let x = (CGFloat(i) - CGFloat(phase)) / CGFloat(verticalCount) * width
                guard x >= 0, x <= width else { continue }
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
            }
        }

        for i in 0...horizontalCount {
            let y = CGFloat(i) / CGFloat(horizontalCount) * height
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
            context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
        }
    }

    private func graphUnitsOverlay(size: CGSize, showDbUnits: Bool, trailingInset: CGFloat) -> some View {
        let topValue = range.upperBound
        let bottomValue = range.lowerBound
        let thresholdValue = alertThreshold

        let topLabel = String(format: "%.0f", topValue)
        let bottomLabel = String(format: "%.0f", bottomValue)
        let elapsedSeconds = max(0, (samples.last?.graphTimestamp ?? 0) - (samples.first?.graphTimestamp ?? 0))
        let targetSeconds = min(historyWindowSeconds, elapsedSeconds)
        let maxSeconds = max(0, Int(targetSeconds.rounded()))
        let xLabelWidth = max(0, size.width - trailingInset)

        return ZStack {
            if showDbUnits {
                ZStack(alignment: .topTrailing) {
                    Text(topLabel)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.62))

                    Text(bottomLabel)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.62))
                        .position(x: size.width - 12, y: size.height - 8)

                    if let thresholdValue {
                        let y = map(value: thresholdValue, size: size)
                        Text(String(format: "%.0f", thresholdValue))
                            .font(.caption2)
                            .foregroundStyle(thresholdLineColor)
                            .position(x: size.width - 12, y: y)
                    }
                }
            }

            HStack {
                Text("0s")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.62))
                Spacer()
                Text("\(maxSeconds)s")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.62))
            }
            .frame(width: xLabelWidth, alignment: .leading)
            .padding(.bottom, 0)
            .offset(y: 8)
            .frame(maxHeight: .infinity, alignment: .bottomLeading)
        }
    }

    private func map(value: Double, size: CGSize) -> CGFloat {
        guard value.isFinite, range.lowerBound.isFinite, range.upperBound.isFinite, range.upperBound > range.lowerBound else {
            return size.height
        }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let t = (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
        return size.height - CGFloat(t) * size.height
    }

    // Drop points that have already scrolled off the left edge and synthesize
    // a leading point at exactly `startTime`. Averaged lines are calculated
    // before this clipping step so historical averages do not change as their
    // older source samples scroll out of the visible graph window.
    private static func clipPointsToWindow(
        samples: [DbSample],
        values: [Double],
        startTime: Double
    ) -> [TrendPoint] {
        let count = min(samples.count, values.count)
        guard count > 0 else { return [] }
        var firstInWindowIdx = 0
        while firstInWindowIdx < count,
              samples[firstInWindowIdx].graphTimestamp < startTime {
            firstInWindowIdx += 1
        }
        if firstInWindowIdx == 0 {
            return (0..<count).map { TrendPoint(sample: samples[$0], value: values[$0]) }
        }
        if firstInWindowIdx >= count { return [] }

        let interpolated = Self.interpolatedPoint(
            before: TrendPoint(sample: samples[firstInWindowIdx - 1], value: values[firstInWindowIdx - 1]),
            after: TrendPoint(sample: samples[firstInWindowIdx], value: values[firstInWindowIdx]),
            at: startTime
        )
        var result: [TrendPoint] = []
        result.reserveCapacity(count - firstInWindowIdx + 1)
        result.append(interpolated)
        for index in firstInWindowIdx..<count {
            result.append(TrendPoint(sample: samples[index], value: values[index]))
        }
        return result
    }

    private func downsample(
        points: [TrendPoint],
        maxPoints: Int,
        historyWindowSeconds: Double,
        elapsedSeconds: Double,
        currentTimestamp: Double,
        windowFilled: Bool
    ) -> [TrendPoint] {
        guard points.count > maxPoints, maxPoints > 1 else { return points }

        let windowSeconds = max(1, historyWindowSeconds)
        let duration = windowFilled ? windowSeconds : max(0.001, elapsedSeconds)
        let startTime = currentTimestamp - duration
        let stepSeconds = duration / Double(maxPoints - 1)

        var result: [TrendPoint] = []
        result.reserveCapacity(maxPoints)

        var pointIndex = 0
        for i in 0..<maxPoints {
            let targetTime = startTime + (Double(i) * stepSeconds)
            while pointIndex + 1 < points.count,
                  points[pointIndex + 1].sample.graphTimestamp < targetTime {
                pointIndex += 1
            }

            if pointIndex + 1 < points.count {
                result.append(Self.interpolatedPoint(
                    before: points[pointIndex],
                    after: points[pointIndex + 1],
                    at: targetTime
                ))
            } else {
                result.append(points[pointIndex])
            }
        }

        return result
    }

    private static func interpolatedPoint(before: TrendPoint, after: TrendPoint, at targetTime: Double) -> TrendPoint {
        let span = after.sample.graphTimestamp - before.sample.graphTimestamp
        let t: Double = span > 0
            ? min(1.0, max(0.0, (targetTime - before.sample.graphTimestamp) / span))
            : 0
        let sample = DbSample(
            id: before.sample.id,
            timestamp: Date(timeIntervalSinceReferenceDate: targetTime),
            graphTimestamp: targetTime,
            spl: before.sample.spl + (after.sample.spl - before.sample.spl) * t,
            peak: before.sample.peak + (after.sample.peak - before.sample.peak) * t,
            rawDbFS: before.sample.rawDbFS + (after.sample.rawDbFS - before.sample.rawDbFS) * t,
            rawPeakDbFS: before.sample.rawPeakDbFS + (after.sample.rawPeakDbFS - before.sample.rawPeakDbFS) * t
        )
        let value = before.value + (after.value - before.value) * t
        return TrendPoint(sample: sample, value: value)
    }
}
