import SwiftUI

private struct FloatingEQSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .padding(12)
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.18), OpenEQTheme.accentCyan.opacity(0.12), .white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
            }
    }
}

extension View {
    func floatingEQSurface(cornerRadius: CGFloat = 16) -> some View {
        modifier(FloatingEQSurfaceModifier(cornerRadius: cornerRadius))
    }
}
