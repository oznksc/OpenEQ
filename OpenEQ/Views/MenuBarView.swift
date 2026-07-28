import SwiftUI

struct MenuBarView: View {
    @Bindable var viewModel: OpenEQViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "slider.vertical.3")
                    .foregroundStyle(.blue)
                Text("OpenEQ")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(systemStatusColor)
                    .frame(width: 7, height: 7)
                    .help(systemStatusHelp)
            }
            .padding(.bottom, 4)

            Divider()

            Toggle(isOn: toggleBinding) {
                Label(
                    viewModel.isEnabled ? "EQ Enabled" : "EQ Bypassed",
                    systemImage: viewModel.isEnabled ? "power" : "waveform.slash"
                )
            }

            HStack {
                Image(systemName: viewModel.isMuted ? "speaker.slash" : "speaker.wave.2")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Slider(
                    value: Binding(
                        get: { viewModel.volume },
                        set: { viewModel.volume = $0 }
                    ),
                    in: 0...1.5
                )
                Text("\(Int(viewModel.volume * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }

            Divider()

            if viewModel.selectedFileURL != nil {
                Label(viewModel.selectedFileName, systemImage: "music.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Button("Play") { viewModel.play() }
                        .disabled(viewModel.playbackState == .playing)
                    Button("Pause") { viewModel.pause() }
                        .disabled(viewModel.playbackState != .playing)
                    Button("Stop") {
                        viewModel.stop()
                    }
                    .disabled(viewModel.selectedFileURL == nil)
                }
                .buttonStyle(.bordered)

                Divider()
            }

            Text("Preset: \(viewModel.selectedPreset.name)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !viewModel.recentPresets.isEmpty {
                ForEach(viewModel.recentPresets.prefix(3)) { preset in
                    Button {
                        viewModel.applyPreset(preset)
                    } label: {
                        HStack {
                            Text(preset.name)
                            Spacer()
                            if preset.id == viewModel.selectedPreset.id {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                            }
                        }
                    }
                }

                Divider()
            }

            if viewModel.isSystemEQActive || viewModel.isExternalLoopbackActive {
                Label(
                    viewModel.isSystemEQActive ? "System EQ Running" : "Loopback Running",
                    systemImage: "waveform.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.green)

                if let latency = viewModel.isSystemEQActive
                    ? viewModel.systemAudioLatency
                    : viewModel.externalLoopbackLatency {
                    Text(String(format: "Latency ~%.0f ms", latency * 1000))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button("Emergency Stop") {
                    viewModel.enterSafeMode()
                }
                .foregroundStyle(.red)

                Divider()
            }

            Button("System Audio…") {
                viewModel.isShowingSystemAudio = true
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

            Button("Show OpenEQ") {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("o")

            Divider()

            Button("Quit") {
                viewModel.shutdown()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(8)
        .frame(width: 240)
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isEnabled },
            set: { viewModel.setEnabled($0) }
        )
    }

    private var systemStatusColor: Color {
        if viewModel.isSystemEQActive || viewModel.isExternalLoopbackActive {
            return viewModel.isEnabled ? .green : .orange
        }
        if case .failed = viewModel.systemAudioStatus {
            return .red
        }
        if viewModel.systemAudioStatus == .permissionRequired {
            return .orange
        }
        return .secondary
    }

    private var systemStatusHelp: String {
        if viewModel.isSystemEQActive {
            return viewModel.isEnabled ? "System EQ active" : "System EQ bypassed"
        }
        if viewModel.isExternalLoopbackActive {
            return "External loopback active"
        }
        return "Local EQ only"
    }
}
