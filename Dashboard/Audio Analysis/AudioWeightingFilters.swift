import Foundation

// MARK: - Weighting Filter Implementation

nonisolated struct BiquadCoefficients {
    let b0: Double
    let b1: Double
    let b2: Double
    let a1: Double
    let a2: Double
}

nonisolated struct Biquad {
    var z1: Double = 0
    var z2: Double = 0
    let c: BiquadCoefficients

    mutating func process(_ x: Double) -> Double {
        let y = c.b0 * x + z1
        z1 = c.b1 * x - c.a1 * y + z2
        z2 = c.b2 * x - c.a2 * y
        return y
    }

    mutating func reset() {
        z1 = 0
        z2 = 0
    }
}

nonisolated struct IIRCoefficients {
    let b: [Double]
    let a: [Double]
}

nonisolated struct IIRFilter {
    private var xHist: [Double]
    private var yHist: [Double]
    private let b: [Double]
    private let a: [Double]

    init(coeffs: IIRCoefficients) {
        self.b = coeffs.b
        self.a = coeffs.a
        let order = max(b.count, a.count) - 1
        self.xHist = Array(repeating: 0, count: max(0, order))
        self.yHist = Array(repeating: 0, count: max(0, order))
    }

    mutating func process(_ x: Double) -> Double {
        var y = b.isEmpty ? x : (b[0] * x)
        if !xHist.isEmpty {
            for i in 1...xHist.count {
                if i < b.count {
                    y += b[i] * xHist[i - 1]
                }
                if i < a.count {
                    y -= a[i] * yHist[i - 1]
                }
            }
            for i in stride(from: xHist.count - 1, through: 1, by: -1) {
                xHist[i] = xHist[i - 1]
                yHist[i] = yHist[i - 1]
            }
            xHist[0] = x
            yHist[0] = y
        }
        return y
    }

    mutating func reset() {
        for i in xHist.indices { xHist[i] = 0 }
        for i in yHist.indices { yHist[i] = 0 }
    }
}

nonisolated struct WeightingFilter {
    let weighting: DbWeighting
    let sampleRate: Double
    var stages: [Biquad]
    private var iir: IIRFilter?
    private static var didLogKeys: Set<String> = []

    init?(weighting: DbWeighting, sampleRate: Double) {
        self.weighting = weighting
        self.sampleRate = sampleRate

        switch weighting {
        case .z:
            self.stages = []
            self.iir = nil
        case .ca:
            return nil
        case .a:
            if let iirCoeffs = WeightingCoefficients.aIIR(sampleRate: sampleRate) {
                self.stages = []
                self.iir = IIRFilter(coeffs: iirCoeffs)
            } else if let coeffs = WeightingCoefficients.a(sampleRate: sampleRate) {
                self.stages = coeffs.map { Biquad(c: $0) }
                self.iir = nil
            } else {
                return nil
            }
        case .c:
            if let iirCoeffs = WeightingCoefficients.cIIR(sampleRate: sampleRate) {
                self.stages = []
                self.iir = IIRFilter(coeffs: iirCoeffs)
            } else if let coeffs = WeightingCoefficients.c(sampleRate: sampleRate) {
                self.stages = coeffs.map { Biquad(c: $0) }
                self.iir = nil
            } else {
                return nil
            }
        }

        let key = "\(weighting.rawValue)-\(String(format: "%.0f", sampleRate))"
        if !Self.didLogKeys.contains(key) {
            Self.didLogKeys.insert(key)
            if let summary = WeightingCoefficients.debugResponseSummary(weighting: weighting, sampleRate: sampleRate) {
                #if DEBUG
                print("[Audio Weighting] Weighting response: \(summary)")
                #endif
            }
        }
    }

    mutating func processSample(_ x: Double) -> Double {
        guard weighting != .z else { return x }
        if iir != nil {
            return iir!.process(x)
        }
        var y = x
        for i in stages.indices {
            y = stages[i].process(y)
        }
        return y
    }

    mutating func reset() {
        if iir != nil {
            iir!.reset()
        }
        for i in stages.indices {
            stages[i].reset()
        }
    }
}

