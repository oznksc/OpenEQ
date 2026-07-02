//
//  ParametricEQView.swift
//  OpenEQ
//
//  Created by Ozan
//

import SwiftUI

struct ParametricEQView: View {
    let viewModel: OpenEQViewModel

    var body: some View {
        VStack(spacing: 10) {
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
        .frame(maxWidth: .infinity)
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
        VStack(alignment: .leading, spacing: 10) {
            headerControls
            sliderControls
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(band.isEnabled ? 0.025 : 0.012))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .opacity(band.isEnabled ? 1.0 : 0.58)
    }

    private var headerControls: some View {
        HStack(spacing: 12) {
            Text("Band \(index + 1)")
                .font(.subheadline.weight(.semibold))
                .frame(width: 58, alignment: .leading)

            Toggle("Enabled", isOn: enabledBinding)
                .toggleStyle(.switch)
                .frame(width: 98, alignment: .leading)

            Picker("Filter", selection: filterTypeBinding) {
                ForEach(EQFilterType.allCases) { filterType in
                    Text(filterType.title).tag(filterType)
                }
            }
            .labelsHidden()
            .frame(width: 142)

            HStack(spacing: 6) {
                Text("Freq")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Hz", value: frequencyBinding, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 78)

                Text("Hz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sliderControls: some View {
        HStack(spacing: 14) {
            Text("Gain")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)

            Slider(value: gainBinding, in: gainRange, step: 0.5)

            Text(String(format: "%+.1f dB", band.gain))
                .font(.caption.monospacedDigit())
                .foregroundStyle(gainColor)
                .frame(width: 64, alignment: .trailing)

            Text("Q")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)

            Slider(value: qBinding, in: qRange, step: 0.1)
                .frame(width: 150)

            Text(String(format: "%.1f", band.q))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
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

    private var gainRange: ClosedRange<Double> {
        Double(EQBand.gainRange.lowerBound)...Double(EQBand.gainRange.upperBound)
    }

    private var qRange: ClosedRange<Double> {
        Double(EQBand.qRange.lowerBound)...Double(EQBand.qRange.upperBound)
    }

    private var gainColor: Color {
        if band.gain == 0 {
            return .secondary
        }

        return band.gain > 0 ? .green : .red
    }
}

#Preview {
    ParametricEQView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .frame(width: 984, height: 420)
}
