import SwiftUI

struct EqualizerView: View {
    @Bindable var viewModel: OpenEQViewModel
    @State private var spectrumDisplayMode: SpectrumDisplayMode = .backdrop
    @State private var isShowingBandCountActions = false
    @State private var isShowingSpectrumDisplayActions = false
    private let graphicCurveHeight: CGFloat = 230
    private let graphicFadersHeight: CGFloat = 184

    var body: some View {
        VStack(alignment: .leading, spacing: OpenEQTheme.sectionSpacing) {
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    StudioLED(isOn: viewModel.isEnabled, activeColor: OpenEQTheme.accentCyan, size: 9)
                    Text("\(viewModel.eqMode.title) EQ")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }

                activeHeadphoneBadge

                Spacer(minLength: 8)

                spectrumDisplayButton

                if viewModel.eqMode == .graphic {
                    bandCountButton
                }
            }

            if viewModel.eqMode == .parametric {
                curvePanel(fixedHeight: 172)

                HStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill")
                        .font(.caption2)
                        .foregroundStyle(OpenEQTheme.accentCyan)
                    Text("Drag nodes for frequency & gain • Scroll over node for Q")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 4)

                ParametricEQView(viewModel: viewModel)
                    .floatingEQSurface(cornerRadius: 16)
                    .opacity(viewModel.isEnabled ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.isEnabled)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    curvePanel(fixedHeight: nil)
                        .frame(maxWidth: .infinity)
                        .frame(height: graphicCurveHeight)

