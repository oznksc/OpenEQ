import SwiftUI

enum SpectrumVisualizationStyle: String, CaseIterable, Identifiable {
    case neon
    case aurora
    case ember

    var id: Self { self }

    var title: String {
        switch self {
        case .neon: "Neon"
        case .aurora: "Aurora"
        case .ember: "Ember"
        }
    }

    var icon: String {
        switch self {
        case .neon: "chart.bar.fill"
        case .aurora: "waveform.path"
        case .ember: "flame.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .neon: OpenEQTheme.accentCyan
        case .aurora: OpenEQTheme.accentPurple
        case .ember: OpenEQTheme.accentAmber
        }
    }
}
