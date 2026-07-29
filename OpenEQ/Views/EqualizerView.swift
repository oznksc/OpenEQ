import SwiftUI

struct EqualizerView: View {
    @Bindable var viewModel: OpenEQViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: OpenEQTheme.sectionSpacing) {
            HStack(spacing: 16) {
                Text("\(viewModel.eqMode.title) EQ")
                    .font(.title3.weight(.semibold))

                Spacer(minLength: 8)

                Toggle("EQ", isOn: eqBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .help("Toggle EQ")

                Picker("Mode", selection: Binding(
                    get: { viewModel.eqMode },
                    set: { viewModel.setEQMode($0) }
                )) {
                    ForEach(EQMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                .labelsHidden()

                if viewModel.eqMode == .graphic {
                    Picker("Bands", selection: bandCountBinding) {
                        ForEach(GraphicBandCount.allCases) { count in
                            Text(count.title).tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 140)
                    .labelsHidden()
                }
            }

            EQCurveView(
                bands: viewModel.bands,
                mode: viewModel.eqMode,
                preamp: viewModel.preamp,
                selectedBandID: viewModel.selectedBandID,
                isInteractive: viewModel.isEnabled,
                onSelectBand: { viewModel.selectBand(id: $0) },
                onBandChanged: { index, band in
                    viewModel.updateBandFromCurve(index: index, band: band)
                }
            )
            .frame(height: 168)
            .opacity(viewModel.isEnabled ? 1 : 0.4)

            if viewModel.eqMode == .parametric {
                Text("Drag nodes · scroll for Q")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                ParametricEQView(viewModel: viewModel)
                    .opacity(viewModel.isEnabled ? 1 : 0.4)
            } else {
                graphicFaders
                    .opacity(viewModel.isEnabled ? 1 : 0.4)
            }
        }
    }

    private var graphicFaders: some View {
        HStack(alignment: .center, spacing: 14) {
            preampControl

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(viewModel.bands.enumerated()), id: \.element.id) { index, band in
                        EQBandControl(
                            band: band,
                            gain: viewModel.gain(for: band.id),
                            onGainChanged: { viewModel.updateBandGain(index: index, gain: $0) }
                        )
                    }
                }
            }
        }
    }

    private var preampControl: some View {
        VStack(spacing: 6) {
            Text(String(format: "%+.1f", viewModel.preamp))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(viewModel.preamp == 0 ? Color.secondary : Color.orange)

            GeometryReader { geometry in
                let height = geometry.size.height
                let thumb: CGFloat = 12
                let track = height - thumb
                let percent = CGFloat(
                    (viewModel.preamp - EQBand.gainRange.lowerBound)
                    / (EQBand.gainRange.upperBound - EQBand.gainRange.lowerBound)
                )
                let thumbY = track * (1 - percent)
                let center = track / 2
                let fillH = abs(percent - 0.5) * track
                let fillY = percent > 0.5 ? thumbY : center

                ZStack(alignment: .top) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 3)

                    Capsule()
                        .fill(Color.orange.opacity(0.8))
                        .frame(width: 3, height: fillH)
                        .offset(y: fillY + thumb / 2)

                    Capsule()
                        .fill(Color.primary.opacity(0.2))
                        .frame(width: 16, height: 8)
                        .offset(y: thumbY)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let y = min(max(0, value.location.y - 4), track)
                                    let p = 1 - (y / track)
                                    let raw = EQBand.gainRange.lowerBound
                                        + Float(p) * (EQBand.gainRange.upperBound - EQBand.gainRange.lowerBound)
                                    viewModel.updatePreamp(gain: abs(raw) < 0.4 ? 0 : Float(round(raw * 2) / 2))
                                }
                        )
                }
            }
            .frame(width: 20, height: 120)

            Text("Pre")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        }
        .frame(width: 40)
        .onTapGesture(count: 2) { viewModel.updatePreamp(gain: 0) }
    }

    private var eqBinding: Binding<Bool> {
        Binding(get: { viewModel.isEnabled }, set: { viewModel.setEnabled($0) })
    }

    private var bandCountBinding: Binding<GraphicBandCount> {
        Binding(get: { viewModel.graphicBandCount }, set: { viewModel.setGraphicBandCount($0) })
    }
}

struct EQBandControl: View {
    let band: EQBand
    let gain: Float
    let onGainChanged: (Float) -> Void

    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 6) {
            Text(String(format: "%+.0f", gain))
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(gain == 0 ? Color.secondary : (gain > 0 ? Color.cyan : Color.orange))

            GeometryReader { geometry in
                let height = geometry.size.height
                let thumb: CGFloat = 12
                let track = height - thumb
                let minG = EQBand.gainRange.lowerBound
                let maxG = EQBand.gainRange.upperBound
                let percent = CGFloat((gain - minG) / (maxG - minG))
                let thumbY = track * (1 - percent)
                let center = track / 2
                let fillH = abs(percent - 0.5) * track
                let fillY = percent > 0.5 ? thumbY : center

                ZStack(alignment: .top) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 3)

                    Capsule()
                        .fill(gain > 0 ? Color.cyan.opacity(0.8) : Color.orange.opacity(0.8))
                        .frame(width: 3, height: fillH)
                        .offset(y: fillY + thumb / 2)

                    Capsule()
                        .fill(isDragging ? Color.accentColor : Color.primary.opacity(0.22))
                        .frame(width: 14, height: 8)
                        .offset(y: thumbY)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDragging = true
                                    let y = min(max(0, value.location.y - 4), track)
                                    let p = 1 - (y / track)
                                    let raw = minG + Float(p) * (maxG - minG)
                                    onGainChanged(abs(raw) < 0.4 ? 0 : Float(round(raw * 2) / 2))
                                }
                                .onEnded { _ in isDragging = false }
                        )
                }
            }
            .frame(width: 18, height: 120)

            Text(band.label)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 36)
        }
        .frame(width: 40)
        .onTapGesture(count: 2) { onGainChanged(0) }
    }
}

#Preview {
    EqualizerView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .padding(24)
}