nonisolated struct DbComplex {
    let re: Double
    let im: Double

    static let one = DbComplex(re: 1, im: 0)

    func magnitude() -> Double {
        sqrt(re * re + im * im)
    }

    static func +(lhs: DbComplex, rhs: DbComplex) -> DbComplex {
        DbComplex(re: lhs.re + rhs.re, im: lhs.im + rhs.im)
    }

    static func -(lhs: DbComplex, rhs: DbComplex) -> DbComplex {
        DbComplex(re: lhs.re - rhs.re, im: lhs.im - rhs.im)
    }

    static func *(lhs: DbComplex, rhs: DbComplex) -> DbComplex {
        DbComplex(re: lhs.re * rhs.re - lhs.im * rhs.im, im: lhs.re * rhs.im + lhs.im * rhs.re)
    }
}

nonisolated enum WeightingCoefficients {
    static func aIIR(sampleRate: Double) -> IIRCoefficients? {
        switch Int(sampleRate.rounded()) {
        case 44100:
            return IIRCoefficients(
                b: [
                    2.5574112520425752e-01,
                    -5.1148225040851503e-01,
                    -2.5574112520425752e-01,
                    1.0229645008170301e+00,
                    -2.5574112520425752e-01,
                    -5.1148225040851503e-01,
                    2.5574112520425752e-01
                ],
                a: [
                    1.0000000000000000e+00,
                    -4.0195761811158324e+00,
                    6.1894064429206939e+00,
                    -4.4531989035441164e+00,
                    1.4208429496218766e+00,
                    -1.4182547383030442e-01,
                    4.3511772334951177e-03
                ]
            )
        case 48000:
            return IIRCoefficients(
                b: [
                    2.3430179229951323e-01,
                    -4.6860358459902651e-01,
                    -2.3430179229951320e-01,
                    9.3720716919805303e-01,
                    -2.3430179229951320e-01,
                    -4.6860358459902651e-01,
                    2.3430179229951323e-01
                ],
                a: [
                    1.0000000000000000e+00,
                    -4.1130434087758720e+00,
                    6.5531217526550503e+00,
                    -4.9908492941633851e+00,
                    1.7857373029375756e+00,
                    -2.4619059531948767e-01,
                    1.1224250033231239e-02
                ]
            )
        default:
            return nil
        }
    }

    static func cIIR(sampleRate: Double) -> IIRCoefficients? {
        switch Int(sampleRate.rounded()) {
        case 44100:
            return IIRCoefficients(
                b: [
                    2.1700856194921903e-01,
                    0.0000000000000000e+00,
                    -4.3401712389843805e-01,
                    0.0000000000000000e+00,
                    2.1700856194921903e-01
                ],
                a: [
                    1.0000000000000000e+00,
                    -2.1346749636870408e+00,
                    1.2793335332360627e+00,
                    -1.4955984608939571e-01,
                    4.9087001746246839e-03
                ]
            )
        case 48000:
            return IIRCoefficients(
                b: [
                    1.9788712002639328e-01,
                    0.0000000000000000e+00,
                    -3.9577424005278655e-01,
                    0.0000000000000000e+00,
                    1.9788712002639328e-01
                ],
                a: [
                    1.0000000000000000e+00,
                    -2.2191729140528018e+00,
                    1.4551358789471716e+00,
                    -2.4849607388778305e-01,
                    1.2538823147272466e-02
                ]
            )
        default:
            return nil
        }
    }

    static func a(sampleRate: Double) -> [BiquadCoefficients]? {
        design(weighting: .a, sampleRate: sampleRate)
    }

    static func c(sampleRate: Double) -> [BiquadCoefficients]? {
        design(weighting: .c, sampleRate: sampleRate)
    }

    // IEC 61672-style A/C weighting via bilinear transform of analog poles/zeros.
    // Normalized to 0 dB at 1 kHz. Returns nil for unsupported sample rates.
    private static func design(weighting: DbWeighting, sampleRate: Double) -> [BiquadCoefficients]? {
        let supported = abs(sampleRate - 48000) < 1 || abs(sampleRate - 44100) < 1
        guard supported else { return nil }

        let polesHz: [Double]
        let zerosHz: [Double]

        switch weighting {
        case .a:
            zerosHz = [0, 0, 0, 0]
            polesHz = [
                20.598997, 20.598997,
                107.65265,
                737.86223,
                12194.217, 12194.217
            ]
        case .c:
            zerosHz = [0, 0]
            polesHz = [
                20.598997, 20.598997,
                12194.217, 12194.217
            ]
        case .z:
            return []
        case .ca:
            return nil
        }

        let fs2 = 2.0 * sampleRate
        func prewarp(_ fHz: Double) -> Double {
            guard fHz != 0 else { return 0 }
            return (sampleRate / Double.pi) * tan(Double.pi * fHz / sampleRate)
        }
        func bilinear(_ sRadPerSec: Double) -> Double {
            (fs2 + sRadPerSec) / (fs2 - sRadPerSec)
        }

        let zerosRad = zerosHz.map { fHz -> Double in
            guard fHz != 0 else { return 0 }
            return -2.0 * Double.pi * prewarp(fHz)
        }
        let polesRad = polesHz.map { fHz -> Double in
            -2.0 * Double.pi * prewarp(fHz)
        }

        var digitalZeros = zerosRad.map { bilinear($0) }
        let digitalPoles = polesRad.map { bilinear($0) }

        let extraZeros = max(0, digitalPoles.count - digitalZeros.count)
        if extraZeros > 0 {
            digitalZeros.append(contentsOf: Array(repeating: -1.0, count: extraZeros))
        }

        let w = 2.0 * Double.pi * 1000.0 / sampleRate
        let zInv = DbComplex(re: cos(w), im: -sin(w))

        var num = DbComplex.one
        for z0 in digitalZeros {
            num = num * (DbComplex.one - DbComplex(re: z0, im: 0) * zInv)
        }
        var den = DbComplex.one
        for p0 in digitalPoles {
            den = den * (DbComplex.one - DbComplex(re: p0, im: 0) * zInv)
        }

        let magnitude = (num.magnitude() / max(1e-12, den.magnitude()))
        let gain = 1.0 / max(1e-12, magnitude)

        return buildSOS(zeros: digitalZeros, poles: digitalPoles, gain: gain)
    }

    static func debugResponseSummary(weighting: DbWeighting, sampleRate: Double) -> String? {
        guard weighting != .z,
              weighting != .ca,
              let coeffs = (weighting == .a ? aIIR(sampleRate: sampleRate) : cIIR(sampleRate: sampleRate)) else {
            return nil
        }
        let freqs: [Double] = [31.5, 100, 1000, 10000]
        let parts = freqs.map { freq in
            let db = 20.0 * log10(max(1e-12, magnitudeResponse(iir: coeffs, freq: freq, sampleRate: sampleRate)))
            return "\(String(format: "%.1f", freq))Hz=\(String(format: "%.1f", db))dB"
        }
        return "\(weighting.rawValue.uppercased()) @ \(String(format: "%.0f", sampleRate))Hz • " + parts.joined(separator: ", ")
    }

    private static func magnitudeResponse(iir: IIRCoefficients, freq: Double, sampleRate: Double) -> Double {
        let w = 2.0 * Double.pi * freq / sampleRate
        let zInv = DbComplex(re: cos(w), im: -sin(w))
        var num = DbComplex(re: 0, im: 0)
        var den = DbComplex(re: 0, im: 0)
        var zPow = DbComplex.one
        for i in 0..<max(iir.b.count, iir.a.count) {
            if i < iir.b.count {
                num = num + DbComplex(re: iir.b[i], im: 0) * zPow
            }
            if i < iir.a.count {
                den = den + DbComplex(re: iir.a[i], im: 0) * zPow
            }
            zPow = zPow * zInv
        }
        let denom = max(1e-12, den.re * den.re + den.im * den.im)
        let div = DbComplex(
            re: (num.re * den.re + num.im * den.im) / denom,
            im: (num.im * den.re - num.re * den.im) / denom
        )
        return div.magnitude()
    }

    private static func buildSOS(zeros: [Double], poles: [Double], gain: Double) -> [BiquadCoefficients] {
        var z = zeros
        var p = poles
        var sections: [BiquadCoefficients] = []

        func popPair(from array: inout [Double]) -> (Double, Double) {
            let first = array.removeFirst()
            if array.isEmpty {
                return (first, 0)
            }
            let second = array.removeFirst()
            return (first, second)
        }

        while !z.isEmpty || !p.isEmpty {
            let (z1, z2) = z.isEmpty ? (0, 0) : popPair(from: &z)
            let (p1, p2) = p.isEmpty ? (0, 0) : popPair(from: &p)

            let b0 = 1.0
            let b1 = -(z1 + z2)
            let b2 = z1 * z2
            let a1 = -(p1 + p2)
            let a2 = p1 * p2

            sections.append(BiquadCoefficients(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2))
        }

        if !sections.isEmpty {
            var first = sections[0]
            first = BiquadCoefficients(
                b0: first.b0 * gain,
                b1: first.b1 * gain,
                b2: first.b2 * gain,
                a1: first.a1,
                a2: first.a2
            )
            sections[0] = first
        }

        return sections
    }
}
