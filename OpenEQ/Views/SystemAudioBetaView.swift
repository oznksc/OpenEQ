//
//  SystemAudioBetaView.swift
//  OpenEQ
//
//  Created by Codex on 27.06.2026.
//

import SwiftUI

struct SystemAudioBetaView: View {
    let viewModel: OpenEQViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            routingInstructions
            deviceControls
            statusPanel
            actionControls
            privacyNote
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            viewModel.refreshSystemAudioDevices()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("System Audio", systemImage: "waveform.badge.magnifyingglass")
                .font(.headline)

            Text("BETA")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            Spacer()
        }
    }

    private var routingInstructions: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("External Loopback Setup")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            instruction("1", "Install BlackHole manually")
            instruction("2", "Open macOS System Settings > Sound")
            instruction("3", "Set Output to BlackHole")
            instruction("4", "Select BlackHole as Input")
            instruction("5", "Select speakers/headphones as Output")
            instruction("6", "Start External Loopback Mode")
        }
    }

    private func instruction(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text(number)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Color.secondary.opacity(0.55))
                .clipShape(Circle())

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var deviceControls: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                .help("Refresh audio devices")
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

    private func devicePicker(
        title: String,
        selection: Binding<AudioDevice.ID?>,
        devices: [AudioDevice]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker(title, selection: selection) {
                Text("None").tag(AudioDevice.ID?.none)

                ForEach(devices) { device in
                    Text(deviceLabel(device)).tag(Optional(device.id))
                }
            }
            .labelsHidden()
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(viewModel.systemAudioStatus.title, systemImage: "smallcircle.filled.circle")
                .font(.caption)
                .foregroundStyle(statusColor)

            Label("Feedback risk: keep input and output on different devices.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)

            Label("Latency is expected in beta loopback mode.", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Latency")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(latencyText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ClippingIndicatorView(isClipping: viewModel.isClipping)
        }
    }

    private var actionControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    if viewModel.isExternalLoopbackActive {
                        viewModel.stopExternalLoopbackMode()
                    } else {
                        viewModel.startExternalLoopbackMode()
                    }
                } label: {
                    Label(viewModel.isExternalLoopbackActive ? "Stop" : "Start", systemImage: viewModel.isExternalLoopbackActive ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.setExternalLoopbackBypassed(!viewModel.isExternalLoopbackBypassed)
                } label: {
                    Label(viewModel.isExternalLoopbackBypassed ? "Bypassed" : "Bypass", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button(role: .destructive) {
                viewModel.stopExternalLoopbackMode()
            } label: {
                Label("Emergency Stop", systemImage: "exclamationmark.octagon.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var privacyNote: some View {
        Text("Audio is processed locally on your Mac. OpenEQ does not record, upload or store system audio.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var blackHoleStatus: String {
        if let device = viewModel.detectedBlackHoleDevice {
            return "Detected: \(device.name)"
        }

        return "Install a virtual audio loopback device such as BlackHole, then set macOS Sound Output to it."
    }

    private var latencyText: String {
        guard let latency = viewModel.externalLoopbackLatency else {
            return "-- ms"
        }

        return "\(Int(latency * 1000)) ms"
    }

    private var statusColor: Color {
        switch viewModel.systemAudioStatus {
        case .running:
            return .green
        case .ready:
            return .blue
        case .failed:
            return .red
        case .permissionRequired:
            return .orange
        case .unavailable, .stopped:
            return .secondary
        }
    }

    private func deviceLabel(_ device: AudioDevice) -> String {
        var label = device.name

        if device.isDefaultInput {
            label += " - Default Input"
        } else if device.isDefaultOutput {
            label += " - Default Output"
        }

        return label
    }
}

#Preview {
    SystemAudioBetaView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .frame(width: 340)
}
