import SwiftUI
import AppKit
import Combine

struct MainWindowView: View {
    @Bindable var viewModel: OpenEQViewModel
    @State private var selectedTab: MainTab = .equalizer
    @State private var hoveredTab: MainTab?
    @State private var isShowingNodePalette = false
    @State private var bottomBarHeight = OpenEQTheme.bottomBarReservedSpace
    private let comfortTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var graphStore: GraphStore { viewModel.graphStore }

    private struct BottomBarHeightPreferenceKey: PreferenceKey {
        static let defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    enum MainTab: String, CaseIterable, Identifiable {
        case equalizer, comfort, routing, library, system
        var id: Self { self }
        var title: String { [Self.equalizer: "Equalizer", .comfort: "Comfort", .routing: "Routing", .library: "Library", .system: "System Audio"][self]! }
        var icon: String { [Self.equalizer: "slider.vertical.3", .comfort: "ear.and.waveform", .routing: "point.3.connected.trianglepath.dotted", .library: "square.stack.3d.up", .system: "waveform.badge.magnifyingglass"][self]! }
    }

    var body: some View {
        ZStack {
            // Main Chassis Background
            OpenEQTheme.chassisBg.ignoresSafeArea()

            MainWindowTabContent(
                selectedTab: selectedTab,
                viewModel: viewModel,
                graphStore: graphStore,
                bottomContentPadding: bottomContentPadding
            )

            if selectedTab == .routing,
               viewModel.showGraphInspector,
               graphStore.selectedNode != nil {
                routingInspectorPanel
                    .padding(.horizontal, 24)
                    .padding(.bottom, 54)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(10)
            }
        }
        .overlay(alignment: .bottom) {
            bottomBar
        }
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .animation(.easeInOut(duration: 0.16), value: viewModel.showGraphInspector)
        .frame(width: OpenEQTheme.minWindowWidth, height: OpenEQTheme.minWindowHeight)
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { viewModel.refreshAudioProcesses() }
        .onPreferenceChange(BottomBarHeightPreferenceKey.self) { height in
            guard height > 0, abs(height - bottomBarHeight) > 0.5 else { return }
            bottomBarHeight = height
        }
        .onReceive(comfortTimer) { _ in
            viewModel.updateListeningComfort(elapsed: 1)
        }
    }

    private var bottomContentPadding: CGFloat {
        bottomBarHeight * 1.1
    }

    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 10) {
            brandLogoBadge

            if selectedTab == .routing {
                nodesButton
            }

            Spacer(minLength: 0)

            if selectedTab != .routing {
                PlayerControlsView(viewModel: viewModel)
                    .frame(maxWidth: 760)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer(minLength: 0)

            bottomTrailingControls
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: BottomBarHeightPreferenceKey.self,
                    value: geometry.size.height
                )
            }
        }
    }

    private var isGraphRunning: Bool {
        viewModel.isSystemEQActive || viewModel.isExternalLoopbackActive
    }

    private var graphRunButton: some View {
        Button {
            viewModel.toggleGraph()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isGraphRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(isGraphRunning ? "Stop Routing" : "Run Routing")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7.5)
            .background(
                isGraphRunning ? OpenEQTheme.accentRed : OpenEQTheme.accentCyan,
                in: Capsule()
            )
            .foregroundStyle(isGraphRunning ? .white : .black)
        }
        .buttonStyle(TactileButtonStyle(pressedScale: 0.95))
        .help(isGraphRunning ? "Stop Routing (⌘↩)" : "Run Routing (⌘↩)")
    }

    private var bottomTrailingControls: some View {
        HStack(spacing: 10) {
            if selectedTab == .routing {
                graphRunButton
            }

            eqStatusControl
        }
        .frame(minWidth: 174, alignment: .trailing)
    }

    private var eqStatusControl: some View {
        HStack(spacing: 2) {
            eqStatusSegment(
                title: "ACTIVE",
                icon: "checkmark.circle.fill",
                isSelected: viewModel.isEnabled,
                color: OpenEQTheme.accentGreen,
                action: { viewModel.setEnabled(true) }
            )

            eqStatusSegment(
                title: "BYPASS",
                icon: "circle.slash",
                isSelected: !viewModel.isEnabled,
                color: OpenEQTheme.accentAmber,
                action: { viewModel.setEnabled(false) }
            )
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.24), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Equalizer state")
    }

    private func eqStatusSegment(
        title: String,
        icon: String,
        isSelected: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                action()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
            }
            .foregroundStyle(isSelected ? color : .secondary)
            .frame(width: 72, height: 26)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                Capsule()
                    .fill(color.opacity(0.18))
                    .overlay {
                        Capsule()
                            .stroke(color.opacity(0.38), lineWidth: 0.8)
                    }
            }
        }
        .accessibilityLabel(title == "ACTIVE" ? "Equalizer active" : "Equalizer bypassed")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var routingInspectorPanel: some View {
        NodeInspectorView(
            store: graphStore,
            viewModel: viewModel,
            onClose: { viewModel.showGraphInspector = false }
        )
        .frame(width: 420)
        .padding(6)
        .background(OpenEQTheme.cardBgElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.55), radius: 24, x: 0, y: -8)
    }

    private var nodesButton: some View {
        Button {
            isShowingNodePalette.toggle()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(OpenEQTheme.accentCyan.opacity(0.16))
                        .frame(width: 22, height: 22)

                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(OpenEQTheme.accentCyan)
                }

                Text("Nodes")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .tracking(0.3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(OpenEQTheme.cardBgElevated, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(isShowingNodePalette ? OpenEQTheme.accentCyan.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingNodePalette, arrowEdge: .top) {
            GraphPaletteView(
                store: graphStore,
                processes: viewModel.audioProcesses,
                inputDevices: viewModel.availableInputDevices,
                outputDevices: viewModel.availableOutputDevices,
                onOpenFile: { viewModel.openAudioFile() }
            )
            .frame(width: 270, height: 420)
            .background(OpenEQTheme.chassisBg)
        }
        .help("Node Library / Add Nodes")
    }

    private var brandLogoBadge: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            Text("OpenEQ")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .tracking(0.3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(OpenEQTheme.cardBgElevated, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
        )
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
                            if selectedTab == tab {
                                Text(tab.title)
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                        .foregroundStyle(selectedTab == tab ? .white : .secondary)
                        .padding(.horizontal, selectedTab == tab ? 10 : 0)
                        .frame(height: 30)
                        .frame(width: selectedTab == tab ? nil : 30)
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
            .frame(height: 36)
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
                viewModel.resetEQ()
            } label: {
                Label("Reset EQ", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(TactileButtonStyle())
            .help("Reset EQ to a flat response")
        }
    }
}

#Preview { MainWindowView(viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())).frame(width: 1280, height: 800) }
