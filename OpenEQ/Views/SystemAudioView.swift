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

                    safeModeSection
                }
                .padding(16)
            }
        }
        .frame(width: 420, height: 560)
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

                    Label("Requires macOS 14.2+ and Screen & System Audio Recording permission", systemImage: "shield")
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

            if viewModel.systemAudioStatus == .permissionRequired {
                permissionRecoveryPanel
            }

            systemEQControls

            systemEQStatus
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var permissionRecoveryPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "Screen & System Audio Recording permission is required.",
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)

            Text("Open System Settings, enable OpenEQ under Privacy & Security → Screen & System Audio Recording, then start again.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                viewModel.openSystemAudioPrivacySettings()
            } label: {
                Label("Open Privacy Settings", systemImage: "gear")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
    }

    private var systemEQControls: some View {
        HStack(spacing: 8) {
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

            Button {
                viewModel.setEnabled(!viewModel.isEnabled)
            } label: {
                Label(
                    viewModel.isEnabled ? "EQ On" : "Bypassed",
                    systemImage: viewModel.isEnabled ? "waveform" : "waveform.slash"
                )
                .font(.caption)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(viewModel.isEnabled ? nil : .orange)
            .disabled(viewModel.systemAudioStatus != .running)
        }
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

            if viewModel.systemAudioStatus == .running {
                Text(viewModel.isEnabled ? "EQ active on system audio" : "Passthrough (EQ bypassed)")
                    .font(.caption2)
                    .foregroundStyle(viewModel.isEnabled ? .green : .orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                            Label(
                                viewModel.isExternalLoopbackActive ? "Stop" : "Start",
                                systemImage: viewModel.isExternalLoopbackActive ? "stop.fill" : "play.fill"
                            )
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            viewModel.setEnabled(!viewModel.isEnabled)
                        } label: {
                            Label(
                                viewModel.isEnabled ? "EQ On" : "Bypassed",
                                systemImage: viewModel.isEnabled ? "waveform" : "waveform.slash"
                            )
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(viewModel.isEnabled ? nil : .orange)
                        .disabled(!viewModel.isExternalLoopbackActive)
                    }
                }
            }
        }
    }

    private var safeModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Safety")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                viewModel.enterSafeMode()
            } label: {
                Label("Emergency Stop / Safe Mode", systemImage: "exclamationmark.octagon.fill")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Immediately stop system processing and restore the original output device.")
        }
    }

    private var statusPanel: some View {
        VStack(spacing: 4) {
            Label(viewModel.systemAudioStatus.title, systemImage: statusIcon)
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
        if viewModel.systemAudioMode == .systemEQ {
            return systemAudioLatencyText
        }
        guard let latency = viewModel.externalLoopbackLatency else { return "-- ms" }
        return "\(Int(latency * 1000)) ms"
    }

    private var statusIcon: String {
        switch viewModel.systemAudioStatus {
        case .running: return "checkmark.circle.fill"
        case .ready: return "smallcircle.filled.circle"
        case .failed: return "xmark.octagon.fill"
        case .permissionRequired: return "lock.shield"
        case .unavailable, .stopped: return "pause.circle"
        }
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
    .frame(width: 420, height: 560)
}
