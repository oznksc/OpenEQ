import SwiftUI

struct EqualizerView: View {
    @Bindable var viewModel: OpenEQViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(viewModel.eqMode.title) Equalizer", systemImage: "slider.vertical.3")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Toggle(isOn: eqBinding) {
                    Image(systemName: "power")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Toggle EQ on/off")

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
                .frame(width: 180)

                if viewModel.eqMode == .graphic {
                    Picker("Bands", selection: bandCountBinding) {
                        ForEach(GraphicBandCount.allCases) { count in
                            Text(count.title).tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }

                Button(action: {
                    viewModel.resetEQ()
                }) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            EQCurveView(
                bands: viewModel.bands,
                mode: viewModel.eqMode,
                preamp: viewModel.preamp
            )
            .frame(height: 120)
            .opacity(viewModel.isEnabled ? 1.0 : 0.4)

            if viewModel.eqMode == .graphic {
                HStack(alignment: .center, spacing: 8) {
                    preampControl

                    Divider()
                        .frame(height: 120)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
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
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(8)
                .opacity(viewModel.isEnabled ? 1.0 : 0.4)
            } else {
                ParametricEQView(viewModel: viewModel)
                    .opacity(viewModel.isEnabled ? 1.0 : 0.4)
            }
        }
        .padding(14)
    }

    private var preampControl: some View {
        VStack(spacing: 6) {
            Text(String(format: "%+.1f dB", viewModel.preamp))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(viewModel.preamp == 0.0 ? Color.secondary : Color.orange)
                .frame(height: 12)

            GeometryReader { geometry in
                let height = geometry.size.height
                let thumbSize: CGFloat = 12
                let trackHeight = height - thumbSize

                let percent = CGFloat((viewModel.preamp - EQBand.gainRange.lowerBound) / (EQBand.gainRange.upperBound - EQBand.gainRange.lowerBound))
                let thumbY = trackHeight * (1.0 - percent)
                
                let centerPos = trackHeight / 2
                let fillHeight = abs(percent - 0.5) * trackHeight
                let fillY = percent > 0.5 ? thumbY : centerPos

                ZStack(alignment: .top) {
                    // Track Background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 4)

                    // Center Tick Mark
                    Rectangle()
                        .fill(Color.primary.opacity(0.2))
                        .frame(width: 12, height: 1)
                        .offset(y: centerPos + thumbSize / 2)

                    // Active Fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.orange.opacity(0.85))
                        .frame(width: 4, height: fillHeight)
                        .offset(y: fillY + thumbSize / 2)

                    // Fader Handle
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [Color(nsColor: .controlColor), Color(nsColor: .alternateSelectedControlTextColor).opacity(0.8)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                        )
                        .overlay(
                            Rectangle()
                                .fill(Color.orange)
                                .frame(height: 2)
                        )
                        .frame(width: 18, height: 10)
                        .shadow(color: Color.black.opacity(0.15), radius: 1, y: 1)
                        .offset(y: thumbY)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let newY = min(max(0, value.location.y - 5), trackHeight)
                                    let newPercent = 1.0 - (newY / trackHeight)
                                    let rawPreamp = EQBand.gainRange.lowerBound + Float(newPercent) * (EQBand.gainRange.upperBound - EQBand.gainRange.lowerBound)
                                    viewModel.updatePreamp(gain: abs(rawPreamp) < 0.4 ? 0.0 : Float(round(rawPreamp * 2) / 2))
                                }
                        )
                }
            }
            .frame(width: 22, height: 120)

            Text("Preamp")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
        }
        .frame(width: 48)
        .onTapGesture(count: 2) { viewModel.updatePreamp(gain: 0.0) }
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

    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 6) {
            Text(String(format: "%+.1f", gain))
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(gain == 0.0 ? Color.secondary : (gain > 0 ? Color.cyan : Color.orange))
                .frame(height: 10)

            GeometryReader { geometry in
                let height = geometry.size.height
                let thumbSize: CGFloat = 12
                let trackHeight = height - thumbSize
                let minGain = EQBand.gainRange.lowerBound
                let maxGain = EQBand.gainRange.upperBound
                let percent = CGFloat((gain - minGain) / (maxGain - minGain))
                let thumbY = trackHeight * (1.0 - percent)
                
                let centerPos = trackHeight / 2
                let fillHeight = abs(percent - 0.5) * trackHeight
                let fillY = percent > 0.5 ? thumbY : centerPos

                ZStack(alignment: .top) {
                    // Track Background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 4)
                        .frame(maxHeight: .infinity)

                    // Center zero tick
                    Rectangle()
                        .fill(Color.primary.opacity(0.2))
                        .frame(width: 10, height: 1)
                        .offset(y: centerPos + thumbSize / 2)

                    // Dynamic Fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(gain > 0 ? Color.cyan.opacity(0.85) : Color.orange.opacity(0.85))
                        .frame(width: 4, height: fillHeight)
                        .offset(y: fillY + thumbSize / 2)

                    // Fader Handle
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(LinearGradient(
                            colors: isDragging ? [.cyan, .blue] : [Color(nsColor: .controlColor), Color(nsColor: .alternateSelectedControlTextColor).opacity(0.8)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2.5)
                                .stroke(isDragging ? Color.cyan : Color.primary.opacity(0.2), lineWidth: 1)
                        )
                        .overlay(
                            Rectangle()
                                .fill(isDragging ? Color.white : (gain == 0.0 ? Color.primary.opacity(0.3) : (gain > 0 ? Color.cyan : Color.orange)))
                                .frame(height: 1.5)
                        )
                        .frame(width: 16, height: 8)
                        .shadow(color: Color.black.opacity(0.12), radius: 1, y: 1)
                        .offset(y: thumbY)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDragging = true
                                    let newY = min(max(0, value.location.y - 4), trackHeight)
                                    let newPercent = 1.0 - (newY / trackHeight)
                                    let rawGain = minGain + Float(newPercent) * (maxGain - minGain)
                                    onGainChanged(abs(rawGain) < 0.4 ? 0.0 : Float(round(rawGain * 2) / 2))
                                }
                                .onEnded { _ in isDragging = false }
                        )
                }
            }
            .frame(width: 20, height: 120)

            Text(band.label)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 40)
        }
        .frame(width: 42)
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { onGainChanged(0.0) }
    }
}

#Preview {
    EqualizerView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .frame(width: 984, height: 280)
}
