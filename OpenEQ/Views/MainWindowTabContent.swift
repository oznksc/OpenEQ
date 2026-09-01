import SwiftUI

struct MainWindowTabContent: View {
    let selectedTab: MainWindowView.MainTab
    @Bindable var viewModel: OpenEQViewModel
    let graphStore: GraphStore
    let bottomContentPadding: CGFloat
    @Binding var spectrumStyle: SpectrumVisualizationStyle

    @ViewBuilder
    var body: some View {
        switch selectedTab {
        case .equalizer:
            equalizerPage
        case .comfort:
            comfortPage
        case .routing:
            GraphWorkspaceView(viewModel: viewModel, store: graphStore)
        case .library:
            libraryPage
        case .settings:
            settingsPage
        }
    }

    private var equalizerPage: some View {
        ZStack(alignment: .bottom) {
            SpectrumBackdropView(
                levels: viewModel.spectrumLevels,
                title: viewModel.spectrumTitle,
                isSystemAudio: viewModel.isSystemAudioVisualizationActive,
                style: spectrumStyle
            )
            .offset(y: 68)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    EqualizerView(viewModel: viewModel)
                }
                .padding(24)
                .padding(.bottom, bottomContentPadding)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .background(OpenEQTheme.chassisBg)
    }

    private var settingsPage: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                SettingsSpectrumDemo(style: spectrumStyle)
                    .frame(height: geometry.size.height * 0.5)
                    .mask {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.82), .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(OpenEQTheme.accentCyan)
                Text("Settings")
                    .font(.title3.weight(.bold))
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("SPECTRUM THEME")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(.secondary)

                Text("Choose the visual style used behind the equalizer.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(SpectrumVisualizationStyle.allCases) { style in
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                                spectrumStyle = style
                            }
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: style.icon)
                                    .foregroundStyle(style.accentColor)
                                Text(style.title)
                                    .font(.system(size: 12, weight: spectrumStyle == style ? .bold : .medium))
                                Spacer(minLength: 0)
                                if spectrumStyle == style {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(OpenEQTheme.accentCyan)
                                }
                            }
                            .padding(12)
                            .background(
                                spectrumStyle == style
                                    ? OpenEQTheme.accentCyan.opacity(0.12)
                                    : OpenEQTheme.recessedSlotBg,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(spectrumStyle == style ? OpenEQTheme.accentCyan.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.8)
                            }
                        }
                        .buttonStyle(TactileButtonStyle())
                    }
                }
            }
            .padding(18)
            .studioCard(cornerRadius: 14)
        }
                .padding(24)
                .padding(.bottom, bottomContentPadding)
                .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(OpenEQTheme.chassisBg)
    }

    private var comfortPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "ear.and.waveform")
                        .font(.title3)
                        .foregroundStyle(OpenEQTheme.accentPurple)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Listening Comfort")
                            .font(.title3.weight(.bold))
                        Text("Keep an eye on session load and give your ears an easier listen.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("REAL-TIME EAR HEALTH")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(OpenEQTheme.accentPurple.opacity(0.75))
            }

            HStack(alignment: .top, spacing: 18) {
                ListeningComfortView(viewModel: viewModel)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 14) {
                    comfortInsight("Session awareness", "Comfort Guard watches exposure and spectral strain while you listen.", "waveform.path.ecg", OpenEQTheme.accentCyan)
                    comfortInsight("Gentle by design", "Relief is reversible and only appears when high-frequency load rises.", "wand.and.stars", OpenEQTheme.accentPurple)
                }
                .frame(width: 260)
            }
        }
        .padding(28)
        .padding(.bottom, bottomContentPadding)
        .frame(maxWidth: 1120, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OpenEQTheme.chassisBg)
    }

    private func comfortInsight(_ title: String, _ detail: String, _ icon: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .bold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard(cornerRadius: 14)
    }

    private var libraryPage: some View {
        VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.title3)
                        .foregroundStyle(OpenEQTheme.accentCyan)
                    Text("Presets & Audio Rack Modules")
                        .font(.title3.weight(.bold))
                }

            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 14) {
                    rackModule("Presets", icon: "bookmark.fill") {
                    PresetPanelView(viewModel: viewModel).padding(14)
                    }

                    rackModule("Headphone Calibration Library", icon: "headphones") {
                    HeadphoneLibraryView(viewModel: viewModel, searchText: .constant("")).padding(14)
                    }
                }

                VStack(spacing: 14) {
                    rackModule("Dynamics & Compressor", icon: "waveform.path.ecg") {
                    DynamicsPanelView(viewModel: viewModel).padding(14)
                    }

                    rackModule("AUv3 Effect Units", icon: "puzzlepiece.extension.fill") {
                    AUv3PanelView(viewModel: viewModel).padding(14)
                    }
                }
            }
        }
        .padding(24)
        .padding(.bottom, bottomContentPadding)
        .frame(maxWidth: 1100, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OpenEQTheme.chassisBg)
    }

    private func rackModule<Content: View>(
        _ title: String,
        icon: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(OpenEQTheme.accentCyan)
                }
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            content()
        }
        .studioCard(cornerRadius: 12)
    }
}

