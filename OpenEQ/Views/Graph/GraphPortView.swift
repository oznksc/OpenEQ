import SwiftUI

struct GraphPortView: View {
    let isOutput: Bool
    let accent: Color
    let isHighlighted: Bool
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    var body: some View {
        Circle()
            .fill(isHighlighted ? accent : Color.primary.opacity(0.85))
            .frame(width: GraphTheme.portSize, height: GraphTheme.portSize)
            .overlay(
                Circle()
                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
            )
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged(onDragChanged)
                    .onEnded(onDragEnded)
            )
            .accessibilityLabel(isOutput ? "Output port" : "Input port")
    }
}
