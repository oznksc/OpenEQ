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
    static let duration = 512
    private var current: BiquadCoefficients = .identity
    private var target: BiquadCoefficients = .identity
    private var remaining = 0

    mutating func startTransition(to newTarget: BiquadCoefficients) {
        if remaining > 0 {
            let t = 1 - Float(remaining) / Float(Self.duration)
            current = lerp(current, target, t)
        }
        target = newTarget
        remaining = Self.duration
    }

    func interpolatedCoeffs() -> BiquadCoefficients {
        guard remaining > 0 else { return current }
        let t = 1 - Float(remaining) / Float(Self.duration)
        return lerp(current, target, t)
    }

    mutating func advance(frames: Int) {
        guard remaining > 0 else { return }
        if frames >= remaining {
            current = target
            remaining = 0
        } else {
            let t = 1 - Float(remaining - frames) / Float(Self.duration)
            current = lerp(current, target, t)
            remaining -= frames
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

private struct BiquadState {
    var x1: Float = 0
    var x2: Float = 0
    var y1: Float = 0
    var y2: Float = 0
}

private enum SystemAudioLimiter {
    static let ceiling: Float = 0.98
    static let attack: Float = 0.35
    static let release: Float = 0.0025
}

final class SystemAudioDSPState {
    private var smoothingCoeffs = Array(repeating: SmoothingCoefficients(), count: 31)
    private var leftStates = Array(repeating: BiquadState(), count: 31)
    private var rightStates = Array(repeating: BiquadState(), count: 31)
    private var currentInterpolated: [BiquadCoefficients] = Array(repeating: .identity, count: 31)
    private var preampLinear: Float = 1
    private var targetPreampLinear: Float = 1
    private var leftLimiterGain: Float = 1
    private var rightLimiterGain: Float = 1
    var isBypassed = false
    var isEmergencyMuted = false

    func configure(_ preset: EQPreset, sampleRate: Double) {
        targetPreampLinear = pow(10, preset.preamp / 20)
        for index in smoothingCoeffs.indices {
            guard index < preset.bands.count else {
                smoothingCoeffs[index].startTransition(to: .identity)
                continue
            }
            smoothingCoeffs[index].startTransition(
                to: Self.makeCoefficients(for: preset.bands[index], sampleRate: Float(sampleRate))
            )
        }
    }

    func reset() {
        preampLinear = 1
        targetPreampLinear = 1
        leftLimiterGain = 1
        rightLimiterGain = 1
        isBypassed = false
        isEmergencyMuted = false
        smoothingCoeffs = Array(repeating: SmoothingCoefficients(), count: 31)
        currentInterpolated = Array(repeating: .identity, count: 31)
        leftStates = Array(repeating: BiquadState(), count: 31)
        rightStates = Array(repeating: BiquadState(), count: 31)
    }

    func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channel: Int) {
        if isEmergencyMuted {
            memset(samples, 0, frames * MemoryLayout<Float>.size)
            return
        }

        if !isBypassed {
            if channel == 0 {
                let preampDelta = targetPreampLinear - preampLinear
                if abs(preampDelta) > 0.00001 {
                    preampLinear += preampDelta * min(1, Float(frames) / 256)
                } else {
                    preampLinear = targetPreampLinear
                }

                for index in smoothingCoeffs.indices {
                    currentInterpolated[index] = smoothingCoeffs[index].interpolatedCoeffs()
                    smoothingCoeffs[index].advance(frames: frames)
                }
            }

            if abs(preampLinear - 1) > 0.0001 {
                var gain = preampLinear
                vDSP_vsmul(samples, 1, &gain, samples, 1, vDSP_Length(frames))
            }

            if channel == 0 {
                processFilters(samples, frames: frames, states: &leftStates)
            } else {
                processFilters(samples, frames: frames, states: &rightStates)
            }
        }

        if channel == 0 {
            applyPeakLimiter(samples, frames: frames, gain: &leftLimiterGain)
        } else {
            applyPeakLimiter(samples, frames: frames, gain: &rightLimiterGain)
        }
    }

    private func processFilters(
        _ samples: UnsafeMutablePointer<Float>,
        frames: Int,
        states: inout [BiquadState]
    ) {
        for band in currentInterpolated.indices {
            let coeff = currentInterpolated[band]
            if coeff.isIdentity { continue }
            var state = states[band]
            for index in 0..<frames {
                let input = samples[index]
                let output = coeff.b0 * input
                    + coeff.b1 * state.x1
                    + coeff.b2 * state.x2
                    - coeff.a1 * state.y1
                    - coeff.a2 * state.y2
                samples[index] = output
                state.x2 = state.x1
                state.x1 = input
                state.y2 = state.y1
                state.y1 = output
            }
            states[band] = state
        }
    }

    private func applyPeakLimiter(
        _ samples: UnsafeMutablePointer<Float>,
        frames: Int,
        gain: inout Float
    ) {
        let ceiling = SystemAudioLimiter.ceiling
        for index in 0..<frames {
            let absSample = abs(samples[index])
            let needed = absSample > ceiling ? ceiling / absSample : 1
            if needed < gain {
                gain += (needed - gain) * SystemAudioLimiter.attack
            } else {
                gain += (1 - gain) * SystemAudioLimiter.release
            }
            var out = samples[index] * gain
            if out > 1 { out = 1 }
            if out < -1 { out = -1 }
            samples[index] = out
        }
    }

    private static func makeCoefficients(for band: EQBand, sampleRate: Float) -> BiquadCoefficients {
        guard band.isEnabled, sampleRate > 0 else { return .identity }
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
