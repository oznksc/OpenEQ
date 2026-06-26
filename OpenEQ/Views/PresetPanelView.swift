//
//  PresetPanelView.swift
//  OpenEQ
//
//  Created by Gökmen on 26.06.2026.
//

import SwiftUI

struct PresetPanelView: View {
    let viewModel: OpenEQViewModel

    @State private var newPresetName = ""
    @State private var hoveredPresetId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            Label("Presets Manager", systemImage: "slider.horizontal.below.rectangle")
                .font(.headline)
                .foregroundStyle(.primary)

            // Preset Saving Form
            VStack(alignment: .leading, spacing: 8) {
                Text("Save Current EQ State")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    TextField("New Preset Name...", text: $newPresetName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                    
                    Button(action: savePreset) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Save current bands to preset")
                    .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )

            // Presets List
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    
                    // SECTION: Built-in Presets
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BUILT-IN PRESETS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        
                        ForEach(viewModel.presets.filter { preset in
                            EQPreset.defaultPresets().contains(where: { $0.id == preset.id })
                        }) { preset in
                            presetRow(preset: preset, isCustom: false)
                        }
                    }
                    
                    // SECTION: Custom User Presets
                    VStack(alignment: .leading, spacing: 6) {
                        Text("USER PRESETS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        
                        let customPresets = viewModel.presets.filter { preset in
                            !EQPreset.defaultPresets().contains(where: { $0.id == preset.id })
                        }
                        
                        if customPresets.isEmpty {
                            Text("No custom presets yet")
                                .font(.caption)
                                .foregroundStyle(.secondary.opacity(0.7))
                                .padding(.leading, 12)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(customPresets) { preset in
                                presetRow(preset: preset, isCustom: true)
                            }
                        }
                    }
                }
            }

            Divider()

            // Bottom Actions (Import/Export Interface)
            HStack(spacing: 12) {
                Button(action: {
                    viewModel.importPreset()
                }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("Import preset from JSON")
                
                Button(action: {
                    viewModel.exportPreset(viewModel.selectedPreset)
                }) {
                    Label("Export Active", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("Export currently active preset to JSON")
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Reusable Preset List Row
    @ViewBuilder
    private func presetRow(preset: EQPreset, isCustom: Bool) -> some View {
        let isSelected = preset.id == viewModel.selectedPreset.id
        
        HStack {
            Button(action: {
                viewModel.applyPreset(preset)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isCustom ? "person.circle.fill" : "music.note")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .font(.system(size: 11))
                    
                    Text(preset.name)
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Actions for custom presets: Export & Delete
            if isCustom {
                HStack(spacing: 6) {
                    Button(action: {
                        viewModel.exportPreset(preset)
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Export preset")
                    
                    Button(action: {
                        viewModel.deletePreset(id: preset.id)
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(hoveredPresetId == preset.id ? Color.red : Color.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Delete custom preset")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.24) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            if hovering {
                hoveredPresetId = preset.id
            } else if hoveredPresetId == preset.id {
                hoveredPresetId = nil
            }
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
    .frame(width: 312, height: 720)
}
