import SwiftUI

struct SystemAudioView: View {
    let viewModel: OpenEQViewModel

    @State private var showAdvanced = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    if viewModel.showSystemEQOnboarding {
                        onboardingCard
                    }

                    oneClickCard

                    if viewModel.didTripFeedbackProtection {
                        safetyTripBanner
                    }

                    if let banner = viewModel.safetyBannerMessage, !viewModel.didTripFeedbackProtection {
                        infoBanner(banner)
                    }

                    deviceProfileCard

                    advancedSection
                    safeModeSection
                }
                .padding(16)
            }
        }
        .frame(width: 440, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { viewModel.refreshSystemAudioDevices() }
    }

    private var header: some View {
        HStack {
            Label("System Audio", systemImage: "speaker.wave.2.circle")
                .font(.title3.weight(.semibold))
            Spacer()
            Button("Done") { viewModel.isShowingSystemAudio = false }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.escape)
        }
        .padding(16)
    }

    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enable System EQ in one click")
                .font(.headline)
            Text("OpenEQ uses a macOS process tap — no BlackHole or virtual driver install required. You will be asked for Screen & System Audio Recording permission.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    viewModel.enableSystemEQOneClick()
                } label: {
                    Label("Start System EQ", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Not now") {
                    viewModel.dismissSystemEQOnboarding()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(10)
    }

    private var oneClickCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("System-Wide EQ")
                        .font(.subheadline.weight(.semibold))
                    Text(statusSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusDot
            }

            Button {
                viewModel.toggleSystemEQOneClick()
            } label: {
                Label(
                    viewModel.isSystemEQActive ? "Stop System EQ" : "Start System EQ",
                    systemImage: viewModel.isSystemEQActive ? "stop.fill" : "play.fill"
                )
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isSystemEQActive ? .red : .accentColor)
            .controlSize(.large)

            if viewModel.systemAudioStatus == .permissionRequired {
                permissionRecoveryPanel
            }

            if !viewModel.conflictingHALPlugins.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        "Conflicting audio drivers detected",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    Text(viewModel.conflictingHALPlugins.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Boom / DeskFx HAL plugins often break process taps (empty spectrum, no sound). Quit or uninstall them, then restart OpenEQ.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }

            HStack {
                Label("Latency", systemImage: "timer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(latencyText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if viewModel.isSystemEQActive {
                HStack {
                    Label(
                        viewModel.isReceivingTapAudio ? "Tap signal: yes" : "Tap signal: waiting…",
                        systemImage: viewModel.isReceivingTapAudio ? "waveform" : "waveform.slash"
                    )
                    .font(.caption2)
                    .foregroundStyle(viewModel.isReceivingTapAudio ? .green : .orange)
                    Spacer()
                }
            }

            if let detail = viewModel.systemEQSetupDetail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let device = viewModel.activePhysicalOutputName {
                HStack {
                    Label("Output", systemImage: "hifispeaker")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(device)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Toggle(isOn: Binding(
                get: { viewModel.isEnabled },
                set: { viewModel.setEnabled($0) }
            )) {
                Text("EQ Enabled")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!viewModel.isSystemEQActive)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }

    private var safetyTripBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Feedback protection activated", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Sustained near-clip energy was detected. Output was muted to protect your hearing. Fix routing, then resume.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                viewModel.clearFeedbackProtectionTrip()
            } label: {
                Label("Resume after check", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
    }

    private func infoBanner(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
    }

    private var deviceProfileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Device profile")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Toggle(isOn: Binding(
                get: { viewModel.autoApplyDeviceProfiles },
                set: { viewModel.setAutoApplyDeviceProfiles($0) }
            )) {
                Text("Auto-load EQ when this output connects")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            HStack(spacing: 8) {
                Button {
                    viewModel.rememberPresetForCurrentDevice()
                } label: {
                    Label("Remember “\(viewModel.selectedPreset.name)”", systemImage: "bookmark")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.activePhysicalOutputUID == nil && !viewModel.isSystemEQActive)

                Button(role: .destructive) {
                    viewModel.clearProfileForCurrentDevice()
                } label: {
                    Image(systemName: "bookmark.slash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.activePhysicalOutputUID == nil)
            }

            if !viewModel.deviceProfiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.deviceProfiles.prefix(5)) { profile in
                        HStack {
                            Text(profile.deviceName)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                            Text(profile.presetName ?? "—")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
            } label: {
                HStack {
                    Text("Advanced")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showAdvanced {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { viewModel.preferSystemEQOnLaunch },
                        set: { viewModel.setPreferSystemEQOnLaunch($0) }
                    )) {
                        Text("Start System EQ when OpenEQ launches")
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Toggle(isOn: Binding(
                        get: { viewModel.feedbackProtectionEnabled },
                        set: { viewModel.setFeedbackProtectionEnabled($0) }
                    )) {
                        Text("Feedback / howling protection")
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Picker("Mode", selection: Binding(
                        get: { viewModel.systemAudioMode },
                        set: { viewModel.setSystemAudioMode($0) }
                    )) {
                        ForEach(SystemAudioMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(viewModel.systemAudioMode.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if viewModel.systemAudioMode == .externalLoopback {
                        externalLoopbackSection
                    }

                    Label("Driverless path uses Core Audio process taps (macOS 14.2+). A bundled virtual driver is not required for System-Wide EQ.", systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)
            }
        }
    }

    private var externalLoopbackSection: some View {
        VStack(spacing: 8) {
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

            HStack(spacing: 8) {
                Button {
                    if viewModel.isExternalLoopbackActive {
                        viewModel.stopExternalLoopbackMode()
                    } else {
                        viewModel.startExternalLoopbackMode()
                    }
                } label: {
                    Label(
                        viewModel.isExternalLoopbackActive ? "Stop Loopback" : "Start Loopback",
                        systemImage: viewModel.isExternalLoopbackActive ? "stop.fill" : "play.fill"
                    )
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
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

    private var safeModeSection: some View {
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

    private var statusSubtitle: String {
        if viewModel.isSystemEQActive {
            return viewModel.isEnabled ? "Processing all system audio" : "Running · EQ bypassed"
        }
        switch viewModel.systemAudioStatus {
        case .permissionRequired:
            return "Permission required"
        case .failed(let message):
            return message
        case .ready:
            return "Ready — no drivers needed"
        default:
            return "Driverless Core Audio tap"
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
            .help(viewModel.systemAudioStatus.title)
    }

    private var statusColor: Color {
        if viewModel.didTripFeedbackProtection { return .orange }
        switch viewModel.systemAudioStatus {
        case .running: return .green
        case .ready: return .blue
        case .failed: return .red
        case .permissionRequired: return .orange
        case .unavailable, .stopped: return .secondary
        }
    }

    private var latencyText: String {
        if viewModel.systemAudioMode == .externalLoopback {
            guard let latency = viewModel.externalLoopbackLatency else { return "-- ms" }
            return "\(Int(latency * 1000)) ms"
        }
        guard let latency = viewModel.systemAudioLatency else { return "-- ms" }
        return "\(Int(latency * 1000)) ms"
    }

    private var blackHoleStatus: String {
        if let device = viewModel.detectedBlackHoleDevice {
            return "BlackHole: \(device.name)"
        }
        return "Install BlackHole for loopback"
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
                    Text(device.name).tag(Optional(device.id))
                }
            }
            .labelsHidden()
            .controlSize(.small)
        }
    }
}

#Preview {
    SystemAudioView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .frame(width: 440, height: 600)
}