private struct SpectrumBackdropView: View {
    let levels: SpectrumLevels
    let title: String
    let isSystemAudio: Bool
    let style: SpectrumVisualizationStyle
    var height: CGFloat = 320

    @State private var peakLevels = SpectrumLevels()
    @State private var idleLevels = Self.makeIdleLevels()
    @State private var displayedLevels = SpectrumLevels()
    @State private var latestLevels = SpectrumLevels()
    @State private var peakVisibility: Float = 0

    private var hasLiveSignal: Bool {
        latestLevels.contains { $0 > 0.02 }
    }

    private var targetLevels: SpectrumLevels {
        hasLiveSignal ? latestLevels : idleLevels
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if style == .globe {
                SpectrumGlobeView(levels: displayedLevels)
                    .frame(width: 270, height: 270)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .offset(y: 72)
            } else {
                Canvas { context, size in
                let count = displayedLevels.count
                guard count > 0 else { return }

                let gap: CGFloat = 3
                let barWidth = max(1, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
                let baseline = size.height - 12
                let usableHeight = max(1, baseline - 14)

                var trace = Path()
                var auroraArea = Path()
                auroraArea.move(to: CGPoint(x: 0, y: baseline))
                for index in 0..<count {
                    let level = CGFloat(max(0, min(1, displayedLevels[index])))
                    let peak = CGFloat(max(0, min(1, peakLevels[index])))
                    let x = CGFloat(index) * (barWidth + gap)
                    let height = max(2, usableHeight * level)
                    let barRect = CGRect(x: x, y: baseline - height, width: barWidth, height: height)

                    let tracePoint = CGPoint(x: x + barWidth / 2, y: baseline - usableHeight * (0.08 + level * 0.84))
                    if index == 0 {
                        trace.move(to: tracePoint)
                    } else {
                        trace.addLine(to: tracePoint)
                    }

                    switch style {
                    case .neon:
                        context.fill(
                            Path(roundedRect: barRect, cornerRadius: min(3, barWidth / 2)),
                            with: .linearGradient(
                                Gradient(colors: [OpenEQTheme.accentPurple.opacity(0.12), OpenEQTheme.accentCyan.opacity(0.50)]),
                                startPoint: CGPoint(x: 0, y: barRect.minY),
                                endPoint: CGPoint(x: 0, y: barRect.maxY)
                            )
                        )
                    case .aurora:
                        auroraArea.addLine(to: tracePoint)
                    case .ember:
                        context.fill(
                            Path(roundedRect: barRect, cornerRadius: min(5, barWidth / 2)),
                            with: .linearGradient(
                                Gradient(colors: [OpenEQTheme.accentAmber.opacity(0.18), Color.red.opacity(0.58)]),
                                startPoint: CGPoint(x: 0, y: barRect.minY),
                                endPoint: CGPoint(x: 0, y: barRect.maxY)
                            )
                        )
                    case .prism:
                        let prismRect = CGRect(
                            x: x + barWidth * 0.28,
                            y: barRect.minY,
                            width: max(1, barWidth * 0.44),
                            height: barRect.height
                        )
                        context.fill(
                            Path(roundedRect: prismRect, cornerRadius: prismRect.width / 2),
                            with: .linearGradient(
                                Gradient(colors: [Color.blue.opacity(0.12), Color.cyan.opacity(0.82), Color.white.opacity(0.55)]),
                                startPoint: CGPoint(x: prismRect.midX, y: prismRect.maxY),
                                endPoint: CGPoint(x: prismRect.midX, y: prismRect.minY)
                            )
                        )
                    case .orbit:
                        let radius = 2 + level * 5
                        let orb = CGRect(x: tracePoint.x - radius, y: tracePoint.y - radius, width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: orb), with: .color(Color.pink.opacity(0.72)))
                    case .matrix:
                        let blockCount = max(1, Int(ceil(level * 8)))
                        let blockHeight = usableHeight / 10
                        for block in 0..<blockCount {
                            let blockRect = CGRect(
                                x: x + 0.5,
                                y: baseline - CGFloat(block + 1) * blockHeight,
                                width: max(1, barWidth - 1),
                                height: max(1, blockHeight - 2)
                            )
                            context.fill(
                                Path(roundedRect: blockRect, cornerRadius: 1),
                                with: .color(Color.green.opacity(0.25 + Double(block) * 0.06))
                            )
                        }
                    case .globe:
                        break
                    }

                    if style != .aurora {
                        let peakY = baseline - usableHeight * peak
                        context.fill(
                            Path(CGRect(x: x, y: peakY, width: barWidth, height: 1)),
                            with: .color(style.accentColor.opacity(Double(0.68 * peakVisibility)))
                        )
                    }
                }

                if style == .aurora {
                    auroraArea.addLine(to: CGPoint(x: size.width, y: baseline))
                    auroraArea.closeSubpath()
                    context.fill(
                        auroraArea,
                        with: .linearGradient(
                            Gradient(colors: [OpenEQTheme.accentPurple.opacity(0.52), OpenEQTheme.accentCyan.opacity(0.04)]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: baseline)
                        )
                    )
                }

                context.stroke(trace, with: .color(style.accentColor.opacity(0.78)), style: StrokeStyle(lineWidth: style == .aurora ? 2 : 1.2, lineJoin: .round))

                var baselinePath = Path()
                baselinePath.move(to: CGPoint(x: 0, y: baseline))
                baselinePath.addLine(to: CGPoint(x: size.width, y: baseline))
                context.stroke(baselinePath, with: .color(style.accentColor.opacity(0.2)), lineWidth: 1)
            }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    StudioLED(isOn: hasLiveSignal, activeColor: style.accentColor, size: 6)
                    Text("REALTIME FFT SPECTRUM")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(style.accentColor.opacity(0.7))
                }
                HStack(spacing: 5) {
                    Text(title.uppercased())
                    Text("·")
                    Text(isSystemAudio ? "PROCESS TAP" : "LOCAL PLAYBACK")
                }
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSystemAudio ? OpenEQTheme.accentAmber.opacity(0.72) : .secondary.opacity(0.55))
            }
            .padding(.leading, 10)
            .padding(.bottom, 25)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .opacity(0.8)
        .allowsHitTesting(false)
        .onChange(of: levels, initial: true) { _, newValue in
            latestLevels = newValue
        }
        .task {
            while !Task.isCancelled {
                smoothSpectrumStep()

                do {
                    try await Task.sleep(for: .milliseconds(33))
                } catch {
                    return
                }
            }
        }
        .accessibilityHidden(true)
    }

    private static func makeIdleLevels() -> SpectrumLevels {
        var result = SpectrumLevels()

        for index in result.indices {
            let position = Float(index) / Float(max(1, result.count - 1))
            let contour = 0.085 + 0.05 * sin(position * .pi * 3.4)
            let rolloff = 0.065 * (1 - position)
            let idleLevel = max(0.06, contour + rolloff + Float.random(in: 0.015...0.085))
            result[index] = min(1, idleLevel * 1.3)
        }

        return result
    }

    private func smoothSpectrumStep() {
        let target = targetLevels
        let targetPeakVisibility: Float = hasLiveSignal ? 1 : 0
        let peakSmoothing: Float = hasLiveSignal ? 0.2 : 0.12
        peakVisibility += (targetPeakVisibility - peakVisibility) * peakSmoothing

        for index in displayedLevels.indices {
            let current = displayedLevels[index]
            let smoothing: Float = target[index] > current ? 0.18 : 0.09
            displayedLevels[index] = current + (target[index] - current) * smoothing
        }

        if hasLiveSignal {
            updatePeaks(with: displayedLevels)
        }
    }

    private func updatePeaks(with current: SpectrumLevels) {
        if peakLevels.count != current.count {
            peakLevels = current
            return
        }

        for index in current.indices {
            if current[index] >= peakLevels[index] {
                peakLevels[index] = current[index]
            } else {
                peakLevels[index] = max(0, peakLevels[index] - 0.028)
            }
        }
    }
}

private struct SettingsSpectrumDemo: View {
    let style: SpectrumVisualizationStyle

    @State private var levels = SpectrumLevels()
    @State private var phase: Float = 0

    var body: some View {
        GeometryReader { geometry in
            SpectrumBackdropView(
                levels: levels,
                title: "Theme Preview",
                isSystemAudio: false,
                style: style,
                height: geometry.size.height
            )
        }
        .task {
            while !Task.isCancelled {
                updateLevels()
                do {
                    try await Task.sleep(for: .milliseconds(170))
                } catch {
                    return
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func updateLevels() {
        phase += Float.random(in: 0.16...0.34)

        for index in levels.indices {
            let position = Float(index) / Float(max(1, levels.count - 1))
            let wave = 0.22 * (sin(phase + position * 12) + 1) / 2
            let pulse = 0.25 * (sin(phase * 0.7 + position * 5.5) + 1) / 2
            let rolloff = 0.24 * (1 - position)
            let noise = Float.random(in: 0.02...0.24)
            levels[index] = min(0.96, 0.08 + wave + pulse + rolloff + noise)
        }
    }
}
