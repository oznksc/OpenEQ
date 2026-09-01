import SwiftUI
import AppKit

@MainActor
final class OpenEQAppDelegate: NSObject, NSApplicationDelegate {
    weak var viewModel: OpenEQViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel?.handleAppLaunch()
        DispatchQueue.main.async {
            self.showMainWindowIfNeeded()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindowIfNeeded()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.shutdown()
    }

    func showMainWindowIfNeeded() {
        let presentationMode = viewModel?.presentationMode ?? AppPreferences.presentationMode
        if presentationMode.showsDockIcon {
            NSApplication.shared.setActivationPolicy(.regular)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)

        let candidateWindows = NSApplication.shared.windows.filter { window in
            window.isVisible && isMainAppWindow(window)
        }

        if let existing = candidateWindows.first {
            moveWindowOnScreenIfNeeded(existing)
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
        } else {
            NSApplication.shared.sendAction(Selector(("newWindow:")), to: nil, from: nil)
            DispatchQueue.main.async {
                guard let window = NSApplication.shared.windows.first(where: { self.isMainAppWindow($0) }) else {
                    return
                }
                self.moveWindowOnScreenIfNeeded(window)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    private func isMainAppWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.canBecomeKey && !window.description.contains("StatusBar")
    }

    private func moveWindowOnScreenIfNeeded(_ window: NSWindow) {
        guard !NSScreen.screens.contains(where: { window.frame.intersects($0.visibleFrame) }) else {
            return
        }

        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = window.frame.size
        window.setFrameOrigin(
            NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2
            )
        )
    }
}

@main
struct OpenEQApp: App {
    @NSApplicationDelegateAdaptor(OpenEQAppDelegate.self) private var appDelegate
    @State private var viewModel: OpenEQViewModel

    init() {
        let vm = OpenEQViewModel(
            audioEngineController: AudioEngineController()
        )
        _viewModel = State(initialValue: vm)
    }

    var body: some Scene {
        WindowGroup("OpenEQ", id: "main") {
            ContentView(viewModel: viewModel)
                .onAppear {
                    appDelegate.viewModel = viewModel
                    viewModel.handleAppLaunch()
                }
                .onReceive(NotificationCenter.default.publisher(for: .showMainWindow)) { _ in
                    appDelegate.showMainWindowIfNeeded()
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

        MenuBarExtra(isInserted: Binding(
            get: { viewModel.presentationMode.showsMenuBarExtra },
            set: { isInserted in
                if !isInserted && viewModel.presentationMode == .both {
                    viewModel.setPresentationMode(.dock)
                }
            }
        )) {
            MenuBarAudioHubView(viewModel: viewModel)
        } label: {
            MenuBarBadgeIconView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

extension Notification.Name {
    static let openAudioFile = Notification.Name("com.openeq.notification.openAudioFile")
    static let resetEQ = Notification.Name("com.openeq.notification.resetEQ")
    static let showMainWindow = Notification.Name("com.openeq.notification.showMainWindow")
}
