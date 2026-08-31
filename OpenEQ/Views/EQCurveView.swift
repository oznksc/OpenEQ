import SwiftUI

/// Frequency-response curve with tactile studio oscilloscope rendering, glow layers, and interactive nodes.
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
    @State private var cursorLocation: CGPoint? = nil

    var body: some View {
        GeometryReader { geometry in
            let plotRect = CGRect(
                x: 44,
                y: 14,
                width: max(1, geometry.size.width - 60),
                height: max(1, geometry.size.height - 40)
            )

            ZStack(alignment: .topTrailing) {
                Canvas { context, size in
                    let rect = CGRect(
                        x: 44,
                        y: 14,
                        width: max(1, size.width - 60),
                        height: max(1, size.height - 40)
                    )
                    drawOscilloscopeGrid(in: rect, context: &context)
                    if mode == .parametric, let activeID = hoveredBandID ?? draggingBandID ?? selectedBandID,
                       let band = bands.first(where: { $0.id == activeID }) {
                        drawQEnvelope(for: band, in: rect, context: &context)
                    }
                    drawCurveGlow(in: rect, context: &context)
                    drawBandNodes(in: rect, context: &context)
                }

                // Coordinate HUD Overlay
                if let cursor = cursorLocation, plotRect.contains(cursor) {
                    let freq = frequency(atX: cursor.x, in: plotRect)
                    let g = gain(atY: cursor.y, in: plotRect)
                    HStack(spacing: 8) {
                        Text(formatFrequency(freq))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(OpenEQTheme.accentCyan)
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%+.1f dB", g))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(g > 0.1 ? OpenEQTheme.accentCyan : (g < -0.1 ? OpenEQTheme.accentAmber : .secondary))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.75), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .padding(8)
                    .transition(.opacity)
                }

                if isInteractive {
                    interactionLayer(plotRect: plotRect)
                }
            }
        }
        .frame(height: 172)
        .background(OpenEQTheme.recessedSlotBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                        cursorLocation = value.location
                        handleDrag(at: value.location, in: plotRect, ended: false)
                    }
                    .onEnded { value in
                        cursorLocation = nil
                        handleDrag(at: value.location, in: plotRect, ended: true)
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    cursorLocation = location
                    hoveredBandID = nearestBand(at: location, in: plotRect, maxDistance: 20)?.id
                case .ended:
                    cursorLocation = nil
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
            guard let nearest = nearestBand(at: point, in: rect, maxDistance: 24),
                  let _ = bands.firstIndex(where: { $0.id == nearest.id }) else {
                return
            }
            draggingBandID = nearest.id
            onSelectBand?(nearest.id)
        }

        guard let dragID = draggingBandID,
              let index = bands.firstIndex(where: { $0.id == dragID }) else {
            if ended { draggingBandID = nil }
            return
        }

        var band = bands[index]
        if mode == .parametric {
            band.frequency = frequency(atX: point.x, in: rect)
        }
        band.gain = gain(atY: point.y, in: rect)
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

    // MARK: - Canvas Rendering

    private func drawOscilloscopeGrid(in rect: CGRect, context: inout GraphicsContext) {
        let gridColor = Color.white.opacity(0.06)
        let textColor = Color.white.opacity(0.42)
        let zeroLineColor = OpenEQTheme.accentCyan.opacity(0.25)

        for gain in gainLabels {
            let y = yPosition(for: gain, in: rect)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))

            if gain == 0 {
                context.stroke(path, with: .color(zeroLineColor), lineWidth: 1.2)
            } else {
                context.stroke(path, with: .color(gridColor), lineWidth: 0.8)
            }

            let label = gain > 0 ? "+\(Int(gain))" : "\(Int(gain))"
            context.draw(
                Text(label)
                    .font(.system(size: 9, weight: gain == 0 ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(gain == 0 ? OpenEQTheme.accentCyan.opacity(0.8) : textColor),
                at: CGPoint(x: rect.minX - 22, y: y),
                anchor: .center
            )
        }

        for marker in frequencyLabels {
            let x = xPosition(for: marker.frequency, in: rect)
            var path = Path()
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.8)

            context.draw(
                Text(marker.label)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(textColor),
                at: CGPoint(x: x, y: rect.maxY + 14),
                anchor: .center
            )
        }
    }

    private func drawQEnvelope(for band: EQBand, in rect: CGRect, context: inout GraphicsContext) {
        let sampleCount = 100
        var path = Path()
        let centerIndex = bands.firstIndex(where: { $0.id == band.id }) ?? 0
        let color = OpenEQTheme.bandColor(at: centerIndex)

        for i in 0..<sampleCount {
            let progress = Float(i) / Float(sampleCount - 1)
            let freq = frequencyAt(progress: progress)
            let contribution = effectiveGain(for: band)
            let singleGain = preamp + parametricInfluence(for: band, frequency: freq, contribution: contribution)
            let point = CGPoint(x: xPosition(for: freq, in: rect), y: yPosition(for: singleGain, in: rect))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }

        context.stroke(path, with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
    }

    private func drawUnderCurveFill(in rect: CGRect, context: inout GraphicsContext) {
        let sampleCount = 160
        var fillPath = Path()
        let zeroY = yPosition(for: 0, in: rect)

        fillPath.move(to: CGPoint(x: rect.minX, y: zeroY))

        for index in 0..<sampleCount {
            let progress = Float(index) / Float(sampleCount - 1)
            let frequency = frequencyAt(progress: progress)
            let gain = curveGain(at: frequency)
            let point = CGPoint(x: xPosition(for: frequency, in: rect), y: yPosition(for: gain, in: rect))
            fillPath.addLine(to: point)
        }

        fillPath.addLine(to: CGPoint(x: rect.maxX, y: zeroY))
        fillPath.closeSubpath()

        let gradient = Gradient(colors: [
            OpenEQTheme.accentCyan.opacity(0.08),
            Color.clear
        ])
        context.fill(fillPath, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
    }

    private func drawCurveGlow(in rect: CGRect, context: inout GraphicsContext) {
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

        // Clean crisp curve
        context.stroke(path, with: .color(OpenEQTheme.accentCyan.opacity(0.9)), lineWidth: 1.8)
    }

    private func drawBandNodes(in rect: CGRect, context: inout GraphicsContext) {
        for (index, band) in bands.enumerated() {
            let center = pointFor(band: band, in: rect)
            let isSelected = band.id == selectedBandID || band.id == draggingBandID
            let isHovered = band.id == hoveredBandID
            let bandColor = mode == .parametric ? OpenEQTheme.bandColor(at: index) : OpenEQTheme.accentCyan

            if !band.isEnabled {
                let dotRect = CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: dotRect), with: .color(Color.white.opacity(0.2)))
                continue
            }

            // Crisp selection/hover ring
            if isSelected || isHovered {
                let ringRadius: CGFloat = isSelected ? 8 : 6.5
                let ringRect = CGRect(x: center.x - ringRadius, y: center.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2)
                context.stroke(Path(ellipseIn: ringRect), with: .color(bandColor.opacity(0.8)), lineWidth: 1.2)
            }

            // Main node dot
            let coreRadius: CGFloat = isSelected ? 4.5 : 3.5
            let coreRect = CGRect(x: center.x - coreRadius, y: center.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)
            context.fill(Path(ellipseIn: coreRect), with: .color(bandColor))
            context.stroke(Path(ellipseIn: coreRect), with: .color(.white.opacity(0.9)), lineWidth: 1.0)
        }
    }

    // MARK: - Curve Math Helpers

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

    private func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.1f kHz", freq / 1000)
        } else {
            return "\(Int(round(freq))) Hz"
        }
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
