import Foundation

enum SystemAudioMode: String, CaseIterable, Codable, Identifiable {
    case disabled
    case systemEQ
    case externalLoopback

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled: return "Disabled"
        case .systemEQ: return "System-Wide EQ"
        case .externalLoopback: return "External Loopback"
        }
    }

    var description: String {
        switch self {
        case .disabled: return "EQ applies to local files only"
        case .systemEQ: return "EQ applies to all system audio via Core Audio Tap"
        case .externalLoopback: return "Route system audio through a virtual device"
        }
    }
}
