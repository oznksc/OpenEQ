import Foundation

/// Output dynamics and stereo imaging applied after the EQ stage.
struct DynamicsSettings: Equatable, Codable {
    var isCompressorEnabled: Bool
    /// dB, typical musical range.
    var threshold: Float
    /// Compression ratio (1 = no compression, 20 ≈ brickwall-ish).
    var ratio: Float
    /// Seconds.
    var attack: Float
    /// Seconds.
    var release: Float
    /// Makeup gain in dB.
    var makeupGain: Float
    /// Stereo balance: -1 = full left, 0 = center, 1 = full right.
    var balance: Float

    static let thresholdRange: ClosedRange<Float> = -60...0
    static let ratioRange: ClosedRange<Float> = 1...20
    static let attackRange: ClosedRange<Float> = 0.001...0.2
    static let releaseRange: ClosedRange<Float> = 0.01...1.0
    static let makeupRange: ClosedRange<Float> = -12...12
    static let balanceRange: ClosedRange<Float> = -1...1

    static let `default` = DynamicsSettings(
        isCompressorEnabled: false,
        threshold: -18,
        ratio: 3,
        attack: 0.01,
        release: 0.1,
        makeupGain: 0,
        balance: 0
    )

    mutating func clamp() {
        threshold = min(max(threshold, Self.thresholdRange.lowerBound), Self.thresholdRange.upperBound)
        ratio = min(max(ratio, Self.ratioRange.lowerBound), Self.ratioRange.upperBound)
        attack = min(max(attack, Self.attackRange.lowerBound), Self.attackRange.upperBound)
        release = min(max(release, Self.releaseRange.lowerBound), Self.releaseRange.upperBound)
        makeupGain = min(max(makeupGain, Self.makeupRange.lowerBound), Self.makeupRange.upperBound)
        balance = min(max(balance, Self.balanceRange.lowerBound), Self.balanceRange.upperBound)
    }
}
