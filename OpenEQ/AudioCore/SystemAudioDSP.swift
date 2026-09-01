import Accelerate
import Darwin

private struct BiquadCoefficients {
    let b0: Float
    let b1: Float
    let b2: Float
    let a1: Float
    let a2: Float
    static let identity = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
    var isIdentity: Bool { b0 == 1 && b1 == 0 && b2 == 0 && a1 == 0 && a2 == 0 }

    static func normalized(b0: Float, b1: Float, b2: Float, a0: Float, a1: Float, a2: Float) -> BiquadCoefficients {
        let inv = 1 / a0
        return BiquadCoefficients(b0: b0 * inv, b1: b1 * inv, b2: b2 * inv, a1: a1 * inv, a2: a2 * inv)
    }
}

private struct SmoothingCoefficients {
    private var start: BiquadCoefficients = .identity
    private var current: BiquadCoefficients = .identity
    private var target: BiquadCoefficients = .identity
    private var remaining = 0
    private var duration = 512

    mutating func startTransition(to newTarget: BiquadCoefficients, durationFrames: Int) {
        current = interpolatedCoeffs()
        start = current
        target = newTarget
        duration = max(1, durationFrames)
        remaining = duration
    }

    func interpolatedCoeffs() -> BiquadCoefficients {
        guard remaining > 0 else { return current }
        let t = 1 - Float(remaining) / Float(duration)
        return lerp(start, target, t)
    }

    mutating func advance(frames: Int) {
        guard remaining > 0 else { return }
        if frames >= remaining {
            current = target
            remaining = 0
        } else {
            remaining -= frames
            let t = 1 - Float(remaining) / Float(duration)
            current = lerp(start, target, t)
        }
    }

    private func lerp(_ a: BiquadCoefficients, _ b: BiquadCoefficients, _ t: Float) -> BiquadCoefficients {
        BiquadCoefficients(
            b0: a.b0 + (b.b0 - a.b0) * t,
            b1: a.b1 + (b.b1 - a.b1) * t,
            b2: a.b2 + (b.b2 - a.b2) * t,
            a1: a.a1 + (b.a1 - a.a1) * t,
            a2: a.a2 + (b.a2 - a.a2) * t
        )
    }
}

private final class VDSPBiquadCascade {
    private let sectionCount: Int
    private let setup: vDSP_biquad_Setup
    private var coefficients: [Float]
    private var leftDelay: [Float]
    private var rightDelay: [Float]

    init(sectionCount: Int) {
        self.sectionCount = sectionCount
        var initial = [Double](repeating: 0, count: sectionCount * 5)
        for section in 0..<sectionCount {
            initial[section * 5] = 1
        }
        setup = initial.withUnsafeBufferPointer {
            vDSP_biquad_CreateSetup($0.baseAddress!, vDSP_Length(sectionCount))!
        }
        coefficients = [Float](repeating: 0, count: sectionCount * 5)
        leftDelay = [Float](repeating: 0, count: sectionCount * 2 + 2)
        rightDelay = [Float](repeating: 0, count: sectionCount * 2 + 2)
    }

    deinit {
        vDSP_biquad_DestroySetup(setup)
    }

    func updateCoefficients(_ sections: [BiquadCoefficients]) {
        for section in 0..<sectionCount {
            let values = sections[section]
            let offset = section * 5
            coefficients[offset] = values.b0
            coefficients[offset + 1] = values.b1
            coefficients[offset + 2] = values.b2
            coefficients[offset + 3] = values.a1
            coefficients[offset + 4] = values.a2
        }
        coefficients.withUnsafeBufferPointer {
            vDSP_biquad_SetCoefficientsSingle(
                setup,
                $0.baseAddress!,
                0,
                vDSP_Length(sectionCount)
            )
        }
    }

    func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channel: Int) {
        if channel == 0 {
            leftDelay.withUnsafeMutableBufferPointer {
                vDSP_biquad(setup, $0.baseAddress!, samples, 1, samples, 1, vDSP_Length(frames))
            }
        } else {
            rightDelay.withUnsafeMutableBufferPointer {
                vDSP_biquad(setup, $0.baseAddress!, samples, 1, samples, 1, vDSP_Length(frames))
            }
        }
    }

    func reset() {
        leftDelay.withUnsafeMutableBufferPointer {
            $0.initialize(repeating: 0)
        }
        rightDelay.withUnsafeMutableBufferPointer {
            $0.initialize(repeating: 0)
        }
    }
}

private struct SmoothedGain {
    private var start: Float = 1
    private var current: Float = 1
    private var target: Float = 1
    private var remaining = 0
    private var duration = 256

    mutating func startTransition(to newTarget: Float, durationFrames: Int) {
        current = value
        start = current
        target = newTarget
        duration = max(1, durationFrames)
        remaining = duration
    }

