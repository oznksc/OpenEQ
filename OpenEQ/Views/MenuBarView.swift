import SwiftUI
import AppKit

struct MenuBarView: View {
    @Bindable var viewModel: OpenEQViewModel
    @Environment(\.openWindow) private var openWindow

    private var builtInPresets: [EQPreset] {
        let builtInIDs = Set(EQPreset.defaultPresets().map(\.id))
        return viewModel.presets.filter { builtInIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            presets
            Divider()
            footer
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: viewModel.isSystemEQActive ? "waveform.circle.fill" : "waveform.circle")
                .font(.system(size: 24))
                .foregroundStyle(viewModel.isSystemEQActive ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("OpenEQ").font(.headline)
                Text(statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Circle()
                .fill(viewModel.isSystemEQActive ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
        }
        .padding(14)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                compactButton(
                    viewModel.isSystemEQActive ? "Stop System Audio" : "Start System Audio",
                    icon: viewModel.isSystemEQActive ? "stop.fill" : "play.fill",
                    tint: viewModel.isSystemEQActive ? .red : .green
                ) { viewModel.toggleSystemEQOneClick() }
                compactButton(viewModel.isEnabled ? "Bypass EQ" : "Enable EQ", icon: "power", tint: .blue) {
                    viewModel.setEnabled(!viewModel.isEnabled)
                }
            }

            if let output = viewModel.activePhysicalOutputName ?? viewModel.selectedSystemOutputDevice?.name {
                Label(output, systemImage: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.didTripFeedbackProtection {
                Button("Resume after feedback trip") {
                    viewModel.clearFeedbackProtectionTrip()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(14)
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRESETS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(builtInPresets) { preset in
                        Button {
                            viewModel.applyPreset(preset)
                        } label: {
                            HStack {
                                Text(preset.name).lineLimit(1)
                                Spacer()
                                if preset.id == viewModel.selectedPreset.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(
                            preset.id == viewModel.selectedPreset.id ? Color.blue.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                    }
                }
            }
            .frame(maxHeight: 210)
        }
        .padding(14)
    }

    private var footer: some View {
        HStack {
            Button("Open Main Window") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            Spacer()
            Button("Quit") {
                viewModel.shutdown()
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(.borderless)
        .padding(14)
    }

    private func compactButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }

    private var statusText: String {
        if viewModel.isSystemEQActive { return "System Audio · \(viewModel.selectedPreset.name)" }
        if viewModel.systemAudioStatus == .permissionRequired { return "Permission required" }
        return viewModel.isEnabled ? "Ready · \(viewModel.selectedPreset.name)" : "EQ bypassed"
    }
}
