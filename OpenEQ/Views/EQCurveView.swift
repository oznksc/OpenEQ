//
//  EQCurveView.swift
//  OpenEQ
//
//  Created by Ozan
//

import SwiftUI

struct EQCurveView: View {
    let bands: [EQBand]
    let mode: EQMode
    let preamp: Float

    private let minimumFrequency: Float = 20
    private let maximumFrequency: Float = 20_000
    private let minimumGain: Float = -24
    private let maximumGain: Float = 24

    var body: some View {
        Canvas { context, size in
            let plotRect = CGRect(
                x: 42,
                y: 12,
                width: max(1, size.width - 58),
                height: max(1, size.height - 38)
            )

            drawGrid(in: plotRect, context: &context)
            drawCurve(in: plotRect, context: &context)
            drawBandPoints(in: plotRect, context: &context)
        }
        .frame(height: 170)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.075, green: 0.082, blue: 0.095))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityLabel("EQ curve preview showing frequency response from 20 hertz to 20 kilohertz and gain from minus 24 to plus 24 decibels.")
    }

    private func drawGrid(in rect: CGRect, context: inout GraphicsContext) {
        let gridColor = Color.white.opacity(0.08)
        let textColor = Color.white.opacity(0.48)

        for gain in gainLabels {
            let y = yPosition(for: gain, in: rect)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))

            let opacity = gain == 0 ? 0.22 : 0.08
            context.stroke(path, with: .color(Color.white.opacity(opacity)), lineWidth: gain == 0 ? 1.2 : 1)

            let label = gain > 0 ? "+\(Int(gain))" : "\(Int(gain))"
            context.draw(
                Text(label)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(textColor),
                at: CGPoint(x: rect.minX - 22, y: y),
                anchor: .center
            )
        }

        for marker in frequencyLabels {
            let x = xPosition(for: marker.frequency, in: rect)
            var path = Path()
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            context.stroke(path, with: .color(gridColor), lineWidth: 1)

            context.draw(
                Text(marker.label)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(textColor),
                at: CGPoint(x: x, y: rect.maxY + 14),
                anchor: .center
            )
        }
    }

    private func drawCurve(in rect: CGRect, context: inout GraphicsContext) {
        let sampleCount = 180
        var path = Path()

        for index in 0..<sampleCount {
            let progress = Float(index) / Float(sampleCount - 1)
            let frequency = frequencyAt(progress: progress)
            let gain = curveGain(at: frequency)
            let point = CGPoint(
                x: xPosition(for: frequency, in: rect),
                y: yPosition(for: gain, in: rect)
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        context.stroke(path, with: .color(Color.cyan.opacity(0.22)), lineWidth: 5)
        context.stroke(path, with: .color(Color.cyan.opacity(0.92)), lineWidth: 2)
    }

    private func drawBandPoints(in rect: CGRect, context: inout GraphicsContext) {
        for band in bands {
            let gain = clampedGain(preamp + effectiveGain(for: band))
            let center = CGPoint(
                x: xPosition(for: band.frequency, in: rect),
                y: yPosition(for: gain, in: rect)
            )
            let dotRect = CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)
            let color = band.isEnabled ? Color.cyan.opacity(0.85) : Color.white.opacity(0.28)
            context.fill(Path(ellipseIn: dotRect), with: .color(color))
        }
    }

    private func curveGain(at frequency: Float) -> Float {
        var gain = preamp

        for band in bands {
            let contribution = effectiveGain(for: band)

            switch mode {
            case .graphic:
                gain += contribution * bellInfluence(frequency: frequency, center: band.frequency, q: 0.9)
            case .parametric:
                gain += parametricInfluence(for: band, frequency: frequency, contribution: contribution)
            }
        }

        return clampedGain(gain)
    }

    private func parametricInfluence(for band: EQBand, frequency: Float, contribution: Float) -> Float {
        switch band.filterType {
        case .parametric:
            return contribution * bellInfluence(frequency: frequency, center: band.frequency, q: band.q)
        case .lowShelf:
            return contribution * lowShelfInfluence(frequency: frequency, cutoff: band.frequency)
        case .highShelf:
            return contribution * highShelfInfluence(frequency: frequency, cutoff: band.frequency)
        case .highPass:
            return highPassInfluence(frequency: frequency, cutoff: band.frequency, enabled: band.isEnabled)
        case .lowPass:
            return lowPassInfluence(frequency: frequency, cutoff: band.frequency, enabled: band.isEnabled)
        }
    }

    private func bellInfluence(frequency: Float, center: Float, q: Float) -> Float {
        let distance = abs(log2(max(frequency, 1) / max(center, 1)))
        let width = max(0.18, 1.25 / max(q, 0.1))
        return exp(-pow(distance / width, 2))
    }

    private func lowShelfInfluence(frequency: Float, cutoff: Float) -> Float {
        let distance = log2(max(frequency, 1) / max(cutoff, 1))
        return 1 / (1 + exp(distance * 3))
    }

    private func highShelfInfluence(frequency: Float, cutoff: Float) -> Float {
        let distance = log2(max(frequency, 1) / max(cutoff, 1))
        return 1 / (1 + exp(-distance * 3))
    }

    private func highPassInfluence(frequency: Float, cutoff: Float, enabled: Bool) -> Float {
        let strength: Float = enabled ? -18 : -3
        return strength * lowShelfInfluence(frequency: frequency, cutoff: cutoff)
    }

    private func lowPassInfluence(frequency: Float, cutoff: Float, enabled: Bool) -> Float {
        let strength: Float = enabled ? -18 : -3
        return strength * highShelfInfluence(frequency: frequency, cutoff: cutoff)
    }

    private func effectiveGain(for band: EQBand) -> Float {
        band.isEnabled ? band.gain : band.gain * 0.12
    }

    private func xPosition(for frequency: Float, in rect: CGRect) -> CGFloat {
        let minLog = log10(minimumFrequency)
        let maxLog = log10(maximumFrequency)
        let frequencyLog = log10(max(minimumFrequency, min(maximumFrequency, frequency)))
        let progress = CGFloat((frequencyLog - minLog) / (maxLog - minLog))
        return rect.minX + rect.width * progress
    }

    private func yPosition(for gain: Float, in rect: CGRect) -> CGFloat {
        let clamped = clampedGain(gain)
        let progress = CGFloat((clamped - minimumGain) / (maximumGain - minimumGain))
        return rect.maxY - rect.height * progress
    }

    private func frequencyAt(progress: Float) -> Float {
        let minLog = log10(minimumFrequency)
        let maxLog = log10(maximumFrequency)
        return pow(10, minLog + progress * (maxLog - minLog))
    }

    private func clampedGain(_ gain: Float) -> Float {
        max(minimumGain, min(maximumGain, gain))
    }

    private var frequencyLabels: [(frequency: Float, label: String)] {
        [
            (20, "20"),
            (50, "50"),
            (100, "100"),
            (200, "200"),
            (500, "500"),
            (1000, "1k"),
            (2000, "2k"),
            (5000, "5k"),
            (10_000, "10k"),
            (20_000, "20k")
        ]
    }

    private var gainLabels: [Float] {
        [24, 12, 0, -12, -24]
    }
}

#Preview {
    EQCurveView(
        bands: EQBand.defaultParametricBands().enumerated().map { index, band in
            var updatedBand = band
            updatedBand.gain = index.isMultiple(of: 2) ? 4 : -3
            return updatedBand
        },
        mode: .parametric,
        preamp: -1
    )
    .padding()
    .frame(width: 900)
}