    var value: Float {
        guard remaining > 0 else { return current }
        let progress = 1 - Float(remaining) / Float(duration)
        return start + (target - start) * progress
    }

    var isTransitioning: Bool { remaining > 0 }

    mutating func advance(frames: Int) {
        guard remaining > 0 else { return }
        if frames >= remaining {
            current = target
            remaining = 0
        } else {
            remaining -= frames
            current = value
        }
    }

    mutating func reset() {
        self = SmoothedGain()
    }
}

private struct DSPChannelControlState {
    private var smoothingCoeffs = Array(repeating: SmoothingCoefficients(), count: 31)
    private var interpolatedCoeffs = Array(repeating: BiquadCoefficients.identity, count: 31)
    private var preamp = SmoothedGain()
    private var coefficientUpdateInterval = 32
    private var framesUntilCoefficientUpdate = 0
    private var hasActiveFilters = false

    mutating func configureTiming(sampleRate: Double) {
        coefficientUpdateInterval = max(1, Int((32 * sampleRate / 48_000).rounded()))
        framesUntilCoefficientUpdate = 0
    }

    mutating func startFilterTransition(index: Int, to coefficients: BiquadCoefficients, durationFrames: Int) {
        smoothingCoeffs[index].startTransition(to: coefficients, durationFrames: durationFrames)
        framesUntilCoefficientUpdate = 0
    }

    mutating func startPreampTransition(to target: Float, durationFrames: Int) {
        preamp.startTransition(to: target, durationFrames: durationFrames)
        framesUntilCoefficientUpdate = 0
    }

    mutating func process(
        _ samples: UnsafeMutablePointer<Float>,
        frames: Int,
        channel: Int,
        cascade: VDSPBiquadCascade
    ) {
        var offset = 0
        while offset < frames {
            if framesUntilCoefficientUpdate == 0 {
                hasActiveFilters = false
                for index in smoothingCoeffs.indices {
                    let coefficients = smoothingCoeffs[index].interpolatedCoeffs()
                    interpolatedCoeffs[index] = coefficients
                    if !coefficients.isIdentity { hasActiveFilters = true }
                }
                if hasActiveFilters {
                    cascade.updateCoefficients(interpolatedCoeffs)
                }
                framesUntilCoefficientUpdate = coefficientUpdateInterval
            }

            let chunkFrames = min(frames - offset, framesUntilCoefficientUpdate)
            let chunk = samples.advanced(by: offset)
            if preamp.isTransitioning {
                for frame in 0..<chunkFrames {
                    chunk[frame] *= preamp.value
                    preamp.advance(frames: 1)
                }
            } else if abs(preamp.value - 1) > 0.0001 {
                var gain = preamp.value
                vDSP_vsmul(chunk, 1, &gain, chunk, 1, vDSP_Length(chunkFrames))
            }
            if hasActiveFilters {
                cascade.process(chunk, frames: chunkFrames, channel: channel)
            }
            for index in smoothingCoeffs.indices {
                smoothingCoeffs[index].advance(frames: chunkFrames)
            }
            framesUntilCoefficientUpdate -= chunkFrames
            offset += chunkFrames
        }
    }

    mutating func reset() {
        smoothingCoeffs = Array(repeating: SmoothingCoefficients(), count: 31)
        interpolatedCoeffs = Array(repeating: .identity, count: 31)
        preamp.reset()
        framesUntilCoefficientUpdate = 0
        hasActiveFilters = false
    }
}

private enum SystemAudioLimiter {
    static let ceiling: Float = 0.98
    static let lookAheadSeconds = 0.001
    static let releaseSeconds = 0.050
    static let maximumLookAheadFrames = 2_048
}

private struct LookAheadLimiterState {
    private var delayLine = [Float](repeating: 0, count: SystemAudioLimiter.maximumLookAheadFrames)
    private var writeIndex = 0
    private var delayFrames = 48
    private var holdFrames = 0
    private var gain: Float = 1
    private var releaseCoefficient: Float = 0.000_416_58

    mutating func configure(sampleRate: Double) {
        let newDelayFrames = SystemAudioDSPState.limiterLatencyFrames(for: sampleRate)
        releaseCoefficient = Float(1 - exp(-1 / (SystemAudioLimiter.releaseSeconds * sampleRate)))
        guard newDelayFrames != delayFrames else { return }
        delayFrames = newDelayFrames
        reset()
    }

