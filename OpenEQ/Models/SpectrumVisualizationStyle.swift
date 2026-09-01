import SwiftUI

enum SpectrumVisualizationStyle: String, CaseIterable, Identifiable {
    case neon
    case aurora
    case ember
    case prism
    case orbit
    case matrix
    case globe

    var id: Self { self }

    var title: String {
        switch self {
        case .neon: "Neon"
        case .aurora: "Aurora"
        case .ember: "Ember"
        case .prism: "Prism"
        case .orbit: "Orbit"
        case .matrix: "Matrix"
        case .globe: "Globe"
        }
    }

    var icon: String {
        switch self {
        case .neon: "chart.bar.fill"
        case .aurora: "waveform.path"
        case .ember: "flame.fill"
        case .prism: "sparkles"
        case .orbit: "circle.dotted"
        case .matrix: "square.grid.3x3.fill"
        case .globe: "circle.hexagongrid.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .neon: OpenEQTheme.accentCyan
        case .aurora: OpenEQTheme.accentPurple
        case .ember: OpenEQTheme.accentAmber
        case .prism: .blue
        case .orbit: .pink
        case .matrix: .green
        case .globe: .indigo
        }
    }
}
