import SwiftUI

struct SponsorView: View {
    let sponsors: [Sponsor]

    var body: some View {
        let activeSponsors = sponsors.filter(\.isActive)

        VStack(alignment: .leading, spacing: 8) {
            if !activeSponsors.isEmpty {
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

            VStack(spacing: 4) {
                Link(destination: URL(string: "https://github.com/sponsors")!) {
                    Label("Sponsor on GitHub", systemImage: "heart.fill")
                        .font(.caption2)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Link(destination: URL(string: "https://github.com/ozan/OpenEQ")!) {
                    Label("Star on GitHub", systemImage: "star.fill")
                        .font(.caption2)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func sponsorRow(_ sponsor: Sponsor) -> some View {
        Group {
            if let url = sponsor.websiteURL.flatMap(URL.init) {
                Link(destination: url) { sponsorContent(sponsor) }.buttonStyle(.plain)
            } else {
                sponsorContent(sponsor)
            }
        }
    }

    private func sponsorContent(_ sponsor: Sponsor) -> some View {
        HStack(spacing: 6) {
            Image(systemName: sponsor.imageName ?? "building.2.fill")
                .font(.caption)
                .foregroundStyle(tierColor(sponsor.tier))

            VStack(alignment: .leading, spacing: 0) {
                Text(sponsor.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                if let tagline = sponsor.tagline {
                    Text(tagline)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(sponsor.tier.rawValue)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(tierColor(sponsor.tier))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(tierColor(sponsor.tier).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .padding(.vertical, 2)
    }

    private func tierColor(_ tier: Sponsor.SponsorTier) -> Color {
        switch tier { case .gold: return .yellow; case .silver: return .gray; case .bronze: return .orange }
    }
}

#Preview {
    SponsorView(sponsors: [
        Sponsor(id: UUID(), name: "Example Corp", websiteURL: nil, imageName: "building.2.fill", tagline: "Making audio better", tier: .gold, isActive: true),
    ])
    .frame(width: 260)
    .padding()
}
