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
            }
            .padding(.bottom, 4)

            Divider()

            Toggle(isOn: toggleBinding) {
                Label("EQ Enabled", systemImage: "power")
            }

            Divider()

            if viewModel.selectedFileURL != nil {
                Label(viewModel.selectedFileName, systemImage: "music.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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

            Text("Active Preset: \(viewModel.selectedPreset.name)")
                .font(.caption)

            Divider()

            Button("Show OpenEQ") {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("o")

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(8)
        .frame(width: 220)
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isEnabled },
            set: { viewModel.setEnabled($0) }
        )
    }
}
