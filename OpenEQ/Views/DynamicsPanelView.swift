import SwiftUI

struct DynamicsPanelView: View {
    @Bindable var viewModel: OpenEQViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                StudioLED(isOn: viewModel.dynamics.isCompressorEnabled, activeColor: OpenEQTheme.accentCyan, size: 7)
                Text("Studio Dynamics Processor")
                    .font(.system(size: 12, weight: .bold))
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

            VStack(spacing: 10) {
                row("Threshold", String(format: "%.0f dB", viewModel.dynamics.threshold),
                    Binding(
                        get: { Double(viewModel.dynamics.threshold) },
                        set: { viewModel.setCompressorThreshold(Float($0)) }
                    ),
                    Double(DynamicsSettings.thresholdRange.lowerBound)...Double(DynamicsSettings.thresholdRange.upperBound)
                )
                row("Ratio", String(format: "%.1f : 1", viewModel.dynamics.ratio),
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
                row("Makeup Gain", String(format: "%+.1f dB", viewModel.dynamics.makeupGain),
                    Binding(
                        get: { Double(viewModel.dynamics.makeupGain) },
                        set: { viewModel.setCompressorMakeup(Float($0)) }
                    ),
                    Double(DynamicsSettings.makeupRange.lowerBound)...Double(DynamicsSettings.makeupRange.upperBound),
                    color: viewModel.dynamics.makeupGain > 0 ? OpenEQTheme.accentCyan : (viewModel.dynamics.makeupGain < 0 ? OpenEQTheme.accentAmber : .secondary)
                )
            }
            .disabled(!viewModel.dynamics.isCompressorEnabled)
            .opacity(viewModel.dynamics.isCompressorEnabled ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.15), value: viewModel.dynamics.isCompressorEnabled)

            Divider().opacity(0.15)

            row("Stereo Balance", balanceLabel,
                Binding(
                    get: { Double(viewModel.dynamics.balance) },
                    set: { viewModel.setStereoBalance(Float($0)) }
                ),
                Double(DynamicsSettings.balanceRange.lowerBound)...Double(DynamicsSettings.balanceRange.upperBound),
                color: abs(viewModel.dynamics.balance) > 0.05 ? OpenEQTheme.accentCyan : .secondary
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
        _ range: ClosedRange<Double>,
        color: Color = .secondary
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }
            Slider(value: binding, in: range)
                .controlSize(.small)
        }
    }
}

