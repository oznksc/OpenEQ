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
        case .system:
            SystemAudioView(viewModel: viewModel, contentBottomPadding: bottomContentPadding)
        }
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
            .padding(.bottom, bottomContentPadding)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(OpenEQTheme.chassisBg)
    }

    private var comfortPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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

                ListeningComfortView(viewModel: viewModel)
            }
            .padding(24)
            .padding(.bottom, bottomContentPadding)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(OpenEQTheme.chassisBg)
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
            .padding(.bottom, bottomContentPadding)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
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
