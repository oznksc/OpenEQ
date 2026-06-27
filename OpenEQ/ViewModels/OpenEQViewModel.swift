//
//  OpenEQViewModel.swift
//  OpenEQ
//
//  Created by Gökmen on 26.06.2026.
//

import Foundation
import Observation
import UniformTypeIdentifiers
import AppKit

@MainActor
@Observable
final class OpenEQViewModel {
    // Published State
    var selectedFileURL: URL?
    var selectedFileName: String = "No File Selected"
    var eqMode: EQMode
    var bands: [EQBand]
    var preamp: Float
    var errorMessage: String?
    
    var playbackState: AudioEngineState {
        audioEngineController.playbackState
    }

    var spectrumLevels: [Float] {
        audioEngineController.spectrumLevels
    }

    var leftLevel: Float {
        audioEngineController.leftLevel
    }

    var rightLevel: Float {
        audioEngineController.rightLevel
    }

    var peakLevel: Float {
        audioEngineController.peakLevel
    }

    var isClipping: Bool {
        audioEngineController.isClipping
    }

    var presets: [EQPreset]
    var userPresets: [EQPreset] = []
    var selectedPreset: EQPreset
    var volume: Double
    var isMuted: Bool

    private let audioEngineController: AudioEngineController
    private let presetStore = PresetStore()
    private var graphicBands: [EQBand]
    private var parametricBands: [EQBand]

    init(audioEngineController: AudioEngineController) {
        self.audioEngineController = audioEngineController
        
        // Load custom user presets at app start via local variable
        let loadedUserPresets = presetStore.loadUserPresets()
        
        // Initialize all stored properties before accessing self
        self.userPresets = loadedUserPresets
        self.presets = EQPreset.defaultPresets() + loadedUserPresets
        
        let initialPreset = EQPreset.flatPreset()
        self.selectedPreset = initialPreset
        self.eqMode = initialPreset.mode
        self.bands = initialPreset.bands
        self.graphicBands = initialPreset.bands
        self.parametricBands = EQBand.defaultParametricBands()
        self.preamp = initialPreset.preamp
        self.volume = 0.72
        self.isMuted = false
        
        self.audioEngineController.applyPreset(initialPreset)
    }

    // MARK: - Playback Controls
    
    func play() {
        errorMessage = nil
        audioEngineController.play()
        
        if case .failed(let message) = audioEngineController.playbackState {
            errorMessage = message
        }
    }

    func pause() {
        audioEngineController.pause()
    }

    func stop() {
        audioEngineController.stop()
    }

    func togglePlayback() {
        switch playbackState {
        case .playing:
            pause()
        case .paused, .stopped, .idle, .ready, .failed:
            play()
        case .preparing:
            break
        }
    }

    // MARK: - File Management
    
    func openAudioFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        panel.allowedContentTypes = [
            .audio,
            .mp3,
            .wav,
            .mpeg4Audio,
            .coreAudioFormat,
            UTType(filenameExtension: "aiff")
        ].compactMap { $0 }
        
