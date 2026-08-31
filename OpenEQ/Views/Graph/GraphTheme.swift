import SwiftUI

enum GraphTheme {
    static let nodeCornerRadius: CGFloat = 12
    static let portSize: CGFloat = 11
    static let gridSpacing: CGFloat = 32
    static let wireWidth: CGFloat = 2
    static let selectionLineWidth: CGFloat = 2
    static let nodePadding: CGFloat = 12

    static func accent(for kind: GraphNodeKind) -> Color {
        switch kind {
        case .appSource: return .cyan
        case .systemSource: return .green
        case .inputSource: return .orange
        case .fileSource: return .blue
        case .equalizer: return .purple
        case .dynamics: return .pink
        case .output: return .mint
        case .monitor: return .secondary
        }
    }
}

/// Flat node chrome — no glass/shadow (GPU-friendly).
struct GraphNodeChrome<Content: View>: View {
    var isSelected: Bool
    var isRunning: Bool = false
    var accent: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GraphTheme.nodeCornerRadius, style: .continuous)
        content()
            .padding(GraphTheme.nodePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.94), in: shape)
            .overlay(
                shape.strokeBorder(
                    borderColor,
                    lineWidth: isSelected || isRunning ? GraphTheme.selectionLineWidth : 1
                )
            )
    }

    private var borderColor: Color {
        if isSelected { return accent.opacity(0.95) }
        if isRunning { return Color.green.opacity(0.75) }
        return Color.primary.opacity(0.12)
    }
}

/// Dual meter for the status strip only.
struct CompactLevelMeter: View {
    var left: Float
    var right: Float
    var width: CGFloat = 56
    var height: CGFloat = 12

    var body: some View {
        HStack(spacing: 3) {
            bar(left)
            bar(right)
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level")
        .accessibilityValue("\(Int(max(left, right) * 100)) percent")
    }

    private func bar(_ level: Float) -> some View {
        let t = CGFloat(min(1, max(0, level)))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(OpenEQTheme.recessedSlotBg.opacity(0.8))
                Capsule()
                    .fill(t > 0.9 ? OpenEQTheme.accentRed : (t > 0.7 ? OpenEQTheme.accentGold : OpenEQTheme.accentGreen))
                    .frame(width: max(2, geo.size.width * t))
            }
        }
    }
}

