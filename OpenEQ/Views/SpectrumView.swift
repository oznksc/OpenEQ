import SwiftUI

struct SpectrumView: View {
    let title: String
    let warning: String?
    let levels: [Float]
    let leftLevel: Float
    let rightLevel: Float
    let peakLevel: Float
    let isClipping: Bool

    @State private var peakLevels: [Float] = Array(repeating: 0.0, count: SpectrumAnalyzer.barCount)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(title, systemImage: "chart.bar.xaxis")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                LevelMeterView(
                    leftLevel: leftLevel,
                    rightLevel: rightLevel,
                    peakLevel: peakLevel
                )

                ClippingIndicatorView(isClipping: isClipping)
            }

            if let warning {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            GeometryReader { proxy in
                Canvas { context, size in
                    let barCount = levels.count
                    guard barCount > 0 else { return }

                    let spacing: CGFloat = 1.5
                    let totalSpacing = spacing * CGFloat(barCount - 1)
                    let barWidth = (size.width - totalSpacing) / CGFloat(barCount)

                    for i in 1...3 {
                        let y = size.height * CGFloat(i) * 0.25
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(path, with: .color(Color.primary.opacity(0.04)), lineWidth: 1)
                    }

                    for index in 0..<barCount {
                        let level = levels[index]
                        let peakLevel = index < peakLevels.count ? peakLevels[index] : level
                        let x = CGFloat(index) * (barWidth + spacing)
                        let barHeight = max(1.0, size.height * CGFloat(level))
                        let barRect = CGRect(x: x, y: size.height - barHeight, width: barWidth, height: barHeight)

                        let gradient = GraphicsContext.Shading.linearGradient(
                            Gradient(colors: [.cyan.opacity(0.95), .blue.opacity(0.85), .purple.opacity(0.75)]),
                            startPoint: CGPoint(x: 0, y: size.height),
                            endPoint: CGPoint(x: 0, y: 0)
                        )

                        context.fill(Path(roundedRect: barRect, cornerRadius: 1), with: gradient)

                        let peakY = size.height - max(1.0, size.height * CGFloat(peakLevel))
                        context.fill(Path(CGRect(x: x, y: peakY - 1, width: barWidth, height: 2)), with: .color(Color.teal.opacity(0.9)))
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                .overlay(
                    Group {
                        if !levels.contains(where: { $0 > 0.025 }) {
                            VStack(spacing: 6) {
                                Image(systemName: "music.note.house")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.secondary.opacity(0.7))
                                Text("No Audio Source")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary.opacity(0.8))
                                Text("Press ⌘O or click 'Open Audio'")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.96))
                            .cornerRadius(8)
                        }
                    }
                )
            }

            HStack {
                Text("20 Hz").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Text("250 Hz").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Text("1 kHz").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Text("4 kHz").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Text("20 kHz").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
        }
        .padding(12)
        .onChange(of: levels) { _, newValue in
            updatePeaks(with: newValue)
        }
    }

    private func updatePeaks(with currentLevels: [Float]) {
        if peakLevels.count != currentLevels.count {
            peakLevels = currentLevels
            return
        }
        for i in 0..<currentLevels.count {
            let current = currentLevels[i]
            let existing = peakLevels[i]
            if current >= existing {
                peakLevels[i] = current
            } else {
                peakLevels[i] = max(0.0, existing - 0.035)
            }
        }
    }
}

#Preview {
    SpectrumView(
        title: "Real-Time FFT Spectrum",
        warning: nil,
        levels: Array(repeating: 0.35, count: SpectrumAnalyzer.barCount),
        leftLevel: 0.62, rightLevel: 0.58, peakLevel: 0.62, isClipping: false
    )
    .frame(height: 260)
}
