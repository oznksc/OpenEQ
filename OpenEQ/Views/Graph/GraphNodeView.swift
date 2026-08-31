import SwiftUI

/// Visual chrome for a graph node. Gestures live on the canvas.
struct GraphNodeView: View, Equatable {
    let node: GraphNode
    let isSelected: Bool
    let isRunning: Bool

    private var accent: Color { GraphTheme.accent(for: node.kind) }

    static func == (lhs: GraphNodeView, rhs: GraphNodeView) -> Bool {
        lhs.node == rhs.node
            && lhs.isSelected == rhs.isSelected
            && lhs.isRunning == rhs.isRunning
    }

    var body: some View {
        GraphNodeChrome(isSelected: isSelected, isRunning: isRunning, accent: accent) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: node.kind.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 24, height: 24)
                        .background(
                            accent.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(node.config.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if isRunning {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("Running")
                    }
                }

                nodeBody
            }
        }
        .frame(width: node.size.width, height: node.size.height)
        .overlay(alignment: .leading) {
            if !node.kind.inputPortNames.isEmpty {
                portDot
                    .offset(x: -GraphTheme.portSize / 2)
            }
        }
        .overlay(alignment: .trailing) {
            if !node.kind.outputPortNames.isEmpty {
                portDot
                    .offset(x: GraphTheme.portSize / 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: GraphTheme.nodeCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(node.kind.title), \(node.title)")
        .accessibilityValue(node.config.subtitle + (isRunning ? ", running" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var portDot: some View {
        Circle()
            .fill(Color.primary.opacity(0.8))
            .frame(width: GraphTheme.portSize, height: GraphTheme.portSize)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }

    @ViewBuilder
    private var nodeBody: some View {
        switch node.config {
        case .equalizer(let eq):
            MiniEQCurvePreview(bands: eq.bands, preamp: eq.preamp, isEnabled: eq.isEnabled)
                .frame(height: 40)
                .opacity(eq.isEnabled ? 1 : 0.4)
                .allowsHitTesting(false)
        case .appSource, .systemSource:
            Text(isRunning ? "Tapping output" : "Process audio out")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .inputSource:
            Text("Mic monitor path")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .fileSource:
            Text(isRunning ? "Playing" : "Local file")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .output:
            Text(node.config.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .dynamics(let dyn):
            Text(dyn.settings.isCompressorEnabled ? "Compressor on" : "Compressor off")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .monitor:
            Text("Analysis only")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

struct MiniEQCurvePreview: View {
    let bands: [EQBand]
    let preamp: Float
    let isEnabled: Bool

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let midY = h * 0.5

            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: midY))
            zero.addLine(to: CGPoint(x: w, y: midY))
            context.stroke(zero, with: .color(.primary.opacity(0.08)), lineWidth: 1)

            guard !bands.isEmpty else { return }
            var curve = Path()
            let last = max(1, bands.count - 1)
            for (index, band) in bands.enumerated() {
                let x = w * CGFloat(index) / CGFloat(last)
                let y = midY - CGFloat(Double(band.gain + preamp) / 24.0) * (h * 0.4)
                if index == 0 {
                    curve.move(to: CGPoint(x: x, y: y))
                } else {
                    curve.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(
                curve,
                with: .color(isEnabled ? .cyan.opacity(0.9) : .secondary.opacity(0.5)),
                style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round)
            )
        }
        .accessibilityHidden(true)
    }
}
