//
//  EQBand.swift
//  OpenEQ
//
//  Created by Gökmen on 26.06.2026.
//

import Foundation

/// Represents a single equalizer band parameter set for audio filtering.
struct EQBand: Identifiable, Codable, Equatable {
    static let neutralGain: Float = 0.0
    static let gainRange: ClosedRange<Float> = -24.0...24.0
    static let defaultQ: Float = 1.0

    let id: UUID
    let frequency: Float
    var gain: Float {
        didSet {
            // Clamp gain to range [-24.0, 24.0] dB
            gain = max(Self.gainRange.lowerBound, min(Self.gainRange.upperBound, gain))
        }
    }
    var q: Float
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        frequency: Float,
        gain: Float = Self.neutralGain,
        q: Float = Self.defaultQ,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.frequency = frequency
        self.gain = max(Self.gainRange.lowerBound, min(Self.gainRange.upperBound, gain))
        self.q = q
        self.isEnabled = isEnabled
    }

    /// Computed label representing the frequency in a clean, human-readable format.
    var label: String {
        if frequency >= 1000 {
            return "\(Int(frequency / 1000))k"
        }
        return "\(Int(frequency))"
    }

    /// Backwards compatibility label helper.
    var frequencyLabel: String {
        return label
    }
}

extension EQBand {
    /// Generates the standard 10-band equalizer frequencies.
    static func defaultBands() -> [EQBand] {
        let standardFrequencies: [Float] = [
            32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
        ]
        return standardFrequencies.map { EQBand(frequency: $0) }
    }
    
    /// For compatibility with older view files until updated
    static var mockTenBand: [EQBand] {
        return defaultBands()
    }
}
