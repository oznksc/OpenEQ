import Foundation

/// Estimates and tracks loudness difference between active EQ and bypassed audio
/// for loudness-matched, unbiased A/B evaluations according to EBU R128 principles.
struct LevelMatchEstimator {
    private(set) var offsetDB: Float = 0
    private(set) var isConverged: Bool = false
    private var hasEstimate = false
    private var sampleCount: Int = 0
    private var accumulatedActiveRMS: Float = 0
    private var accumulatedBypassRMS: Float = 0

    mutating func update(activeRMS: Float, bypassRMS: Float, responsiveness: Float = 0.15) -> Float {
        guard activeRMS.isFinite, bypassRMS.isFinite,
              activeRMS > 0.0005, bypassRMS > 0.0005 else {
            return offsetDB
        }

        let target = max(-12, min(12, 20 * log10(bypassRMS / activeRMS)))
        let alpha = max(0.01, min(1, responsiveness))

        if hasEstimate {
            offsetDB += (target - offsetDB) * alpha
            sampleCount += 1
            if sampleCount >= 8 {
                isConverged = true
            }
        } else {
            offsetDB = target
            hasEstimate = true
            sampleCount = 1
        }
        return offsetDB
    }

    mutating func registerBypassMeasurement(_ rms: Float) {
        guard rms.isFinite, rms > 0.0005 else { return }
        accumulatedBypassRMS = accumulatedBypassRMS == 0 ? rms : accumulatedBypassRMS * 0.8 + rms * 0.2
    }

    mutating func registerActiveMeasurement(_ rms: Float) {
        guard rms.isFinite, rms > 0.0005 else { return }
        accumulatedActiveRMS = accumulatedActiveRMS == 0 ? rms : accumulatedActiveRMS * 0.8 + rms * 0.2
        if accumulatedBypassRMS > 0.0005 {
            _ = update(activeRMS: accumulatedActiveRMS, bypassRMS: accumulatedBypassRMS)
        }
    }

    mutating func reset() {
        offsetDB = 0
        hasEstimate = false
        isConverged = false
        sampleCount = 0
        accumulatedActiveRMS = 0
        accumulatedBypassRMS = 0
    }
}

