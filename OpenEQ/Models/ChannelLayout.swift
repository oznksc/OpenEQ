import Foundation

/// Output channel layout awareness for future multi-channel calibration.
enum ChannelLayout: String, CaseIterable, Codable, Identifiable {
    case stereo
    case multiChannel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stereo: return "Stereo"
        case .multiChannel: return "Multi-channel"
        }
    }

    var description: String {
        switch self {
        case .stereo:
            return "Standard 2-channel EQ (default). Stereo balance is available in Dynamics."
        case .multiChannel:
            return "Per-channel EQ for 5.1 / 7.1 / Atmos is planned. Stereo path remains active."
        }
    }

    var isFullySupported: Bool {
        self == .stereo
    }
}

/// Placeholder for future per-channel gain offsets (Phase 4 foundation).
struct ChannelGainOffset: Identifiable, Codable, Equatable {
    var id: String { channelName }
    var channelName: String
    var gainDB: Float

    static let stereoDefaults: [ChannelGainOffset] = [
        ChannelGainOffset(channelName: "Left", gainDB: 0),
        ChannelGainOffset(channelName: "Right", gainDB: 0)
    ]
}