        if panel.runModal() == .OK, let url = panel.url {
            loadAudioFile(url: url)
        }
    }

    func loadAudioFile(url: URL) {
        do {
            errorMessage = nil
            try audioEngineController.prepare(url: url)
            selectedFileURL = url
            selectedFileName = url.lastPathComponent
        } catch {
            errorMessage = "Failed to load audio: \(error.localizedDescription)"
            selectedFileURL = nil
            selectedFileName = "No File Selected"
        }
    }

    // MARK: - EQ Controls

    func setEQMode(_ mode: EQMode) {
        guard mode != eqMode else { return }

        cacheActiveBands()
        eqMode = mode
        bands = bandsForMode(mode)
        selectedPreset = EQPreset(name: "Custom", mode: eqMode, bands: bands, preamp: preamp)
        audioEngineController.applyPreset(selectedPreset)
    }

    func gain(for bandID: EQBand.ID) -> Float {
        bands.first { $0.id == bandID }?.gain ?? EQBand.neutralGain
    }

    func setGain(_ gain: Float, for bandID: EQBand.ID) {
        guard let index = bands.firstIndex(where: { $0.id == bandID }) else {
            return
        }

        bands[index].gain = gain
        commitActiveBandsAsCustom()
        audioEngineController.updateBand(bands[index])
    }

    func updateBandGain(index: Int, gain: Float) {
        guard index >= 0 && index < bands.count else { return }
        bands[index].gain = gain
        commitActiveBandsAsCustom()
        audioEngineController.updateBand(bands[index])
    }

    func updateBandFrequency(index: Int, frequency: Float) {
        guard index >= 0 && index < bands.count else { return }
        bands[index].frequency = frequency
        commitActiveBandsAsCustom()
        audioEngineController.updateBand(bands[index])
    }

    func updateBandQ(index: Int, q: Float) {
        guard index >= 0 && index < bands.count else { return }
        bands[index].q = q
        commitActiveBandsAsCustom()
        audioEngineController.updateBand(bands[index])
    }

    func updateBandFilterType(index: Int, filterType: EQFilterType) {
        guard index >= 0 && index < bands.count else { return }
        bands[index].filterType = filterType
        commitActiveBandsAsCustom()
        audioEngineController.updateBand(bands[index])
    }

    func updateBandEnabled(index: Int, isEnabled: Bool) {
        guard index >= 0 && index < bands.count else { return }
        bands[index].isEnabled = isEnabled
        commitActiveBandsAsCustom()
        audioEngineController.updateBand(bands[index])
    }

    func updatePreamp(gain: Float) {
        preamp = gain
        audioEngineController.setPreampGain(gain)
        selectedPreset = EQPreset(name: "Custom", mode: eqMode, bands: bands, preamp: preamp)
    }

    func resetEQ() {
        bands = EQBand.defaultBands(for: eqMode)
        preamp = 0.0
        cacheActiveBands()
        selectedPreset = EQPreset(name: "Flat", mode: eqMode, bands: bands, preamp: preamp)
        audioEngineController.applyPreset(selectedPreset)
    }

    // MARK: - Preset Management

    func loadUserPresets() {
        userPresets = presetStore.loadUserPresets()
        presets = EQPreset.defaultPresets() + userPresets
    }

    func saveCurrentPreset(name: String, bands: [EQBand], preamp: Float) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        // Prevent overwriting built-in presets
        guard !EQPreset.defaultPresets().contains(where: { $0.name.lowercased() == trimmedName.lowercased() }) else {
            errorMessage = "Cannot overwrite built-in presets."
            return
        }
        
        if let existingIndex = userPresets.firstIndex(where: { $0.name.lowercased() == trimmedName.lowercased() }) {
            // Overwrite existing user preset
            let updatedPreset = EQPreset(
                id: userPresets[existingIndex].id,
                name: trimmedName,
                mode: eqMode,
                bands: bands,
                preamp: preamp,
                createdAt: userPresets[existingIndex].createdAt,
                updatedAt: Date()
            )
            userPresets[existingIndex] = updatedPreset
            selectedPreset = updatedPreset
        } else {
            // Create a new user preset
            let newPreset = EQPreset(name: trimmedName, mode: eqMode, bands: bands, preamp: preamp)
            userPresets.append(newPreset)
            selectedPreset = newPreset
        }
        
        presets = EQPreset.defaultPresets() + userPresets
        presetStore.saveUserPresets(userPresets)
    }

    func deletePreset(id: UUID) {
        // Prevent deleting built-in presets
        guard !EQPreset.defaultPresets().contains(where: { $0.id == id }) else {
            errorMessage = "Cannot delete built-in presets."
            return
        }
        
        if let index = userPresets.firstIndex(where: { $0.id == id }) {
            userPresets.remove(at: index)
            presets = EQPreset.defaultPresets() + userPresets
            presetStore.saveUserPresets(userPresets)
            
            // Revert back to Flat if the active preset was deleted
            if selectedPreset.id == id {
                applyPreset(.flatPreset())
            }
        }
    }

    func applyPreset(_ preset: EQPreset) {
        cacheActiveBands()
        selectedPreset = preset
        eqMode = preset.mode
        bands = preset.bands
        cacheActiveBands()
        preamp = preset.preamp
        audioEngineController.applyPreset(preset)
    }

    func selectPreset(_ preset: EQPreset) {
        applyPreset(preset)
    }

    func exportPreset(_ preset: EQPreset) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(preset.name).json"
        panel.title = "Export Preset"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                errorMessage = nil
                try presetStore.exportPreset(preset, to: url)
            } catch {
                errorMessage = "Failed to export preset: \(error.localizedDescription)"
            }
        }
    }

    func importPreset() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.title = "Import Preset"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                errorMessage = nil
                let imported = try presetStore.importPreset(from: url)
                
                // Add to custom user presets list (prevent duplicate names in user presets)
                if let index = userPresets.firstIndex(where: { $0.name.lowercased() == imported.name.lowercased() }) {
                    userPresets[index] = imported
                } else {
                    userPresets.append(imported)
                }
                
                presets = EQPreset.defaultPresets() + userPresets
                presetStore.saveUserPresets(userPresets)
                
                // Apply imported preset
                applyPreset(imported)
            } catch {
                errorMessage = "Failed to import preset: \(error.localizedDescription)"
            }
        }
    }

    private func persistCustomPresets() {
        presetStore.saveUserPresets(userPresets)
    }

    private func cacheActiveBands() {
        switch eqMode {
        case .graphic:
            graphicBands = bands
        case .parametric:
            parametricBands = bands
        }
    }

    private func bandsForMode(_ mode: EQMode) -> [EQBand] {
        switch mode {
        case .graphic:
            return graphicBands.isEmpty ? EQBand.defaultBands() : graphicBands
        case .parametric:
            return parametricBands.isEmpty ? EQBand.defaultParametricBands() : parametricBands
        }
    }

    private func commitActiveBandsAsCustom() {
        cacheActiveBands()
        selectedPreset = EQPreset(name: "Custom", mode: eqMode, bands: bands, preamp: preamp)
    }
}

// MARK: - UTType Extension
extension UTType {
    public static var coreAudioFormat: UTType {
        UTType("com.apple.coreaudio-format") ?? UTType.audio
    }
}
