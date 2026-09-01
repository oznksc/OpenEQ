import SwiftUI

struct ParametricEQView: View {
    let viewModel: OpenEQViewModel

    private var selectedBandIndex: Int? {
        if let selectedBandID = viewModel.selectedBandID,
           let index = viewModel.bands.firstIndex(where: { $0.id == selectedBandID }) {
            return index
        }
        return viewModel.bands.isEmpty ? nil : 0
    }

    var body: some View {
        VStack(spacing: 10) {
            if let index = selectedBandIndex {
                let band = viewModel.bands[index]
                FocusedBandInspector(
                    index: index,
                    band: band,
                    onFrequencyChanged: { viewModel.updateBandFrequency(index: index, frequency: $0) },
                    onGainChanged: { viewModel.updateBandGain(index: index, gain: $0) },
                    onQChanged: { viewModel.updateBandQ(index: index, q: $0) },
                    onFilterTypeChanged: { viewModel.updateBandFilterType(index: index, filterType: $0) },
                    onEnabledChanged: { viewModel.updateBandEnabled(index: index, isEnabled: $0) }
                )
            }

            BandMatrix(
                bands: viewModel.bands,
                selectedBandID: viewModel.selectedBandID,
                onSelect: { viewModel.selectBand(id: $0) }
            )
        }
    }
}

private struct FocusedBandInspector: View {
    let index: Int
    let band: EQBand
    let onFrequencyChanged: (Float) -> Void
    let onGainChanged: (Float) -> Void
    let onQChanged: (Float) -> Void
    let onFilterTypeChanged: (EQFilterType) -> Void
    let onEnabledChanged: (Bool) -> Void

    private var bandColor: Color { OpenEQTheme.bandColor(at: index) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                StudioLED(isOn: band.isEnabled, activeColor: bandColor, size: 8)
                Text("BAND \(index + 1) INSPECTOR")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                Text(band.filterType.title.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(bandColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(bandColor.opacity(0.12), in: Capsule())
                Spacer()
                Toggle("Band enabled", isOn: Binding(
                    get: { band.isEnabled },
                    set: { onEnabledChanged($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            HStack(alignment: .center, spacing: 16) {
                StudioRotaryKnob(
                    value: Binding(
                        get: { Double(band.frequency) },
                        set: { onFrequencyChanged(Float($0)) }
                    ),
                    range: Double(EQBand.frequencyRange.lowerBound)...Double(EQBand.frequencyRange.upperBound),
                    defaultValue: 1000,
                    title: "FREQUENCY",
                    unit: "Hz",
                    valueText: formatFrequency(band.frequency),
                    tint: bandColor,
                    dragUnitsPerPoint: 90,
                    progress: logarithmicProgress
                )

                StudioRotaryKnob(
                    value: Binding(
                        get: { Double(band.gain) },
                        set: { onGainChanged(Float($0)) }
                    ),
                    range: Double(EQBand.gainRange.lowerBound)...Double(EQBand.gainRange.upperBound),
                    defaultValue: 0,
                    title: "GAIN",
                    unit: "dB",
                    valueText: String(format: "%+.1f", band.gain),
                    tint: band.gain >= 0 ? OpenEQTheme.accentCyan : OpenEQTheme.accentAmber,
                    dragUnitsPerPoint: 24,
                    progress: gainProgress
                )

                StudioRotaryKnob(
                    value: Binding(
                        get: { Double(band.q) },
                        set: { onQChanged(Float($0)) }
                    ),
                    range: Double(EQBand.qRange.lowerBound)...Double(EQBand.qRange.upperBound),
                    defaultValue: Double(EQBand.defaultQ),
                    title: "Q / WIDTH",
                    unit: "",
                    valueText: String(format: "%.2f", band.q),
                    tint: OpenEQTheme.accentPurple,
                    dragUnitsPerPoint: 8,
                    progress: qProgress
                )

                Divider()
                    .frame(height: 74)
                    .opacity(0.2)

                filterTypeControl
            }
        }
        .padding(12)
        .background(OpenEQTheme.cardBgElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(bandColor.opacity(0.34), lineWidth: 1)
        }
        .opacity(band.isEnabled ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.15), value: band.isEnabled)
    }

    private var filterTypeControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FILTER TYPE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)

            HStack(spacing: 4) {
                ForEach(EQFilterType.allCases) { filterType in
                    Button {
                        onFilterTypeChanged(filterType)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: filterType.symbolName)
                                .font(.system(size: 13, weight: .semibold))
                            Text(filterType.shortTitle)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(band.filterType == filterType ? bandColor : .secondary)
                        .frame(width: 48, height: 42)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(band.filterType == filterType ? bandColor.opacity(0.14) : OpenEQTheme.recessedSlotBg)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(band.filterType == filterType ? bandColor.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 0.8)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(filterType.title)
                    .accessibilityAddTraits(band.filterType == filterType ? .isSelected : [])
                }
            }
        }
    }

    private func formatFrequency(_ frequency: Float) -> String {
        frequency >= 1000 ? String(format: "%.2f", frequency / 1000) : String(format: "%.0f", frequency)
    }

    private func logarithmicProgress(_ value: Double) -> Double {
        let minimum = log10(Double(EQBand.frequencyRange.lowerBound))
        let maximum = log10(Double(EQBand.frequencyRange.upperBound))
        return (log10(max(Double(EQBand.frequencyRange.lowerBound), value)) - minimum) / (maximum - minimum)
    }

    private func gainProgress(_ value: Double) -> Double {
        (value - Double(EQBand.gainRange.lowerBound)) / Double(EQBand.gainRange.upperBound - EQBand.gainRange.lowerBound)
    }

    private func qProgress(_ value: Double) -> Double {
        (value - Double(EQBand.qRange.lowerBound)) / Double(EQBand.qRange.upperBound - EQBand.qRange.lowerBound)
    }
}

private struct BandMatrix: View {
    let bands: [EQBand]
    let selectedBandID: EQBand.ID?
    let onSelect: (EQBand.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("BAND MATRIX")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("CLICK A BAND TO FOCUS")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(bands.enumerated()), id: \.element.id) { index, band in
                        Button {
                            onSelect(band.id)
                        } label: {
                            HStack(spacing: 7) {
                                StudioLED(isOn: band.isEnabled, activeColor: OpenEQTheme.bandColor(at: index), size: 6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("B\(index + 1)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    Text(frequencyLabel(band.frequency))
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Text(String(format: "%+.1f", band.gain))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(band.gain >= 0 ? OpenEQTheme.accentCyan : OpenEQTheme.accentAmber)
                            }
                            .padding(.horizontal, 9)
                            .frame(width: 116, height: 38)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(band.id == selectedBandID ? OpenEQTheme.bandColor(at: index).opacity(0.14) : OpenEQTheme.cardBg)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(band.id == selectedBandID ? OpenEQTheme.bandColor(at: index).opacity(0.62) : Color.white.opacity(0.06), lineWidth: band.id == selectedBandID ? 1 : 0.8)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Band \(index + 1), \(frequencyLabel(band.frequency)), \(String(format: "%+.1f dB", band.gain))")
                        .accessibilityAddTraits(band.id == selectedBandID ? .isSelected : [])
                    }
                }
            }
        }
        .padding(10)
        .background(OpenEQTheme.cardBg.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func frequencyLabel(_ frequency: Float) -> String {
        frequency >= 1000 ? String(format: "%.1fk", frequency / 1000) : String(format: "%.0f", frequency)
    }
}

private struct StudioRotaryKnob: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    let title: String
    let unit: String
    let valueText: String
    let tint: Color
    let dragUnitsPerPoint: Double
    let progress: (Double) -> Double

