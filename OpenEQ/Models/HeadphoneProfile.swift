import Foundation

/// A headphone (or IEM) correction profile that maps to OpenEQ bands.
struct HeadphoneProfile: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var brand: String
    var source: String
    var target: String
    /// Gains in dB aligned to OpenEQ 10-band ISO centers when `bandCount == 10`.
    var gains: [Float]
    var preamp: Float
    var notes: String?

    var bandCount: Int { gains.count }

    var displayName: String {
        brand.isEmpty ? name : "\(brand) \(name)"
    }

    init(
        id: UUID = UUID(),
        name: String,
        brand: String,
        source: String = "AutoEQ",
        target: String = "Harman",
        gains: [Float],
        preamp: Float = 0,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.source = source
        self.target = target
        self.gains = gains
        self.preamp = preamp
        self.notes = notes
    }

    /// Builds a graphic EQ preset using 10-band or 31-band defaults for frequencies.
    func asPreset(graphicBandCount: GraphicBandCount = .ten) -> EQPreset {
        let frequencies: [Float]
        switch graphicBandCount {
        case .ten:
            frequencies = EQBand.tenBandFrequencies
        case .thirtyOne:
            frequencies = EQBand.thirtyOneBandFrequencies
        }

        let bands: [EQBand]
        if gains.count == frequencies.count {
            bands = zip(frequencies, gains).map { frequency, gain in
                EQBand(frequency: frequency, gain: gain)
            }
        } else if gains.count == EQBand.tenBandFrequencies.count, graphicBandCount == .thirtyOne {
            // Upsample 10-band → 31-band by nearest log-frequency neighbor.
            bands = frequencies.map { frequency in
                let nearest = nearestTenBandGain(for: frequency)
                return EQBand(frequency: frequency, gain: nearest)
            }
        } else {
            // Downsample or pad.
            bands = frequencies.enumerated().map { index, frequency in
                let gain = index < gains.count ? gains[index] : 0
                return EQBand(frequency: frequency, gain: gain)
            }
        }

        return EQPreset(
            name: displayName,
            mode: .graphic,
            bands: bands,
            preamp: preamp
        )
    }

    private func nearestTenBandGain(for frequency: Float) -> Float {
        let centers = EQBand.tenBandFrequencies
        guard !gains.isEmpty else { return 0 }
        var bestIndex = 0
        var bestDistance = Float.greatestFiniteMagnitude
        for (index, center) in centers.enumerated() where index < gains.count {
            let distance = abs(log2(max(frequency, 1) / max(center, 1)))
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return gains[bestIndex]
    }
}
