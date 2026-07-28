import AVFoundation

enum PeakLimiterConfigurator {
    /// Shared peak-limiter defaults used by local playback and external loopback.
    static func applyDefaults(to effect: AVAudioUnitEffect) {
        guard let paramTree = effect.auAudioUnit.parameterTree else { return }

        for param in paramTree.allParameters {
            switch param.identifier {
            case "attackTime":
                param.value = 0.005
            case "releaseTime":
                param.value = 0.05
            case "preGain":
                param.value = 0.0
            default:
                break
            }
        }

        effect.bypass = false
    }
}
