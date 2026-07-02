//
//  EQPreset.swift
//  OpenEQ
//
//  Created by Ozan
//

import Foundation

/// Represents a persistent equalizer configuration template.
struct EQPreset: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    var mode: EQMode
    var bands: [EQBand]
    var preamp: Float
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        mode: EQMode = .graphic,
        bands: [EQBand],
        preamp: Float = 0.0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.bands = bands
        self.preamp = preamp
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case mode
        case bands
        case preamp
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            mode: try container.decodeIfPresent(EQMode.self, forKey: .mode) ?? .graphic,
            bands: try container.decode([EQBand].self, forKey: .bands),
            preamp: try container.decode(Float.self, forKey: .preamp),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt)
        )
    }
}

extension EQPreset {
    /// Returns a standard flat preset.
    static func flatPreset() -> EQPreset {
        EQPreset(name: "Flat", mode: .graphic, bands: EQBand.defaultBands(), preamp: 0.0)
    }

    /// Backwards compatibility property.
    static var flat: EQPreset {
        flatPreset()
    }

    /// List of standard presets.
    static func defaultPresets() -> [EQPreset] {
        return [
            flatPreset(),
            
            EQPreset(
                name: "Bass Boost",
                bands: EQBand.defaultBands().enumerated().map { index, band in
                    var b = band
                    // Boost the first 4 bands (32, 64, 125, 250 Hz)
                    if index == 0 { b.gain = 6.0 }
                    else if index == 1 { b.gain = 5.5 }
                    else if index == 2 { b.gain = 4.0 }
                    else if index == 3 { b.gain = 2.0 }
                    return b
                },
                preamp: -2.0
            ),
            
            EQPreset(
                name: "Vocal Clarity",
                bands: EQBand.defaultBands().enumerated().map { index, band in
                    var b = band
                    // Boost frequencies in core vocal range (500, 1k, 2k, 4k)
                    if index == 4 { b.gain = 1.0 }
                    else if index == 5 { b.gain = 3.5 }
                    else if index == 6 { b.gain = 4.0 }
                    else if index == 7 { b.gain = 2.0 }
                    // Slight cut on sub-bass and extreme treble
                    else if index == 0 { b.gain = -3.0 }
                    else if index == 9 { b.gain = -2.0 }
                    return b
                },
                preamp: -1.0
            ),
            
            EQPreset(
                name: "Warm",
                bands: EQBand.defaultBands().enumerated().map { index, band in
                    var b = band
                    // Gentle slope boosting lows/low-mids, cutting highs
                    if index == 0 { b.gain = 3.5 }
                    else if index == 1 { b.gain = 3.0 }
                    else if index == 2 { b.gain = 2.0 }
                    else if index == 3 { b.gain = 1.5 }
                    else if index == 4 { b.gain = 0.5 }
                    else if index >= 7 { b.gain = -2.5 }
                    return b
                },
                preamp: 0.0
            ),
            
            EQPreset(
                name: "Bright",
                bands: EQBand.defaultBands().enumerated().map { index, band in
                    var b = band
                    // Boost upper mids and highs
                    if index >= 6 {
                        b.gain = Float(index - 5) * 1.5
                    } else if index <= 2 {
                        b.gain = -1.5
                    }
                    return b
                },
                preamp: -1.5
            )
        ]
    }

    /// Backwards compatibility property.
    static var mockPresets: [EQPreset] {
        defaultPresets()
    }
}
