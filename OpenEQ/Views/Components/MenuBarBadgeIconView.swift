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
    
    var body: some View {
        Image(nsImage: MenuBarBadgeRenderer.image(
            levels: viewModel.spectrumLevels,
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
        isActive: Bool,
        isEnabled: Bool,
        isClipping: Bool
    ) -> NSImage {
        let size = NSSize(width: 96, height: 18)
        let image = NSImage(size: size)
        let indices = Array(stride(from: 0, to: levels.count, by: 3)).prefix(22)
        let barWidth: CGFloat = 3
        let spacing: CGFloat = 1.2
        let totalWidth = CGFloat(indices.count) * barWidth + CGFloat(max(0, indices.count - 1)) * spacing
        let startX = (size.width - totalWidth) / 2
        let alpha: CGFloat = isEnabled ? 1 : 0.42

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        for (offset, index) in indices.enumerated() {
            let level = displayLevel(levels: levels, index: index, offset: offset, isActive: isActive)
            let height = max(4, size.height * level)
            let rect = NSRect(
                x: startX + CGFloat(offset) * (barWidth + spacing),
                y: (size.height - height) / 2,
                width: barWidth,
                height: height
            )
            barColor(level: level, isActive: isActive, isClipping: isClipping)
                .withAlphaComponent(alpha)
                .setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func displayLevel(levels: SpectrumLevels, index: Int, offset: Int, isActive: Bool) -> CGFloat {
        if isActive {
            return CGFloat(max(0.12, min(1, levels[index])))
        }
        return 0.22 + CGFloat((offset % 5)) * 0.055
    }

    private static func barColor(level: CGFloat, isActive: Bool, isClipping: Bool) -> NSColor {
        if isClipping {
            return .red
        }
        if !isActive {
            return .secondaryLabelColor
        }
        if level > 0.78 {
            return .systemOrange
        }
        return .labelColor
    }
}
