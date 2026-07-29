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
            VStack(alignment: .leading, spacing: 3) {
                meter("L", displayedLeft)
                meter("R", displayedRight)
            }

            Text(peakText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .trailing)
        }
        .onAppear {
            displayedLeft = leftLevel
            displayedRight = rightLevel
        }
        .onChange(of: leftLevel) { _, v in displayedLeft = v }
        .onChange(of: rightLevel) { _, v in displayedRight = v }
        .accessibilityLabel("Peak \(peakText)")
    }

    private func meter(_ label: String, _ level: Float) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 8, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(level > 0.9 ? Color.orange : Color.accentColor.opacity(0.85))
                        .frame(width: max(2, proxy.size.width * CGFloat(min(max(level, 0), 1))))
                }
            }
            .frame(width: 64, height: 4)
        }
    }

    private var peakText: String {
        if peakLevel <= 0.0001 { return "−∞ dB" }
        let db = 20.0 * log10(max(Double(peakLevel), 1e-6))
        return String(format: "%+.1f dB", db)
    }
}
