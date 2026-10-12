import Foundation
import SwiftUI
import Combine
import CoreGraphics

@MainActor
final class SpectrogramController: ObservableObject {
    @Published private(set) var image: CGImage?
    @Published private(set) var isRunning: Bool = false

    private var settings: SpectrogramModuleModel
    private var lut: SpectrogramLUT

    // Raw dB rows — stored before colour mapping so threshold changes re-render everything.
    // Each value is a raw dB float (e.g. -80.0). We keep these and re-apply the LUT on demand.
    private var rawRows: [[Float]] = []
    private var maxRows: Int = 256
    private var outputWidth: Int = 512

    private var fftTask: Task<Void, Never>?
    private var fftSubscriptionID: UUID?
    // Pre-allocated pixel buffer reused across renderImage calls to avoid 512 KB
    // malloc/free at 23 Hz.
    private var pixelBuffer: [UInt32] = []

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

        settings = newSettings

        if colorChanged { lut = SpectrogramLUT(colorMap: settings.colorMap) }

        // Re-map the entire history whenever any display parameter changes
        if (colorChanged || rangeChanged) && !rawRows.isEmpty {
            image = renderImage(rawRows: rawRows, width: outputWidth)
        }

        if !newSettings.isEnabled {
            stopSubscription()
        } else if inputChanged || enabledChanged {
            restartSubscription()
        }
    }

    func setLiveMode(_ isLive: Bool) {
        if isLive && settings.isEnabled { restartSubscription() } else { stopSubscription() }
    }

    func setTileActive(_ isActive: Bool) {
        if isActive && settings.isEnabled { restartSubscription() } else { stopSubscription() }
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
        if newMaxRows != maxRows {
            maxRows = newMaxRows
            if rawRows.count > maxRows { rawRows = Array(rawRows.suffix(maxRows)) }
        }
    }

    // MARK: - Subscription

    private func restartSubscription() {
        stopSubscription()
        guard let inputID = settings.inputID,
              let config = AudioInputsConfigStore.shared.input(for: inputID) else {
            isRunning = false; return
        }
        fftTask = Task { [weak self] in
            guard let self else { return }
            let (subID, stream) = await AudioAnalysisEngine.shared.subscribeFFT(
                to: inputID, config: config, resolution: .thirdOct)
            guard !Task.isCancelled else {
                await AudioAnalysisEngine.shared.unsubscribeFFT(id: subID)
                return
            }
            self.fftSubscriptionID = subID
            self.isRunning = true
            for await frame in stream {
                guard !Task.isCancelled else { break }
                self.appendRow(frame: frame)
            }
            self.isRunning = false
        }
    }

    private func stopSubscription() {
        fftTask?.cancel(); fftTask = nil
        if let subID = fftSubscriptionID {
            let id = subID
            Task { await AudioAnalysisEngine.shared.unsubscribeFFT(id: id) }
            fftSubscriptionID = nil
        }
        rawRows.removeAll()
        image = nil
        isRunning = false
    }

    // MARK: - Row building

    private func appendRow(frame: FFTFrame) {
        guard !frame.isRepeated else { return }
        let binCount = frame.magnitudes.count
        outputWidth = min(binCount, 512)

        // Build raw dB row
        var row = [Float](repeating: -160, count: outputWidth)
        for x in 0..<outputWidth {
            let binIndex: Int
            if settings.frequencyScale == .logarithmic {
                let fMin = max(20.0, frame.sampleRate / Double(binCount * 2))
                let fMax = frame.sampleRate / 2.0
                let freq = fMin * pow(fMax / fMin, Double(x) / Double(max(1, outputWidth - 1)))
                binIndex = min(binCount - 1, Int(freq * Double(binCount) * 2 / frame.sampleRate))
            } else {
                binIndex = min(binCount - 1, Int(Double(x) / Double(outputWidth) * Double(binCount)))
            }
            let mag = Double(frame.magnitudes[binIndex])
            row[x] = Float(mag > 1e-10 ? 20 * log10(mag) : -160)
        }

        // Pre-fill with silence rows on first frame so display scrolls from the very start
        if rawRows.isEmpty {
            let silence = [Float](repeating: -160, count: outputWidth)
            rawRows = Array(repeating: silence, count: maxRows)
        }

        if rawRows.count >= maxRows { rawRows.removeFirst() }
        rawRows.append(row)
        image = renderImage(rawRows: rawRows, width: outputWidth)
    }

    // MARK: - Image rendering

    /// Maps raw dB rows through the current LUT and threshold settings.
    /// Called both for new frames AND whenever the user changes dBRangeLow / dBRangeHigh / colorMap.
    private func renderImage(rawRows: [[Float]], width: Int) -> CGImage? {
        guard !rawRows.isEmpty, width > 0 else { return nil }
        let height = rawRows.count
        let dbLow  = Float(settings.dBRangeLow)
        let dbRange = Float(settings.dBRangeHigh) - dbLow
        guard dbRange > 0 else { return nil }

        // Reuse pre-allocated buffer; resize only when dimensions change.
        // Avoids a ~512 KB malloc/free on every FFT frame (23 Hz × N sources).
        let pixelCount = width * height
        if pixelBuffer.count != pixelCount {
            pixelBuffer = [UInt32](repeating: 0xFF000000, count: pixelCount)
        }
        // while loops avoid IndexingIterator<Range<Int>> which, in unoptimised
        // debug builds, routes through unspecialised generic protocol witnesses
        // and hits swift_getTupleTypeMetadata2 → LockingConcurrentMap on every
        // iteration — causing severe main-thread mutex contention at 23 Hz.
        var rowIdx = 0
        while rowIdx < height {
            let row = rawRows[height - 1 - rowIdx]
            let base = rowIdx * width
            let cols = min(row.count, width)
            var x = 0
            while x < cols {
                let normalized = (row[x] - dbLow) / dbRange
                pixelBuffer[base + x] = lut.color(normalizedValue: normalized)
                x += 1
            }
            rowIdx += 1
        }
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
