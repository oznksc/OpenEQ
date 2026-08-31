import Foundation

enum ListeningComfortStatus: String, Codable, Equatable {
    case comfortable
    case elevated
    case takeBreak

    var title: String {
        switch self {
        case .comfortable:
            return "Comfortable"
        case .elevated:
            return "Getting intense"
        case .takeBreak:
            return "Take a short break"
        }
    }
}

struct ListeningComfortState: Equatable {
    let score: Float
    let exposurePercent: Float
    let loudnessPressure: Float
    let spectralStrain: Float
    let isActive: Bool
    let status: ListeningComfortStatus

    static let idle = ListeningComfortState(
        score: 100,
        exposurePercent: 0,
        loudnessPressure: 0,
        spectralStrain: 0,
        isActive: false,
        status: .comfortable
    )

    var recommendation: String {
        switch status {
        case .comfortable:
            return isActive ? "Your current level and tone look comfortable." : "Start playback to track listening comfort."
        case .elevated:
            return "A little less level or treble can make this session easier on your ears."
        case .takeBreak:
            return "OpenEQ recommends a short quiet break before continuing."
        }
    }

    var suggestedReliefDB: Float {
        let value = (100 - score) * 0.035 + spectralStrain * 1.5
        return max(0, min(3, value))
    }
}
