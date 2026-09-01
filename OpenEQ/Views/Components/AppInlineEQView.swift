//
//  AppInlineEQView.swift
//  OpenEQ
//
//  Created by Ozan
//

import SwiftUI

struct AppInlineEQView: View {
    @Binding var channel: AppAudioChannel
    var onGainChange: ((Int, Float) -> Void)?
    var onPresetChange: ((String, [EQBand]) -> Void)?
    
    private let frequencies = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    private let presetOptions = ["Flat", "Vocal Clarity", "Bass Boost", "Treble Boost", "Podcast / Voice", "Warm & Cozy", "Acoustic"]
    
    var body: some View {
        VStack(spacing: 12) {
            // Header: EQ Toggle & Preset Selection
            HStack {
                Toggle(isOn: $channel.isEQEnabled) {
                    Text("EQ")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                
                Spacer()
                
                HStack(spacing: 6) {
                    Text("Preset")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Menu {
                        ForEach(presetOptions, id: \.self) { presetName in
                            Button {
                                applyQuickPreset(named: presetName)
                            } label: {
                                HStack {
                                    Text(presetName)
                                    if channel.selectedPresetName == presetName {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(channel.selectedPresetName)
                                .font(.system(size: 11, weight: .semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            
            // 10 Slider Bands
            HStack(spacing: 8) {
                ForEach(0..<min(10, channel.eqBands.count), id: \.self) { index in
                    VStack(spacing: 6) {
                        CustomVerticalSlider(
                            value: Binding(
                                get: { Double(channel.eqBands[index].gain) },
                                set: { newValue in
                                    channel.eqBands[index].gain = Float(newValue)
                                    onGainChange?(index, Float(newValue))
                                }
                            ),
                            range: -12.0...12.0
                        )
                        .frame(height: 100)
                        
                        Text(index < frequencies.count ? frequencies[index] : "\(Int(channel.eqBands[index].frequency))")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .opacity(channel.isEQEnabled ? 1.0 : 0.4)
            .disabled(!channel.isEQEnabled)
            
            // Bottom Actions: Reset
            HStack {
                Spacer()
                Button("Reset") {
                    applyQuickPreset(named: "Flat")
                }
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }
    
    private func applyQuickPreset(named name: String) {
        var newBands = EQBand.defaultBands()
        switch name {
        case "Vocal Clarity":
            let gains: [Float] = [-2, -1, 0, 1, 3, 4, 3, 2, 0, -1]
            for i in 0..<min(gains.count, newBands.count) { newBands[i].gain = gains[i] }
        case "Bass Boost":
            let gains: [Float] = [5, 4.5, 3.5, 2, 0.5, 0, 0, 0, 0, 0]
            for i in 0..<min(gains.count, newBands.count) { newBands[i].gain = gains[i] }
        case "Treble Boost":
            let gains: [Float] = [0, 0, 0, 0, 0, 1, 2.5, 4, 5, 5]
            for i in 0..<min(gains.count, newBands.count) { newBands[i].gain = gains[i] }
        case "Podcast / Voice":
            let gains: [Float] = [-4, -2, 0, 1, 2.5, 3, 2.5, 1, 0, -2]
            for i in 0..<min(gains.count, newBands.count) { newBands[i].gain = gains[i] }
        case "Warm & Cozy":
            let gains: [Float] = [3, 2.5, 2, 1, 0.5, 0, -0.5, -1, -2, -3]
            for i in 0..<min(gains.count, newBands.count) { newBands[i].gain = gains[i] }
        default:
            break
        }
        
        channel.selectedPresetName = name
        channel.eqBands = newBands
        onPresetChange?(name, newBands)
    }
}

private struct CustomVerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    
    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let normalized = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let thumbY = height * (1.0 - normalized)
            
            ZStack(alignment: .top) {
                // Track Line
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 2, height: height)
                    .position(x: geo.size.width / 2, y: height / 2)
                
                // Zero center tick
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 6, height: 1.5)
                    .position(x: geo.size.width / 2, y: height / 2)
                
                // Slider Thumb Knob
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .overlay(
                        Circle()
                            .fill(Color.black.opacity(0.8))
                            .frame(width: 4, height: 4)
                    )
                    .position(x: geo.size.width / 2, y: max(6, min(height - 6, thumbY)))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let clampedY = max(0, min(height, drag.location.y))
                        let percent = 1.0 - (clampedY / height)
                        let val = range.lowerBound + Double(percent) * (range.upperBound - range.lowerBound)
                        value = max(range.lowerBound, min(range.upperBound, val))
                    }
            )
        }
    }
}
