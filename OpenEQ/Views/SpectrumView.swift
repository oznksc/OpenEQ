import SwiftUI

struct SpectrumView: View {
    let title: String
    let warning: String?
    let levels: [Float]
    let leftLevel: Float
    let rightLevel: Float
    let peakLevel: Float
    let isClipping: Bool

    @State private var peakLevels: [Float] = Array(repeating: 0, count: SpectrumAnalyzer.barCount)

    var body: some View {
        VStack(alignment: .leading, spacing: OpenEQTheme.controlSpacing) {
            HStack(alignment: .center, spacing: 16) {
                Text(title)
                    .font(.title3.weight(.semibold))

                Spacer(minLength: 12)

                LevelMeterView(
                    leftLevel: leftLevel,
                    rightLevel: rightLevel,
                    peakLevel: peakLevel
                )

                ClippingIndicatorView(isClipping: isClipping)
            }

            if let warning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { _ in
                Canvas { context, size in
                    let barCount = levels.count
                    guard barCount > 0 else { return }

                    let gap: CGFloat = 2
                    let totalGap = gap * CGFloat(barCount - 1)
                    let barWidth = max(1, (size.width - totalGap) / CGFloat(barCount))

                    for i in 1...3 {
                        let y = size.height * CGFloat(i) * 0.25
                        var grid = Path()
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(grid, with: .color(Color.primary.opacity(0.05)), lineWidth: 1)
                    }

                    for index in 0..<barCount {
                        let level = levels[index]
                        let peak = index < peakLevels.count ? peakLevels[index] : level
                        let x = CGFloat(index) * (barWidth + gap)
                        let h = max(1, size.height * CGFloat(level))
                        let rect = CGRect(x: x, y: size.height - h, width: barWidth, height: h)

                        context.fill(
                            Path(roundedRect: rect, cornerRadius: 1.5),
                            with: .linearGradient(
                                Gradient(colors: [
                                    Color.accentColor.opacity(0.9),
                                    Color.cyan.opacity(0.55)
                                ]),
                                startPoint: CGPoint(x: 0, y: size.height),
                                endPoint: CGPoint(x: 0, y: 0)
                            )
                        )

                        let peakY = size.height - max(1, size.height * CGFloat(peak))
                        context.fill(
                            Path(CGRect(x: x, y: peakY - 1, width: barWidth, height: 1.5)),
                            with: .color(Color.primary.opacity(0.35))
                        )
                    }
                }
                .overlay {
                    if !levels.contains(where: { $0 > 0.025 }) {
                        VStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                            Text("No audio")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("⌘O to open a file")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(minHeight: 140)

            HStack {
                ForEach(["20 Hz", "250 Hz", "1 kHz", "4 kHz", "20 kHz"], id: \.self) { label in
                    Text(label)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                    if label != "20 kHz" { Spacer() }
                }
            }
        }
        .onChange(of: levels) { _, newValue in
            updatePeaks(with: newValue)
        }
    }

    private func updatePeaks(with current: [Float]) {
        if peakLevels.count != current.count {
            peakLevels = current
            return
        }
        for i in current.indices {
            if current[i] >= peakLevels[i] {
                peakLevels[i] = current[i]
            } else {
                peakLevels[i] = max(0, peakLevels[i] - 0.035)
            }
        }
    }
}

#Preview {
    SpectrumView(
        title: "Spectrum",
        warning: nil,
        levels: Array(repeating: 0.35, count: SpectrumAnalyzer.barCount),
        leftLevel: 0.6, rightLevel: 0.55, peakLevel: 0.6, isClipping: false
    )
    .padding(24)
    .frame(height: 280)
}
