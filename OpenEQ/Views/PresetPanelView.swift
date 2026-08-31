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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Save current curve as…", text: $newPresetName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(OpenEQTheme.recessedSlotBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 0.8))

                Button {
                    save()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Save")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(OpenEQTheme.accentCyan.opacity(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.2 : 0.9), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.black)
                }
                .buttonStyle(TactileButtonStyle())
                .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Save preset")
            }

            presetGroup("BUILT-IN PROFILES", presets: builtIn, custom: false)

            presetGroup("CUSTOM PRESETS", presets: custom, custom: true)

            Divider().opacity(0.15)

            HStack(spacing: 16) {
                Button {
                    viewModel.importPreset()
                } label: {
                    Label("Import Preset", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(TactileButtonStyle())

                Button {
                    viewModel.exportPreset(viewModel.selectedPreset)
                } label: {
                    Label("Export Current", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(TactileButtonStyle())
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(OpenEQTheme.accentCyan)
        }
    }

    @ViewBuilder
    private func presetGroup(_ title: String, presets: [EQPreset], custom: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)

            if presets.isEmpty {
                Text("No custom presets yet")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 2) {
                    ForEach(presets) { preset in
                        presetRow(preset, isCustom: custom)
                    }
                }
            }
        }
    }

    private func presetRow(_ preset: EQPreset, isCustom: Bool) -> some View {
        let selected = preset.id == viewModel.selectedPreset.id

        return HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    viewModel.applyPreset(preset)
                }
            } label: {
                HStack(spacing: 8) {
                    StudioLED(isOn: selected, activeColor: OpenEQTheme.accentCyan, inactiveColor: .clear, size: 6)

                    Text(preset.name)
                        .font(.system(size: 12, weight: selected ? .bold : .medium))
                        .foregroundStyle(selected ? .white : .secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(OpenEQTheme.accentCyan)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? OpenEQTheme.accentCyan.opacity(0.12) : Color.white.opacity(0.02))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(TactileButtonStyle())

            if isCustom {
                Button {
                    viewModel.deletePreset(id: preset.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(TactileButtonStyle())
            }
        }
    }

    private func save() {
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        viewModel.saveCurrentPreset(name: name, bands: viewModel.bands, preamp: viewModel.preamp)
        newPresetName = ""
    }
}

