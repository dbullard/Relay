import Foundation
import SwiftUI
import Combine
import CoreGraphics

@MainActor
final class SpectrogramController: ObservableObject {
    @Published private(set) var image: CGImage?
    @Published private(set) var isRunning: Bool = false
    /// Frequency span of the image's x axis (Hz). Depends on the input's sample rate and
    /// the frequency scale, so the view's grid, labels and hover readout use this instead
    /// of assuming 20 Hz–22.05 kHz.
    @Published private(set) var frequencyRange: ClosedRange<Double> = 20...24_000

    private var settings: SpectrogramModuleModel
    private var lut: SpectrogramLUT

    /// Audio runs only while enabled, live, and on screen (see RTAController).
    private var isLive = false
    private var isViewActive = true
    private var shouldRun: Bool { settings.isEnabled && isLive && isViewActive }

    // Raw dB rows (oldest first) — stored before colour mapping so threshold changes
    // re-render everything. Each value is a raw dB float (e.g. -80.0).
    private var rawRows: [[Float]] = []
    private var maxRows: Int = 256
    private var outputWidth: Int = 512

    private var fftTask: Task<Void, Never>?
    private var fftSubscriptionID: UUID?
    /// False while the canvas is hidden (e.g. behind the Automation view). Rows keep
    /// accumulating so history is preserved, but image rendering is skipped.
    private var isVisible: Bool = true
    /// Set when `pixelBuffer` no longer matches `rawRows` (hidden, resized, recoloured),
    /// so the next render recolours everything instead of scrolling one row in.
    private var needsFullRender = true

    /// Coloured pixels, newest row first, `outputWidth × rawRows.count`. New rows are
    /// scrolled in (one memmove + colouring one row) instead of recolouring the whole
    /// history every frame.
    private var pixelBuffer: [UInt32] = []

    // FFT bin range for each image column; rebuilt when any of the keys change.
    private var columnBinStart: [Int] = []
    private var columnBinEnd: [Int] = []
    private var columnKey: (binCount: Int, sampleRate: Double, scale: FrequencyScale, width: Int)?

    // Steady scrolling at `settings.scrollRate` rows per second, independent of how often
    // FFT frames arrive (which changes with the FFT size other tiles on the input ask for).
    private var lastFrameTimestamp: TimeInterval?
    private var rowAccumulator: Double = 0
    /// Max of the frames received since the last row was emitted, so short events between
    /// rows aren't lost when frames arrive faster than the scroll rate.
    private var pendingRow: [Float]?

    init(settings: SpectrogramModuleModel) {
        self.settings = settings
        self.lut = SpectrogramLUT(colorMap: settings.colorMap)
    }

    deinit {
        fftTask?.cancel()
        if let subID = fftSubscriptionID {
            let id = subID
            Task { await AudioAnalysisEngine.shared.unsubscribeFFT(id: id) }
        }
    }

    func updateSettings(_ newSettings: SpectrogramModuleModel) {
        let inputChanged   = newSettings.inputID    != settings.inputID
        let colorChanged   = newSettings.colorMap   != settings.colorMap
        let rangeChanged   = newSettings.dBRangeLow != settings.dBRangeLow
                          || newSettings.dBRangeHigh != settings.dBRangeHigh
        let enabledChanged = newSettings.isEnabled  != settings.isEnabled
        let scaleChanged   = newSettings.frequencyScale != settings.frequencyScale
            || newSettings.levelScale != settings.levelScale

        settings = newSettings

        if colorChanged { lut = SpectrogramLUT(colorMap: settings.colorMap) }

        if scaleChanged {
            // History columns were mapped with the old scale; mixing scales in one image
            // would be misleading, so start the waterfall over.
            clearHistory()
        } else if (colorChanged || rangeChanged) && !rawRows.isEmpty {
            // Re-map the entire history whenever any display parameter changes
            needsFullRender = true
            renderIfVisible()
        }

        if !shouldRun {
            stopSubscription()
        } else if inputChanged || enabledChanged || fftTask == nil {
            restartSubscription()
        }
    }

