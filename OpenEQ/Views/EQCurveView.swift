import SwiftUI

/// Frequency-response curve with interactive nodes (drag gain/freq, scroll Q).
struct EQCurveView: View {
    let bands: [EQBand]
    let mode: EQMode
    let preamp: Float
    var selectedBandID: EQBand.ID?
    var isInteractive: Bool = true
    var onSelectBand: ((EQBand.ID) -> Void)?
    var onBandChanged: ((Int, EQBand) -> Void)?

    private let minimumFrequency: Float = 20
    private let maximumFrequency: Float = 20_000
    private let minimumGain: Float = -24
    private let maximumGain: Float = 24

    @State private var draggingBandID: EQBand.ID?
    @State private var hoveredBandID: EQBand.ID?

    var body: some View {
        GeometryReader { geometry in
            let plotRect = CGRect(
                x: 42,
                y: 12,
                width: max(1, geometry.size.width - 58),
                height: max(1, geometry.size.height - 38)
            )

            ZStack {
                Canvas { context, size in
                    let rect = CGRect(
                        x: 42,
                        y: 12,
                        width: max(1, size.width - 58),
                        height: max(1, size.height - 38)
                    )
                    drawGrid(in: rect, context: &context)
                    drawCurve(in: rect, context: &context)
                    drawBandPoints(in: rect, context: &context)
                }

                if isInteractive {
                    interactionLayer(plotRect: plotRect)
                }
            }
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
        .help(isInteractive
              ? "Drag nodes to set frequency/gain. Scroll over a node to change Q."
              : "EQ frequency response")
        .accessibilityLabel("EQ curve from 20 hertz to 20 kilohertz, gain minus 24 to plus 24 decibels.")
    }

    private func interactionLayer(plotRect: CGRect) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(at: value.location, in: plotRect, ended: false)
                    }
                    .onEnded { value in
                        handleDrag(at: value.location, in: plotRect, ended: true)
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredBandID = nearestBand(at: location, in: plotRect, maxDistance: 18)?.id
                case .ended:
                    hoveredBandID = nil
                }
            }
            .onScrollWheel { delta in
                handleScroll(delta: delta, in: plotRect)
            }
    }

    private func handleDrag(at point: CGPoint, in rect: CGRect, ended: Bool) {
        guard isInteractive else { return }

        if draggingBandID == nil {
            guard let nearest = nearestBand(at: point, in: rect, maxDistance: 22),
                  let index = bands.firstIndex(where: { $0.id == nearest.id }) else {
                return
            }
            draggingBandID = nearest.id
            onSelectBand?(nearest.id)
            _ = index
        }

        guard let dragID = draggingBandID,
              let index = bands.firstIndex(where: { $0.id == dragID }) else {
            if ended { draggingBandID = nil }
            return
        }

        var band = bands[index]
        // Graphic mode: lock frequency to ISO centers; only gain is draggable.
        if mode == .parametric {
            band.frequency = frequency(atX: point.x, in: rect)
        }
        band.gain = gain(atY: point.y, in: rect)
        // Snap near zero for easier flat reset.
        if abs(band.gain) < 0.35 { band.gain = 0 }
        onBandChanged?(index, band)

        if ended {
            draggingBandID = nil
        }
    }

    private func handleScroll(delta: CGFloat, in rect: CGRect) {
        guard isInteractive, mode == .parametric else { return }
        let targetID = hoveredBandID ?? selectedBandID ?? draggingBandID
        guard let targetID,
              let index = bands.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        var band = bands[index]
        // Trackpad scroll: positive deltaY typically means scroll up → increase Q.
        let step = Float(delta) * 0.05
        band.q = band.q + step
        onBandChanged?(index, band)
        onSelectBand?(band.id)
    }

    private func nearestBand(at point: CGPoint, in rect: CGRect, maxDistance: CGFloat) -> EQBand? {
        var best: (EQBand, CGFloat)?
        for band in bands {
            let center = pointFor(band: band, in: rect)
            let distance = hypot(center.x - point.x, center.y - point.y)
            if distance <= maxDistance {
                if best == nil || distance < best!.1 {
                    best = (band, distance)
                }
            }
        }
        return best?.0
    }

    private func pointFor(band: EQBand, in rect: CGRect) -> CGPoint {
        let gain = clampedGain(preamp + effectiveGain(for: band))
        return CGPoint(
            x: xPosition(for: band.frequency, in: rect),
            y: yPosition(for: gain, in: rect)
        )
    }

    // MARK: - Drawing

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
            let center = pointFor(band: band, in: rect)
            let isSelected = band.id == selectedBandID || band.id == draggingBandID || band.id == hoveredBandID
            let radius: CGFloat = isSelected ? 7 : 4
            let dotRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            let color: Color = {
                if !band.isEnabled { return Color.white.opacity(0.28) }
                if isSelected { return Color.white }
                return Color.cyan.opacity(0.9)
            }()
            context.fill(Path(ellipseIn: dotRect), with: .color(color))
            if isSelected {
                context.stroke(
                    Path(ellipseIn: dotRect.insetBy(dx: -2, dy: -2)),
                    with: .color(Color.cyan.opacity(0.8)),
                    lineWidth: 1.5
                )
            }
        }
    }

    // MARK: - Curve math

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

    private func frequency(atX x: CGFloat, in rect: CGRect) -> Float {
        let progress = Float((x - rect.minX) / max(rect.width, 1))
        let clamped = min(max(progress, 0), 1)
        return frequencyAt(progress: clamped)
    }

    private func gain(atY y: CGFloat, in rect: CGRect) -> Float {
        let progress = Float((rect.maxY - y) / max(rect.height, 1))
        let clamped = min(max(progress, 0), 1)
        return minimumGain + clamped * (maximumGain - minimumGain)
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

// MARK: - Scroll wheel helper (AppKit)

private extension View {
    func onScrollWheel(perform: @escaping (CGFloat) -> Void) -> some View {
        background(ScrollWheelCatcher(onScroll: perform))
    }
}

private struct ScrollWheelCatcher: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

private final class ScrollWheelNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        // Prefer precise deltas (trackpad); fall back to line-based.
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 10
        if abs(delta) > 0.01 {
            onScroll?(delta)
        }
        // Do not call super so parent scroll views do not steal the gesture while editing Q.
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Participate in hit testing so scroll events arrive here when pointer is over the curve.
        self
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
        preamp: -1,
        selectedBandID: nil,
        isInteractive: true
    )
    .padding()
    .frame(width: 900, height: 200)
}
