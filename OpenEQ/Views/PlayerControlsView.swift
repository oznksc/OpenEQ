import SwiftUI
import Combine

struct PlayerControlsView: View {
    @Bindable var viewModel: OpenEQViewModel

    @State private var currentTime: Double = 0.0
    private let totalDuration: Double = 214.0
    @State private var rotationAngle: Double = 0.0
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button(action: { viewModel.errorMessage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.1))
            }

            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.caption)
                        .foregroundStyle(viewModel.selectedFileURL != nil ? Color.accentColor : Color.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)

                    Text(viewModel.selectedFileName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(width: 120, alignment: .leading)
                }

                HStack(spacing: 4) {
                    Button(action: { viewModel.openAudioFile() }) {
                        Image(systemName: "doc.badge.plus")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: {
                        viewModel.stop()
                        currentTime = 0.0
                        rotationAngle = 0.0
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.selectedFileURL == nil)

                    Button(action: { viewModel.play() }) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .frame(width: 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(viewModel.selectedFileURL == nil)

                    Button(action: { viewModel.pause() }) {
                        Image(systemName: "pause.fill")
                            .font(.caption)
                            .frame(width: 8)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.selectedFileURL == nil)
                }

                HStack(spacing: 6) {
                    Text(formatTime(currentTime))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 32)

                    Slider(value: Binding(get: { currentTime }, set: { currentTime = $0 }), in: 0...totalDuration)
                        .disabled(viewModel.selectedFileURL == nil)
                        .controlSize(.small)

                    Text(formatTime(totalDuration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 32)
                }

                Divider()
                    .frame(height: 24)

                HStack(spacing: 6) {
                    Button(action: { viewModel.isMuted.toggle() }) {
                        Image(systemName: volumeIcon)
                            .font(.caption)
                            .foregroundStyle(viewModel.isMuted ? .red : .secondary)
                            .frame(width: 14)
                    }
                    .buttonStyle(.plain)

                    Slider(
                        value: Binding(
                            get: { viewModel.isMuted ? 0.0 : viewModel.volume },
                            set: { viewModel.volume = $0; if viewModel.isMuted { viewModel.isMuted = false } }
                        ),
                        in: 0...(viewModel.isVolumeBoostEnabled ? 2.0 : 1.0)
                    )
                    .controlSize(.small)
                    .frame(width: 80)

                    Text("\(Int((viewModel.isMuted ? 0.0 : viewModel.volume) * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)

                    Button(action: { viewModel.toggleVolumeBoost() }) {
                        Image(systemName: viewModel.isVolumeBoostEnabled ? "bolt.fill" : "bolt")
                            .font(.caption)
                            .foregroundStyle(viewModel.isVolumeBoostEnabled ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.isVolumeBoostEnabled ? "200% Boost ON" : "Volume Boost OFF")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onReceive(timer) { _ in
            if viewModel.playbackState == .playing {
                currentTime = (currentTime + 0.1).truncatingRemainder(dividingBy: totalDuration)
                rotationAngle = (rotationAngle + 4.5).truncatingRemainder(dividingBy: 360)
            }
        }
    }

    private var volumeIcon: String {
        if viewModel.isMuted || viewModel.volume == 0 { return "speaker.slash.fill" }
        else if viewModel.volume < 0.33 { return "speaker.wave.1.fill" }
        else if viewModel.volume < 0.67 { return "speaker.wave.2.fill" }
        else { return "speaker.wave.3.fill" }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

#Preview {
    PlayerControlsView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .frame(width: 1080)
}
