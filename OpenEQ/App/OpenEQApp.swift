import SwiftUI
import AppKit

@MainActor
final class OpenEQAppDelegate: NSObject, NSApplicationDelegate {
    weak var viewModel: OpenEQViewModel?

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.shutdown()
    }
}

@main
struct OpenEQApp: App {
    @NSApplicationDelegateAdaptor(OpenEQAppDelegate.self) private var appDelegate
    @State private var viewModel = OpenEQViewModel(
        audioEngineController: AudioEngineController()
    )

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onAppear {
                    appDelegate.viewModel = viewModel
                    viewModel.handleAppLaunch()
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: OpenEQTheme.minWindowWidth, height: OpenEQTheme.minWindowHeight)
        .windowToolbarStyle(.unified)
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

            CommandMenu("System Audio") {
                Button(viewModel.isSystemEQActive ? "Stop System EQ" : "Start System EQ") {
                    viewModel.toggleSystemEQOneClick()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("System Audio Settings…") {
                    viewModel.isShowingSystemAudio = true
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
        } label: {
            Image(systemName: viewModel.isEnabled ? "slider.vertical.3" : "speaker.slash")
        }
        .menuBarExtraStyle(.menu)
    }
}

extension Notification.Name {
    static let openAudioFile = Notification.Name("com.openeq.notification.openAudioFile")
    static let resetEQ = Notification.Name("com.openeq.notification.resetEQ")
}
