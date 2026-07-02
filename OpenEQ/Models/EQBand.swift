//
//  EQBand.swift
//  OpenEQ
//
//  Created by Ozan
//

import Foundation

enum EQFilterType: String, CaseIterable, Codable, Identifiable {
    case parametric
    case lowShelf
    case highShelf
    case highPass
    case lowPass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .parametric:
            return "Parametric"
        case .lowShelf:
            return "Low Shelf"
        case .highShelf:
            return "High Shelf"
        case .highPass:
            return "High Pass"
        case .lowPass:
            return "Low Pass"
        }
    }
}

enum GraphicBandCount: String, CaseIterable, Codable, Identifiable {
    case ten = "10-Band"
    case thirtyOne = "31-Band"

    var id: String { rawValue }

    var title: String { rawValue }

    var bandCount: Int {
        switch self {
        case .ten: return 10
        case .thirtyOne: return 31
        }
    }
}

/// Represents a single equalizer band parameter set for audio filtering.
struct EQBand: Identifiable, Codable, Equatable {
    static let neutralGain: Float = 0.0
    static let gainRange: ClosedRange<Float> = -24.0...24.0
    static let defaultQ: Float = 1.0
    static let qRange: ClosedRange<Float> = 0.1...10.0
    static let frequencyRange: ClosedRange<Float> = 20.0...20_000.0

    let id: UUID
    var frequency: Float {
        didSet {
            frequency = max(Self.frequencyRange.lowerBound, min(Self.frequencyRange.upperBound, frequency))
        }
    }
    var gain: Float {
        didSet {
            // Clamp gain to range [-24.0, 24.0] dB
            gain = max(Self.gainRange.lowerBound, min(Self.gainRange.upperBound, gain))
        }
    }
    var q: Float {
        didSet {
            q = max(Self.qRange.lowerBound, min(Self.qRange.upperBound, q))
        }
    }
    var filterType: EQFilterType
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        frequency: Float,
        gain: Float = Self.neutralGain,
        q: Float = Self.defaultQ,
        filterType: EQFilterType = .parametric,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.frequency = max(Self.frequencyRange.lowerBound, min(Self.frequencyRange.upperBound, frequency))
        self.gain = max(Self.gainRange.lowerBound, min(Self.gainRange.upperBound, gain))
        self.q = max(Self.qRange.lowerBound, min(Self.qRange.upperBound, q))
        self.filterType = filterType
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case frequency
        case gain
        case q
        case filterType
        case isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            frequency: try container.decode(Float.self, forKey: .frequency),
            gain: try container.decode(Float.self, forKey: .gain),
            q: try container.decodeIfPresent(Float.self, forKey: .q) ?? Self.defaultQ,
            filterType: try container.decodeIfPresent(EQFilterType.self, forKey: .filterType) ?? .parametric,
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        )
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
    static func defaultBands(count: GraphicBandCount = .ten) -> [EQBand] {
        switch count {
        case .ten:
            return tenBandFrequencies.map { EQBand(frequency: $0) }
        case .thirtyOne:
            return thirtyOneBandFrequencies.map { EQBand(frequency: $0) }
        }
    }

    static func defaultParametricBands() -> [EQBand] {
        [
            EQBand(frequency: 80, q: 0.7, filterType: .lowShelf),
            EQBand(frequency: 250, q: 1.0, filterType: .parametric),
            EQBand(frequency: 1000, q: 1.0, filterType: .parametric),
            EQBand(frequency: 4000, q: 1.0, filterType: .parametric),
            EQBand(frequency: 12000, q: 0.7, filterType: .highShelf)
        ]
    }

    static func defaultBands(for mode: EQMode, graphicBandCount: GraphicBandCount = .ten) -> [EQBand] {
        switch mode {
        case .graphic:
            return defaultBands(count: graphicBandCount)
        case .parametric:
            return defaultParametricBands()
        }
    }

    static let tenBandFrequencies: [Float] = [
        32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
    ]

    static let thirtyOneBandFrequencies: [Float] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630,
        800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000,
        12500, 16000, 20000
    ]
}
