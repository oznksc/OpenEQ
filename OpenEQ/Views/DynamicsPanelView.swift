import SwiftUI

struct DynamicsPanelView: View {
    @Bindable var viewModel: OpenEQViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Dynamics", systemImage: "waveform.path.ecg")
                    .font(.caption.weight(.semibold))
                Spacer()
                Toggle("Comp", isOn: Binding(
                    get: { viewModel.dynamics.isCompressorEnabled },
                    set: { viewModel.setCompressorEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help("Enable compressor")
            }

            parameterRow(
                title: "Thresh",
                valueText: String(format: "%.0f dB", viewModel.dynamics.threshold),
                value: Binding(
                    get: { Double(viewModel.dynamics.threshold) },
                    set: { viewModel.setCompressorThreshold(Float($0)) }
                ),
                range: Double(DynamicsSettings.thresholdRange.lowerBound)...Double(DynamicsSettings.thresholdRange.upperBound)
            )
            .disabled(!viewModel.dynamics.isCompressorEnabled)

            parameterRow(
                title: "Ratio",
                valueText: String(format: "%.1f:1", viewModel.dynamics.ratio),
                value: Binding(
                    get: { Double(viewModel.dynamics.ratio) },
                    set: { viewModel.setCompressorRatio(Float($0)) }
                ),
                range: Double(DynamicsSettings.ratioRange.lowerBound)...Double(DynamicsSettings.ratioRange.upperBound)
            )
            .disabled(!viewModel.dynamics.isCompressorEnabled)

            parameterRow(
                title: "Attack",
                valueText: String(format: "%.0f ms", viewModel.dynamics.attack * 1000),
                value: Binding(
                    get: { Double(viewModel.dynamics.attack) },
                    set: { viewModel.setCompressorAttack(Float($0)) }
                ),
                range: Double(DynamicsSettings.attackRange.lowerBound)...Double(DynamicsSettings.attackRange.upperBound)
            )
            .disabled(!viewModel.dynamics.isCompressorEnabled)

            parameterRow(
                title: "Release",
                valueText: String(format: "%.0f ms", viewModel.dynamics.release * 1000),
                value: Binding(
                    get: { Double(viewModel.dynamics.release) },
                    set: { viewModel.setCompressorRelease(Float($0)) }
                ),
                range: Double(DynamicsSettings.releaseRange.lowerBound)...Double(DynamicsSettings.releaseRange.upperBound)
            )
            .disabled(!viewModel.dynamics.isCompressorEnabled)

            parameterRow(
                title: "Makeup",
                valueText: String(format: "%+.1f dB", viewModel.dynamics.makeupGain),
                value: Binding(
                    get: { Double(viewModel.dynamics.makeupGain) },
                    set: { viewModel.setCompressorMakeup(Float($0)) }
                ),
                range: Double(DynamicsSettings.makeupRange.lowerBound)...Double(DynamicsSettings.makeupRange.upperBound)
            )
            .disabled(!viewModel.dynamics.isCompressorEnabled)

            Divider().opacity(0.4)

            parameterRow(
                title: "Balance",
                valueText: balanceLabel,
                value: Binding(
                    get: { Double(viewModel.dynamics.balance) },
                    set: { viewModel.setStereoBalance(Float($0)) }
                ),
                range: Double(DynamicsSettings.balanceRange.lowerBound)...Double(DynamicsSettings.balanceRange.upperBound)
            )

            Text("Peak limiter remains always-on after the compressor.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .cornerRadius(10)
    }

    private var balanceLabel: String {
        let b = viewModel.dynamics.balance
        if abs(b) < 0.05 { return "Center" }
        return b < 0 ? String(format: "L %.0f%%", abs(b) * 100) : String(format: "R %.0f%%", b * 100)
    }

    private func parameterRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
                Spacer()
                Text(valueText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .controlSize(.mini)
        }
    }
}
