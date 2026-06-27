//
//  EqualizerView.swift
//  OpenEQ
//
//  Created by Gökmen on 26.06.2026.
//

import SwiftUI

struct EqualizerView: View {
    let viewModel: OpenEQViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("\(viewModel.eqMode.title) Equalizer", systemImage: "slider.vertical.3")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Picker(
                    "EQ Mode",
                    selection: Binding(
                        get: { viewModel.eqMode },
                        set: { viewModel.setEQMode($0) }
                    )
                ) {
                    ForEach(EQMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Button(action: {
                    viewModel.resetEQ()
                }) {
                    Label("Reset EQ", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }

            EQCurveView(
                bands: viewModel.bands,
                mode: viewModel.eqMode,
                preamp: viewModel.preamp
            )

            if viewModel.eqMode == .graphic {
                HStack(alignment: .center, spacing: 12) {
                    // 1. Preamp Slider Control
                    VStack(spacing: 8) {
                        Text(String(format: "%+.1f dB", viewModel.preamp))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(viewModel.preamp == 0.0 ? Color.secondary : Color.orange)
                            .frame(height: 14)
                        
                        GeometryReader { geometry in
                            let height = geometry.size.height
                            let thumbSize: CGFloat = 16
                            let trackHeight = height - thumbSize
                            
                            let percent = CGFloat((viewModel.preamp - EQBand.gainRange.lowerBound) / (EQBand.gainRange.upperBound - EQBand.gainRange.lowerBound))
                            let thumbY = trackHeight * (1.0 - percent)
                            
                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.orange.opacity(0.12))
                                    .frame(width: 4)
                                    .frame(maxHeight: .infinity)
                                
                                Rectangle()
                                    .fill(Color.orange.opacity(0.4))
                                    .frame(width: 14, height: 1.5)
                                    .offset(y: trackHeight / 2 + thumbSize / 2 - 0.75)
                                
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.orange, .red],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: thumbSize, height: thumbSize)
                                    .shadow(color: Color.orange.opacity(0.3), radius: 3)
                                    .offset(y: thumbY)
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                let newY = min(max(0, value.location.y - thumbSize / 2), trackHeight)
                                                let newPercent = 1.0 - (newY / trackHeight)
                                                let rawPreamp = EQBand.gainRange.lowerBound + Float(newPercent) * (EQBand.gainRange.upperBound - EQBand.gainRange.lowerBound)
                                                
                                                let snapped: Float
                                                if abs(rawPreamp) < 0.4 {
                                                    snapped = 0.0
                                                } else {
                                                    snapped = Float(round(rawPreamp * 2) / 2)
                                                }
                                                viewModel.updatePreamp(gain: snapped)
                                            }
                                    )
                            }
                        }
                        .frame(width: 28, height: 160)
                        
                        Text("Preamp")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                            .frame(width: 52)
                    }
                    .frame(width: 58)
                    .onTapGesture(count: 2) {
                        viewModel.updatePreamp(gain: 0.0)
                    }
                    .help("Double-click to reset preamp to 0.0 dB")
                    
                    Divider()
                        .frame(height: 160)
                        .padding(.horizontal, 4)

                    // 2. EQ Bands Controls
                    ForEach(Array(viewModel.bands.enumerated()), id: \.element.id) { index, band in
                        EQBandControl(
                            band: band,
                            gain: viewModel.gain(for: band.id),
                            onGainChanged: { newGain in
                                viewModel.updateBandGain(index: index, gain: newGain)
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.02))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                )
            } else {
                ParametricEQView(viewModel: viewModel)
            }
        }
        .padding(20)
    }
}

// MARK: - Custom Equalizer Band Slider Control
struct EQBandControl: View {
    let band: EQBand
    let gain: Float
    let onGainChanged: (Float) -> Void
    
    @State private var isHovered = false
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 8) {
            // dB Value label (changes color when boosted or cut)
            Text(String(format: "%+.1f dB", gain))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(gain == 0.0 ? Color.secondary : (gain > 0 ? Color.green : Color.red))
                .frame(height: 14)
            
            // Fader track and thumb
            GeometryReader { geometry in
                let height = geometry.size.height
                let thumbSize: CGFloat = 16
                let trackHeight = height - thumbSize
                
                // Calculate position percentage: -24.0 is bottom (0%), +24.0 is top (100%)
                let minGain = EQBand.gainRange.lowerBound
                let maxGain = EQBand.gainRange.upperBound
                let percent = CGFloat((gain - minGain) / (maxGain - minGain))
                
                // Invert percentage because Y-axis goes from top-down
                let thumbY = trackHeight * (1.0 - percent)
                
                ZStack(alignment: .top) {
                    // Track groove
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 4)
                        .frame(maxHeight: .infinity)
                    
                    // 0 dB center marker line
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 14, height: 1.5)
                        .offset(y: trackHeight / 2 + thumbSize / 2 - 0.75)
                    
                    // +12 dB tick line
                    Rectangle()
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 10, height: 1)
                        .offset(y: trackHeight * 0.25 + thumbSize / 2)
                    
                    // -12 dB tick line
                    Rectangle()
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 10, height: 1)
                        .offset(y: trackHeight * 0.75 + thumbSize / 2)

                    // Fader cap / thumb
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isDragging ? [.cyan, .blue] : [Color(nsColor: .controlColor), Color(nsColor: .alternateSelectedControlTextColor)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            Circle()
                                .stroke(isDragging ? Color.blue : Color.primary.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 2, y: 1)
                        .shadow(color: isHovered || isDragging ? Color.cyan.opacity(0.4) : Color.clear, radius: 4)
                        .frame(width: thumbSize, height: thumbSize)
                        .offset(y: thumbY)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDragging = true
                                    let newY = min(max(0, value.location.y - thumbSize / 2), trackHeight)
                                    let newPercent = 1.0 - (newY / trackHeight)
                                    let rawGain = minGain + Float(newPercent) * (maxGain - minGain)
                                    
                                    // Snapping helper: zero-in when close to center (neutral)
                                    let snappedGain: Float
                                    if abs(rawGain) < 0.4 {
                                        snappedGain = 0.0
                                    } else {
                                        // Round to nearest 0.5 dB
                                        snappedGain = Float(round(rawGain * 2) / 2)
                                    }
                                    onGainChanged(snappedGain)
                                }
                                .onEnded { _ in
                                    isDragging = false
                                }
                        )
                }
            }
            .frame(width: 28, height: 160)
            
            // Frequency label below
            Text(band.label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 52)
        }
        .frame(width: 58)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(count: 2) {
            onGainChanged(0.0)
        }
        .help("Double-click to reset band to 0.0 dB")
    }
}

#Preview {
    EqualizerView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .frame(width: 984, height: 312)
}
