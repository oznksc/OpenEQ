import SwiftUI

struct SpectrumGlobeView: View {
    let levels: SpectrumLevels

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.42))
                .frame(width: 220, height: 58)
                .blur(radius: 16)
                .offset(y: 104)

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let pointCount = 40
                let baseRadius = min(size.width, size.height) * 0.37
                var points: [CGPoint] = []

                for index in 0..<pointCount {
                    let angle = CGFloat(index) / CGFloat(pointCount) * .pi * 2
                    let levelIndex = index * levels.count / pointCount
                    let level = CGFloat(levels[levelIndex])
                    let wobble = sin(angle * 3) * 8 + cos(angle * 5) * 5
                    let radius = baseRadius + level * 46 + wobble
                    points.append(CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                }

                guard let first = points.first else { return }
                var blob = Path()
                blob.move(to: first)
                for index in points.indices {
                    let current = points[index]
                    let next = points[(index + 1) % points.count]
                    let midpoint = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
                    blob.addQuadCurve(to: midpoint, control: current)
                }
                blob.closeSubpath()

                context.fill(
                    blob,
                    with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(0.72), Color.cyan.opacity(0.62), Color.indigo.opacity(0.48), Color.black.opacity(0.62)]),
                        center: CGPoint(x: center.x - 38, y: center.y - 52),
                        startRadius: 4,
                        endRadius: baseRadius * 1.4
                    )
                )
                context.stroke(
                    blob,
                    with: .linearGradient(
                        Gradient(colors: [Color.white.opacity(0.78), Color.cyan.opacity(0.6), Color.indigo.opacity(0.16)]),
                        startPoint: CGPoint(x: center.x - baseRadius, y: center.y - baseRadius),
                        endPoint: CGPoint(x: center.x + baseRadius, y: center.y + baseRadius)
                    ),
                    lineWidth: 1.4
                )

                let highlight = CGRect(x: center.x - 70, y: center.y - 88, width: 92, height: 34)
                context.fill(Path(ellipseIn: highlight), with: .color(Color.white.opacity(0.28)))
            }
        }
        .shadow(color: Color.cyan.opacity(0.38), radius: 28)
        .accessibilityHidden(true)
    }
}