    mutating func process(_ samples: UnsafeMutablePointer<Float>, frames: Int) {
        let ceiling = SystemAudioLimiter.ceiling
        for frame in 0..<frames {
            let input = samples[frame]
            let delayed = delayLine[writeIndex]
            delayLine[writeIndex] = input
            writeIndex += 1
            if writeIndex == delayFrames { writeIndex = 0 }

            let magnitude = abs(input)
            let requiredGain = magnitude > ceiling ? ceiling / magnitude : 1
            if requiredGain < gain {
                gain = requiredGain
                holdFrames = delayFrames + 1
            } else if holdFrames > 0 {
                holdFrames -= 1
            } else {
                gain += (1 - gain) * releaseCoefficient
            }

            samples[frame] = max(-ceiling, min(ceiling, delayed * gain))
        }
    }

    mutating func reset() {
        delayLine.withUnsafeMutableBufferPointer { $0.initialize(repeating: 0) }
        writeIndex = 0
        holdFrames = 0
        gain = 1
    }
}

private struct LinkedLookAheadLimiterState {
    private var leftDelay = [Float](repeating: 0, count: SystemAudioLimiter.maximumLookAheadFrames)
    private var rightDelay = [Float](repeating: 0, count: SystemAudioLimiter.maximumLookAheadFrames)
    private var writeIndex = 0
    private var delayFrames = 48
    private var holdFrames = 0
    private var gain: Float = 1
    private var releaseCoefficient: Float = 0.000_416_58

    mutating func configure(sampleRate: Double) {
        let newDelayFrames = SystemAudioDSPState.limiterLatencyFrames(for: sampleRate)
        releaseCoefficient = Float(1 - exp(-1 / (SystemAudioLimiter.releaseSeconds * sampleRate)))
        guard newDelayFrames != delayFrames else { return }
        delayFrames = newDelayFrames
        reset()
    }

    mutating func process(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frames: Int
    ) {
        let ceiling = SystemAudioLimiter.ceiling
        for frame in 0..<frames {
            let leftInput = left[frame]
            let rightInput = right[frame]
            let delayedLeft = leftDelay[writeIndex]
            let delayedRight = rightDelay[writeIndex]
            leftDelay[writeIndex] = leftInput
            rightDelay[writeIndex] = rightInput
            writeIndex += 1
            if writeIndex == delayFrames { writeIndex = 0 }

            let magnitude = max(abs(leftInput), abs(rightInput))
            let requiredGain = magnitude > ceiling ? ceiling / magnitude : 1
            if requiredGain < gain {
                gain = requiredGain
                holdFrames = delayFrames + 1
            } else if holdFrames > 0 {
                holdFrames -= 1
            } else {
                gain += (1 - gain) * releaseCoefficient
            }

            left[frame] = max(-ceiling, min(ceiling, delayedLeft * gain))
            right[frame] = max(-ceiling, min(ceiling, delayedRight * gain))
        }
    }

    mutating func reset() {
        leftDelay.withUnsafeMutableBufferPointer { $0.initialize(repeating: 0) }
        rightDelay.withUnsafeMutableBufferPointer { $0.initialize(repeating: 0) }
        writeIndex = 0
        holdFrames = 0
        gain = 1
    }
}

final class SystemAudioDSPState {
    private static let sectionCount = 31
    private let biquadCascade = VDSPBiquadCascade(sectionCount: sectionCount)
    private var leftControl = DSPChannelControlState()
    private var rightControl = DSPChannelControlState()
    private var leftLimiter = LookAheadLimiterState()
    private var rightLimiter = LookAheadLimiterState()
    private var linkedLimiter = LinkedLookAheadLimiterState()
    var isBypassed = false
    var isEmergencyMuted = false

    func configure(_ preset: EQPreset, sampleRate: Double) {
        let safeSampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 48_000
        let filterTransitionFrames = max(1, Int((512 * safeSampleRate / 48_000).rounded()))
        let preampTransitionFrames = max(1, Int((256 * safeSampleRate / 48_000).rounded()))
        let preampTarget = pow(10, preset.preamp / 20)
        leftControl.configureTiming(sampleRate: safeSampleRate)
        rightControl.configureTiming(sampleRate: safeSampleRate)
        leftLimiter.configure(sampleRate: safeSampleRate)
        rightLimiter.configure(sampleRate: safeSampleRate)
        linkedLimiter.configure(sampleRate: safeSampleRate)
        leftControl.startPreampTransition(to: preampTarget, durationFrames: preampTransitionFrames)
        rightControl.startPreampTransition(to: preampTarget, durationFrames: preampTransitionFrames)
        for index in 0..<Self.sectionCount {
            let coefficients = index < preset.bands.count
                ? Self.makeCoefficients(for: preset.bands[index], sampleRate: Float(safeSampleRate))
                : .identity
            leftControl.startFilterTransition(index: index, to: coefficients, durationFrames: filterTransitionFrames)
            rightControl.startFilterTransition(index: index, to: coefficients, durationFrames: filterTransitionFrames)
        }
    }

