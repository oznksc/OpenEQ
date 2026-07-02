import Foundation

@MainActor
final class SponsorStore {
    private let logger = AppLogger(category: "Sponsor")

    func loadSponsors() -> [Sponsor] {
        guard let url = Bundle.main.url(forResource: "sponsors", withExtension: "json") else {
            logger.info("No sponsors.json found in bundle.")
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let sponsors = try decoder.decode([Sponsor].self, from: data)
            logger.info("Loaded \(sponsors.filter(\.isActive).count) active sponsors")
            return sponsors
        } catch {
            logger.error("Failed to load sponsors: \(error.localizedDescription)")
            return []
        }
    }
}
