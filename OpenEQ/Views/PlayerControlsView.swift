import SwiftUI
import Combine

/// One glass surface, plain controls inside — no glass-on-glass nesting.
struct PlayerControlsView: View {
    @Bindable var viewModel: OpenEQViewModel

    @State private var currentTime: Double = 0.0
    // 8 Hz is enough for transport UI; lower main-thread wakeups.
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if #available(macOS 26.0, *) {
                controlRow.glassEffect(
                    .regular.interactive(),
                    in: Capsule()
                )
            } else {
                controlRow.background(
                    .thinMaterial,
                    in: Capsule()
                )
            }
        }
        .onReceive(timer) { _ in
            switch viewModel.playbackState {
            case .playing, .paused, .stopped:
                currentTime = min(duration, max(0, viewModel.playbackPosition))
            default:
                currentTime = 0
            }
        }
    }

    private var fileInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.selectedFileName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text(viewModel.selectedFileURL != nil ? "Local file" : "No file")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 96, maxWidth: 140, alignment: .leading)
    }

    private var transport: some View {
        HStack(spacing: 14) {
            Button {
                viewModel.openAudioFile()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Open Audio (⌘O)")
            .accessibilityLabel("Open audio file")

            Button {
                viewModel.stop()
                currentTime = 0
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.selectedFileURL == nil)
            .help("Stop")
            .accessibilityLabel("Stop")

            Button {
                if viewModel.playbackState == .playing {
                    viewModel.pause()
                } else {
                    viewModel.play()
                }
            } label: {
                Image(systemName: viewModel.playbackState == .playing ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.selectedFileURL == nil)
            .help(viewModel.playbackState == .playing ? "Pause" : "Play")
            .accessibilityLabel(viewModel.playbackState == .playing ? "Pause" : "Play")
        }
        .imageScale(.medium)
        .font(.body.weight(.semibold))
        .foregroundStyle(.primary)
    }

    private func progress(duration: Double) -> some View {
        HStack(spacing: 10) {
            Text(formatTime(currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)

            Slider(
                value: Binding(get: { currentTime }, set: { currentTime = $0 }),
                in: 0...duration,
                onEditingChanged: { editing in
                    if !editing { viewModel.seek(to: currentTime) }
                }
            )
            .controlSize(.small)
            .disabled(viewModel.selectedFileURL == nil)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(formatTime(currentTime)) of \(formatTime(viewModel.playbackDuration))")

            Text(formatTime(viewModel.playbackDuration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .imageScale(.large)
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity)
    }

    private var volume: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.isMuted.toggle()
            } label: {
                Image(systemName: volumeIcon)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(viewModel.isMuted ? .red : .primary)
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
            .frame(width: 88)
            .accessibilityLabel("Volume")
            .accessibilityValue("\(Int((viewModel.isMuted ? 0 : viewModel.volume) * 100)) percent")

            Button {
                viewModel.toggleVolumeBoost()
            } label: {
                Image(systemName: viewModel.isVolumeBoostEnabled ? "bolt.fill" : "bolt")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(viewModel.isVolumeBoostEnabled ? .yellow : .secondary)
            .help(viewModel.isVolumeBoostEnabled ? "Boost on" : "Volume boost")
            .accessibilityLabel(viewModel.isVolumeBoostEnabled ? "Disable volume boost" : "Enable volume boost")
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
