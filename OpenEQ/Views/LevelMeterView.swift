import Foundation
import SwiftUI

struct LevelMeterView: View {
    let leftLevel: Float
    let rightLevel: Float
    let peakLevel: Float
    var leftRMS: Float = 0
    var rightRMS: Float = 0
    var headroomDB: Float = .infinity
    var limiterGainReductionDB: Float = 0
    var truePeak: Float = 0

    @State private var displayedLeft: Float = 0
    @State private var displayedRight: Float = 0
    @State private var heldPeak: Float = 0
    @State private var peakHoldUntil = Date.distantPast

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                meterRow("L", displayedLeft, leftRMS)
                meterRow("R", displayedRight, rightRMS)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(peakText)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(peakLevel > 0.95 ? OpenEQTheme.accentRed : (peakLevel > 0.7 ? OpenEQTheme.accentGold : .secondary))
                Text(heldPeakText)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text(headroomText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(headroomDB < 0 ? OpenEQTheme.accentRed : .secondary)
                Text(truePeakText)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(truePeak > 1 ? OpenEQTheme.accentRed : Color.secondary.opacity(0.7))
                if limiterGainReductionDB < -0.1 {
                    Text(String(format: "GR %+.1f dB", limiterGainReductionDB))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(OpenEQTheme.accentAmber)
                }
            }
            .frame(width: 76, alignment: .trailing)
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
        .onChange(of: peakLevel) { _, value in
            if value >= heldPeak {
                heldPeak = value
                peakHoldUntil = Date().addingTimeInterval(1.5)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                if Date() > peakHoldUntil { heldPeak = max(0, heldPeak - 0.025) }
            }
        }
        .accessibilityLabel("Peak \(peakText)")
    }

    private func meterRow(_ label: String, _ level: Float, _ rms: Float) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 8, alignment: .leading)

            SegmentedLEDBar(level: level)
                .frame(width: 80, height: 5)
            Text(rmsText(rms))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private func rmsText(_ level: Float) -> String {
        guard level > 0.0001 else { return "—" }
        return String(format: "%+.0f", 20 * log10(max(Double(level), 1e-6)))
    }

    private var peakText: String {
        if peakLevel <= 0.0001 { return "−∞ dB" }
        let db = 20.0 * log10(max(Double(peakLevel), 1e-6))
        return String(format: "%+.1f dB", db)
    }

    private var headroomText: String {
        guard headroomDB.isFinite else { return "Headroom —" }
        return String(format: "HR %+.1f dB", headroomDB)
    }

    private var heldPeakText: String {
        guard heldPeak > 0.0001 else { return "Hold —" }
        return String(format: "Hold %+.1f dB", 20 * log10(max(Double(heldPeak), 1e-6)))
    }

    private var truePeakText: String {
        guard truePeak > 0.0001 else { return "TP —" }
        return String(format: "TP %+.1f dB", 20 * log10(max(Double(truePeak), 1e-6)))
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
