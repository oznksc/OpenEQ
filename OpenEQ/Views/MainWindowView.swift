import SwiftUI

struct MainWindowView: View {
    @Bindable var viewModel: OpenEQViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(
                    min: OpenEQTheme.minSidebarWidth,
                    ideal: OpenEQTheme.idealSidebarWidth,
                    max: OpenEQTheme.maxSidebarWidth
                )
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        // Keep toolbar chrome in the system safe area so sidebar search / content
        // sit below traffic lights and window toolbar actions.
        .toolbarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $viewModel.isShowingSystemAudio) {
            SystemAudioView(viewModel: viewModel)
        }
    }

    /// Single flat surface: spectrum → EQ → glass player. No content cards.
    private var detailColumn: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: OpenEQTheme.blockSpacing) {
                    SpectrumView(
                        title: viewModel.spectrumTitle,
                        warning: viewModel.spectrumWarning,
                        levels: viewModel.spectrumLevels,
                        leftLevel: viewModel.leftLevel,
                        rightLevel: viewModel.rightLevel,
                        peakLevel: viewModel.peakLevel,
                        isClipping: viewModel.isClipping
                    )
                    .frame(minHeight: 180)

                    EqualizerView(viewModel: viewModel)
                }
                .padding(OpenEQTheme.pagePadding)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            PlayerControlsView(viewModel: viewModel)
                .padding(.horizontal, OpenEQTheme.pagePadding)
                .padding(.bottom, OpenEQTheme.pagePadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(detailTitle)
        .navigationSubtitle(detailSubtitle)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 6) {
                OpenEQStatusDot(kind: statusKind)
                Text(statusLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospaced()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(statusLabel)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                viewModel.setEnabled(!viewModel.isEnabled)
            } label: {
                Label(
                    viewModel.isEnabled ? "EQ On" : "Bypassed",
                    systemImage: viewModel.isEnabled ? "power.circle.fill" : "power.circle"
                )
            }
            .help(viewModel.isEnabled ? "Bypass EQ (⌘B)" : "Enable EQ (⌘B)")
            .tint(viewModel.isEnabled ? .green : .orange)

            Button {
                viewModel.resetEQ()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .help("Reset EQ (⌘R)")
        }

        ToolbarItem(placement: .confirmationAction) {
            Button {
                viewModel.toggleSystemEQOneClick()
            } label: {
                Label(
                    viewModel.isSystemEQActive ? "System EQ On" : "System EQ",
                    systemImage: viewModel.isSystemEQActive ? "waveform.circle.fill" : "waveform.circle"
                )
            }
            .tint(viewModel.isSystemEQActive ? .green : nil)
            .help(viewModel.isSystemEQActive ? "Stop system-wide EQ" : "Start system-wide EQ")
        }

        ToolbarItem(placement: .automatic) {
            Button {
                viewModel.isShowingSystemAudio = true
            } label: {
                Label("System Audio", systemImage: "gearshape")
            }
            .help("System audio settings")
        }
    }

    private var detailTitle: String {
        if viewModel.isSystemEQActive { return "System EQ" }
        if viewModel.selectedFileURL != nil { return viewModel.selectedFileName }
        return "Equalizer"
    }

    private var detailSubtitle: String {
        if !viewModel.isEnabled { return "Bypassed" }
        return "\(viewModel.eqMode.title) · \(viewModel.selectedPreset.name)"
    }

    private var statusLabel: String {
        if viewModel.didTripFeedbackProtection { return "FEEDBACK" }
        if viewModel.isSystemEQActive {
            return viewModel.isEnabled ? "SYSTEM EQ" : "SYSTEM · BYPASS"
        }
        if viewModel.isExternalLoopbackActive { return "LOOPBACK" }
        return viewModel.playbackState.title.uppercased()
    }

    private var statusKind: OpenEQStatusDot.Kind {
        if viewModel.didTripFeedbackProtection { return .warning }
        if !viewModel.isEnabled && (viewModel.isSystemEQActive || viewModel.isExternalLoopbackActive) {
            return .bypassed
        }
        if viewModel.isSystemEQActive || viewModel.isExternalLoopbackActive { return .active }
        if case .failed = viewModel.systemAudioStatus { return .error }
        if viewModel.systemAudioStatus == .permissionRequired { return .warning }
        switch viewModel.playbackState {
        case .playing: return .active
        case .paused, .preparing, .ready: return .ready
        case .failed: return .error
        case .stopped, .idle: return .idle
        }
    }
}

#Preview {
    MainWindowView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .frame(width: 1100, height: 700)
}
