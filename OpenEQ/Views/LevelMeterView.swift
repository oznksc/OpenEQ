import Foundation
import SwiftUI

struct LevelMeterView: View {
    let leftLevel: Float
    let rightLevel: Float
    let peakLevel: Float

    @State private var displayedLeft: Float = 0
    @State private var displayedRight: Float = 0

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                meterRow("L", displayedLeft)
                meterRow("R", displayedRight)
            }

            Text(peakText)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(peakLevel > 0.95 ? OpenEQTheme.accentRed : (peakLevel > 0.7 ? OpenEQTheme.accentGold : .secondary))
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(OpenEQTheme.recessedSlotBg.opacity(0.8))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
        .onAppear {
            displayedLeft = leftLevel
            displayedRight = rightLevel
        }
        .onChange(of: leftLevel) { _, v in displayedLeft = v }
        .onChange(of: rightLevel) { _, v in displayedRight = v }
        .accessibilityLabel("Peak \(peakText)")
    }

    private func meterRow(_ label: String, _ level: Float) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 8, alignment: .leading)

            SegmentedLEDBar(level: level)
                .frame(width: 80, height: 5)
        }
    }

    private var peakText: String {
        if peakLevel <= 0.0001 { return "−∞ dB" }
        let db = 20.0 * log10(max(Double(peakLevel), 1e-6))
        return String(format: "%+.1f dB", db)
    }
}

// MARK: - Segmented LED VU Bar
struct SegmentedLEDBar: View {
    let level: Float
    private let segmentCount = 14

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<segmentCount, id: \.self) { index in
                let threshold = Float(index + 1) / Float(segmentCount)
                let isLit = level >= threshold
                let color = segmentColor(for: index)

                RoundedRectangle(cornerRadius: 0.75)
                    .fill(isLit ? color : color.opacity(0.14))
            }
        }
    }

    private func segmentColor(for index: Int) -> Color {
        let progress = Float(index) / Float(segmentCount)
        if progress > 0.85 {
            return OpenEQTheme.accentRed
        } else if progress > 0.65 {
            return OpenEQTheme.accentAmber
        } else {
            return OpenEQTheme.accentGreen
        }
    }
}

