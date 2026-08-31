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
        var icon: String { [Self.equalizer: "slider.vertical.3", .routing: "point.3.connected.trianglepath.dotted", .library: "square.stack", .system: "waveform"][self]! }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .equalizer: equalizerPage
                case .routing: routingPage
                case .library: libraryPage
                case .system: SystemAudioView(viewModel: viewModel)
                }
            }

            PlayerControlsView(viewModel: viewModel)
                .frame(maxWidth: 760)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        }
        .frame(width: OpenEQTheme.minWindowWidth, height: OpenEQTheme.minWindowHeight)
        .toolbarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { viewModel.refreshAudioProcesses() }
    }

    private var equalizerPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                EqualizerView(viewModel: viewModel)
                SpectrumView(title: viewModel.spectrumTitle, warning: viewModel.spectrumWarning, levels: viewModel.spectrumLevels, leftLevel: viewModel.leftLevel, rightLevel: viewModel.rightLevel, peakLevel: viewModel.peakLevel, isClipping: viewModel.isClipping)
            }
            .padding(24).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
        }.navigationTitle("Equalizer")
    }

    private var routingPage: some View {
        GraphWorkspaceView(viewModel: viewModel, store: graphStore)
            .navigationTitle("Routing")
            .inspector(isPresented: $viewModel.showGraphInspector) {
                NodeInspectorView(store: graphStore, viewModel: viewModel)
                    .inspectorColumnWidth(min: 300, ideal: 320, max: 380)
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { Button { viewModel.showGraphInspector.toggle() } label: { Image(systemName: "sidebar.trailing") }.help("Inspector") } }
    }

    private var libraryPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Presets and tools").font(.title2.weight(.semibold))
                GroupBox("Presets") { PresetPanelView(viewModel: viewModel).padding(12) }
                GroupBox("Headphone profiles") { HeadphoneLibraryView(viewModel: viewModel, searchText: .constant("")).padding(12) }
                GroupBox("Dynamics") { DynamicsPanelView(viewModel: viewModel).padding(12) }
                GroupBox("Audio Units") { AUv3PanelView(viewModel: viewModel).padding(12) }
            }.padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }.navigationTitle("Library")
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 3) {
                ForEach(MainTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Image(systemName: tab.icon)
                            .font(.body.weight(.semibold))
                            .imageScale(.large)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                    .background {
                        Capsule()
                            .fill(selectedTab == tab ? Color.accentColor.opacity(0.22) : (hoveredTab == tab ? Color.primary.opacity(0.10) : .clear))
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
            .frame(width: 440, height: 36)
            .background(.black.opacity(0.16), in: Capsule())
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { viewModel.setEnabled(!viewModel.isEnabled) } label: { Label(viewModel.isEnabled ? "EQ" : "Bypass", systemImage: viewModel.isEnabled ? "power.circle.fill" : "power.circle") }.tint(viewModel.isEnabled ? .green : .orange)
            Button { viewModel.resetEQ() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
        }
    }
}

#Preview { MainWindowView(viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())).frame(width: 1280, height: 800) }