    func setLiveMode(_ isLive: Bool) {
        self.isLive = isLive
        if shouldRun { restartSubscription() } else { stopSubscription() }
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            needsFullRender = true
            renderIfVisible()
        }
    }

    /// False when the tile leaves the screen (or the dashboard closes): releases the input
    /// even if SwiftUI keeps this controller object around.
    func setTileActive(_ isActive: Bool) {
        isViewActive = isActive
        if !shouldRun {
            stopSubscription()
        } else if fftTask == nil {
            restartSubscription()
        }
    }

    /// Returns the raw dB value at a normalized position within the waterfall.
    /// `x` is 0...1 across the frequency axis, `y` is 0...1 from newest (top) to oldest (bottom) row.
    func sample(atNormalizedX x: Double, normalizedY y: Double) -> Float? {
        guard !rawRows.isEmpty else { return nil }
        let rowsAgo = Int(y * Double(rawRows.count))
        guard rowsAgo >= 0, rowsAgo < rawRows.count else { return nil }
        let row = rawRows[rawRows.count - 1 - rowsAgo]
        guard !row.isEmpty else { return nil }
        let col = Int(round(x * Double(row.count - 1)))
        guard col >= 0, col < row.count else { return nil }
        return row[col]
    }

    func updateDisplaySize(_ size: CGSize) {
        let newMaxRows = max(64, Int(size.height))
        guard newMaxRows != maxRows else { return }
        maxRows = newMaxRows
        if rawRows.count > maxRows {
            rawRows.removeFirst(rawRows.count - maxRows)
        } else if !rawRows.isEmpty, rawRows.count < maxRows {
            // Taller view: pad with silence at the old end so the image fills the height.
            let silence = [Float](repeating: -160, count: outputWidth)
            rawRows.insert(contentsOf: Array(repeating: silence, count: maxRows - rawRows.count), at: 0)
        }
        needsFullRender = true
        renderIfVisible()
    }

    // MARK: - Subscription

    private func restartSubscription() {
        stopSubscription()
        guard let inputID = settings.inputID,
              let config = AudioInputsConfigStore.shared.input(for: inputID) else {
            isRunning = false; return
        }
        // Hold `self` only per frame: a strong capture for the stream's lifetime kept the
        // controller alive, so deinit never cancelled the FFT after the tile was removed.
        fftTask = Task { [weak self] in
            let (subID, stream) = await AudioAnalysisEngine.shared.subscribeFFT(
                to: inputID, config: config, resolution: .thirdOct)
            if !Task.isCancelled, let owner = self {
                owner.fftSubscriptionID = subID
                owner.isRunning = true
            } else {
                await AudioAnalysisEngine.shared.unsubscribeFFT(id: subID)
                return
            }
            for await frame in stream {
                guard !Task.isCancelled, let owner = self else { break }
                owner.handleFrame(frame)
            }
            // A cancelled task must not clear the flag a newer subscription already set.
            if !Task.isCancelled { self?.isRunning = false }
        }
    }

    private func stopSubscription() {
        fftTask?.cancel(); fftTask = nil
        if let subID = fftSubscriptionID {
            let id = subID
            Task { await AudioAnalysisEngine.shared.unsubscribeFFT(id: id) }
            fftSubscriptionID = nil
        }
        clearHistory()
        isRunning = false
    }

    private func clearHistory() {
        rawRows.removeAll()
        pixelBuffer.removeAll()
        image = nil
        needsFullRender = true
        lastFrameTimestamp = nil
        rowAccumulator = 0
        pendingRow = nil
    }

    // MARK: - Row building

    private func handleFrame(_ frame: FFTFrame) {
        guard !frame.isRepeated, !frame.magnitudes.isEmpty, frame.sampleRate > 0 else { return }
        let row = buildRow(frame: frame)

        // Pre-fill with silence rows on first frame so display scrolls from the very start
        if rawRows.isEmpty {
            let silence = [Float](repeating: -160, count: outputWidth)
            rawRows = Array(repeating: silence, count: maxRows)
            needsFullRender = true
        }

        // How many rows this frame is worth at the configured scroll rate.
        let rowsDue: Int
        if let last = lastFrameTimestamp {
            let dt = min(max(frame.timestamp - last, 0), 0.5)
            rowAccumulator += dt * max(1, settings.scrollRate)
            rowsDue = min(Int(rowAccumulator), 30)
            rowAccumulator -= Double(Int(rowAccumulator))
        } else {
            rowsDue = 1
        }
        lastFrameTimestamp = frame.timestamp

        if var pending = pendingRow, pending.count == row.count {
            for i in pending.indices where row[i] > pending[i] { pending[i] = row[i] }
            pendingRow = pending
        } else {
            pendingRow = row
        }
        guard rowsDue > 0, let emitted = pendingRow else { return }
        pendingRow = nil
        appendRows(emitted, count: rowsDue)
    }

    /// Maps one FFT frame to `outputWidth` dB columns. Each column covers a range of bins
    /// and shows the loudest of them, so narrow tones (feedback) stay visible where many
    /// bins share one pixel — sampling a single bin per pixel could skip them entirely.
    private func buildRow(frame: FFTFrame) -> [Float] {
        let binCount = frame.magnitudes.count
        let width = min(binCount, 512)
        if let key = columnKey, key.binCount == binCount, key.sampleRate == frame.sampleRate,
           key.scale == settings.frequencyScale, key.width == width {
            // mapping is current
        } else {
            rebuildColumnMap(binCount: binCount, sampleRate: frame.sampleRate, width: width)
        }
        var row = [Float](repeating: -160, count: width)
        // Bin magnitudes are peak amplitudes; −3.01 dB puts them on the SPL meter's RMS scale
        // (same as the RTA), then the calibration offset gives dB SPL when selected.
        let offset = Float(-3.0103 + (settings.levelScale == .calibrated ? frame.calibrationOffsetDb : 0))
        frame.magnitudes.withUnsafeBufferPointer { mags in
            for x in 0..<width {
                var peak: Float = 0
                var bin = columnBinStart[x]
                let end = columnBinEnd[x]
                while bin <= end {
                    if mags[bin] > peak { peak = mags[bin] }
                    bin += 1
                }
                row[x] = peak > 1e-10 ? 20 * log10(peak) + offset : -160
            }
        }
        return row
    }

    private func rebuildColumnMap(binCount: Int, sampleRate: Double, width: Int) {
        let binHz = sampleRate / Double(binCount * 2)
        let nyquist = sampleRate / 2
        let scale = settings.frequencyScale
        let fMin: Double
        switch scale {
        case .logarithmic: fMin = max(20.0, binHz)
        case .linear:      fMin = 0
        }
        // Column x covers [edge(x), edge(x + 1)].
        func edge(_ x: Int) -> Double {
            let t = Double(x) / Double(width)
            switch scale {
            case .logarithmic: return fMin * pow(nyquist / fMin, t)
            case .linear:      return fMin + t * (nyquist - fMin)
            }
        }
        columnBinStart = [Int](repeating: 0, count: width)
        columnBinEnd = [Int](repeating: 0, count: width)
        for x in 0..<width {
            let lo = edge(x) / binHz
            let hi = edge(x + 1) / binHz
            // Nearest bin to the column's lower edge, through every bin centre inside it;
            // at least one bin even when the column is narrower than a bin.
            let start = min(binCount - 1, max(0, Int(lo.rounded())))
            let end = min(binCount - 1, max(start, Int(hi.rounded(.down))))
            columnBinStart[x] = start
            columnBinEnd[x] = end
        }
        columnKey = (binCount, sampleRate, scale, width)
        if width != outputWidth {
            outputWidth = width
            rawRows.removeAll()
            needsFullRender = true
        }
        let range = fMin...nyquist
        if range != frequencyRange { frequencyRange = range }
    }

    /// Total waterfall rows emitted since creation (for tests of the scroll rate).
    private(set) var rowsEmittedForTesting = 0

    /// Feeds one FFT frame as if it came from the audio engine (tests only).
    func ingestForTesting(_ frame: FFTFrame) {
        handleFrame(frame)
    }

    private func appendRows(_ row: [Float], count: Int) {
        let n = min(count, maxRows)
        rowsEmittedForTesting += n
        for _ in 0..<n {
            if rawRows.count >= maxRows { rawRows.removeFirst() }
            rawRows.append(row)
        }
        guard isVisible else { needsFullRender = true; return }

        let width = outputWidth
        let height = rawRows.count
        guard !needsFullRender, pixelBuffer.count == width * height else {
            renderIfVisible()
            return
        }
        guard let lowAndRange = dbScale() else { return }
        pixelBuffer.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            // Scroll the existing image down by n rows, then colour the new rows on top.
            if n < height {
                memmove(base + n * width, base, (height - n) * width * MemoryLayout<UInt32>.stride)
            }
            colorRow(row, into: base, width: width, dbLow: lowAndRange.low, dbRange: lowAndRange.range)
            for r in 1..<max(1, n) {
                memcpy(base + r * width, base, width * MemoryLayout<UInt32>.stride)
            }
        }
        image = makeImage(width: width, height: height)
    }

    // MARK: - Image rendering

    private func dbScale() -> (low: Float, range: Float)? {
        let low = Float(settings.dBRangeLow)
        let range = Float(settings.dBRangeHigh) - low
        return range > 0 ? (low, range) : nil
    }

    private func colorRow(_ row: [Float], into dest: UnsafeMutablePointer<UInt32>, width: Int,
                          dbLow: Float, dbRange: Float) {
        // while loops avoid IndexingIterator<Range<Int>> which, in unoptimised
        // debug builds, routes through unspecialised generic protocol witnesses
        // and hits swift_getTupleTypeMetadata2 → LockingConcurrentMap on every iteration.
        let cols = min(row.count, width)
        var x = 0
        while x < cols {
            dest[x] = lut.color(normalizedValue: (row[x] - dbLow) / dbRange)
            x += 1
        }
        while x < width {
            dest[x] = 0xFF000000
            x += 1
        }
    }

    /// Recolours the whole history (new thresholds/colours, resize, or after being hidden).
    private func renderIfVisible() {
        guard isVisible else { needsFullRender = true; return }
        let width = outputWidth
        let height = rawRows.count
        guard height > 0, width > 0, let scale = dbScale() else {
            image = nil
            return
        }
        let pixelCount = width * height
        if pixelBuffer.count != pixelCount {
            pixelBuffer = [UInt32](repeating: 0xFF000000, count: pixelCount)
        }
        pixelBuffer.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            var rowIdx = 0
            while rowIdx < height {
                colorRow(rawRows[height - 1 - rowIdx], into: base + rowIdx * width, width: width,
                         dbLow: scale.low, dbRange: scale.range)
                rowIdx += 1
            }
        }
        needsFullRender = false
        image = makeImage(width: width, height: height)
    }

    private func makeImage(width: Int, height: Int) -> CGImage? {
        let pixelCount = width * height
        guard pixelCount > 0, pixelBuffer.count == pixelCount else { return nil }
        let data = Data(bytes: pixelBuffer, count: pixelCount * 4)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                                         | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
