import SwiftUI

struct AUv3PanelView: View {
    @Bindable var viewModel: OpenEQViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.availableAUPlugins.isEmpty {
                Text("No effect units found")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Picker("Plugin", selection: Binding(
                    get: { viewModel.selectedAUPluginID },
                    set: { viewModel.selectedAUPluginID = $0 }
                )) {
                    Text("None").tag(String?.none)
                    ForEach(viewModel.availableAUPlugins) { plugin in
                        Text(plugin.displayName).tag(Optional(plugin.id))
                    }
                }
                .labelsHidden()
            }

            HStack(spacing: 16) {
                Button("Load") { viewModel.loadSelectedAUPlugin() }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.selectedAUPluginID == nil || viewModel.isLoadingAUPlugin)

                Button("Unload") { viewModel.unloadAUPlugin() }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.loadedAUPluginName == nil)

                Button {
                    viewModel.refreshAUPlugins()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Rescan")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if viewModel.isLoadingAUPlugin {
                ProgressView()
                    .controlSize(.small)
            }

            if let loaded = viewModel.loadedAUPluginName {
                Text(loaded)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(2)
            }

            if let error = viewModel.auPluginError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Local playback only")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .onAppear {
            if viewModel.availableAUPlugins.isEmpty {
                viewModel.refreshAUPlugins()
            }
        }
    }
}
