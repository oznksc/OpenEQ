//
//  LevelMeterView.swift
//  OpenEQ
//
//  Created by Ozan
//

import Foundation
import SwiftUI

struct LevelMeterView: View {
    let leftLevel: Float
    let rightLevel: Float
    let peakLevel: Float

    @State private var displayedLeftLevel: Float = 0.0
    @State private var displayedRightLevel: Float = 0.0

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                meterRow(label: "L", level: displayedLeftLevel)
                meterRow(label: "R", level: displayedRightLevel)
            }

            Text(peakText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear {
            displayedLeftLevel = leftLevel
            displayedRightLevel = rightLevel
        }
        .onChange(of: leftLevel) { _, newValue in
            updateDisplayedLevels(left: newValue, right: rightLevel)
        }
        .onChange(of: rightLevel) { _, newValue in
            updateDisplayedLevels(left: leftLevel, right: newValue)
        }
        .accessibilityLabel("Peak level meter. Current peak is \(peakText).")
    }

    private func meterRow(label: String, level: Float) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 8, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))

                    Capsule()
                        .fill(meterColor(for: level))
                        .frame(width: proxy.size.width * CGFloat(max(0.0, min(1.0, level))))
                }
            }
            .frame(width: 82, height: 5)
        }
    }

    private func updateDisplayedLevels(left: Float, right: Float) {
        let duration = max(left, right) >= max(displayedLeftLevel, displayedRightLevel) ? 0.08 : 0.35

        withAnimation(.easeOut(duration: duration)) {
            displayedLeftLevel = left
            displayedRightLevel = right
        }
    }

    private func meterColor(for level: Float) -> Color {
        if level >= 0.96 {
            return .red.opacity(0.85)
        }

        if level >= 0.82 {
            return .yellow.opacity(0.85)
        }

        return .green.opacity(0.78)
    }

    private var peakText: String {
        guard peakLevel > 0.000_1 else {
            return "-inf dB"
        }

        let db = 20 * log10(max(peakLevel, 0.000_1))
        return String(format: "%+.1f dB", db)
    }
}

#Preview {
    LevelMeterView(leftLevel: 0.62, rightLevel: 0.74, peakLevel: 0.74)
        .padding()
        .frame(width: 240)
}
