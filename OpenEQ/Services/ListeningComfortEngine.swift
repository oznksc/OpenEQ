import Foundation

final class ListeningComfortEngine {
    private(set) var state = ListeningComfortState.idle

    private var exposure: Double = 0
    private var smoothedPressure: Float = 0

    func update<Levels: Collection>(
        peakLevel: Float,
        spectrumLevels: Levels,
        isActive: Bool,
        elapsed: TimeInterval
    ) -> ListeningComfortState where Levels.Element == Float {
        let safeElapsed = max(0, min(elapsed, 5))
        let loudnessPressure = pressure(for: peakLevel)
        let spectralStrain = highFrequencyStrain(in: spectrumLevels)
        let instantaneousPressure = loudnessPressure * 0.7 + spectralStrain * 0.3

        if isActive {
            smoothedPressure = smoothedPressure * 0.82 + instantaneousPressure * 0.18
            exposure += Double(max(0, smoothedPressure - 0.18)) * safeElapsed / 3600
        } else {
            smoothedPressure *= Float(exp(-safeElapsed / 18))
        }

        exposure = max(0, min(1, exposure))
        let exposureLoad = Float(exposure) * 0.72
        let pressureLoad = smoothedPressure * 0.28
        let combinedLoad = exposureLoad + pressureLoad
        let score = max(0, min(100, 100 * (1 - combinedLoad)))
        let status: ListeningComfortStatus
        if score < 45 || exposure >= 0.8 {
            status = .takeBreak
        } else if score < 72 || exposure >= 0.45 {
            status = .elevated
        } else {
            status = .comfortable
        }

        state = ListeningComfortState(
            score: score,
            exposurePercent: Float(exposure),
            loudnessPressure: loudnessPressure,
            spectralStrain: spectralStrain,
            isActive: isActive,
            status: status
        )
        return state
    }

    func reset() {
        exposure = 0
        smoothedPressure = 0
        state = .idle
    }

    private func pressure(for peakLevel: Float) -> Float {
        let safePeak = max(0.0001, min(1, peakLevel))
        let peakDB = 20 * log10(safePeak)
        return max(0, min(1, (peakDB + 24) / 24))
    }

    private func highFrequencyStrain<Levels: Collection>(in levels: Levels) -> Float where Levels.Element == Float {
        guard !levels.isEmpty else { return 0 }
        let start = max(0, levels.count * 3 / 4)
        let highBandLevels = levels.dropFirst(start)
        let average = highBandLevels.reduce(0, +) / Float(highBandLevels.count)
        return max(0, min(1, average))
    }
}
