import SwiftUI

/// Minimal layout tokens. Chrome stays system Liquid Glass; content is flat (no nested cards).
enum OpenEQTheme {
    static let pagePadding: CGFloat = 24
    static let blockSpacing: CGFloat = 28
    static let sectionSpacing: CGFloat = 20
    static let controlSpacing: CGFloat = 12
    static let playerBarCornerRadius: CGFloat = 18
    static let minSidebarWidth: CGFloat = 260
    static let idealSidebarWidth: CGFloat = 300
    static let maxSidebarWidth: CGFloat = 360
    static let minWindowWidth: CGFloat = 960
    static let minWindowHeight: CGFloat = 600
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
