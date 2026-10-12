import SwiftUI

struct RTATileView: View {
    @Binding var tab: DashboardTab
    @Binding var tile: DashboardTileModel
    @Binding var module: DashboardModuleModel
    var isLiveMode: Bool

    @StateObject private var controller: RTAController

    /// Cursor position in canvas-local coordinates (post-padding), set while hovering/dragging.
    @State private var cursorLocation: CGPoint?

    init(tab: Binding<DashboardTab>, tile: Binding<DashboardTileModel>,
         module: Binding<DashboardModuleModel>, isLiveMode: Bool) {
        self._tab = tab; self._tile = tile; self._module = module
        self.isLiveMode = isLiveMode
        _controller = StateObject(wrappedValue: RTAController(settings: Self.resolveModel(module: module.wrappedValue)))
    }

    var body: some View {
        let model = Self.resolveModel(module: module)

        let primaryBands = model.visibleBands(model.inputID.flatMap { controller.bandsBySource[$0] } ?? [])
        let secondarySources: [(id: UUID, bands: [RTABand], color: Color)] = model.additionalInputIDs.compactMap { id in
            guard !model.hiddenSourceIDs.contains(id),
                  let raw = controller.bandsBySource[id] else { return nil }
            let visible = model.visibleBands(raw)
            guard !visible.isEmpty else { return nil }
            return (id, visible, sourceColor(for: id))
        }
        let layoutBands = !primaryBands.isEmpty ? primaryBands : (secondarySources.first?.bands ?? [])
        let hasAnySource = model.inputID != nil || !model.additionalInputIDs.isEmpty

        ZStack {
            if !hasAnySource {
                VStack(spacing: 6) {
                    Image(systemName: "mic.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No audio input available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if layoutBands.isEmpty {
                Text("Waiting…")
                    .font(.caption).foregroundStyle(.secondary)
            } else if isLiveMode {
                rtaCanvas(model: model, layoutBands: layoutBands, primaryBands: primaryBands, secondarySources: secondarySources)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            cursorLocation = CGPoint(x: location.x - 6, y: location.y - 6)
                        case .ended:
                            cursorLocation = nil
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                cursorLocation = CGPoint(x: value.location.x - 6, y: value.location.y - 6)
                            }
                            .onEnded { _ in cursorLocation = nil }
                    )
            } else {
                rtaCanvas(model: model, layoutBands: layoutBands, primaryBands: primaryBands, secondarySources: secondarySources)
            }
            if !controller.isRunning {
                pausedOverlay(model: model)
            }
        }
        .overlay(alignment: .topLeading) {
            legendRow(model: model)
        }
        .opacity(model.isEnabled ? 1 : 0.45)
        .onAppear {
            controller.updateSettings(model)
            controller.setLiveMode(isLiveMode && model.isEnabled)
        }
        .onChange(of: module) { _, newValue in
            controller.updateSettings(Self.resolveModel(module: newValue))
        }
        .onChange(of: isLiveMode) { _, newValue in
            let m = Self.resolveModel(module: module)
            controller.setLiveMode(newValue && m.isEnabled)
            if !newValue { cursorLocation = nil }
        }
    }

