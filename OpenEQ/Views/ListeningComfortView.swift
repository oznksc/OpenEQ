import SwiftUI

struct ListeningComfortView: View {
    @Bindable var viewModel: OpenEQViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "ear.and.waveform")
                    .foregroundStyle(OpenEQTheme.accentPurple)
                Text("COMFORT GUARD")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1)
                Spacer()
                statusBadge
            }

            HStack(alignment: .center, spacing: 28) {
                scoreView

                VStack(alignment: .leading, spacing: 7) {
                    Text(viewModel.listeningComfortState.recommendation)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        metric("Session load", value: viewModel.listeningComfortState.exposurePercent, color: OpenEQTheme.accentAmber)
                        metric("Harshness", value: viewModel.listeningComfortState.spectralStrain, color: OpenEQTheme.accentPurple)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 10) {
                    Toggle("Track", isOn: $viewModel.isListeningComfortEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    Toggle("Auto-soothe", isOn: $viewModel.isListeningComfortAutoSootheEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }

                if viewModel.listeningComfortState.suggestedReliefDB > 0.2 {
                    Button {
                        viewModel.applyListeningComfortRelief()
                    } label: {
                        Label("Gentle relief", systemImage: "wand.and.stars")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OpenEQTheme.accentPurple)
                    .help("Apply a reversible, gentle high-frequency reduction")
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard(cornerRadius: 18, elevation: true)
    }

    private var statusBadge: some View {
        Text(viewModel.listeningComfortState.status.title.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var statusColor: Color {
        switch viewModel.listeningComfortState.status {
        case .comfortable:
            return OpenEQTheme.accentGreen
        case .elevated:
            return OpenEQTheme.accentAmber
        case .takeBreak:
            return OpenEQTheme.accentRed
        }
    }

    private var scoreView: some View {
        VStack(spacing: 2) {
            Gauge(value: Double(viewModel.listeningComfortState.score) / 100) {
                Text("Comfort")
            } currentValueLabel: {
                Text("\(Int(viewModel.listeningComfortState.score))")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(statusColor)
            .frame(width: 122, height: 122)
        }
    }

    private func metric(_ title: String, value: Float, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            ProgressView(value: Double(value))
                .tint(color)
                .frame(width: 110)
        }
    }
}
