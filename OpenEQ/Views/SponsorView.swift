import SwiftUI

struct SponsorView: View {
    let sponsors: [Sponsor]

    var body: some View {
        let activeSponsors = sponsors.filter(\.isActive)
        let hasSponsors = !activeSponsors.isEmpty

        VStack(alignment: .leading, spacing: 10) {
            if hasSponsors {
                Label("Sponsors", systemImage: "heart.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(Sponsor.SponsorTier.allCases.sorted(by: { $0.sortOrder < $1.sortOrder })) { tier in
                    let tierSponsors = activeSponsors.filter { $0.tier == tier }
                    if !tierSponsors.isEmpty {
                        ForEach(tierSponsors) { sponsor in
                            sponsorRow(sponsor)
                        }
                    }
                }
            }

            supportLinks
        }
        .padding(12)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(10)
    }

    private func sponsorRow(_ sponsor: Sponsor) -> some View {
        Group {
            if let url = sponsor.websiteURL.flatMap(URL.init) {
                Link(destination: url) {
                    sponsorContent(sponsor)
                }
                .buttonStyle(.plain)
            } else {
                sponsorContent(sponsor)
            }
        }
    }

    private func sponsorContent(_ sponsor: Sponsor) -> some View {
        HStack(spacing: 8) {
            Image(systemName: sponsor.imageName ?? "building.2.fill")
                .font(.title3)
                .foregroundStyle(tierColor(sponsor.tier))

            VStack(alignment: .leading, spacing: 1) {
                Text(sponsor.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                if let tagline = sponsor.tagline {
                    Text(tagline)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(sponsor.tier.rawValue)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tierColor(sponsor.tier))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(tierColor(sponsor.tier).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.vertical, 4)
    }

    private var supportLinks: some View {
        VStack(spacing: 6) {
            Divider()

            Link(destination: URL(string: "https://github.com/sponsors")!) {
                Label("Sponsor on GitHub", systemImage: "heart.fill")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Link(destination: URL(string: "https://github.com/ozan/OpenEQ")!) {
                Label("Star on GitHub", systemImage: "star.fill")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func tierColor(_ tier: Sponsor.SponsorTier) -> Color {
        switch tier {
        case .gold: return .yellow
        case .silver: return .gray
        case .bronze: return .orange
        }
    }
}

#Preview {
    SponsorView(sponsors: [
        Sponsor(id: UUID(), name: "Example Corp", websiteURL: nil, imageName: "building.2.fill", tagline: "Making audio better", tier: .gold, isActive: true),
        Sponsor(id: UUID(), name: "Test Inc", websiteURL: nil, imageName: "heart.circle.fill", tagline: "We love sound", tier: .silver, isActive: true),
    ])
    .frame(width: 300)
    .padding()
}
