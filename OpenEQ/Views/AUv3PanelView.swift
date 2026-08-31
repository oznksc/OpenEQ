import SwiftUI

struct AUv3PanelView: View {
    @Bindable var viewModel: OpenEQViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.availableAUPlugins.isEmpty {
                Text("No Audio Unit effect plugins detected")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                Picker("Plugin", selection: Binding(
                    get: { viewModel.selectedAUPluginID },
                    set: { viewModel.selectedAUPluginID = $0 }
                )) {
                    Text("None Selected").tag(String?.none)
                    ForEach(viewModel.availableAUPlugins) { plugin in
                        Text(plugin.displayName).tag(Optional(plugin.id))
                    }
                }
                .labelsHidden()
            }

            HStack(spacing: 12) {
                Button("Load Unit") {
                    viewModel.loadSelectedAUPlugin()
                }
                .buttonStyle(TactileButtonStyle())
                .disabled(viewModel.selectedAUPluginID == nil || viewModel.isLoadingAUPlugin)

                Button("Unload") {
                    viewModel.unloadAUPlugin()
                }
                .buttonStyle(TactileButtonStyle())
                .disabled(viewModel.loadedAUPluginName == nil)

                Button {
                    viewModel.refreshAUPlugins()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(TactileButtonStyle())
                .help("Rescan AUv3 plugins")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(OpenEQTheme.accentCyan)

            if viewModel.isLoadingAUPlugin {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading Audio Unit…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let loaded = viewModel.loadedAUPluginName {
                HStack(spacing: 6) {
                    StudioLED(isOn: true, activeColor: OpenEQTheme.accentGreen, size: 6)
                    Text("Active: \(loaded)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(OpenEQTheme.accentGreen)
                        .lineLimit(2)
                }
            }

            if let error = viewModel.auPluginError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(OpenEQTheme.accentRed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Local playback graph insert only")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.tertiary)
        }
        .onAppear {
            if viewModel.availableAUPlugins.isEmpty {
                viewModel.refreshAUPlugins()
            }
        }
    }
}

