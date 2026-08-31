import SwiftUI
import Combine

/// Tactile floating studio player deck with smoked glassmorphism and illuminated controls.
struct PlayerControlsView: View {
    @Bindable var viewModel: OpenEQViewModel

    @State private var currentTime: Double = 0.0
    @State private var isDraggingScrubber = false
    private let timer = Timer.publish(every: 0.125, on: .main, in: .common).autoconnect()

    var body: some View {
        let duration = max(viewModel.playbackDuration, 1)

        VStack(alignment: .leading, spacing: 8) {
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            let controlRow = HStack(spacing: 16) {
                fileInfo
                transport
                progress(duration: duration)
                volume
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            controlRow
                .background(OpenEQTheme.cardBgElevated, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .onReceive(timer) { _ in
            guard !isDraggingScrubber else { return }
            switch viewModel.playbackState {
            case .playing, .paused, .stopped:
                currentTime = min(duration, max(0, viewModel.playbackPosition))
            default:
                currentTime = 0
            }
        }
    }

    private var fileInfo: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(viewModel.selectedFileURL != nil ? OpenEQTheme.accentCyan.opacity(0.15) : Color.white.opacity(0.05))
                    .frame(width: 28, height: 28)
                Image(systemName: viewModel.selectedFileURL != nil ? "waveform.circle.fill" : "music.note")
                    .font(.system(size: 14))
                    .foregroundStyle(viewModel.selectedFileURL != nil ? OpenEQTheme.accentCyan : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.selectedFileName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(viewModel.selectedFileURL != nil ? "Local Audio" : "No File Loaded")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minWidth: 110, maxWidth: 150, alignment: .leading)
    }

    private var transport: some View {
        HStack(spacing: 8) {
            // Open File
            Button {
                viewModel.openAudioFile()
            } label: {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(TactileButtonStyle())
            .help("Open Audio (⌘O)")
            .accessibilityLabel("Open audio file")

            // Stop
            Button {
                viewModel.stop()
                currentTime = 0
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(TactileButtonStyle())
            .disabled(viewModel.selectedFileURL == nil)
            .help("Stop")
            .accessibilityLabel("Stop")

            // Play / Pause (Master Button)
            Button {
                if viewModel.playbackState == .playing {
                    viewModel.pause()
                } else {
                    viewModel.play()
                }
            } label: {
                let isPlaying = viewModel.playbackState == .playing
                ZStack {
                    Circle()
                        .fill(
                            isPlaying
                                ? OpenEQTheme.accentCyan
                                : Color.white.opacity(0.12)
                        )
                        .frame(width: 32, height: 32)
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
                        }

                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isPlaying ? .black : .white)
                        .offset(x: isPlaying ? 0 : 1)
                }
            }
            .buttonStyle(TactileButtonStyle(pressedScale: 0.94))
            .disabled(viewModel.selectedFileURL == nil)
            .help(viewModel.playbackState == .playing ? "Pause" : "Play")
            .accessibilityLabel(viewModel.playbackState == .playing ? "Pause" : "Play")
        }
    }

    private func progress(duration: Double) -> some View {
        HStack(spacing: 10) {
            Text(formatTime(currentTime))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            Slider(
                value: Binding(
                    get: { currentTime },
                    set: {
                        isDraggingScrubber = true
                        currentTime = $0
                    }
                ),
                in: 0...duration,
                onEditingChanged: { editing in
                    isDraggingScrubber = editing
                    if !editing { viewModel.seek(to: currentTime) }
                }
            )
            .controlSize(.small)
            .disabled(viewModel.selectedFileURL == nil)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(formatTime(currentTime)) of \(formatTime(viewModel.playbackDuration))")

            Text(formatTime(viewModel.playbackDuration))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private var volume: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.isMuted.toggle()
            } label: {
                Image(systemName: volumeIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(viewModel.isMuted ? OpenEQTheme.accentRed : .primary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(TactileButtonStyle())
            .help(viewModel.isMuted ? "Unmute" : "Mute")
            .accessibilityLabel(viewModel.isMuted ? "Unmute" : "Mute")

            Slider(
                value: Binding(
                    get: { viewModel.isMuted ? 0 : viewModel.volume },
                    set: {
                        viewModel.volume = $0
                        if viewModel.isMuted { viewModel.isMuted = false }
                    }
                ),
                in: 0...(viewModel.isVolumeBoostEnabled ? 2 : 1)
            )
            .controlSize(.small)
            .frame(width: 78)
            .accessibilityLabel("Volume")
            .accessibilityValue("\(Int((viewModel.isMuted ? 0 : viewModel.volume) * 100)) percent")

            // Volume Boost Button
            Button {
                viewModel.toggleVolumeBoost()
            } label: {
                ZStack {
                    Circle()
                        .fill(viewModel.isVolumeBoostEnabled ? OpenEQTheme.accentGold : Color.white.opacity(0.06))
                        .frame(width: 22, height: 22)

                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(viewModel.isVolumeBoostEnabled ? .black : .secondary)
                }
            }
            .buttonStyle(TactileButtonStyle())
            .help(viewModel.isVolumeBoostEnabled ? "Overdrive Boost On (+6 dB)" : "Enable Overdrive Boost")
            .accessibilityLabel(viewModel.isVolumeBoostEnabled ? "Disable volume boost" : "Enable volume boost")
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(OpenEQTheme.accentRed)
            Text(message)
                .font(.caption)
                .foregroundStyle(OpenEQTheme.accentRed)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(OpenEQTheme.accentRed.opacity(0.14))
        }
        .overlay {
            Capsule()
                .stroke(OpenEQTheme.accentRed.opacity(0.4), lineWidth: 1)
        }
    }

    private var volumeIcon: String {
        if viewModel.isMuted || viewModel.volume == 0 { return "speaker.slash.fill" }
        if viewModel.volume < 0.33 { return "speaker.wave.1.fill" }
        if viewModel.volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func formatTime(_ seconds: Double) -> String {
        String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

#Preview {
    PlayerControlsView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .padding()
    .frame(width: 1000)
}

