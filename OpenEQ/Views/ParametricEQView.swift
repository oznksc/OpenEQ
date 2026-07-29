import SwiftUI

struct ParametricEQView: View {
    let viewModel: OpenEQViewModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.bands.enumerated()), id: \.element.id) { index, band in
                if index > 0 {
                    Divider().opacity(0.25)
                }
                ParametricBandRow(
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

private struct ParametricBandRow: View {
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
                    .font(.caption.weight(.bold).monospaced())
                    .foregroundStyle(band.isEnabled ? Color.accentColor : .secondary)
                    .frame(width: 22, alignment: .leading)

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
                .frame(width: 100)

                Spacer(minLength: 8)

                TextField("", value: frequencyBinding, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.plain)
                    .font(.caption.monospaced())
                    .frame(width: 48)
                    .multilineTextAlignment(.trailing)
                Text("Hz")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 16) {
                labeledSlider("Gain", gainBinding,
                              Double(EQBand.gainRange.lowerBound)...Double(EQBand.gainRange.upperBound),
                              String(format: "%+.1f dB", band.gain))
                labeledSlider("Q", qBinding,
                              Double(EQBand.qRange.lowerBound)...Double(EQBand.qRange.upperBound),
                              String(format: "%.1f", band.q))
                .frame(maxWidth: 200)
            }
        }
        .padding(.vertical, 10)
        .opacity(band.isEnabled ? 1 : 0.5)
    }

    private func labeledSlider(
        _ title: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        _ label: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .leading)
            Slider(value: value, in: range)
                .controlSize(.small)
            Text(label)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
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
