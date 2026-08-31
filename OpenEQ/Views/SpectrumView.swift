import SwiftUI

struct SpectrumView: View {
    let title: String
    let warning: String?
    let levels: SpectrumLevels
    let leftLevel: Float
    let rightLevel: Float
    let peakLevel: Float
    let isClipping: Bool

    @State private var peakLevels = SpectrumLevels()

    var body: some View {
        VStack(alignment: .leading, spacing: OpenEQTheme.controlSpacing) {
            HStack(alignment: .center, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(OpenEQTheme.accentCyan)
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }

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
                    .foregroundStyle(OpenEQTheme.accentAmber)
            }

            ZStack {
                // Background & Grid
                GeometryReader { _ in
                    Canvas { context, size in
                        let barCount = levels.count
                        guard barCount > 0 else { return }

                        let gap: CGFloat = 2.5
                        let totalGap = gap * CGFloat(barCount - 1)
                        let barWidth = max(1, (size.width - totalGap) / CGFloat(barCount))

                        // Grid lines
                        for i in 1...3 {
                            let y = size.height * CGFloat(i) * 0.25
                            var grid = Path()
                            grid.move(to: CGPoint(x: 0, y: y))
                            grid.addLine(to: CGPoint(x: size.width, y: y))
                            context.stroke(grid, with: .color(Color.white.opacity(0.04)), lineWidth: 1)
                        }

                        // RTA Bars
                        for index in 0..<barCount {
                            let level = levels[index]
                            let peak = index < peakLevels.count ? peakLevels[index] : level
                            let x = CGFloat(index) * (barWidth + gap)
                            let h = max(1, size.height * CGFloat(level))
                            let rect = CGRect(x: x, y: size.height - h, width: barWidth, height: h)

                            // Clean, solid pro-audio bar
                            context.fill(
                                Path(roundedRect: rect, cornerRadius: 1.5),
                                with: .color(OpenEQTheme.accentCyan.opacity(0.85))
                            )

                            // Floating Peak Hold Needle
                            if peak > 0.02 {
                                let peakY = size.height - max(2, size.height * CGFloat(peak))
                                let peakRect = CGRect(x: x, y: peakY - 1, width: barWidth, height: 1.5)
                                context.fill(
                                    Path(roundedRect: peakRect, cornerRadius: 0.75),
                                    with: .color(Color.white.opacity(0.9))
                                )
                            }
                        }
                    }
                }

                // Empty State Overlay
                if !levels.contains(where: { $0 > 0.025 }) {
                    VStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(OpenEQTheme.accentCyan.opacity(0.6))
                        Text("No Audio Signal")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("Open a file or enable System EQ to visualize")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 140)
            .background(OpenEQTheme.recessedSlotBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            HStack {
                ForEach(["20 Hz", "100 Hz", "500 Hz", "1 kHz", "4 kHz", "10 kHz", "20 kHz"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if label != "20 kHz" { Spacer() }
                }
            }
            .padding(.horizontal, 4)
        }
        .onChange(of: levels) { _, newValue in
            updatePeaks(with: newValue)
        }
    }

    private func updatePeaks(with current: SpectrumLevels) {
        if peakLevels.count != current.count {
            peakLevels = current
            return
        }
        for i in current.indices {
            if current[i] >= peakLevels[i] {
                peakLevels[i] = current[i]
            } else {
                peakLevels[i] = max(0, peakLevels[i] - 0.028)
            }
        }
    }
}

#Preview {
    SpectrumView(
        title: "Spectrum",
        warning: nil,
        levels: SpectrumLevels(repeating: 0.35),
        leftLevel: 0.6, rightLevel: 0.55, peakLevel: 0.6, isClipping: false
    )
    .padding(24)
    .frame(height: 280)
}