    /// The chart canvas, including grid, data, axis labels, and (when set) the cursor crosshair.
    private func rtaCanvas(model: RTAModuleModel, layoutBands: [RTABand], primaryBands: [RTABand],
                            secondarySources: [(id: UUID, bands: [RTABand], color: Color)]) -> some View {
        Canvas { ctx, size in
            // Reserve bottom strip for frequency labels when enabled.
            let axisH: CGFloat = model.showFrequencyAxis ? 18 : 0
            let chartSize = CGSize(width: size.width, height: size.height - axisH)

            // Grid (background, drawn before data)
            drawGrid(ctx: &ctx, size: chartSize, bands: layoutBands, model: model)

            // Primary source
            let primaryVisible = model.inputID != nil
                && !model.hiddenSourceIDs.contains(model.inputID!)
                && !primaryBands.isEmpty
            if primaryVisible {
                switch model.displayMode {
                case .bars:        drawBars(ctx: &ctx, size: chartSize, bands: primaryBands, model: model)
                case .filledCurve: drawFilledCurve(ctx: &ctx, size: chartSize, bands: primaryBands, model: model)
                }
            }

            // Additional sources, overlaid as colored line traces
            for source in secondarySources {
                drawSourceTrace(ctx: &ctx, size: chartSize, bands: source.bands, model: model, color: source.color)
            }

            // Frequency axis labels
            if model.showFrequencyAxis {
                drawFrequencyAxis(ctx: &ctx, size: size, axisY: chartSize.height, bands: layoutBands)
            }

            // Cursor crosshair / readout
            if let cursor = cursorLocation {
                let primary: (bands: [RTABand], color: Color)? = primaryVisible
                    ? (primaryBands, sourceColor(for: model.inputID))
                    : nil
                drawCursor(ctx: &ctx, size: chartSize, model: model, cursor: cursor,
                           layoutBands: layoutBands, primary: primary, secondary: secondarySources)
            }
        }
        .padding(6)
        .clipped()
    }

    // MARK: - Shared coordinate helper
    //
    // topPad reserves a small strip at the top so the 0 dBFS line (or whatever dBRangeHigh is)
    // never sits flush with the canvas edge and the graph doesn't look clipped.
    private static let topPad: CGFloat = 8

    /// Maps a dB value to a canvas y-coordinate, leaving `topPad` px of headroom at the top.
    /// Clamps to [topPad, height] so values outside the dB range never escape the canvas.
    private func chartY(db: Double, model: RTAModuleModel, height: CGFloat) -> CGFloat {
        let usableH = height - Self.topPad
        let norm = max(0, min(1, CGFloat((db - model.dBRangeLow) / (model.dBRangeHigh - model.dBRangeLow))))
        return Self.topPad + usableH * (1.0 - norm)
    }

    // MARK: - Grid

