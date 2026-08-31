import SwiftUI

struct MainWindowView: View {
    @Bindable var viewModel: OpenEQViewModel
    @State private var selectedTab: MainTab = .equalizer
    @State private var hoveredTab: MainTab?
    private var graphStore: GraphStore { viewModel.graphStore }

    enum MainTab: String, CaseIterable, Identifiable {
        case equalizer, routing, library, system
        var id: Self { self }
        var title: String { [Self.equalizer: "Equalizer", .routing: "Routing", .library: "Library", .system: "System Audio"][self]! }
        var icon: String { [Self.equalizer: "slider.vertical.3", .routing: "point.3.connected.trianglepath.dotted", .library: "square.stack.3d.up", .system: "waveform.badge.magnifyingglass"][self]! }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main Chassis Background
            OpenEQTheme.chassisBg.ignoresSafeArea()

            Group {
                switch selectedTab {
                case .equalizer: equalizerPage
                case .routing: routingPage
                case .library: libraryPage
                case .system: SystemAudioView(viewModel: viewModel)
                }
            }

            if selectedTab != .routing {
                PlayerControlsView(viewModel: viewModel)
                    .frame(maxWidth: 780)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .frame(width: OpenEQTheme.minWindowWidth, height: OpenEQTheme.minWindowHeight)
        .toolbarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { viewModel.refreshAudioProcesses() }
    }

    private var equalizerPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EqualizerView(viewModel: viewModel)
                SpectrumView(
                    title: viewModel.spectrumTitle,
                    warning: viewModel.spectrumWarning,
                    levels: viewModel.spectrumLevels,
                    leftLevel: viewModel.leftLevel,
                    rightLevel: viewModel.rightLevel,
                    peakLevel: viewModel.peakLevel,
                    isClipping: viewModel.isClipping
                )
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var routingPage: some View {
        GraphWorkspaceView(viewModel: viewModel, store: graphStore)
            .inspector(isPresented: $viewModel.showGraphInspector) {
                NodeInspectorView(store: graphStore, viewModel: viewModel)
                    .inspectorColumnWidth(min: 300, ideal: 320, max: 380)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showGraphInspector.toggle()
                    } label: {
                        Image(systemName: "sidebar.trailing")
                    }
                    .help("Inspector")
                }
            }
    }

    private var libraryPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.title3)
                        .foregroundStyle(OpenEQTheme.accentCyan)
                    Text("Presets & Audio Rack Modules")
                        .font(.title3.weight(.bold))
                }

                rackModule("Presets", icon: "bookmark.fill") {
                    PresetPanelView(viewModel: viewModel).padding(14)
                }

                rackModule("Headphone Calibration Library", icon: "headphones") {
                    HeadphoneLibraryView(viewModel: viewModel, searchText: .constant("")).padding(14)
                }

                rackModule("Dynamics & Compressor", icon: "waveform.path.ecg") {
                    DynamicsPanelView(viewModel: viewModel).padding(14)
                }

                rackModule("AUv3 Effect Units", icon: "puzzlepiece.extension.fill") {
                    AUv3PanelView(viewModel: viewModel).padding(14)
                }
            }
            .padding(24)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func rackModule<Content: View>(_ title: String, icon: String? = nil, @ViewBuilder content: () -> Content) -> some View {
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

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 2) {
                ForEach(MainTab.allCases) { tab in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 12, weight: selectedTab == tab ? .bold : .medium))
                        }
                        .foregroundStyle(selectedTab == tab ? .white : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background {
                        if selectedTab == tab {
                            Capsule()
                                .fill(Color.white.opacity(0.14))
                                .overlay {
                                    Capsule()
                                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                                }
                        } else if hoveredTab == tab {
                            Capsule()
                                .fill(Color.white.opacity(0.06))
                        }
                    }
                    .onHover { isHovering in
                        hoveredTab = isHovering ? tab : nil
                    }
                    .help(tab.title)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(3)
            .frame(width: 480, height: 36)
            .background {
                Capsule()
                    .fill(OpenEQTheme.recessedSlotBg)
                    .overlay {
                        Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                viewModel.setEnabled(!viewModel.isEnabled)
            } label: {
                HStack(spacing: 6) {
                    StudioLED(isOn: viewModel.isEnabled, activeColor: OpenEQTheme.accentGreen, inactiveColor: OpenEQTheme.accentAmber, size: 7)
                    Text(viewModel.isEnabled ? "EQ ACTIVE" : "BYPASSED")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(TactileButtonStyle())
            .help(viewModel.isEnabled ? "Bypass EQ (⌘B)" : "Enable EQ (⌘B)")

            Button {
                viewModel.resetEQ()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(TactileButtonStyle())
            .help("Reset EQ")
        }
    }
}

#Preview { MainWindowView(viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())).frame(width: 1280, height: 800) }

