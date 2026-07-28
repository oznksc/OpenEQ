import Foundation

/// Detects sustained near-clip high-energy output that often indicates a
/// feedback/howling loop and requests an emergency mute within milliseconds.
struct FeedbackGuard: Equatable {
    /// Peak must stay at/above this fraction of full scale.
    static let peakThreshold: Float = 0.985
    /// RMS must stay high so short musical peaks alone do not trip.
    static let rmsThreshold: Float = 0.42
    /// Consecutive hot analysis windows required before a trip (~0.5–1s depending on hop).
    static let tripWindowCount: Int = 36
    /// Cool-down steps when signal falls back under thresholds.
    static let coolDownStep: Int = 2

    private(set) var hotWindows: Int = 0
    private(set) var isTripped: Bool = false

    mutating func evaluate(peak: Float, rms: Float) -> Bool {
        guard !isTripped else { return true }

        if peak >= Self.peakThreshold, rms >= Self.rmsThreshold {
            hotWindows += 1
        } else if hotWindows > 0 {
            hotWindows = max(0, hotWindows - Self.coolDownStep)
        }

        if hotWindows >= Self.tripWindowCount {
            isTripped = true
            return true
        }
        return false
    }

    /// Convenience for mono/interleaved buffer slices (no allocations).
    mutating func evaluate(samples: UnsafePointer<Float>, frames: Int) -> Bool {
        guard frames > 0 else { return isTripped }

        var peak: Float = 0
        var sumSquares: Float = 0
        for index in 0..<frames {
            let sample = samples[index]
            let absolute = abs(sample)
            if absolute > peak { peak = absolute }
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(frames))
        return evaluate(peak: peak, rms: rms)
    }

    mutating func reset() {
        hotWindows = 0
        isTripped = false
    }
}
