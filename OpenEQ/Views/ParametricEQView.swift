import SwiftUI

struct ParametricEQView: View {
    let viewModel: OpenEQViewModel

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(viewModel.bands.enumerated()), id: \.element.id) { index, band in
                ParametricBandRow(
                    index: index,
                    band: band,
                    isSelected: viewModel.selectedBandID == band.id,
                    onSelect: { viewModel.selectBand(id: band.id) },
                    onFrequencyChanged: { viewModel.updateBandFrequency(index: index, frequency: $0) },
                    onGainChanged: { viewModel.updateBandGain(index: index, gain: $0) },
                    onQChanged: { viewModel.updateBandQ(index: index, q: $0) },
                    onFilterTypeChanged: { viewModel.updateBandFilterType(index: index, filterType: $0) },
                    onEnabledChanged: { viewModel.updateBandEnabled(index: index, isEnabled: $0) }
                )
            }
        }
    }
}

private struct ParametricBandRow: View {
    let index: Int
    let band: EQBand
    var isSelected: Bool = false
    var onSelect: () -> Void
    let onFrequencyChanged: (Float) -> Void
    let onGainChanged: (Float) -> Void
    let onQChanged: (Float) -> Void
    let onFilterTypeChanged: (EQFilterType) -> Void
    let onEnabledChanged: (Bool) -> Void

    @State private var isHovered = false

    var body: some View {
        let bandColor = OpenEQTheme.bandColor(at: index)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // Band Number Pill with Glow
                HStack(spacing: 4) {
                    StudioLED(isOn: band.isEnabled, activeColor: bandColor, size: 6)
                    Text("B\(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(band.isEnabled ? bandColor : .secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    Capsule()
                        .fill(band.isEnabled ? bandColor.opacity(0.12) : Color.white.opacity(0.04))
                }
                .overlay {
                    Capsule()
                        .stroke(band.isEnabled ? bandColor.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.8)
                }

                Toggle("", isOn: enabledBinding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()

                Picker("", selection: filterTypeBinding) {
                    ForEach(EQFilterType.allCases) { ft in
                        Text(ft.title).tag(ft)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 104)

                Spacer(minLength: 8)

                // Frequency Input Capsule
                HStack(spacing: 4) {
                    TextField("", value: frequencyBinding, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(width: 48)
                        .multilineTextAlignment(.trailing)
                    Text("Hz")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(OpenEQTheme.recessedSlotBg.opacity(0.8))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                }
            }

            HStack(spacing: 16) {
                labeledSlider(
                    "Gain",
                    gainBinding,
                    Double(EQBand.gainRange.lowerBound)...Double(EQBand.gainRange.upperBound),
                    String(format: "%+.1f dB", band.gain),
                    valueColor: band.gain > 0 ? OpenEQTheme.accentCyan : (band.gain < 0 ? OpenEQTheme.accentAmber : .secondary)
                )

                labeledSlider(
                    "Q",
                    qBinding,
                    Double(EQBand.qRange.lowerBound)...Double(EQBand.qRange.upperBound),
                    String(format: "%.1f", band.q),
                    valueColor: .primary
                )
                .frame(maxWidth: 220)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? OpenEQTheme.cardBgElevated : (isHovered ? OpenEQTheme.cardBg : OpenEQTheme.cardBg.opacity(0.6)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isSelected ? bandColor.opacity(0.6) : (isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.04)),
                    lineWidth: isSelected ? 1.2 : 0.8
                )
        }
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
        .opacity(band.isEnabled ? 1 : 0.5)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private func labeledSlider(
        _ title: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        _ label: String,
        valueColor: Color = .secondary
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .leading)

            Slider(value: value, in: range)
                .controlSize(.small)

            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(valueColor)
                .frame(width: 54, alignment: .trailing)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { band.isEnabled }, set: { onEnabledChanged($0) })
    }
    private var filterTypeBinding: Binding<EQFilterType> {
        Binding(get: { band.filterType }, set: { onFilterTypeChanged($0) })
    }
    private var frequencyBinding: Binding<Float> {
        Binding(get: { band.frequency }, set: { onFrequencyChanged($0) })
    }
    private var gainBinding: Binding<Double> {
        Binding(get: { Double(band.gain) }, set: { onGainChanged(Float($0)) })
    }
    private var qBinding: Binding<Double> {
        Binding(get: { Double(band.q) }, set: { onQChanged(Float($0)) })
    }
}

#Preview {
    ParametricEQView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .padding(24)
}