    private func drawGrid(ctx: inout GraphicsContext, size: CGSize, bands: [RTABand], model: RTAModuleModel) {
        let dbRange = model.dBRangeHigh - model.dBRangeLow
        guard dbRange > 0 else { return }

        // Horizontal dB lines
        let step: Double = dbRange > 40 ? 10 : (dbRange > 20 ? 6 : 3)
        var dbVal = ceil(model.dBRangeLow / step) * step
        while dbVal <= model.dBRangeHigh {
            let y = chartY(db: dbVal, model: model, height: size.height)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            let alpha: Double = dbVal == 0 ? 0.30 : 0.12
            ctx.stroke(line, with: .color(.white.opacity(alpha)), lineWidth: 0.5)
            if model.showDBAxis {
                let label = Text("\(Int(dbVal))")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.35))
                ctx.draw(label, at: CGPoint(x: 2, y: y - 1), anchor: .bottomLeading)
            }
            dbVal += step
        }

        // Vertical frequency lines at octave centres
        guard !bands.isEmpty else { return }
        let octaveHz = [63.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0]
        let n = CGFloat(bands.count)
        for hz in octaveHz {
            var bestIdx = 0
            var bestDist = abs(bands[0].centerHz - hz)
            // while loop: for-in over Range<Int> uses IndexingIterator which in
            // debug builds hits swift_getTupleTypeMetadata2 on every iteration.
            var i = 1
            while i < bands.count {
                let d = abs(bands[i].centerHz - hz)
                if d < bestDist { bestDist = d; bestIdx = i }
                i += 1
            }
            guard bestDist / hz < 0.30 else { continue }
            let x = (CGFloat(bestIdx) + 0.5) * size.width / n
            var line = Path()
            line.move(to: CGPoint(x: x, y: Self.topPad))
            line.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(line, with: .color(.white.opacity(0.10)), lineWidth: 0.5)
        }
    }

    // MARK: - Bars / Curve

    private func drawBars(ctx: inout GraphicsContext, size: CGSize, bands: [RTABand], model: RTAModuleModel) {
        guard !bands.isEmpty else { return }
        let slotW = size.width / CGFloat(bands.count)
        let gap: CGFloat = slotW > 4 ? min(1, slotW * 0.15) : 0
        let barWidth = slotW - gap
        let usableH = size.height - Self.topPad
        let dbRange = model.dBRangeHigh - model.dBRangeLow
        var i = 0
        while i < bands.count {
            let band = bands[i]
            let x = CGFloat(i) * slotW
            let norm = CGFloat((band.energyDb - model.dBRangeLow) / dbRange)
            let barH = max(0, min(usableH, norm * usableH))
            let rect = CGRect(x: x, y: size.height - barH, width: barWidth, height: barH)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 2),
                     with: .color(bandColor(db: band.energyDb, model: model).opacity(model.opacity)))
            if model.showPeakHold {
                let peakY = max(Self.topPad, min(size.height - 0.5,
                    chartY(db: band.peakDb, model: model, height: size.height)))
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: peakY))
                tick.addLine(to: CGPoint(x: x + barWidth, y: peakY))
                ctx.stroke(tick, with: .color(.white.opacity(min(1, 0.7 * model.opacity))), lineWidth: max(1, slotW * 0.4))
            }
            i += 1
        }
    }

    private func drawFilledCurve(ctx: inout GraphicsContext, size: CGSize, bands: [RTABand], model: RTAModuleModel) {
        guard bands.count > 1 else { return }
        let baseColor = sourceColor(for: model.inputID)
        let stepX = size.width / CGFloat(bands.count - 1)
        var path = Path()
        var i = 0
        while i < bands.count {
            let pt = CGPoint(x: CGFloat(i) * stepX,
                             y: chartY(db: bands[i].energyDb, model: model, height: size.height))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            i += 1
        }
        var fill = path
        fill.addLine(to: CGPoint(x: size.width, y: size.height))
        fill.addLine(to: CGPoint(x: 0, y: size.height))
        fill.closeSubpath()
        ctx.fill(fill, with: .color(baseColor.opacity(0.35 * model.opacity)))
        ctx.stroke(path, with: .color(baseColor.opacity(min(1, 0.9 * model.opacity))), lineWidth: 1.5)
    }

    /// Draws an additional source as a plain colored line trace (no fill), overlaid on the
    /// primary source's bars/curve. Used for every entry in `additionalInputIDs`.
    private func drawSourceTrace(ctx: inout GraphicsContext, size: CGSize, bands: [RTABand], model: RTAModuleModel, color: Color) {
        guard bands.count > 1 else { return }
        let stepX = size.width / CGFloat(bands.count - 1)
        var path = Path()
        var i = 0
        while i < bands.count {
            let pt = CGPoint(x: CGFloat(i) * stepX,
                             y: chartY(db: bands[i].energyDb, model: model, height: size.height))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            i += 1
        }
        ctx.stroke(path, with: .color(color.opacity(min(1, 0.9 * model.opacity))), lineWidth: 1.5)
    }

    // MARK: - Cursor / readout

    /// Draws a SMAART-style crosshair: a vertical line follows the cursor's frequency,
    /// the horizontal line snaps to the primary (or first available) source's trace value at
    /// that frequency, and a readout shows the frequency plus each visible source's level,
    /// color-coded to match its trace.
    private func drawCursor(ctx: inout GraphicsContext, size: CGSize, model: RTAModuleModel, cursor: CGPoint,
                             layoutBands: [RTABand],
                             primary: (bands: [RTABand], color: Color)?,
                             secondary: [(id: UUID, bands: [RTABand], color: Color)]) {
        guard !layoutBands.isEmpty,
              cursor.x >= 0, cursor.x <= size.width,
              cursor.y >= 0, cursor.y <= size.height else { return }

        let n = layoutBands.count
        let slotW = size.width / CGFloat(n)
        let idx = max(0, min(n - 1, Int(cursor.x / slotW)))
        let band = layoutBands[idx]

        let lineX: CGFloat
        switch model.displayMode {
        case .bars:
            lineX = (CGFloat(idx) + 0.5) * slotW
        case .filledCurve:
            let stepX = n > 1 ? size.width / CGFloat(n - 1) : size.width
            lineX = CGFloat(idx) * stepX
        }

        // Gather (color, dB) for every visible source at this band index.
        var entries: [(color: Color, db: Double)] = []
        if let primary, idx < primary.bands.count {
            entries.append((primary.color, primary.bands[idx].energyDb))
        }
        for source in secondary where idx < source.bands.count {
            entries.append((source.color, source.bands[idx].energyDb))
        }
        guard !entries.isEmpty else { return }

        var vLine = Path()
        vLine.move(to: CGPoint(x: lineX, y: 0))
        vLine.addLine(to: CGPoint(x: lineX, y: size.height))
        ctx.stroke(vLine, with: .color(.white.opacity(0.5)), lineWidth: 0.75)

        let lineY = chartY(db: entries[0].db, model: model, height: size.height)
        var hLine = Path()
        hLine.move(to: CGPoint(x: 0, y: lineY))
        hLine.addLine(to: CGPoint(x: size.width, y: lineY))
        ctx.stroke(hLine, with: .color(.white.opacity(0.5)), lineWidth: 0.75)

        let dotRect = CGRect(x: lineX - 2.5, y: lineY - 2.5, width: 5, height: 5)
        ctx.fill(Path(ellipseIn: dotRect), with: .color(.white))

        var lines: [(color: Color?, text: String)]
        if entries.count == 1 {
            lines = [(nil, "\(AudioReadoutFormatting.formatHz(band.centerHz))  \(AudioReadoutFormatting.formatDb(entries[0].db))")]
        } else {
            lines = [(nil, AudioReadoutFormatting.formatHz(band.centerHz))]
            lines.append(contentsOf: entries.map { (Optional($0.color), AudioReadoutFormatting.formatDb($0.db)) })
        }

        drawReadoutLabel(ctx: &ctx, size: size, lines: lines, near: CGPoint(x: lineX, y: lineY))
    }

    /// Draws a small rounded label with a translucent background, flipped to stay within `size`.
    /// Each entry in `lines` is drawn on its own row; entries with a non-nil `color` get a
    /// small color dot in front of the text (used to tie a level readout to its source trace).
    private func drawReadoutLabel(ctx: inout GraphicsContext, size: CGSize, lines: [(color: Color?, text: String)], near point: CGPoint) {
        let charWidth: CGFloat = 5.4
        let lineH: CGFloat = 12
        let vPadding: CGFloat = 4

        let maxChars = lines.map { $0.text.count + ($0.color != nil ? 2 : 0) }.max() ?? 0
        let labelW = CGFloat(maxChars) * charWidth + 8
        let labelH = CGFloat(lines.count) * lineH + vPadding

        var labelX = point.x + 6
        var labelY = point.y - labelH - 4
        if labelX + labelW > size.width { labelX = point.x - labelW - 6 }
        if labelY < 0 { labelY = point.y + 4 }
        labelX = max(0, min(size.width - labelW, labelX))
        labelY = max(0, min(size.height - labelH, labelY))

        let bgRect = CGRect(x: labelX, y: labelY, width: labelW, height: labelH)
        ctx.fill(Path(roundedRect: bgRect, cornerRadius: 3), with: .color(.black.opacity(0.55)))

        for (i, line) in lines.enumerated() {
            let rowY = bgRect.minY + vPadding / 2 + CGFloat(i) * lineH + lineH / 2
            var x = bgRect.minX + 4
            if let color = line.color {
                let dotRect = CGRect(x: x, y: rowY - 3, width: 6, height: 6)
                ctx.fill(Path(ellipseIn: dotRect), with: .color(color))
                x += 10
            }
            ctx.draw(Text(line.text).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.white),
                     at: CGPoint(x: x, y: rowY), anchor: .leading)
        }
    }

    // MARK: - Legend

    /// Color-coded chips for every configured source (primary + additional), shown when more
    /// than one source is active. Tapping a chip in Live Mode toggles that source's visibility
    /// without removing it from the module's configuration.
    private func legendSourceIDs(model: RTAModuleModel) -> [UUID] {
        var sourceIDs: [UUID] = []
        if let primary = model.inputID { sourceIDs.append(primary) }
        for id in model.additionalInputIDs where !sourceIDs.contains(id) { sourceIDs.append(id) }
        return sourceIDs
    }

    @ViewBuilder
    private func legendRow(model: RTAModuleModel) -> some View {
        let sourceIDs = legendSourceIDs(model: model)

        if sourceIDs.count > 1 {
            HStack(spacing: 6) {
                ForEach(sourceIDs, id: \.self) { id in
                    legendChip(id: id, model: model)
                }
            }
            .padding(6)
        }
    }

    private func legendChip(id: UUID, model: RTAModuleModel) -> some View {
        let isHidden = model.hiddenSourceIDs.contains(id)
        let name = AudioInputsConfigStore.shared.input(for: id)?.name ?? "Input"
        let chip = HStack(spacing: 4) {
            Circle().fill(sourceColor(for: id)).frame(width: 7, height: 7)
            Text(name)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(0.4))
        .clipShape(Capsule())
        .opacity(isHidden ? 0.4 : 1.0)
        .frame(maxWidth: 90, alignment: .leading)

        return Group {
            if isLiveMode {
                chip.onTapGesture {
                    var m = Self.resolveModel(module: module)
                    if m.hiddenSourceIDs.contains(id) {
                        m.hiddenSourceIDs.remove(id)
                    } else {
                        m.hiddenSourceIDs.insert(id)
                    }
                    module.kind = .rta(m)
                }
            } else {
                chip
            }
        }
    }

    // MARK: - Frequency axis

    private func drawFrequencyAxis(ctx: inout GraphicsContext, size: CGSize, axisY: CGFloat, bands: [RTABand]) {
        guard bands.count > 0 else { return }
        let labelFreqs: [(hz: Double, label: String)] = [
            (63, "63"), (125, "125"), (250, "250"), (500, "500"),
            (1000, "1k"), (2000, "2k"), (4000, "4k"), (8000, "8k"), (16000, "16k")
        ]
        let n = CGFloat(bands.count)
        var line = Path()
        line.move(to: CGPoint(x: 0, y: axisY))
        line.addLine(to: CGPoint(x: size.width, y: axisY))
        ctx.stroke(line, with: .color(.white.opacity(0.15)), lineWidth: 0.5)

        for (hz, label) in labelFreqs {
            var bestIdx = 0
            var bestDist = abs(bands[0].centerHz - hz)
            var i = 1
            while i < bands.count {
                let d = abs(bands[i].centerHz - hz)
                if d < bestDist { bestDist = d; bestIdx = i }
                i += 1
            }
            guard bestDist / hz < 0.30 else { continue }
            let x = (CGFloat(bestIdx) + 0.5) * size.width / n
            let text = Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.45))
            ctx.draw(text, at: CGPoint(x: x, y: axisY + 9), anchor: .center)
        }
    }

    // MARK: - Helpers

    private func bandColor(db: Double, model: RTAModuleModel) -> Color {
        if model.limitColorEnabled {
            if db >= model.limitAlertDb   { return model.limitColorAlert.swiftUIColor }
            if db >= model.limitWarningDb { return model.limitColorWarning.swiftUIColor }
            return model.limitColorNormal.swiftUIColor
        }
        return sourceColor(for: model.inputID)
    }

    /// Looks up the display color assigned to an audio input, falling back to white when the
    /// input has no configured color (or no input is set).
    private func sourceColor(for id: UUID?) -> Color {
        guard let id, let cfg = AudioInputsConfigStore.shared.input(for: id) else { return .white }
        return cfg.color.swiftUIColor
    }

    private func pausedOverlay(model: RTAModuleModel) -> some View {
        let hasAnySource = model.inputID != nil || !model.additionalInputIDs.isEmpty
        return Text(hasAnySource ? "Paused" : "No Input")
            .font(.caption).foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private static func resolveModel(module: DashboardModuleModel) -> RTAModuleModel {
        if case .rta(let m) = module.kind { return m }
        return RTAModuleModel()
    }
}

private extension RTAModuleModel {
    func visibleBands(_ all: [RTABand]) -> [RTABand] {
        all.filter { $0.centerHz >= frequencyRangeLow && $0.centerHz <= frequencyRangeHigh }
    }
}