                    graphicFaders
                        .frame(maxWidth: .infinity)
                        .frame(height: graphicFadersHeight)
                }
            }
        }
        .confirmationDialog("Graphic EQ Bands", isPresented: $isShowingBandCountActions) {
            ForEach(GraphicBandCount.allCases) { count in
                Button(count.title) {
                    viewModel.setGraphicBandCount(count)
                }
            }
        }
        .confirmationDialog("Spectrum Display", isPresented: $isShowingSpectrumDisplayActions) {
            ForEach(SpectrumDisplayMode.allCases) { mode in
                Button(mode.title) {
                    spectrumDisplayMode = mode
                }
            }
        }
    }

    @ViewBuilder
    private var spectrumDisplayButton: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 4) {
                spectrumDisplayAction
                    .padding(2.5)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
        } else {
            spectrumDisplayAction
                .padding(2.5)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
    }

    private var spectrumDisplayAction: some View {
        Button {
            isShowingSpectrumDisplayActions = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: spectrumDisplayMode.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(OpenEQTheme.accentCyan)
                Text(spectrumDisplayMode.title)
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Spectrum display: \(spectrumDisplayMode.title)")
        .accessibilityLabel("Spectrum display")
        .accessibilityValue(spectrumDisplayMode.title)
    }

    @ViewBuilder
    private var bandCountButton: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 4) {
                bandCountAction
                    .padding(2.5)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
        } else {
            bandCountAction
                .padding(2.5)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
    }

    private var bandCountAction: some View {
        Button {
            isShowingBandCountActions = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .semibold))
                Text(viewModel.graphicBandCount.title)
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Choose graphic EQ band count")
        .accessibilityLabel("Graphic EQ band count")
        .accessibilityValue(viewModel.graphicBandCount.title)
    }

    @ViewBuilder
    private var activeHeadphoneBadge: some View {
        if let profileID = viewModel.selectedHeadphoneProfileID,
           let profile = viewModel.headphoneProfiles.first(where: { $0.id == profileID }) {
            HStack(spacing: 6) {
                StudioLED(isOn: true, activeColor: OpenEQTheme.accentCyan, size: 6)
                Text("\(profile.displayName) · \(profile.target)")
                    .lineLimit(1)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(OpenEQTheme.accentCyan.opacity(0.08), in: Capsule())
        }
    }

    private func curvePanel(fixedHeight: CGFloat?) -> some View {
        EQCurveView(
            bands: viewModel.bands,
            mode: viewModel.eqMode,
            preamp: viewModel.preamp,
            selectedBandID: viewModel.selectedBandID,
            isInteractive: viewModel.isEnabled,
            spectrumLevels: viewModel.spectrumLevels,
            spectrumDisplayMode: spectrumDisplayMode,
            fixedHeight: fixedHeight,
            onSelectBand: { viewModel.selectBand(id: $0) },
            onBandChanged: { index, band in
                viewModel.updateBandFromCurve(index: index, band: band)
            }
        )
        .floatingEQSurface(cornerRadius: 18)
        .opacity(viewModel.isEnabled ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isEnabled)
    }

    private var graphicFaders: some View {
        HStack(alignment: .center, spacing: 14) {
            preampControl

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(viewModel.bands.enumerated()), id: \.element.id) { index, band in
                        EQBandControl(
                            band: band,
                            gain: viewModel.gain(for: band.id),
                            onGainChanged: { viewModel.updateBandGain(index: index, gain: $0) }
                        )
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(minHeight: graphicFadersHeight - 28, alignment: .center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .floatingEQSurface(cornerRadius: 16)
        .clipped()
        .opacity(viewModel.isEnabled ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isEnabled)
    }

    private var preampControl: some View {
        VStack(spacing: 6) {
            Text(String(format: "%+.1f", viewModel.preamp))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(viewModel.preamp == 0 ? Color.secondary : OpenEQTheme.accentAmber)

            GeometryReader { geometry in
                let height = geometry.size.height
                let thumbHeight: CGFloat = 16
                let track = height - thumbHeight
                let percent = CGFloat(
                    (viewModel.preamp - EQBand.gainRange.lowerBound)
                    / (EQBand.gainRange.upperBound - EQBand.gainRange.lowerBound)
                )
                let thumbY = track * (1 - percent)
                let center = track / 2
                let fillH = abs(percent - 0.5) * track
                let fillY = percent > 0.5 ? thumbY + thumbHeight / 2 : center + thumbHeight / 2

                ZStack(alignment: .top) {
                    // Recessed Slot Track
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(OpenEQTheme.recessedSlotBg)
                        .frame(width: 6)
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        }

                    // 0 dB Center Tick Notch
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 10, height: 1)
                        .offset(y: center + thumbHeight / 2)

                    // Bi-directional Level Fill
                    if fillH > 1 {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(OpenEQTheme.accentAmber)
                            .frame(width: 4, height: fillH)
                            .offset(y: fillY)
                    }

                    // Tactile Master Fader Cap
                    TactileFaderCap(isPreamp: true, gain: viewModel.preamp, isDragging: false)
                        .offset(y: thumbY)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let y = min(max(0, value.location.y - thumbHeight / 2), track)
                                    let p = 1 - (y / track)
                                    let raw = EQBand.gainRange.lowerBound
                                        + Float(p) * (EQBand.gainRange.upperBound - EQBand.gainRange.lowerBound)
                                    viewModel.updatePreamp(gain: abs(raw) < 0.4 ? 0 : Float(round(raw * 2) / 2))
                                }
                        )
                }
                .frame(maxWidth: .infinity)
            }
            .frame(width: 32, height: 112)

            Text("PRE")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(OpenEQTheme.accentAmber)
        }
        .frame(width: 44)
        .padding(.vertical, 6)
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                viewModel.updatePreamp(gain: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preamp")
        .accessibilityValue(String(format: "%+.1f dB", viewModel.preamp))
        .accessibilityAdjustableAction { direction in
            let step: Float = 0.5
            switch direction {
            case .increment:
                viewModel.updatePreamp(gain: min(EQBand.gainRange.upperBound, viewModel.preamp + step))
            case .decrement:
                viewModel.updatePreamp(gain: max(EQBand.gainRange.lowerBound, viewModel.preamp - step))
            @unknown default:
                break
            }
        }
    }

}

// MARK: - Tactile EQ Band Control Fader
struct EQBandControl: View {
    let band: EQBand
    let gain: Float
    let onGainChanged: (Float) -> Void

    @State private var isDragging = false
    @State private var isHovered = false
    @State private var isEditingGain = false
    @State private var gainText = ""

