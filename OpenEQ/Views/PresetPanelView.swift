import SwiftUI

struct PresetPanelView: View {
    let viewModel: OpenEQViewModel

    @State private var newPresetName = ""
    @State private var hoveredPresetId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Presets", systemImage: "slider.horizontal.below.rectangle")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 6) {
                TextField("New preset...", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                Button(action: savePreset) {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BUILT-IN")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)

                        ForEach(viewModel.presets.filter { preset in
                            EQPreset.defaultPresets().contains(where: { $0.id == preset.id })
                        }) { preset in
                            presetRow(preset: preset, isCustom: false)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("USER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)

                        let customPresets = viewModel.presets.filter { preset in
                            !EQPreset.defaultPresets().contains(where: { $0.id == preset.id })
                        }

                        if customPresets.isEmpty {
                            Text("No custom presets")
                                .font(.caption)
                                .foregroundStyle(.secondary.opacity(0.7))
                                .padding(.leading, 8)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(customPresets) { preset in
                                presetRow(preset: preset, isCustom: true)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button(action: { viewModel.importPreset() }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: { viewModel.exportPreset(viewModel.selectedPreset) }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func presetRow(preset: EQPreset, isCustom: Bool) -> some View {
        let isSelected = preset.id == viewModel.selectedPreset.id

        HStack {
            Button(action: { viewModel.applyPreset(preset) }) {
                HStack(spacing: 6) {
                    Image(systemName: isCustom ? "person.circle.fill" : "music.note")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .font(.system(size: 10))

                    Text(preset.name)
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isCustom {
                HStack(spacing: 4) {
                    Button(action: { viewModel.exportPreset(preset) }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: { viewModel.deletePreset(id: preset.id) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundStyle(hoveredPresetId == preset.id ? Color.red : Color.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .onHover { hovering in
            hoveredPresetId = hovering ? preset.id : (hoveredPresetId == preset.id ? nil : hoveredPresetId)
        }
    }

    private func savePreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        viewModel.saveCurrentPreset(name: name, bands: viewModel.bands, preamp: viewModel.preamp)
        newPresetName = ""
    }
}

#Preview {
    PresetPanelView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .frame(width: 280, height: 500)
}
