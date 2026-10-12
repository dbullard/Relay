import SwiftUI

struct SpectrogramTileView: View {
    @Binding var tab: DashboardTab
    @Binding var tile: DashboardTileModel
    @Binding var module: DashboardModuleModel
    var isLiveMode: Bool

    @StateObject private var controller: SpectrogramController

    /// Cursor position within the waterfall image area, set while hovering/dragging.
    @State private var cursorLocation: CGPoint?

    init(tab: Binding<DashboardTab>, tile: Binding<DashboardTileModel>,
         module: Binding<DashboardModuleModel>, isLiveMode: Bool) {
        self._tab = tab; self._tile = tile; self._module = module
        self.isLiveMode = isLiveMode
        _controller = StateObject(wrappedValue: SpectrogramController(settings: Self.resolveModel(module: module.wrappedValue)))
    }

    var body: some View {
        let model = effectiveModel(Self.resolveModel(module: module))
        GeometryReader { geo in
            let axisH: CGFloat = model.showFrequencyAxis ? 20 : 0
            let imageH: CGFloat = max(1, geo.size.height - axisH)

            VStack(spacing: 0) {
                // ── Waterfall image ─────────────────────────────────
                ZStack {
                    if let img = controller.image {
                        Image(decorative: img, scale: 1)
                            .resizable()
                            .interpolation(.none)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(model.opacity)
                    } else {
                        Color.black
                    }
                    // Frequency grid lines drawn over image
                    frequencyGridOverlay(width: geo.size.width, height: imageH, model: model)

                    // Cursor crosshair / readout
                    cursorOverlay(width: geo.size.width, height: imageH, model: model)

                    if model.inputID == nil {
                        VStack(spacing: 6) {
                            Image(systemName: "mic.slash")
                                .font(.title2)
                                .foregroundStyle(.secondary.opacity(0.5))
                            Text("No audio input available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !controller.isRunning {
                        pausedOverlay(model: model)
                    }
                }
                .frame(height: imageH)
                .clipped()
                .modifier(SpectrogramCursorGestureModifier(isEnabled: isLiveMode, cursorLocation: $cursorLocation))

                // ── Frequency axis label strip ───────────────────────
                if model.showFrequencyAxis {
                    ZStack {
                        Color.black
                        frequencyAxisRow(width: geo.size.width)
                    }
                    .frame(height: axisH)
                }
            }
            .onAppear {
                controller.updateDisplaySize(CGSize(width: geo.size.width, height: imageH))
                controller.updateSettings(model)
                controller.setLiveMode(isLiveMode && model.isEnabled)
            }
        }
        .opacity(model.isEnabled ? 1 : 0.45)
        .onChange(of: module) { _, newValue in
            let m = effectiveModel(Self.resolveModel(module: newValue))
            controller.updateSettings(m)
        }
        .onChange(of: tab) { _, _ in
            let m = effectiveModel(Self.resolveModel(module: module))
            controller.updateSettings(m)
        }
        .onChange(of: isLiveMode) { _, newValue in
            let m = effectiveModel(Self.resolveModel(module: module))
            controller.setLiveMode(newValue && m.isEnabled)
            if !newValue { cursorLocation = nil }
        }
    }

    /// Finds the first RTA module configured anywhere in this dashboard tab.
    private func linkedRTAModel() -> RTAModuleModel? {
        for tile in tab.tiles {
            for module in tile.modules ?? [] {
                if case .rta(let m) = module.kind { return m }
            }
        }
        return nil
    }

    /// When `linkToRTA` is enabled and an RTA module exists in this tab, follow that RTA's
    /// primary input source and dB range so both modules show the same picture.
    private func effectiveModel(_ base: SpectrogramModuleModel) -> SpectrogramModuleModel {
        guard base.linkToRTA, let rta = linkedRTAModel() else { return base }
        var m = base
        if let id = rta.inputID { m.inputID = id }
        m.dBRangeLow = rta.dBRangeLow
        m.dBRangeHigh = rta.dBRangeHigh
        return m
    }

    // MARK: - Frequency grid lines

    private func frequencyGridOverlay(width: CGFloat, height: CGFloat, model: SpectrogramModuleModel) -> some View {
        let gridHz = [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0]
        let fMin = 20.0, fMax = 22050.0
        return Canvas { ctx, sz in
            for hz in gridHz {
                let xFrac: Double = model.frequencyScale == .logarithmic
                    ? log10(hz / fMin) / log10(fMax / fMin)
                    : (hz - fMin) / (fMax - fMin)
                let x = sz.width * CGFloat(xFrac)
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: sz.height))
                ctx.stroke(line, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: - Cursor / readout

    /// SMAART-style crosshair: vertical line follows cursor frequency, horizontal line follows
    /// cursor time-position, and a label shows the frequency + level sampled at that point.
    /// The waterfall keeps scrolling live, so the sampled value updates each frame.
    private func cursorOverlay(width: CGFloat, height: CGFloat, model: SpectrogramModuleModel) -> some View {
        Canvas { ctx, sz in
            guard let cursor = cursorLocation, sz.width > 0, sz.height > 0,
                  cursor.x >= 0, cursor.x <= sz.width, cursor.y >= 0, cursor.y <= sz.height else { return }

            let xFrac = max(0, min(1, cursor.x / sz.width))
            let yFrac = max(0, min(1, cursor.y / sz.height))
            guard let db = controller.sample(atNormalizedX: xFrac, normalizedY: yFrac) else { return }
            let hz = hzAt(xFrac: xFrac, model: model)

            var vLine = Path()
            vLine.move(to: CGPoint(x: cursor.x, y: 0))
            vLine.addLine(to: CGPoint(x: cursor.x, y: sz.height))
            ctx.stroke(vLine, with: .color(.white.opacity(0.5)), lineWidth: 0.75)

            var hLine = Path()
            hLine.move(to: CGPoint(x: 0, y: cursor.y))
            hLine.addLine(to: CGPoint(x: sz.width, y: cursor.y))
            ctx.stroke(hLine, with: .color(.white.opacity(0.5)), lineWidth: 0.75)

            let text = "\(AudioReadoutFormatting.formatHz(hz))  \(AudioReadoutFormatting.formatDb(Double(db)))"
            let charWidth: CGFloat = 5.4
            let labelW = CGFloat(text.count) * charWidth + 8
            let labelH: CGFloat = 14

            var labelX = cursor.x + 6
            var labelY = cursor.y - labelH - 4
            if labelX + labelW > sz.width { labelX = cursor.x - labelW - 6 }
            if labelY < 0 { labelY = cursor.y + 4 }
            labelX = max(0, min(sz.width - labelW, labelX))
            labelY = max(0, min(sz.height - labelH, labelY))

            let bgRect = CGRect(x: labelX, y: labelY, width: labelW, height: labelH)
            ctx.fill(Path(roundedRect: bgRect, cornerRadius: 3), with: .color(.black.opacity(0.55)))
            ctx.draw(Text(text).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.white),
                     at: CGPoint(x: bgRect.midX, y: bgRect.midY), anchor: .center)
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    /// Inverts the frequency-axis mapping used by `frequencyGridOverlay`/`frequencyAxisRow`.
    private func hzAt(xFrac: Double, model: SpectrogramModuleModel) -> Double {
        let fMin = 20.0, fMax = 22050.0
        return model.frequencyScale == .logarithmic
            ? fMin * pow(fMax / fMin, xFrac)
            : fMin + xFrac * (fMax - fMin)
    }

    // MARK: - Axis label row

    private func frequencyAxisRow(width: CGFloat) -> some View {
        let model = Self.resolveModel(module: module)
        let labels: [(hz: Double, label: String)] = [
            (50,"50"),(100,"100"),(200,"200"),(500,"500"),
            (1000,"1k"),(2000,"2k"),(5000,"5k"),(10000,"10k")
        ]
        let fMin = 20.0, fMax = 22050.0
        return ZStack {
            ForEach(labels, id: \.hz) { entry in
                let xFrac: Double = model.frequencyScale == .logarithmic
                    ? log10(entry.hz / fMin) / log10(fMax / fMin)
                    : (entry.hz - fMin) / (fMax - fMin)
                Text(entry.label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .position(x: width * CGFloat(xFrac), y: 10)
            }
        }
        .frame(width: width, height: 20)
    }

    // MARK: - Helpers

    private func pausedOverlay(model: SpectrogramModuleModel) -> some View {
        Text(model.inputID == nil ? "No Input" : "Paused")
            .font(.caption).foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private static func resolveModel(module: DashboardModuleModel) -> SpectrogramModuleModel {
        if case .spectrograph(let m) = module.kind { return m }
        return SpectrogramModuleModel()
    }
}

/// Attaches the hover/drag cursor-tracking gestures only while `isEnabled` (live mode),
/// so edit-mode interactions like double-click-to-edit aren't intercepted.
private struct SpectrogramCursorGestureModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var cursorLocation: CGPoint?

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        cursorLocation = location
                    case .ended:
                        cursorLocation = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in cursorLocation = value.location }
                        .onEnded { _ in cursorLocation = nil }
                )
        } else {
            content
        }
    }
}
