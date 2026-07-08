import SwiftUI

struct SystemAudioView: View {
    let viewModel: OpenEQViewModel

    @State private var showInstructions = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("System Audio", systemImage: "speaker.wave.2.badge.gearshape")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { viewModel.isShowingSystemAudio = false }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.escape)
            }
            .padding(16)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    modePicker

                    instructionsSection

                    switch viewModel.systemAudioMode {
                    case .disabled:
                        disabledNotice
                    case .systemEQ:
                        systemEQSection
                    case .externalLoopback:
                        externalLoopbackSection
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 420, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { viewModel.refreshSystemAudioDevices() }
    }

    private var modePicker: some View {
        Picker("Mode", selection: Binding(
            get: { viewModel.systemAudioMode },
            set: { viewModel.setSystemAudioMode($0) }
        )) {
            ForEach(SystemAudioMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showInstructions.toggle() }
            } label: {
                HStack {
                    Text("How it works")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: showInstructions ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showInstructions {
                VStack(alignment: .leading, spacing: 4) {
                    Label("System EQ uses macOS Core Audio Tap — no drivers needed", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)

                    Label("Requires macOS 14.2+ and Screen/System Audio Recording permission", systemImage: "shield")
                        .font(.caption2)
                        .foregroundStyle(.orange)

                    if viewModel.systemAudioMode == .externalLoopback {
                        Label("External Loopback requires BlackHole 2ch virtual device installed", systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(6)
            }
        }
    }

    private var disabledNotice: some View {
        VStack(spacing: 8) {
            Image(systemName: "speaker.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("System-wide EQ is disabled")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("EQ applies to local audio files only")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(8)
    }

    private var systemEQSection: some View {
        VStack(spacing: 12) {
            statusPanel

            systemEQControls

            systemEQStatus
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var systemEQControls: some View {
        Button {
            if viewModel.systemAudioStatus == .running {
                viewModel.stopSystemEQMode()
            } else {
                viewModel.startSystemEQMode()
            }
        } label: {
            Label(
                viewModel.systemAudioStatus == .running ? "Stop" : "Start",
                systemImage: viewModel.systemAudioStatus == .running ? "stop.fill" : "play.fill"
            )
            .font(.caption)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    private var systemEQStatus: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Latency")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(systemAudioLatencyText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var systemAudioLatencyText: String {
        guard let latency = viewModel.systemAudioLatency else { return "-- ms" }
        return "\(Int(latency * 1000)) ms"
    }

    private var externalLoopbackSection: some View {
        VStack(spacing: 12) {
            groupBox("Devices") {
                VStack(spacing: 6) {
                    HStack {
                        Text(blackHoleStatus)
                            .font(.caption2)
                            .foregroundStyle(viewModel.detectedBlackHoleDevice == nil ? .orange : .green)
                        Spacer()
                        Button { viewModel.refreshSystemAudioDevices() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    devicePicker(
                        title: "Input",
                        selection: Binding(
                            get: { viewModel.selectedSystemInputDevice?.id },
                            set: { viewModel.selectSystemInputDevice(id: $0) }
                        ),
                        devices: viewModel.availableInputDevices
                    )

                    devicePicker(
                        title: "Output",
                        selection: Binding(
                            get: { viewModel.selectedSystemOutputDevice?.id },
                            set: { viewModel.selectSystemOutputDevice(id: $0) }
                        ),
                        devices: viewModel.availableOutputDevices
                    )
                }
            }

            groupBox("Controls") {
                VStack(spacing: 8) {
                    statusPanel

                    HStack(spacing: 8) {
                        Button {
                            if viewModel.isExternalLoopbackActive {
                                viewModel.stopExternalLoopbackMode()
                            } else {
                                viewModel.startExternalLoopbackMode()
                            }
                        } label: {
                            Label(viewModel.isExternalLoopbackActive ? "Stop" : "Start", systemImage: viewModel.isExternalLoopbackActive ? "stop.fill" : "play.fill")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            viewModel.setExternalLoopbackBypassed(!viewModel.isExternalLoopbackBypassed)
                        } label: {
                            Label(viewModel.isExternalLoopbackBypassed ? "Bypassed" : "Bypass", systemImage: "power")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(viewModel.isExternalLoopbackBypassed ? .orange : nil)
                    }

                    Button(role: .destructive) {
                        viewModel.stopExternalLoopbackMode()
                    } label: {
                        Label("Emergency Stop", systemImage: "exclamationmark.octagon.fill")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var statusPanel: some View {
        VStack(spacing: 4) {
            Label(viewModel.systemAudioStatus.title, systemImage: "smallcircle.filled.circle")
                .font(.caption2)
                .foregroundStyle(statusColor)

            HStack {
                Text("Latency")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(latencyText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(6)
    }

    private func groupBox(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(8)
    }

    private var blackHoleStatus: String {
        if let device = viewModel.detectedBlackHoleDevice {
            return "BlackHole: \(device.name)"
        }
        return "Install BlackHole for loopback"
    }

    private var latencyText: String {
        guard let latency = viewModel.externalLoopbackLatency else { return "-- ms" }
        return "\(Int(latency * 1000)) ms"
    }

    private var statusColor: Color {
        switch viewModel.systemAudioStatus {
        case .running: return .green
        case .ready: return .blue
        case .failed: return .red
        case .permissionRequired: return .orange
        case .unavailable, .stopped: return .secondary
        }
    }

    private func devicePicker(title: String, selection: Binding<AudioDevice.ID?>, devices: [AudioDevice]) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            Picker(title, selection: selection) {
                Text("None").tag(AudioDevice.ID?.none)
                ForEach(devices) { device in
                    Text(deviceLabel(device)).tag(Optional(device.id))
                }
            }
            .labelsHidden()
            .controlSize(.small)
        }
    }

    private func deviceLabel(_ device: AudioDevice) -> String {
        var label = device.name
        if device.isDefaultInput { label += " (Input)" }
        else if device.isDefaultOutput { label += " (Output)" }
        return label
    }
}

#Preview {
    SystemAudioView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .frame(width: 420, height: 520)
}
