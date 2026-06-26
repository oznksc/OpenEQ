//
//  SpectrumView.swift
//  OpenEQ
//
//  Created by Gökmen on 26.06.2026.
//

import SwiftUI

struct SpectrumView: View {
    let levels: [Double]
    
    @State private var peakLevels: [Double] = Array(repeating: 0.02, count: 64)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Real-Time FFT Spectrum", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("64 Bands (vDSP Transform)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
            }

            // High Performance GPU-Accelerated Canvas Rendering
            GeometryReader { proxy in
                Canvas { context, size in
                    let barCount = levels.count
                    guard barCount > 0 else { return }
                    
                    let spacing: CGFloat = 2.0
                    let totalSpacing = spacing * CGFloat(barCount - 1)
                    let barWidth = (size.width - totalSpacing) / CGFloat(barCount)
                    
                    // Draw horizontal decibel grids
                    for i in 1...3 {
                        let y = size.height * CGFloat(i) * 0.25
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(path, with: .color(Color.primary.opacity(0.04)), lineWidth: 1)
                    }

                    // Render spectrum faders and peak hold points
                    for index in 0..<barCount {
                        let level = levels[index]
                        let peakLevel = index < peakLevels.count ? peakLevels[index] : level
                        
                        let x = CGFloat(index) * (barWidth + spacing)
                        
                        // Main Bar
                        let barHeight = max(2.0, size.height * CGFloat(level))
                        let barRect = CGRect(x: x, y: size.height - barHeight, width: barWidth, height: barHeight)
                        
                        let gradient = GraphicsContext.Shading.linearGradient(
                            Gradient(colors: [
                                Color.cyan.opacity(0.95),
                                Color.blue.opacity(0.85),
                                Color.purple.opacity(0.75)
                            ]),
                            startPoint: CGPoint(x: 0, y: size.height),
                            endPoint: CGPoint(x: 0, y: 0)
                        )
                        
                        let barPath = Path(roundedRect: barRect, cornerRadius: 1)
                        context.fill(barPath, with: gradient)
                        
                        // Peak Hold Point (decaying dot)
                        let peakY = size.height - max(2.0, size.height * CGFloat(peakLevel))
                        let peakPath = Path(CGRect(x: x, y: peakY - 1, width: barWidth, height: 2))
                        context.fill(peakPath, with: .color(Color.teal.opacity(0.9)))
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .overlay(
                    Group {
                        // Show a beautiful empty state if no active signals are present
                        if !levels.contains(where: { $0 > 0.025 }) {
                            VStack(spacing: 8) {
                                Image(systemName: "music.note.house")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary.opacity(0.7))
                                
                                Text("No Audio Source Loaded")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary.opacity(0.8))
                                
                                Text("Press ⌘O or click 'Open Audio' to load a file")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.96))
                            .cornerRadius(12)
                        }
                    }
                )
            }
            .frame(minHeight: 200)
            
            // X-Axis Frequencies
            HStack {
                Text("20 Hz").frame(width: 44, alignment: .leading)
                Spacer()
                Text("250 Hz").frame(width: 50, alignment: .center)
                Spacer()
                Text("1 kHz").frame(width: 44, alignment: .center)
                Spacer()
                Text("4 kHz").frame(width: 44, alignment: .center)
                Spacer()
                Text("20 kHz").frame(width: 50, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
        }
        .padding(20)
        .onChange(of: levels) { _, newValue in
            updatePeaks(with: newValue)
        }
    }
    
    private func updatePeaks(with currentLevels: [Double]) {
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
                // Smooth physical decay
                peakLevels[i] = max(0.02, existing - 0.035)
            }
        }
    }
}

#Preview {
    SpectrumView(levels: Array(repeating: 0.35, count: 64))
        .frame(width: 820, height: 320)
}
