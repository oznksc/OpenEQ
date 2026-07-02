import SwiftUI
import Combine

struct PlayerControlsView: View {
    @Bindable var viewModel: OpenEQViewModel

    @State private var currentTime: Double = 0.0
    private let totalDuration: Double = 214.0
    @State private var rotationAngle: Double = 0.0

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            if let error = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)

                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)

                    Spacer()

                    Button(action: {
                        viewModel.errorMessage = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.12))
                .cornerRadius(6)
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }

            HStack(spacing: 24) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.05))
                            .frame(width: 44, height: 44)

                        Image(systemName: "music.note")
                            .font(.title2)
                            .foregroundStyle(viewModel.selectedFileURL != nil ? Color.accentColor : Color.secondary)
                            .rotationEffect(.degrees(rotationAngle))
                            .animation(.linear(duration: 0.1), value: rotationAngle)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.selectedFileName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(viewModel.selectedFileURL != nil ? "Local Audio File" : "No File Loaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: 140, alignment: .leading)
                }

                Divider()
                    .frame(height: 32)

                HStack(spacing: 8) {
                    Button(action: {
                        viewModel.openAudioFile()
                    }) {
                        Label("Open Audio", systemImage: "doc.badge.plus")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .help("Open Audio File...")

                    Button(action: {
                        viewModel.stop()
                        currentTime = 0.0
                        rotationAngle = 0.0
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.body)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.selectedFileURL == nil)
                    .help("Stop")

                    Button(action: {
                        viewModel.play()
                    }) {
                        Image(systemName: "play.fill")
                            .font(.body.weight(.bold))
                            .frame(width: 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedFileURL == nil)
                    .help("Play")

                    Button(action: {
                        viewModel.pause()
                    }) {
                        Image(systemName: "pause.fill")
                            .font(.body.weight(.bold))
                            .frame(width: 12)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.selectedFileURL == nil)
                    .help("Pause")
                }

                HStack(spacing: 10) {
                    Text(formatTime(currentTime))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38)

                    Slider(
                        value: Binding(
                            get: { currentTime },
                            set: { currentTime = $0 }
                        ),
                        in: 0...totalDuration
                    )
                    .disabled(viewModel.selectedFileURL == nil)
                    .frame(maxWidth: .infinity)

                    Text(formatTime(totalDuration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38)
                }

                Divider()
                    .frame(height: 32)

                HStack(spacing: 10) {
                    Button(action: {
                        viewModel.isMuted.toggle()
                    }) {
                        Image(systemName: volumeIcon)
                            .font(.body)
                            .foregroundStyle(viewModel.isMuted ? .red : .secondary)
                            .frame(width: 18)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.isMuted ? "Unmute" : "Mute")

                    Slider(
                        value: Binding(
                            get: { viewModel.isMuted ? 0.0 : viewModel.volume },
                            set: {
                                viewModel.volume = $0
                                if viewModel.isMuted {
                                    viewModel.isMuted = false
                                }
                            }
                        ),
                        in: 0...(viewModel.isVolumeBoostEnabled ? 2.0 : 1.0)
                    )
                    .frame(width: 110)

                    Text("\(Int((viewModel.isMuted ? 0.0 : viewModel.volume) * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)

                    Button(action: {
                        viewModel.toggleVolumeBoost()
                    }) {
                        Image(systemName: viewModel.isVolumeBoostEnabled ? "bolt.fill" : "bolt")
                            .foregroundStyle(viewModel.isVolumeBoostEnabled ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.isVolumeBoostEnabled ? "Volume Boost ON (200%)" : "Volume Boost OFF")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
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
        if viewModel.isMuted || viewModel.volume == 0 {
            return "speaker.slash.fill"
        } else if viewModel.volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if viewModel.volume < 0.67 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
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
