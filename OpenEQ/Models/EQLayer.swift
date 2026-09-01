import Foundation

/// Represents the three operational layers in OpenEQ's layered equalizer architecture.
enum EQLayerKind: String, CaseIterable, Identifiable, Codable {
    case calibration
    case target
    case session

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calibration: return "Calibration"
        case .target: return "Target Curve"
        case .session: return "Session"
        }
    }

    var subtitle: String {
        switch self {
        case .calibration: return "Hardware correction (AutoEQ / Measurement)"
        case .target: return "Acoustic preference target (Harman, Diffuse, etc.)"
        case .session: return "User fine-tuning & taste adjustments"
        }
    }

    var icon: String {
        switch self {
        case .calibration: return "headphones"
        case .target: return "target"
        case .session: return "slider.horizontal.3"
        }
    }
}

/// Represents a single layer of EQ processing with its own bands, preamp, and bypass state.
struct EQLayer: Identifiable, Codable, Equatable {
    let kind: EQLayerKind
    var isEnabled: Bool
    var preamp: Float
    var bands: [EQBand]
    var name: String

    var id: String { kind.rawValue }

    init(
        kind: EQLayerKind,
        isEnabled: Bool = true,
        preamp: Float = 0.0,
        bands: [EQBand] = [],
        name: String = ""
    ) {
        self.kind = kind
        self.isEnabled = isEnabled
        self.preamp = preamp
        self.bands = bands
        self.name = name.isEmpty ? kind.title : name
    }

    static func defaultLayers() -> [EQLayerKind: EQLayer] {
        [
            .calibration: EQLayer(kind: .calibration, isEnabled: true, preamp: 0.0, bands: [], name: "Calibration"),
            .target: EQLayer(kind: .target, isEnabled: true, preamp: 0.0, bands: [], name: "Target"),
            .session: EQLayer(kind: .session, isEnabled: true, preamp: 0.0, bands: EQBand.defaultBands(), name: "Session")
        ]
    }
}

/// Helper that merges layered EQ state into a single composite preset for DSP engines.
struct EQLayerComposite {
    static func compositePreset(
        mode: EQMode,
        layers: [EQLayerKind: EQLayer],
        activeSessionBands: [EQBand],
        sessionPreamp: Float
    ) -> EQPreset {
        var combinedBands: [EQBand] = []
        var totalPreamp: Float = 0

        // 1. Calibration Layer
        if let cal = layers[.calibration], cal.isEnabled, !cal.bands.isEmpty {
            combinedBands.append(contentsOf: cal.bands.filter(\.isEnabled))
            totalPreamp += cal.preamp
        }

        // 2. Target Layer
        if let target = layers[.target], target.isEnabled, !target.bands.isEmpty {
            combinedBands.append(contentsOf: target.bands.filter(\.isEnabled))
            totalPreamp += target.preamp
        }

        // 3. Session Layer (Active User EQ)
        if let session = layers[.session], session.isEnabled {
            combinedBands.append(contentsOf: activeSessionBands.filter(\.isEnabled))
            totalPreamp += sessionPreamp
        }

        // When graphic mode is active and no multi-layer parametric bands are added, return standard structure
        if mode == .graphic && (layers[.calibration]?.bands.isEmpty ?? true) && (layers[.target]?.bands.isEmpty ?? true) {
            return EQPreset(
                name: "Composite",
                mode: .graphic,
                bands: activeSessionBands,
                preamp: sessionPreamp
            )
        }

        // If composite has no bands, provide flat defaults
        if combinedBands.isEmpty {
            combinedBands = activeSessionBands
        }

        return EQPreset(
            name: "Composite",
            mode: mode,
            bands: combinedBands,
            preamp: totalPreamp
        )
    }
}
