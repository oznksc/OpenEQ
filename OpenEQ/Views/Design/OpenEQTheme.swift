import SwiftUI

/// Layout tokens — readable sizes, stable split columns (no content-driven width jumps).
enum OpenEQTheme {
    static let pagePadding: CGFloat = 16
    static let blockSpacing: CGFloat = 20
    static let sectionSpacing: CGFloat = 14
    static let controlSpacing: CGFloat = 10
    static let playerBarCornerRadius: CGFloat = 14
    /// Locked sidebar width — min==max prevents list content from shoving the detail.
    static let sidebarWidth: CGFloat = 268
    static let minSidebarWidth: CGFloat = 268
    static let idealSidebarWidth: CGFloat = 268
    static let maxSidebarWidth: CGFloat = 268
    // The full tab workspace is designed around this fixed macOS window size.
    static let minWindowWidth: CGFloat = 1100
    static let minWindowHeight: CGFloat = 720
    static let inspectorMinWidth: CGFloat = 300
    static let inspectorIdealWidth: CGFloat = 320
    static let inspectorMaxWidth: CGFloat = 380
}

struct OpenEQStatusDot: View {
    enum Kind {
        case idle, ready, active, warning, error, bypassed

        var color: Color {
            switch self {
            case .idle: return .secondary
            case .ready: return .blue
            case .active: return .green
            case .warning: return .orange
            case .error: return .red
            case .bypassed: return .orange
            }
        }
    }

    let kind: Kind
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(kind.color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Simple text section title — no icon chip, no background layer.
struct OpenEQSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