    func reset() {
        leftLimiter.reset()
        rightLimiter.reset()
        linkedLimiter.reset()
        isBypassed = false
        isEmergencyMuted = false
        leftControl.reset()
        rightControl.reset()
        biquadCascade.updateCoefficients(Array(repeating: .identity, count: Self.sectionCount))
        biquadCascade.reset()
    }

    func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channel: Int) {
        if isEmergencyMuted {
            memset(samples, 0, frames * MemoryLayout<Float>.size)
            return
        }

        if !isBypassed {
            if channel == 0 {
                leftControl.process(samples, frames: frames, channel: channel, cascade: biquadCascade)
            } else {
                rightControl.process(samples, frames: frames, channel: channel, cascade: biquadCascade)
            }
        }

        if channel == 0 {
            leftLimiter.process(samples, frames: frames)
        } else {
            rightLimiter.process(samples, frames: frames)
        }
    }

    func processStereo(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frames: Int
    ) {
        if isEmergencyMuted {
            memset(left, 0, frames * MemoryLayout<Float>.size)
            memset(right, 0, frames * MemoryLayout<Float>.size)
            return
        }

        if !isBypassed {
            leftControl.process(left, frames: frames, channel: 0, cascade: biquadCascade)
            rightControl.process(right, frames: frames, channel: 1, cascade: biquadCascade)
        }
        linkedLimiter.process(left: left, right: right, frames: frames)
    }

    static func limiterLatencyFrames(for sampleRate: Double) -> Int {
        let safeSampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 48_000
        return min(
            SystemAudioLimiter.maximumLookAheadFrames,
            max(1, Int((SystemAudioLimiter.lookAheadSeconds * safeSampleRate).rounded()))
        )
    }

    private static func makeCoefficients(for band: EQBand, sampleRate: Float) -> BiquadCoefficients {
        guard band.isEnabled, sampleRate > 0 else { return .identity }
        if abs(band.gain) < 0.0001,
           band.filterType == .parametric || band.filterType == .lowShelf || band.filterType == .highShelf {
            return .identity
        }
        let frequency = max(20, min(band.frequency, sampleRate * 0.49))
        let omega = 2 * Float.pi * frequency / sampleRate
        let sine = sin(omega)
        let cosine = cos(omega)
        let q = max(0.1, min(10, band.q))
        let amplitude = pow(10, band.gain / 40)
        let alpha = sine / (2 * q)

        switch band.filterType {
        case .parametric:
            return .normalized(
                b0: 1 + alpha * amplitude,
                b1: -2 * cosine,
                b2: 1 - alpha * amplitude,
                a0: 1 + alpha / amplitude,
                a1: -2 * cosine,
                a2: 1 - alpha / amplitude
            )
        case .lowShelf, .highShelf:
            let shelfAlpha = sine / 2 * sqrt(max(0, (amplitude + 1 / amplitude) * (1 / q - 1) + 2))
            let beta = 2 * sqrt(amplitude) * shelfAlpha
            if band.filterType == .lowShelf {
                return .normalized(
                    b0: amplitude * ((amplitude + 1) - (amplitude - 1) * cosine + beta),
                    b1: 2 * amplitude * ((amplitude - 1) - (amplitude + 1) * cosine),
                    b2: amplitude * ((amplitude + 1) - (amplitude - 1) * cosine - beta),
                    a0: (amplitude + 1) + (amplitude - 1) * cosine + beta,
                    a1: -2 * ((amplitude - 1) + (amplitude + 1) * cosine),
                    a2: (amplitude + 1) + (amplitude - 1) * cosine - beta
                )
            }
            return .normalized(
                b0: amplitude * ((amplitude + 1) + (amplitude - 1) * cosine + beta),
                b1: -2 * amplitude * ((amplitude - 1) + (amplitude + 1) * cosine),
                b2: amplitude * ((amplitude + 1) + (amplitude - 1) * cosine - beta),
                a0: (amplitude + 1) - (amplitude - 1) * cosine + beta,
                a1: 2 * ((amplitude - 1) + (amplitude + 1) * cosine),
                a2: (amplitude + 1) - (amplitude - 1) * cosine - beta
            )
        case .lowPass:
            return .normalized(
                b0: (1 - cosine) / 2,
                b1: 1 - cosine,
                b2: (1 - cosine) / 2,
                a0: 1 + alpha,
                a1: -2 * cosine,
                a2: 1 - alpha
            )
        case .highPass:
            return .normalized(
                b0: (1 + cosine) / 2,
                b1: -(1 + cosine),
                b2: (1 + cosine) / 2,
                a0: 1 + alpha,
                a1: -2 * cosine,
                a2: 1 - alpha
            )
        }
    }
}