    var body: some View {
        VStack(spacing: 6) {
            Text(String(format: "%+.1f", gain))
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(gain == 0 ? Color.secondary.opacity(0.8) : (gain > 0 ? OpenEQTheme.accentCyan : OpenEQTheme.accentAmber))
                .onTapGesture(count: 2) { gainText = String(format: "%.1f", gain); isEditingGain = true }

            GeometryReader { geometry in
                let height = geometry.size.height
                let thumbHeight: CGFloat = 16
                let track = height - thumbHeight
                let minG = EQBand.gainRange.lowerBound
                let maxG = EQBand.gainRange.upperBound
                let percent = CGFloat((gain - minG) / (maxG - minG))
                let thumbY = track * (1 - percent)
                let center = track / 2
                let fillH = abs(percent - 0.5) * track
                let fillY = percent > 0.5 ? thumbY + thumbHeight / 2 : center + thumbHeight / 2

                ZStack(alignment: .top) {
                    // Recessed Slot Track
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(OpenEQTheme.recessedSlotBg)
                        .frame(width: 5)
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        }

                    // 0 dB Center Tick Notch
                    Rectangle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 8, height: 1)
                        .offset(y: center + thumbHeight / 2)

                    // Bi-directional Level Fill
                    if fillH > 1 {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(gain > 0 ? OpenEQTheme.accentCyan : OpenEQTheme.accentAmber)
                            .frame(width: 3.5, height: fillH)
                            .offset(y: fillY)
                    }

                    // Hardware Fader Cap
                    TactileFaderCap(isPreamp: false, gain: gain, isDragging: isDragging)
                        .offset(y: thumbY)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDragging = true
                                    let y = min(max(0, value.location.y - thumbHeight / 2), track)
                                    let p = 1 - (y / track)
                                    let raw = minG + Float(p) * (maxG - minG)
                                    onGainChanged(abs(raw) < 0.4 ? 0 : Float(round(raw * 2) / 2))
                                }
                                .onEnded { _ in isDragging = false }
                        )
                }
                .frame(maxWidth: .infinity)
            }
            .frame(width: 26, height: 112)

            Text(band.label)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(isDragging || isHovered ? .primary : .secondary)
                .frame(width: 36)
        }
        .frame(width: 38)
        .padding(.vertical, 4)
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                onGainChanged(0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(band.label) band")
        .accessibilityValue(String(format: "%+.0f dB", gain))
        .accessibilityAdjustableAction { direction in
            let step: Float = 0.5
            switch direction {
            case .increment:
                onGainChanged(min(EQBand.gainRange.upperBound, gain + step))
            case .decrement:
                onGainChanged(max(EQBand.gainRange.lowerBound, gain - step))
            @unknown default:
                break
            }
        }
        .popover(isPresented: $isEditingGain) {
            TextField("Gain dB", text: $gainText, onCommit: {
                if let value = Float(gainText) { onGainChanged(max(EQBand.gainRange.lowerBound, min(EQBand.gainRange.upperBound, value))) }
                isEditingGain = false
            })
            .textFieldStyle(.roundedBorder)
            .padding(10)
            .frame(width: 120)
        }
    }
}

// MARK: - Tactile Hardware Fader Cap
struct TactileFaderCap: View {
    var isPreamp: Bool
    var gain: Float
    var isDragging: Bool

    var body: some View {
        let width: CGFloat = isPreamp ? 20 : 18
        let height: CGFloat = 16
        let corner: CGFloat = 3.5

        ZStack {
            // Knob Body
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color(red: 0.22, green: 0.24, blue: 0.28))
                .frame(width: width, height: height)
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
                }

            // Center Position Notch
            Rectangle()
                .fill(
                    isPreamp
                        ? (gain != 0 ? OpenEQTheme.accentAmber : Color.white)
                        : (gain > 0 ? OpenEQTheme.accentCyan : (gain < 0 ? OpenEQTheme.accentAmber : Color.white.opacity(0.85)))
                )
                .frame(width: width - 4, height: 1.5)
        }
        .scaleEffect(isDragging ? 1.05 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.65), value: isDragging)
    }
}

#Preview {
    EqualizerView(viewModel: OpenEQViewModel(audioEngineController: AudioEngineController()))
    .padding(24)
}
