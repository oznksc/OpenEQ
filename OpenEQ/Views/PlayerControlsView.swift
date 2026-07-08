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

            HStack(spacing: 20) {
                // File Info Block
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(viewModel.selectedFileURL != nil ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                            .frame(width: 28, height: 28)

                        Image(systemName: "music.note")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(viewModel.selectedFileURL != nil ? Color.accentColor : Color.secondary)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(viewModel.selectedFileName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(viewModel.selectedFileURL != nil ? "Local Audio File" : "No File Loaded")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 130, alignment: .leading)
                }

                // Playback Control Buttons
                HStack(spacing: 12) {
                    Button(action: { viewModel.openAudioFile() }) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Open Audio File")

                    Button(action: {
                        viewModel.stop()
                        currentTime = 0.0
                        rotationAngle = 0.0
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(viewModel.selectedFileURL == nil ? Color.secondary.opacity(0.3) : .primary)
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.selectedFileURL == nil)
                    .help("Stop Playback")

                    if viewModel.playbackState == .playing {
                        Button(action: { viewModel.pause() }) {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                                .shadow(color: Color.accentColor.opacity(0.3), radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.selectedFileURL == nil)
                        .help("Pause")
                    } else {
                        Button(action: { viewModel.play() }) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(viewModel.selectedFileURL == nil ? Color.secondary.opacity(0.4) : Color.accentColor)
                                .clipShape(Circle())
                                .shadow(color: viewModel.selectedFileURL == nil ? Color.clear : Color.accentColor.opacity(0.3), radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.selectedFileURL == nil)
                        .help("Play")
                    }
                }

                // Progress Bar / Seek Slider
                HStack(spacing: 8) {
                    Text(formatTime(currentTime))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .leading)

                    Slider(value: Binding(get: { currentTime }, set: { currentTime = $0 }), in: 0...totalDuration)
                        .disabled(viewModel.selectedFileURL == nil)
                        .controlSize(.small)

                    Text(formatTime(totalDuration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }

                Divider()
                    .frame(height: 20)
                    .opacity(0.5)

                // Volume Controls Block
                HStack(spacing: 8) {
                    Button(action: { viewModel.isMuted.toggle() }) {
                        Image(systemName: volumeIcon)
                            .font(.system(size: 11))
                            .foregroundStyle(viewModel.isMuted ? .red : .secondary)
                            .frame(width: 16)
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
                    .frame(width: 70)

                    Text("\(Int((viewModel.isMuted ? 0.0 : viewModel.volume) * 100))%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)

                    Button(action: { viewModel.toggleVolumeBoost() }) {
                        Image(systemName: viewModel.isVolumeBoostEnabled ? "bolt.fill" : "bolt")
                            .font(.system(size: 11))
                            .foregroundStyle(viewModel.isVolumeBoostEnabled ? .yellow : .secondary)
                            .frame(width: 14, height: 14)
                            .background(viewModel.isVolumeBoostEnabled ? Color.yellow.opacity(0.12) : Color.clear)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.isVolumeBoostEnabled ? "Volume Boost Active (200%)" : "Enable Volume Boost")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
