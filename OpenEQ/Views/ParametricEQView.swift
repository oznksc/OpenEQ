import SwiftUI

struct ParametricEQView: View {
    let viewModel: OpenEQViewModel

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(viewModel.bands.enumerated()), id: \.element.id) { index, band in
                ParametricBandCard(
                    index: index,
                    band: band,
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

private struct ParametricBandCard: View {
    let index: Int
    let band: EQBand
    let onFrequencyChanged: (Float) -> Void
    let onGainChanged: (Float) -> Void
    let onQChanged: (Float) -> Void
    let onFilterTypeChanged: (EQFilterType) -> Void
    let onEnabledChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("B\(index + 1)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(band.isEnabled ? Color.accentColor : Color.secondary)
                    .frame(width: 20, alignment: .leading)

                Toggle("", isOn: enabledBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()

                Picker("", selection: filterTypeBinding) {
                    ForEach(EQFilterType.allCases) { ft in
                        Text(ft.title).tag(ft)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 105)

                Spacer()

                HStack(spacing: 4) {
                    TextField("", value: frequencyBinding, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(4)
                        .frame(width: 50)
                        .font(.system(size: 11, design: .monospaced))
                    Text("Hz")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text("GAIN")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 30, alignment: .leading)

                    Slider(value: gainBinding, in: Double(EQBand.gainRange.lowerBound)...Double(EQBand.gainRange.upperBound), step: 0.5)
                        .controlSize(.small)

                    Text(String(format: "%+.1f dB", band.gain))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(gainColor)
                        .frame(width: 54, alignment: .trailing)
                }

                Divider()
                    .frame(height: 12)
                    .opacity(0.5)

                HStack(spacing: 6) {
                    Text("Q")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12, alignment: .leading)

                    Slider(value: qBinding, in: Double(EQBand.qRange.lowerBound)...Double(EQBand.qRange.upperBound), step: 0.1)
                        .controlSize(.small)
                        .frame(width: 80)

                    Text(String(format: "%.1f", band.q))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(band.isEnabled ? 0.4 : 0.2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(band.isEnabled ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04), lineWidth: 1)
        )
        .opacity(band.isEnabled ? 1.0 : 0.65)
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
    private var gainColor: Color {
        band.gain == 0 ? .secondary : (band.gain > 0 ? .green : .red)
    }
}

#Preview {
    ParametricEQView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .frame(width: 984, height: 340)
}
