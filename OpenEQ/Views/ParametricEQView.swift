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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("B\(index + 1)")
                    .font(.caption.weight(.semibold))
                    .frame(width: 24)

                Toggle("", isOn: enabledBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .frame(width: 32)

                Picker("", selection: filterTypeBinding) {
                    ForEach(EQFilterType.allCases) { ft in
                        Text(ft.title).tag(ft)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 110)

                HStack(spacing: 4) {
                    TextField("", value: frequencyBinding, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .font(.caption)
                    Text("Hz")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Text("G")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                Slider(value: gainBinding, in: Double(EQBand.gainRange.lowerBound)...Double(EQBand.gainRange.upperBound), step: 0.5)
                    .controlSize(.small)

                Text(String(format: "%+.1f", band.gain))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(gainColor)
                    .frame(width: 44, alignment: .trailing)

                Text("Q")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                Slider(value: qBinding, in: Double(EQBand.qRange.lowerBound)...Double(EQBand.qRange.upperBound), step: 0.1)
                    .controlSize(.small)
                    .frame(width: 100)

                Text(String(format: "%.1f", band.q))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(band.isEnabled ? 0.02 : 0.01)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.05), lineWidth: 1))
        .opacity(band.isEnabled ? 1.0 : 0.5)
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
