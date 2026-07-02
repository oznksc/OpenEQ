import Foundation

@MainActor
final class SponsorStore {
    private let logger = AppLogger(category: "Sponsor")

    func loadSponsors() -> [Sponsor] {
        if let bundled = loadFromBundle() {
            return bundled
        }
        logger.info("No sponsors.json found; using demo placeholder.")
        return demoSponsors()
    }

    private func loadFromBundle() -> [Sponsor]? {
        guard let url = Bundle.main.url(forResource: "sponsors", withExtension: "json") else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let sponsors = try decoder.decode([Sponsor].self, from: data)
            logger.info("Loaded \(sponsors.filter(\.isActive).count) active sponsors from bundle")
            return sponsors
        } catch {
            logger.error("Failed to load sponsors.json: \(error.localizedDescription)")
            return nil
        }
    }

    private func demoSponsors() -> [Sponsor] {
        [
            Sponsor(
                id: UUID(uuidString: "E6B2C8D0-1234-5678-9ABC-DEF012345678") ?? UUID(),
                name: "Support OpenEQ",
                websiteURL: "https://github.com/sponsors",
                imageName: "heart.circle.fill",
                tagline: "Your company could be here!",
                tier: .gold,
                isActive: false
            ),
            Sponsor(
                id: UUID(uuidString: "A1B2C3D4-5678-90AB-CDEF-FEDCBA987654") ?? UUID(),
                name: "Become a Sponsor",
                websiteURL: "https://github.com/sponsors",
                imageName: "star.circle.fill",
                tagline: "Get your logo in the app",
                tier: .silver,
                isActive: false
            ),
            Sponsor(
                id: UUID(uuidString: "FEDCBA98-7654-3210-ABCD-EFGHIJKLMNOP") ?? UUID(),
                name: "Sponsor Slot",
                websiteURL: nil,
                imageName: "bag.circle.fill",
                tagline: "Bronze sponsors welcome",
                tier: .bronze,
                isActive: false
            )
        ]
    }
}
