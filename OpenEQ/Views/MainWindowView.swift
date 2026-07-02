import SwiftUI

struct MainWindowView: View {
    @Bindable var viewModel: OpenEQViewModel

    var body: some View {
        GeometryReader { geometry in
            let sidebarWidth = max(260, min(340, geometry.size.width * 0.28))

            VStack(spacing: 0) {
                header
                    .frame(height: 44)

                Divider()

                HStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            SpectrumView(
                                title: viewModel.spectrumTitle,
                                warning: viewModel.spectrumWarning,
                                levels: viewModel.spectrumLevels,
                                leftLevel: viewModel.leftLevel,
                                rightLevel: viewModel.rightLevel,
                                peakLevel: viewModel.peakLevel,
                                isClipping: viewModel.isClipping
                            )
                            .frame(minHeight: 160)

                            Divider()

                            EqualizerView(viewModel: viewModel)
                        }
                    }
                    .layoutPriority(1)

                    Divider()

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            PresetPanelView(viewModel: viewModel)

                            Divider()

                            SponsorView(sponsors: viewModel.sponsors)
                                .padding(12)
                        }
                    }
                    .frame(width: sidebarWidth)
                }

                Divider()

                PlayerControlsView(viewModel: viewModel)
                    .frame(height: 48)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .sheet(isPresented: $viewModel.isShowingSystemAudio) {
            SystemAudioView(viewModel: viewModel)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 28, height: 28)

                Image(systemName: "slider.vertical.3")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }

            Text("OpenEQ")
                .font(.system(.title3, design: .rounded).weight(.bold))

            Spacer()

            Button {
                viewModel.isShowingSystemAudio = true
            } label: {
                Label("System Audio", systemImage: "speaker.wave.2")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                Text(viewModel.playbackState.title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(14)
        }
        .padding(.horizontal, 16)
    }

    private var statusColor: Color {
        switch viewModel.playbackState {
        case .playing: return .green
        case .paused: return .orange
        case .stopped, .idle: return .gray
        case .preparing, .ready: return .blue
        case .failed: return .red
        }
    }
}

#Preview {
    MainWindowView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .frame(width: 1100, height: 700)
}
