import SwiftUI

struct MainWindowTabContent: View {
    let selectedTab: MainWindowView.MainTab
    @Bindable var viewModel: OpenEQViewModel
    let graphStore: GraphStore
    let bottomContentPadding: CGFloat

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
        }
    }

    private var equalizerPage: some View {
        ZStack(alignment: .bottom) {
            SpectrumBackdropView(
                levels: viewModel.spectrumLevels,
                title: viewModel.spectrumTitle,
                isSystemAudio: viewModel.isSystemAudioVisualizationActive
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

    @State private var peakLevels = SpectrumLevels()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Canvas { context, size in
                let count = levels.count
                guard count > 0 else { return }

                let gap: CGFloat = 3
                let barWidth = max(1, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
                let baseline = size.height - 12
                let usableHeight = max(1, baseline - 14)

                var trace = Path()
                for index in 0..<count {
                    let level = CGFloat(max(0, min(1, levels[index])))
                    let peak = CGFloat(max(0, min(1, peakLevels[index])))
                    let x = CGFloat(index) * (barWidth + gap)
                    let height = max(2, usableHeight * level)
                    let barRect = CGRect(x: x, y: baseline - height, width: barWidth, height: height)

                    context.fill(
                        Path(roundedRect: barRect, cornerRadius: min(3, barWidth / 2)),
                        with: .linearGradient(
                            Gradient(colors: [
                                OpenEQTheme.accentPurple.opacity(0.12),
                                OpenEQTheme.accentCyan.opacity(0.50)
                            ]),
                            startPoint: CGPoint(x: 0, y: barRect.minY),
                            endPoint: CGPoint(x: 0, y: barRect.maxY)
                        )
                    )

                    let peakY = baseline - usableHeight * peak
                    context.fill(
                        Path(CGRect(x: x, y: peakY, width: barWidth, height: 1)),
                        with: .color(OpenEQTheme.accentCyan.opacity(0.62))
                    )

                    let tracePoint = CGPoint(x: x + barWidth / 2, y: baseline - usableHeight * (0.08 + level * 0.84))
                    if index == 0 {
                        trace.move(to: tracePoint)
                    } else {
                        trace.addLine(to: tracePoint)
                    }
                }

                context.stroke(
                    trace,
                    with: .color(OpenEQTheme.accentCyan.opacity(0.72)),
                    style: StrokeStyle(lineWidth: 1.2, lineJoin: .round)
                )

                var baselinePath = Path()
                baselinePath.move(to: CGPoint(x: 0, y: baseline))
                baselinePath.addLine(to: CGPoint(x: size.width, y: baseline))
                context.stroke(baselinePath, with: .color(OpenEQTheme.accentCyan.opacity(0.18)), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [OpenEQTheme.chassisBg, OpenEQTheme.chassisBg.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 150)
                .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    StudioLED(isOn: levels.contains(where: { $0 > 0.02 }), activeColor: OpenEQTheme.accentCyan, size: 6)
                    Text("REALTIME FFT SPECTRUM")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(OpenEQTheme.accentCyan.opacity(0.7))
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
        .frame(height: 320)
        .padding(.horizontal, 24)
        .opacity(0.8)
        .allowsHitTesting(false)
        .onChange(of: levels) { _, newValue in
            updatePeaks(with: newValue)
        }
        .accessibilityHidden(true)
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
