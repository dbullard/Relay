import Foundation
import Accelerate

/// Hann-windowed real FFT producing an amplitude spectrum normalised so a bin-aligned sine
/// of peak amplitude A reads A in its bin. Pure and synchronous, so the RTA/Spectrograph
/// path can be validated with generated signals; `AudioInputProcessor` feeds it the most
/// recent `size` samples.
nonisolated final class FFTAnalyzer {
    let size: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]
    private var windowed: [Float]
    private var realPart: [Float]
    private var imagPart: [Float]
    private var powers: [Float]

    /// `size` must be a power of two.
    init?(size: Int) {
        guard size >= 2, size & (size - 1) == 0 else { return nil }
        let log2n = vDSP_Length(log2(Double(size)).rounded())
        guard let setup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2)) else { return nil }
        self.size = size
        self.log2n = log2n
        self.setup = setup
        window = [Float](repeating: 0, count: size)
        // DENORM (standard 0...1 Hann): its mean value of 0.5 is the coherent-gain loss
        // compensated for below via the 2/n scale. NORM applies an extra sqrt(8/3) factor
        // meant for noise/PSD averaging, which would throw off tone/level accuracy.
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_DENORM))
        windowed = [Float](repeating: 0, count: size)
        realPart = [Float](repeating: 0, count: size / 2)
        imagPart = [Float](repeating: 0, count: size / 2)
        powers = [Float](repeating: 0, count: size / 2)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Amplitude spectrum (size/2 bins, DC first) of `count == size` samples given as up
    /// to two contiguous runs, oldest first (so a ring buffer needs no copy).
    func amplitudeSpectrum(first: UnsafePointer<Float>, firstCount: Int,
                           second: UnsafePointer<Float>?, secondCount: Int) -> [Float] {
        precondition(firstCount + secondCount == size)
        let halfN = size / 2
        window.withUnsafeBufferPointer { win in
            windowed.withUnsafeMutableBufferPointer { out in
                vDSP_vmul(first, 1, win.baseAddress!, 1, out.baseAddress!, 1, vDSP_Length(firstCount))
                if let second, secondCount > 0 {
                    vDSP_vmul(second, 1, win.baseAddress! + firstCount, 1,
                              out.baseAddress! + firstCount, 1, vDSP_Length(secondCount))
                }
            }
        }

        // Real-input FFT via vDSP_fft_zrip ("z" = split-complex, "r" = real input, "ip" = in-place).
        //
        // vDSP_ctoz with stride 2 deinterleaves the n windowed real samples into halfN complex
        // pairs (even sample -> real, odd sample -> imag), Apple's documented real-FFT packing.
        // (Stride 1 silently reports every bin at half its true frequency.) vDSP_fft_zrip — not
        // vDSP_fft_zip, the complex FFT, which would overflow the halfN buffers — then writes
        // exactly halfN complex bins in place.
        realPart.withUnsafeMutableBufferPointer { rPtr in
            imagPart.withUnsafeMutableBufferPointer { iPtr in
                powers.withUnsafeMutableBufferPointer { mPtr in
                    var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                    windowed.withUnsafeBufferPointer { wPtr in
                        wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { cPtr in
                            vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(halfN))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    // Bin 0's imaginary slot holds the Nyquist bin in the packed format, not a
                    // second bin's imaginary part; drop it so bin 0 is pure DC.
                    iPtr[0] = 0
                    vDSP_zvmags(&split, 1, mPtr.baseAddress!, 1, vDSP_Length(halfN))
                }
            }
        }

        var amplitudes = [Float](repeating: 0, count: halfN)
        vvsqrtf(&amplitudes, powers, [Int32(halfN)])
        // vDSP_fft_zrip's forward output is 2x a standard DFT and the Hann window's coherent
        // gain is 0.5, so the net normalisation to true amplitude is 2/n.
        var scale = Float(2.0) / Float(size)
        vDSP_vsmul(amplitudes, 1, &scale, &amplitudes, 1, vDSP_Length(halfN))
        return amplitudes
    }

    /// Convenience for tests: spectrum of exactly `size` samples.
    func amplitudeSpectrum(_ samples: [Float]) -> [Float] {
        samples.withUnsafeBufferPointer {
            amplitudeSpectrum(first: $0.baseAddress!, firstCount: size, second: nil, secondCount: 0)
        }
    }
}
