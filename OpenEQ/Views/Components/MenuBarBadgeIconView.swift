//
//  MenuBarBadgeIconView.swift
//  OpenEQ
//
//  Created by Ozan
//

import AppKit
import SwiftUI

struct MenuBarBadgeIconView: View {
    @Bindable var viewModel: OpenEQViewModel
    @AppStorage("spectrumVisualizationStyle") private var spectrumStyleRawValue = SpectrumVisualizationStyle.neon.rawValue

    private var spectrumStyle: SpectrumVisualizationStyle {
        SpectrumVisualizationStyle(rawValue: spectrumStyleRawValue) ?? .neon
    }
    
    var body: some View {
        Image(nsImage: MenuBarBadgeRenderer.image(
            levels: viewModel.spectrumLevels,
            style: spectrumStyle,
            isActive: viewModel.isSystemEQActive || viewModel.isExternalLoopbackActive,
            isEnabled: viewModel.isEnabled,
            isClipping: viewModel.isClipping || viewModel.systemIsClipping
        ))
        .renderingMode(.original)
    }
}

private enum MenuBarBadgeRenderer {
    static func image(
        levels: SpectrumLevels,
        style: SpectrumVisualizationStyle,
        isActive: Bool,
        isEnabled: Bool,
        isClipping: Bool
    ) -> NSImage {
        let size = NSSize(width: 48, height: 18)
        let image = NSImage(size: size)
        let alpha: CGFloat = isEnabled ? 1 : 0.42

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let samples = sampleLevels(levels: levels, isActive: isActive)
        switch style {
        case .neon, .ember, .prism:
            drawBars(style: style, samples: samples, size: size, alpha: alpha, isActive: isActive, isClipping: isClipping)
        case .aurora:
            drawAurora(samples: samples, size: size, alpha: alpha, isActive: isActive, isClipping: isClipping)
        case .orbit:
            drawOrbit(samples: samples, size: size, alpha: alpha, isActive: isActive, isClipping: isClipping)
        case .matrix:
            drawMatrix(samples: samples, size: size, alpha: alpha, isActive: isActive, isClipping: isClipping)
        case .globe:
            drawGlobe(samples: samples, size: size, alpha: alpha, isActive: isActive, isClipping: isClipping)
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func sampleLevels(levels: SpectrumLevels, isActive: Bool) -> [CGFloat] {
        Array(stride(from: 0, to: levels.count, by: 5)).prefix(12).enumerated().map { offset, index in
            if isActive {
                return CGFloat(max(0.14, min(1, levels[index])))
            }
            return 0.20 + CGFloat((offset % 4)) * 0.045
        }
    }

    private static func drawBars(
        style: SpectrumVisualizationStyle,
        samples: [CGFloat],
        size: NSSize,
        alpha: CGFloat,
        isActive: Bool,
        isClipping: Bool
    ) {
        let baseline = size.height - 2
        let usableHeight = baseline - 2
        let barWidth: CGFloat = 2
        let spacing: CGFloat = 1.5

        for (offset, level) in samples.enumerated() {
            let x = xPosition(offset: offset, count: samples.count, width: barWidth, spacing: spacing, canvasWidth: size.width)
            let height = max(2, usableHeight * level)
            let barRect = NSRect(x: x, y: baseline - height, width: barWidth, height: height)

            if isClipping {
                NSColor.red.withAlphaComponent(alpha).setFill()
                NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1).fill()
                continue
            }

            switch style {
            case .neon:
                NSGradient(colors: [
                    activeColor(for: .aurora, offset: offset).withAlphaComponent(0.12 * alpha),
                    activeColor(for: .neon, offset: offset).withAlphaComponent(0.50 * alpha)
                ])?.draw(in: NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1), angle: 90)
            case .ember:
                NSGradient(colors: [
                    NSColor.systemOrange.withAlphaComponent(0.18 * alpha),
                    NSColor.systemRed.withAlphaComponent(0.58 * alpha)
                ])?.draw(in: NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1), angle: 90)
            case .prism:
                let prismRect = NSRect(x: barRect.midX - 0.55, y: barRect.minY, width: 1.1, height: barRect.height)
                NSGradient(colors: [
                    NSColor.systemBlue.withAlphaComponent(0.12 * alpha),
                    NSColor.systemCyan.withAlphaComponent(0.82 * alpha),
                    NSColor.white.withAlphaComponent(0.55 * alpha)
                ])?.draw(in: NSBezierPath(roundedRect: prismRect, xRadius: 0.55, yRadius: 0.55), angle: 90)
            default:
                break
            }
        }
    }

    private static func drawAurora(
        samples: [CGFloat],
        size: NSSize,
        alpha: CGFloat,
        isActive: Bool,
        isClipping: Bool
    ) {
        let baseline = size.height - 2
        let usableHeight = baseline - 2
        let points = tracePoints(samples: samples, size: size)
        let area = NSBezierPath()
        area.move(to: NSPoint(x: 0, y: baseline))
        points.forEach { area.line(to: $0) }
        area.line(to: NSPoint(x: size.width, y: baseline))
        area.close()

        NSGradient(colors: [
            NSColor.systemPurple.withAlphaComponent(0.52 * alpha),
            NSColor.systemCyan.withAlphaComponent(0.04 * alpha)
        ])?.draw(in: area, angle: 90)

        let trace = polyline(points: points)
        (isClipping ? NSColor.red : activeColor(for: .aurora, offset: 0))
            .withAlphaComponent((isActive ? 0.78 : 0.32) * alpha)
            .setStroke()
        trace.lineWidth = 1.4
        trace.lineJoinStyle = .round
        trace.stroke()

        drawBaseline(size: size, color: activeColor(for: .aurora, offset: 0), alpha: 0.20 * alpha)
        _ = usableHeight
    }

    private static func drawOrbit(
        samples: [CGFloat],
        size: NSSize,
        alpha: CGFloat,
        isActive: Bool,
        isClipping: Bool
    ) {
        let points = tracePoints(samples: samples, size: size)
        let trace = polyline(points: points)
        activeColor(for: .orbit, offset: 0).withAlphaComponent(0.42 * alpha).setStroke()
        trace.lineWidth = 0.8
        trace.stroke()

        for (offset, point) in points.enumerated() {
            let level = samples[offset]
            let radius = 1 + level * 2.4
            let rect = NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            (isClipping ? NSColor.red : activeColor(for: .orbit, offset: offset))
                .withAlphaComponent((isActive ? 0.72 : 0.34) * alpha)
                .setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
    }

    private static func drawMatrix(
        samples: [CGFloat],
        size: NSSize,
        alpha: CGFloat,
        isActive: Bool,
        isClipping: Bool
    ) {
        let baseline = size.height - 2
        let usableHeight = baseline - 2
        let barWidth: CGFloat = 2
        let spacing: CGFloat = 1.5
        let blockHeight = usableHeight / 5

        for (offset, level) in samples.enumerated() {
            let x = xPosition(offset: offset, count: samples.count, width: barWidth, spacing: spacing, canvasWidth: size.width)
            let blockCount = max(1, Int(ceil(level * 5)))
            for block in 0..<blockCount {
                let rect = NSRect(
                    x: x,
                    y: baseline - CGFloat(block + 1) * blockHeight,
                    width: barWidth,
                    height: max(1, blockHeight - 1)
                )
                (isClipping ? NSColor.red : NSColor.systemGreen)
                    .withAlphaComponent((isActive ? 0.25 + CGFloat(block) * 0.1 : 0.22) * alpha)
                    .setFill()
                NSBezierPath(roundedRect: rect, xRadius: 0.6, yRadius: 0.6).fill()
            }
        }
    }

    private static func drawGlobe(
        samples: [CGFloat],
        size: NSSize,
        alpha: CGFloat,
        isActive: Bool,
        isClipping: Bool
    ) {
        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let pointCount = 20
        let baseRadius = min(size.width, size.height) * 0.28
        var points: [NSPoint] = []

        for index in 0..<pointCount {
            let angle = CGFloat(index) / CGFloat(pointCount) * .pi * 2
            let level = samples[index * samples.count / pointCount]
            let wobble = sin(angle * 3) * 0.8 + cos(angle * 5) * 0.5
            let radius = baseRadius + level * 4.2 + wobble
            points.append(NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
        }

        guard let first = points.first else { return }
        let blob = NSBezierPath()
        blob.move(to: first)
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let midpoint = NSPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            blob.curve(to: midpoint, controlPoint1: current, controlPoint2: current)
        }
        blob.close()

        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.72 * alpha),
            NSColor.systemCyan.withAlphaComponent(0.62 * alpha),
            (isClipping ? NSColor.red : NSColor.systemIndigo).withAlphaComponent(0.48 * alpha)
        ])?.draw(in: blob, relativeCenterPosition: NSPoint(x: -0.22, y: 0.28))

        (isClipping ? NSColor.red : NSColor.systemCyan).withAlphaComponent((isActive ? 0.6 : 0.28) * alpha).setStroke()
        blob.lineWidth = 0.7
        blob.stroke()
    }

    private static func xPosition(offset: Int, count: Int, width: CGFloat, spacing: CGFloat, canvasWidth: CGFloat) -> CGFloat {
        let totalWidth = CGFloat(count) * width + CGFloat(max(0, count - 1)) * spacing
        return (canvasWidth - totalWidth) / 2 + CGFloat(offset) * (width + spacing)
    }

    private static func tracePoints(samples: [CGFloat], size: NSSize) -> [NSPoint] {
        let baseline = size.height - 2
        let usableHeight = baseline - 2
        let barWidth: CGFloat = 2
        let spacing: CGFloat = 1.5
        return samples.enumerated().map { offset, level in
            let x = xPosition(offset: offset, count: samples.count, width: barWidth, spacing: spacing, canvasWidth: size.width)
            return NSPoint(x: x + barWidth / 2, y: baseline - usableHeight * (0.08 + level * 0.84))
        }
    }

    private static func polyline(points: [NSPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        points.dropFirst().forEach { path.line(to: $0) }
        return path
    }

    private static func drawBaseline(size: NSSize, color: NSColor, alpha: CGFloat) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: size.height - 2))
        path.line(to: NSPoint(x: size.width, y: size.height - 2))
        color.withAlphaComponent(alpha).setStroke()
        path.lineWidth = 0.6
        path.stroke()
    }

    private static func activeColor(for style: SpectrumVisualizationStyle, offset: Int) -> NSColor {
        switch style {
        case .neon:
            return .labelColor
        case .aurora:
            return offset.isMultiple(of: 2) ? .systemMint : .systemPurple
        case .ember:
            return .systemOrange
        case .prism:
            return prismColor(offset: offset)
        case .orbit:
            return .systemPink
        case .matrix:
            return .systemGreen
        case .globe:
            return .systemIndigo
        }
    }

    private static func prismColor(offset: Int) -> NSColor {
        let colors: [NSColor] = [
            .systemRed,
            .systemOrange,
            .systemYellow,
            .systemGreen,
            .systemBlue,
            .systemPurple
        ]
        return colors[offset % colors.count]
    }
}
