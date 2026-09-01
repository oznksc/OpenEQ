import Foundation

struct LevelMatchEstimator {
    private(set) var offsetDB: Float = 0
    private var hasEstimate = false

    mutating func update(activeRMS: Float, bypassRMS: Float, responsiveness: Float = 0.18) -> Float {
        guard activeRMS.isFinite, bypassRMS.isFinite,
              activeRMS > 0.0001, bypassRMS > 0.0001 else {
            return offsetDB
        }
        let target = max(-12, min(12, 20 * log10(bypassRMS / activeRMS)))
        let alpha = max(0.01, min(1, responsiveness))
        if hasEstimate {
            offsetDB += (target - offsetDB) * alpha
        } else {
            offsetDB = target
            hasEstimate = true
        }
        return offsetDB
    }

    mutating func reset() {
        offsetDB = 0
        hasEstimate = false
    }
}
