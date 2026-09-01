import Foundation

enum AppPresentationMode: String, CaseIterable, Identifiable {
    case dock
    case menuBar
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dock: "Normal"
        case .menuBar: "Menu Bar"
        case .both: "Both"
        }
    }

    var description: String {
        switch self {
        case .dock: "Show OpenEQ in the Dock as a regular app."
        case .menuBar: "Run from the menu bar without a Dock icon."
        case .both: "Keep both the Dock icon and menu bar controller visible."
        }
    }

    var showsMenuBarExtra: Bool { self != .dock }
    var showsDockIcon: Bool { self != .menuBar }
}
