import Foundation

/// Detects sustained *digital clipping* that can indicate a feedback/howling loop.
///
/// Intentionally conservative: loud music, EQ boosts, and the peak limiter working
/// near full scale must not trip. We only care about hard-clip-like energy that
/// persists for multiple seconds after a short startup grace period.
struct FeedbackGuard: Equatable {
    /// True digital full-scale territory (limiter ceiling is 0.98 — music should stay below this).
    static let peakThreshold: Float = 0.999
    /// Very hot average energy; ordinary program material rarely sustains this with hard peaks.
    static let rmsThreshold: Float = 0.72
    /// ~2–4 s at typical Core Audio buffer rates (256–512 frames @ 48 kHz).
    static let tripWindowCount: Int = 200
    /// Ignore the first windows after start/reset (device settle, permission, buffer underruns).
    static let graceWindowCount: Int = 120
    static let coolDownStep: Int = 4

    private(set) var hotWindows: Int = 0
    private(set) var windowsSeen: Int = 0
    private(set) var isTripped: Bool = false

    mutating func evaluate(peak: Float, rms: Float) -> Bool {
        guard !isTripped else { return true }

        windowsSeen += 1
        if windowsSeen <= Self.graceWindowCount {
            return false
        }

        // Require hard clip *and* extreme RMS — not just a limited loud mix.
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
            // Skip non-finite garbage so NaNs cannot trip the guard.
            guard sample.isFinite else { continue }
            let absolute = abs(sample)
            if absolute > peak { peak = absolute }
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(frames))
        return evaluate(peak: peak, rms: rms)
    }

    mutating func reset() {
        hotWindows = 0
        windowsSeen = 0
        isTripped = false
    }
}
