import SwiftUI

struct MainWindowView: View {
    @Bindable var viewModel: OpenEQViewModel

    var body: some View {
        GeometryReader { geometry in
            let sidebarWidth = max(260, min(340, geometry.size.width * 0.28))

            VStack(spacing: 0) {
                header
                    .frame(height: 52)
                    .background(Color(nsColor: .windowBackgroundColor))

                Divider()
                    .opacity(0.4)

                HStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) {
                            SpectrumView(
                                title: viewModel.spectrumTitle,
                                warning: viewModel.spectrumWarning,
                                levels: viewModel.spectrumLevels,
                                leftLevel: viewModel.leftLevel,
                                rightLevel: viewModel.rightLevel,
                                peakLevel: viewModel.peakLevel,
                                isClipping: viewModel.isClipping
                            )
                            .frame(minHeight: 180)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .cornerRadius(12)

                            EqualizerView(viewModel: viewModel)
                                .background(Color(nsColor: .windowBackgroundColor))
                                .cornerRadius(12)
                        }
                        .padding(16)
                    }
                    .layoutPriority(1)

                    Divider()
                        .opacity(0.4)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 12) {
                            PresetPanelView(viewModel: viewModel)
                        }
                    }
                    .frame(width: sidebarWidth)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.2))
                }

                Divider()
                    .opacity(0.4)

                PlayerControlsView(viewModel: viewModel)
                    .frame(height: 56)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .sheet(isPresented: $viewModel.isShowingSystemAudio) {
            SystemAudioView(viewModel: viewModel)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: [.cyan.opacity(0.9), .blue.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 28, height: 28)

                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("OpenEQ")
                .font(.system(.title3, design: .rounded).weight(.semibold))

            Spacer()

            Button {
                viewModel.isShowingSystemAudio = true
            } label: {
                Label("System Audio", systemImage: "speaker.wave.2")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                Text(viewModel.playbackState.title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(12)
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
