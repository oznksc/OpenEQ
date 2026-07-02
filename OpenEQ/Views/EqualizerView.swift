import SwiftUI

struct EqualizerView: View {
    @Bindable var viewModel: OpenEQViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("\(viewModel.eqMode.title) Equalizer", systemImage: "slider.vertical.3")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Toggle(isOn: eqBinding) {
                    Image(systemName: "power")
                }
                .toggleStyle(.switch)
                .help("Toggle EQ on/off")
                .padding(.trailing, 4)

                Picker(
                    "EQ Mode",
                    selection: Binding(
                        get: { viewModel.eqMode },
                        set: { viewModel.setEQMode($0) }
                    )
                ) {
                    ForEach(EQMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                if viewModel.eqMode == .graphic {
                    Picker("Bands", selection: bandCountBinding) {
                        ForEach(GraphicBandCount.allCases) { count in
                            Text(count.title).tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }

                Button(action: {
                    viewModel.resetEQ()
                }) {
                    Label("Reset EQ", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }

            EQCurveView(
                bands: viewModel.bands,
                mode: viewModel.eqMode,
                preamp: viewModel.preamp
            )
            .opacity(viewModel.isEnabled ? 1.0 : 0.4)

            if viewModel.eqMode == .graphic {
                HStack(alignment: .center, spacing: 12) {
                    VStack(spacing: 8) {
                        Text(String(format: "%+.1f dB", viewModel.preamp))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(viewModel.preamp == 0.0 ? Color.secondary : Color.orange)
                            .frame(height: 14)

                        GeometryReader { geometry in
                            let height = geometry.size.height
                            let thumbSize: CGFloat = 16
                            let trackHeight = height - thumbSize

                            let percent = CGFloat((viewModel.preamp - EQBand.gainRange.lowerBound) / (EQBand.gainRange.upperBound - EQBand.gainRange.lowerBound))
                            let thumbY = trackHeight * (1.0 - percent)

                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.orange.opacity(0.12))
                                    .frame(width: 4)
                                    .frame(maxHeight: .infinity)

                                Rectangle()
                                    .fill(Color.orange.opacity(0.4))
                                    .frame(width: 14, height: 1.5)
                                    .offset(y: trackHeight / 2 + thumbSize / 2 - 0.75)

                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.orange, .red],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: thumbSize, height: thumbSize)
                                    .shadow(color: Color.orange.opacity(0.3), radius: 3)
                                    .offset(y: thumbY)
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                let newY = min(max(0, value.location.y - thumbSize / 2), trackHeight)
                                                let newPercent = 1.0 - (newY / trackHeight)
                                                let rawPreamp = EQBand.gainRange.lowerBound + Float(newPercent) * (EQBand.gainRange.upperBound - EQBand.gainRange.lowerBound)

                                                let snapped: Float
                                                if abs(rawPreamp) < 0.4 {
                                                    snapped = 0.0
                                                } else {
                                                    snapped = Float(round(rawPreamp * 2) / 2)
                                                }
                                                viewModel.updatePreamp(gain: snapped)
                                            }
                                    )
                            }
                        }
                        .frame(width: 28, height: 160)

                        Text("Preamp")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                            .frame(width: 52)
                    }
                    .frame(width: 58)
                    .onTapGesture(count: 2) {
                        viewModel.updatePreamp(gain: 0.0)
                    }
                    .help("Double-click to reset preamp to 0.0 dB")

                    Divider()
                        .frame(height: 160)
                        .padding(.horizontal, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Array(viewModel.bands.enumerated()), id: \.element.id) { index, band in
                                EQBandControl(
                                    band: band,
                                    gain: viewModel.gain(for: band.id),
                                    onGainChanged: { newGain in
                                        viewModel.updateBandGain(index: index, gain: newGain)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.02))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                )
                .opacity(viewModel.isEnabled ? 1.0 : 0.4)
            } else {
                ParametricEQView(viewModel: viewModel)
                    .opacity(viewModel.isEnabled ? 1.0 : 0.4)
            }
        }
        .padding(20)
    }

    private var eqBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isEnabled },
            set: { viewModel.setEnabled($0) }
        )
    }

    private var bandCountBinding: Binding<GraphicBandCount> {
        Binding(
            get: { viewModel.graphicBandCount },
            set: { viewModel.setGraphicBandCount($0) }
        )
    }
}

struct EQBandControl: View {
    let band: EQBand
    let gain: Float
    let onGainChanged: (Float) -> Void

    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 8) {
            Text(String(format: "%+.1f dB", gain))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(gain == 0.0 ? Color.secondary : (gain > 0 ? Color.green : Color.red))
                .frame(height: 12)

            GeometryReader { geometry in
                let height = geometry.size.height
                let thumbSize: CGFloat = 14
                let trackHeight = height - thumbSize

                let minGain = EQBand.gainRange.lowerBound
                let maxGain = EQBand.gainRange.upperBound
                let percent = CGFloat((gain - minGain) / (maxGain - minGain))
                let thumbY = trackHeight * (1.0 - percent)

                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 4)
                        .frame(maxHeight: .infinity)

                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 12, height: 1.5)
                        .offset(y: trackHeight / 2 + thumbSize / 2 - 0.75)

                    Rectangle()
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 8, height: 1)
                        .offset(y: trackHeight * 0.25 + thumbSize / 2)

                    Rectangle()
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 8, height: 1)
                        .offset(y: trackHeight * 0.75 + thumbSize / 2)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isDragging ? [.cyan, .blue] : [Color(nsColor: .controlColor), Color(nsColor: .alternateSelectedControlTextColor)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            Circle()
                                .stroke(isDragging ? Color.blue : Color.primary.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 2, y: 1)
                        .shadow(color: isHovered || isDragging ? Color.cyan.opacity(0.4) : Color.clear, radius: 4)
                        .frame(width: thumbSize, height: thumbSize)
                        .offset(y: thumbY)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDragging = true
                                    let newY = min(max(0, value.location.y - thumbSize / 2), trackHeight)
                                    let newPercent = 1.0 - (newY / trackHeight)
                                    let rawGain = minGain + Float(newPercent) * (maxGain - minGain)
                                    let snappedGain: Float
                                    if abs(rawGain) < 0.4 {
                                        snappedGain = 0.0
                                    } else {
                                        snappedGain = Float(round(rawGain * 2) / 2)
                                    }
                                    onGainChanged(snappedGain)
                                }
                                .onEnded { _ in
                                    isDragging = false
                                }
                        )
                }
            }
            .frame(width: 24, height: 160)

            Text(band.label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 48)
        }
        .frame(width: 50)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(count: 2) {
            onGainChanged(0.0)
        }
        .help("Double-click to reset band to 0.0 dB")
    }
}

#Preview {
    EqualizerView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .frame(width: 984, height: 312)
}
