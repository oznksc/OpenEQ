import SwiftUI

struct DynamicsPanelView: View {
    @Bindable var viewModel: OpenEQViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Compressor")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Compressor", isOn: Binding(
                    get: { viewModel.dynamics.isCompressorEnabled },
                    set: { viewModel.setCompressorEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Group {
                row("Thresh", String(format: "%.0f dB", viewModel.dynamics.threshold),
                    Binding(
                        get: { Double(viewModel.dynamics.threshold) },
                        set: { viewModel.setCompressorThreshold(Float($0)) }
                    ),
                    Double(DynamicsSettings.thresholdRange.lowerBound)...Double(DynamicsSettings.thresholdRange.upperBound)
                )
                row("Ratio", String(format: "%.1f:1", viewModel.dynamics.ratio),
                    Binding(
                        get: { Double(viewModel.dynamics.ratio) },
                        set: { viewModel.setCompressorRatio(Float($0)) }
                    ),
                    Double(DynamicsSettings.ratioRange.lowerBound)...Double(DynamicsSettings.ratioRange.upperBound)
                )
                row("Attack", String(format: "%.0f ms", viewModel.dynamics.attack * 1000),
                    Binding(
                        get: { Double(viewModel.dynamics.attack) },
                        set: { viewModel.setCompressorAttack(Float($0)) }
                    ),
                    Double(DynamicsSettings.attackRange.lowerBound)...Double(DynamicsSettings.attackRange.upperBound)
                )
                row("Release", String(format: "%.0f ms", viewModel.dynamics.release * 1000),
                    Binding(
                        get: { Double(viewModel.dynamics.release) },
                        set: { viewModel.setCompressorRelease(Float($0)) }
                    ),
                    Double(DynamicsSettings.releaseRange.lowerBound)...Double(DynamicsSettings.releaseRange.upperBound)
                )
                row("Makeup", String(format: "%+.1f dB", viewModel.dynamics.makeupGain),
                    Binding(
                        get: { Double(viewModel.dynamics.makeupGain) },
                        set: { viewModel.setCompressorMakeup(Float($0)) }
                    ),
                    Double(DynamicsSettings.makeupRange.lowerBound)...Double(DynamicsSettings.makeupRange.upperBound)
                )
            }
            .disabled(!viewModel.dynamics.isCompressorEnabled)
            .opacity(viewModel.dynamics.isCompressorEnabled ? 1 : 0.4)

            row("Balance", balanceLabel,
                Binding(
                    get: { Double(viewModel.dynamics.balance) },
                    set: { viewModel.setStereoBalance(Float($0)) }
                ),
                Double(DynamicsSettings.balanceRange.lowerBound)...Double(DynamicsSettings.balanceRange.upperBound)
            )
        }
    }

    private var balanceLabel: String {
        let b = viewModel.dynamics.balance
        if abs(b) < 0.05 { return "Center" }
        return b < 0 ? String(format: "L %.0f%%", abs(b) * 100) : String(format: "R %.0f%%", b * 100)
    }

    private func row(
        _ title: String,
        _ value: String,
        _ binding: Binding<Double>,
        _ range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Slider(value: binding, in: range)
                .controlSize(.small)
        }
    }
}
