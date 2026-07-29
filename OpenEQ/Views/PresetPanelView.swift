import SwiftUI

struct PresetPanelView: View {
    let viewModel: OpenEQViewModel
    @State private var newPresetName = ""

    private var builtIn: [EQPreset] {
        viewModel.presets.filter { p in
            EQPreset.defaultPresets().contains { $0.id == p.id }
        }
    }

    private var custom: [EQPreset] {
        viewModel.presets.filter { p in
            !EQPreset.defaultPresets().contains { $0.id == p.id }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Save as…", text: $newPresetName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button {
                    save()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Save preset")
            }

            presetGroup("Built-in", presets: builtIn, custom: false)

            presetGroup("Yours", presets: custom, custom: true)

            HStack(spacing: 16) {
                Button("Import") { viewModel.importPreset() }
                    .buttonStyle(.borderless)
                Button("Export") { viewModel.exportPreset(viewModel.selectedPreset) }
                    .buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func presetGroup(_ title: String, presets: [EQPreset], custom: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)

            if presets.isEmpty {
                Text("None yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(presets) { preset in
                    presetRow(preset, isCustom: custom)
                }
            }
        }
    }

    private func presetRow(_ preset: EQPreset, isCustom: Bool) -> some View {
        let selected = preset.id == viewModel.selectedPreset.id

        return HStack(spacing: 8) {
            Button {
                viewModel.applyPreset(preset)
            } label: {
                HStack {
                    Text(preset.name)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isCustom {
                Button {
                    viewModel.deletePreset(id: preset.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
    }

    private func save() {
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        viewModel.saveCurrentPreset(name: name, bands: viewModel.bands, preamp: viewModel.preamp)
        newPresetName = ""
    }
}
