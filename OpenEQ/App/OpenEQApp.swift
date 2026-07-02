import SwiftUI

@main
struct OpenEQApp: App {
    @State private var viewModel = OpenEQViewModel(
        audioEngineController: AudioEngineController()
    )

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 700)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Audio...") {
                    NotificationCenter.default.post(name: .openAudioFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("Equalizer") {
                Button("Reset EQ") {
                    viewModel.resetEQ()
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button(viewModel.isEnabled ? "Disable EQ" : "Enable EQ") {
                    viewModel.setEnabled(!viewModel.isEnabled)
                }
                .keyboardShortcut("b", modifiers: .command)

                Button(viewModel.isVolumeBoostEnabled ? "Disable Volume Boost" : "Enable Volume Boost") {
                    viewModel.toggleVolumeBoost()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }

            CommandMenu("Presets") {
                ForEach(viewModel.presets.prefix(5)) { preset in
                    Button(preset.name) {
                        viewModel.applyPreset(preset)
                    }
                }
            }
        }

        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
        } label: {
            Image(systemName: viewModel.isEnabled ? "slider.vertical.3" : "slider.vertical.3.slash")
        }
        .menuBarExtraStyle(.menu)
    }
}

extension Notification.Name {
    static let openAudioFile = Notification.Name("com.openeq.notification.openAudioFile")
    static let resetEQ = Notification.Name("com.openeq.notification.resetEQ")
}
