import Foundation

struct Sponsor: Identifiable, Codable {
    let id: UUID
    let name: String
    let websiteURL: String?
    let imageName: String?
    let tagline: String?
    let tier: SponsorTier
    let isActive: Bool

    enum SponsorTier: String, Codable, CaseIterable, Identifiable {
        var id: String { rawValue }
        case gold = "Gold"
        case silver = "Silver"
        case bronze = "Bronze"

        var sortOrder: Int {
            switch self {
            case .gold: return 0
            case .silver: return 1
            case .bronze: return 2
            }
        }
    }
}