    @State private var dragStartValue: Double?
    @State private var isEditing = false
    @State private var draftValue = ""

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.tertiary)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 5)
                    .frame(width: 78, height: 78)

                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(0.75, progress(value) * 0.75))))
                    .stroke(tint.opacity(0.9), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .frame(width: 78, height: 78)

                Circle()
                    .fill(OpenEQTheme.recessedSlotBg)
                    .frame(width: 58, height: 58)
                    .overlay {
                        Circle().stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }

                if isEditing {
                    TextField("", text: $draftValue, onCommit: commitDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .frame(width: 48)
                        .onAppear { draftValue = valueText }
                } else {
                    Text(valueText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(width: 50)
                        .contentShape(Rectangle())
                        .onTapGesture { beginEditing() }
                }
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard !isEditing else { return }
                        if dragStartValue == nil { dragStartValue = value }
                        let start = dragStartValue ?? value
                        let nextValue = start - gesture.translation.height * dragUnitsPerPoint / 100
                        value = min(range.upperBound, max(range.lowerBound, nextValue))
                    }
                    .onEnded { _ in
                        dragStartValue = nil
                    }
            )
            .onTapGesture(count: 2) {
                value = defaultValue
                isEditing = false
            }

            Text(unit.isEmpty ? " " : unit)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(tint)
                .frame(height: 11)
        }
        .frame(width: 94)
        .onChange(of: value) { _, _ in
            if !isEditing { draftValue = valueText }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(valueText + (unit.isEmpty ? "" : " " + unit))
        .accessibilityAdjustableAction { direction in
            let step = max((range.upperBound - range.lowerBound) / 100, 0.01)
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private func beginEditing() {
        if title == "FREQUENCY" {
            draftValue = value >= 1000 ? String(format: "%.2fk", value / 1000) : String(format: "%.0f", value)
        } else if title == "GAIN" {
            draftValue = String(format: "%.1f", value)
        } else if title == "Q / WIDTH" {
            draftValue = String(format: "%.2f", value)
        } else {
            draftValue = valueText
        }
        isEditing = true
    }

    private func commitDraft() {
        var raw = draftValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        raw = raw.replacingOccurrences(of: ",", with: ".")
        raw = raw.replacingOccurrences(of: "hz", with: "")
        raw = raw.replacingOccurrences(of: "db", with: "")

        var multiplier: Double = 1.0
        if raw.hasSuffix("k") {
            multiplier = 1000.0
            raw = String(raw.dropLast()).trimmingCharacters(in: .whitespaces)
        } else if raw.hasSuffix("khz") {
            multiplier = 1000.0
            raw = String(raw.dropLast(3)).trimmingCharacters(in: .whitespaces)
        }

        if let parsed = Double(raw) {
            let finalVal = parsed * multiplier
            value = min(range.upperBound, max(range.lowerBound, finalVal))
        }
        isEditing = false
    }
}

private extension EQFilterType {
    var symbolName: String {
        switch self {
        case .parametric: return "waveform.path"
        case .lowShelf: return "arrow.down.to.line"
        case .highShelf: return "arrow.up.to.line"
        case .highPass: return "arrow.right.to.line"
        case .lowPass: return "arrow.left.to.line"
        }
    }

    var shortTitle: String {
        switch self {
        case .parametric: return "Bell"
        case .lowShelf: return "Low"
        case .highShelf: return "High"
        case .highPass: return "HPF"
        case .lowPass: return "LPF"
        }
    }
}

#Preview {
    ParametricEQView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .padding(24)
    .frame(width: 900)
}
