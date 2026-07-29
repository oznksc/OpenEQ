import SwiftUI

struct AUv3PanelView: View {
    @Bindable var viewModel: OpenEQViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("AUv3 Insert", systemImage: "puzzlepiece.extension")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    viewModel.refreshAUPlugins()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Rescan installed Audio Units")
            }

            Text("Local playback chain only. System-wide AU hosting is not available yet.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.availableAUPlugins.isEmpty {
                Text("No effect Audio Units found. Click refresh after installing plugins.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.loadSelectedAUPlugin()
                } label: {
                    Label("Load", systemImage: "plus.circle")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.selectedAUPluginID == nil || viewModel.isLoadingAUPlugin)

                Button {
                    viewModel.unloadAUPlugin()
                } label: {
                    Label("Unload", systemImage: "minus.circle")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.loadedAUPluginName == nil)
            }

            if viewModel.isLoadingAUPlugin {
                ProgressView()
                    .controlSize(.small)
            }

            if let loaded = viewModel.loadedAUPluginName {
                Label(loaded, systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .lineLimit(2)
            }

            if let error = viewModel.auPluginError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .cornerRadius(10)
        .onAppear {
            if viewModel.availableAUPlugins.isEmpty {
                viewModel.refreshAUPlugins()
            }
        }
    }
}
