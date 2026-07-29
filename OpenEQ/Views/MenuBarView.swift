import SwiftUI
import AppKit

struct MenuBarView: View {
    @Bindable var viewModel: OpenEQViewModel

    var body: some View {
        // MenuBarExtra(.menu) expects Button/Toggle/Divider — keep native menu structure.
        Toggle(isOn: toggleBinding) {
            Text(viewModel.isEnabled ? "EQ Enabled" : "EQ Bypassed")
        }

        if viewModel.selectedFileURL != nil {
            Divider()
            Text(viewModel.selectedFileName)
            Button("Play") { viewModel.play() }
                .disabled(viewModel.playbackState == .playing)
            Button("Pause") { viewModel.pause() }
                .disabled(viewModel.playbackState != .playing)
            Button("Stop") { viewModel.stop() }
        }

        Divider()

        Text("Preset: \(viewModel.selectedPreset.name)")

        if !viewModel.recentPresets.isEmpty {
            ForEach(viewModel.recentPresets.prefix(3)) { preset in
                Button(preset.name) {
                    viewModel.applyPreset(preset)
                }
            }
        }

        Divider()

        Button(viewModel.isSystemEQActive ? "Stop System EQ" : "Start System EQ") {
            viewModel.toggleSystemEQOneClick()
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        if viewModel.isSystemEQActive || viewModel.isExternalLoopbackActive {
            if viewModel.didTripFeedbackProtection {
                Button("Resume after feedback trip") {
                    viewModel.clearFeedbackProtectionTrip()
                }
            }

            Button("Emergency Stop") {
                viewModel.enterSafeMode()
            }
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

        Button("Quit OpenEQ") {
            viewModel.shutdown()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isEnabled },
            set: { viewModel.setEnabled($0) }
        )
    }
}
