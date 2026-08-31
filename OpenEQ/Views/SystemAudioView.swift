import SwiftUI

struct SystemAudioView: View {
    let viewModel: OpenEQViewModel

    var body: some View {
        NavigationStack {
            Form {
                if viewModel.showSystemEQOnboarding {
                    Section {
                        onboardingContent
                    }
                }

                Section {
                    oneClickContent
                } header: {
                    Text("System-Wide EQ")
                } footer: {
                    Text("Uses a Core Audio process tap (macOS 14.2+). No BlackHole or virtual driver required.")
                }

                if viewModel.didTripFeedbackProtection {
                    Section {
                        safetyTripContent
                    }
                }

                if let banner = viewModel.safetyBannerMessage, !viewModel.didTripFeedbackProtection {
                    Section {
                        Text(banner)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    deviceProfileContent
                } header: {
                    Text("Device Profile")
                }

                Section {
                    advancedContent
                } header: {
                    Text("Advanced")
                }

                Section {
                    Button(role: .destructive) {
                        viewModel.enterSafeMode()
                    } label: {
                        Label("Emergency Stop / Safe Mode", systemImage: "exclamationmark.octagon.fill")
                    }
                    .help("Immediately stop system processing and restore the original output device.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(OpenEQTheme.chassisBg)
            .navigationTitle("System Audio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        viewModel.isShowingSystemAudio = false
                    }
                    .keyboardShortcut(.escape)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        viewModel.toggleSystemEQOneClick()
                    } label: {
                        Label(
                            viewModel.isSystemEQActive ? "Stop" : "Start",
                            systemImage: viewModel.isSystemEQActive ? "stop.fill" : "play.fill"
                        )
                    }
                    .tint(viewModel.isSystemEQActive ? .red : .accentColor)
                }
            }
            .onAppear { viewModel.refreshSystemAudioDevices() }
        }
        .frame(minWidth: 440, idealWidth: 480, minHeight: 560, idealHeight: 640)
    }

    // MARK: - Onboarding

    private var onboardingContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enable System EQ in one click")
                .font(.headline)
            Text("OpenEQ will request Screen & System Audio Recording permission, then process all system audio.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    viewModel.enableSystemEQOneClick()
                } label: {
                    Label("Start System EQ", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)

                Button("Not now") {
                    viewModel.dismissSystemEQOnboarding()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - One click

    private var oneClickContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Driverless Core Audio Process Tap")
                        .font(.system(size: 13, weight: .bold))
                    Text(statusSubtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                OpenEQStatusDot(kind: statusKind, size: 10)
            }

            Button {
                viewModel.toggleSystemEQOneClick()
            } label: {
                Label(
                    viewModel.isSystemEQActive ? "Stop System EQ" : "Start System EQ",
                    systemImage: viewModel.isSystemEQActive ? "stop.fill" : "bolt.fill"
                )
                .font(.system(size: 13, weight: .bold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isSystemEQActive ? OpenEQTheme.accentRed : OpenEQTheme.accentCyan)
            .controlSize(.large)

            if viewModel.systemAudioStatus == .permissionRequired {
                permissionRecoveryContent
            }

            if case .failed(let message) = viewModel.systemAudioStatus {
                failureContent(message)
            }

            if !viewModel.conflictingHALPlugins.isEmpty {
                conflictContent
            }

            LabeledContent("Latency", value: latencyText)

            if viewModel.isSystemEQActive {
                HStack(spacing: 6) {
                    StudioLED(
                        isOn: viewModel.isReceivingTapAudio,
                        activeColor: OpenEQTheme.accentGreen,
                        inactiveColor: OpenEQTheme.accentAmber,
                        size: 7
                    )
                    Text(viewModel.isReceivingTapAudio ? "Core Audio Tap Signal: Active" : "Core Audio Tap Signal: Waiting for audio…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(viewModel.isReceivingTapAudio ? OpenEQTheme.accentGreen : OpenEQTheme.accentAmber)
                }
            }

            if let detail = viewModel.systemEQSetupDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let device = viewModel.activePhysicalOutputName {
                LabeledContent("Physical Output", value: device)
            }

            Toggle(isOn: Binding(
                get: { viewModel.isEnabled },
                set: { viewModel.setEnabled($0) }
            )) {
                Text("EQ Enabled")
            }
            .disabled(!viewModel.isSystemEQActive)
        }
        .padding(.vertical, 4)
    }

    private var safetyTripContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Feedback protection activated", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Sustained near-clip energy was detected. Output was muted. Fix routing, then resume.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                viewModel.clearFeedbackProtectionTrip()
            } label: {
                Label("Resume after check", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }

    private var deviceProfileContent: some View {
        Group {
            Toggle(isOn: Binding(
                get: { viewModel.autoApplyDeviceProfiles },
                set: { viewModel.setAutoApplyDeviceProfiles($0) }
            )) {
                Text("Auto-load EQ when this output connects")
            }

            Button {
                viewModel.rememberPresetForCurrentDevice()
            } label: {
                Label("Remember “\(viewModel.selectedPreset.name)”", systemImage: "bookmark")
            }
            .disabled(viewModel.activePhysicalOutputUID == nil && !viewModel.isSystemEQActive)

            Button(role: .destructive) {
                viewModel.clearProfileForCurrentDevice()
            } label: {
                Label("Clear profile for this device", systemImage: "bookmark.slash")
            }
            .disabled(viewModel.activePhysicalOutputUID == nil)

            if !viewModel.deviceProfiles.isEmpty {
                ForEach(viewModel.deviceProfiles.prefix(5)) { profile in
                    LabeledContent(profile.deviceName, value: profile.presetName ?? "—")
                }
            }
        }
    }

    private var advancedContent: some View {
        Group {
            Toggle(isOn: Binding(
                get: { viewModel.preferSystemEQOnLaunch },
                set: { viewModel.setPreferSystemEQOnLaunch($0) }
            )) {
                Text("Start System EQ when OpenEQ launches")
            }

            Toggle(isOn: Binding(
                get: { viewModel.feedbackProtectionEnabled },
                set: { viewModel.setFeedbackProtectionEnabled($0) }
            )) {
                Text("Feedback / howling protection")
            }

            Picker("Mode", selection: Binding(
                get: { viewModel.systemAudioMode },
                set: { viewModel.setSystemAudioMode($0) }
            )) {
                ForEach(SystemAudioMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Text(viewModel.systemAudioMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.systemAudioMode == .externalLoopback {
                externalLoopbackContent
            }
        }
    }

    private var externalLoopbackContent: some View {
        Group {
            HStack {
                Text(blackHoleStatus)
                    .font(.caption)
                    .foregroundStyle(viewModel.detectedBlackHoleDevice == nil ? .orange : .green)
                Spacer()
                Button {
                    viewModel.refreshSystemAudioDevices()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Picker("Input", selection: Binding(
                get: { viewModel.selectedSystemInputDevice?.id },
                set: { viewModel.selectSystemInputDevice(id: $0) }
            )) {
                Text("None").tag(AudioDevice.ID?.none)
                ForEach(viewModel.availableInputDevices) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }

            Picker("Output", selection: Binding(
                get: { viewModel.selectedSystemOutputDevice?.id },
                set: { viewModel.selectSystemOutputDevice(id: $0) }
            )) {
                Text("None").tag(AudioDevice.ID?.none)
                ForEach(viewModel.availableOutputDevices) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }

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
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var permissionRecoveryContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "Screen & System Audio Recording may be off for this build.",
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)

            Text("In System Settings → Privacy & Security → Screen & System Audio Recording, enable every OpenEQ checkbox.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    viewModel.openSystemAudioPrivacySettings()
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.retrySystemEQAfterPermission()
                } label: {
                    Label("Retry Start", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }

    private func failureContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("System EQ failed", systemImage: "xmark.octagon.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                viewModel.startSystemEQMode()
            } label: {
                Label("Retry Start", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }

    private var conflictContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Conflicting audio drivers detected", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text(viewModel.conflictingHALPlugins.joined(separator: ", "))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Boom / DeskFx HAL plugins often break process taps. Quit or uninstall them, then restart OpenEQ.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Status helpers

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

    private var statusKind: OpenEQStatusDot.Kind {
        if viewModel.didTripFeedbackProtection { return .warning }
        switch viewModel.systemAudioStatus {
        case .running: return .active
        case .ready: return .ready
        case .failed: return .error
        case .permissionRequired: return .warning
        case .unavailable, .stopped: return .idle
        }
    }

    private var latencyText: String {
        if viewModel.systemAudioMode == .externalLoopback {
            guard let latency = viewModel.externalLoopbackLatency else { return "—" }
            return "\(Int(latency * 1000)) ms"
        }
        guard let latency = viewModel.systemAudioLatency else { return "—" }
        return "\(Int(latency * 1000)) ms"
    }

    private var blackHoleStatus: String {
        if let device = viewModel.detectedBlackHoleDevice {
            return "BlackHole: \(device.name)"
        }
        return "Install BlackHole for loopback"
    }
}

#Preview {
    SystemAudioView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
}
