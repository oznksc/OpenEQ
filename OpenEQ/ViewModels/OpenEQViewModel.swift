//
//  OpenEQViewModel.swift
//  OpenEQ
//
//  Created by Ozan
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
    var isEnabled: Bool = true
    var graphicBandCount: GraphicBandCount = .ten
    var isVolumeBoostEnabled: Bool = false
    var isShowingSystemAudio: Bool = false
    
    var playbackState: AudioEngineState {
        audioEngineController.playbackState
    }

    var spectrumLevels: [Float] {
        if isSystemAudioVisualizationActive {
            return systemAudioManager.spectrumLevels
        }

        return audioEngineController.spectrumLevels
    }

    var leftLevel: Float {
        if isSystemAudioVisualizationActive {
            return systemAudioManager.leftLevel
        }

        return audioEngineController.leftLevel
    }

    var rightLevel: Float {
        if isSystemAudioVisualizationActive {
            return systemAudioManager.rightLevel
        }

        return audioEngineController.rightLevel
    }

    var peakLevel: Float {
        if isSystemAudioVisualizationActive {
            return systemAudioManager.peakLevel
        }

        return audioEngineController.peakLevel
    }

    var isClipping: Bool {
        if isSystemAudioVisualizationActive {
            return systemAudioManager.isClipping
        }

        return audioEngineController.isClipping
    }

    var spectrumTitle: String {
        if isExternalLoopbackActive {
            return "External Loopback EQ"
        }

        return isSystemAudioMonitorActive ? "System Audio Monitor" : "Real-Time FFT Spectrum"
    }

    var spectrumWarning: String? {
        if isExternalLoopbackActive {
            return "External loopback applies EQ to a user-installed virtual input and plays it to your selected output."
        }

        return isSystemAudioMonitorActive
        ? "Monitor mode analyzes system audio only. It does not apply EQ to system output."
        : nil
    }

    var isSystemAudioMonitorActive: Bool {
        systemAudioMode == .systemEQ && systemAudioStatus == .running
    }

    var isExternalLoopbackActive: Bool {
        systemAudioMode == .externalLoopback && systemAudioStatus == .running
    }

    var isSystemAudioVisualizationActive: Bool {
        isSystemAudioMonitorActive || isExternalLoopbackActive
    }

    var presets: [EQPreset]
    var userPresets: [EQPreset] = []
    var selectedPreset: EQPreset
    var volume: Double
    var isMuted: Bool
    var systemAudioMode: SystemAudioMode
    var systemAudioStatus: SystemAudioStatus
    var selectedSystemInputDevice: AudioDevice?
    var selectedSystemOutputDevice: AudioDevice?
    var availableInputDevices: [AudioDevice]
    var availableOutputDevices: [AudioDevice]
    var detectedBlackHoleDevice: AudioDevice?
    var externalLoopbackLatency: TimeInterval?
    var isExternalLoopbackBypassed: Bool
    var systemAudioLatency: TimeInterval?

    private let audioEngineController: AudioEngineController
    private let systemAudioManager: SystemAudioManager
    private let presetStore = PresetStore()
    private var graphicBands: [EQBand]
    private var parametricBands: [EQBand]

    convenience init(audioEngineController: AudioEngineController) {
        self.init(
            audioEngineController: audioEngineController,
            systemAudioManager: SystemAudioManager()
        )
    }

    init(audioEngineController: AudioEngineController, systemAudioManager: SystemAudioManager) {
        self.audioEngineController = audioEngineController
        self.systemAudioManager = systemAudioManager
        
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
        self.systemAudioMode = systemAudioManager.mode
        self.systemAudioStatus = systemAudioManager.status
        self.selectedSystemInputDevice = systemAudioManager.selectedInputDevice
        self.selectedSystemOutputDevice = systemAudioManager.selectedOutputDevice
        self.availableInputDevices = systemAudioManager.availableInputDevices
        self.availableOutputDevices = systemAudioManager.availableOutputDevices
        self.detectedBlackHoleDevice = systemAudioManager.detectedBlackHoleDevice
        self.externalLoopbackLatency = systemAudioManager.externalLoopbackLatency
        self.isExternalLoopbackBypassed = systemAudioManager.isExternalLoopbackBypassed
        self.systemAudioLatency = systemAudioManager.systemAudioLatency

        self.audioEngineController.currentGraphicBandCount = .ten
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

    // MARK: - System Audio Beta

    func refreshSystemAudioDevices() {
        systemAudioManager.refreshDevices()
        syncSystemAudioState()
    }

    func setSystemAudioMode(_ mode: SystemAudioMode) {
        systemAudioManager.setMode(mode)
        syncSystemAudioState()
    }

    func selectSystemInputDevice(_ device: AudioDevice?) {
        systemAudioManager.selectInputDevice(device)
        syncSystemAudioState()
    }

    func selectSystemOutputDevice(_ device: AudioDevice?) {
        systemAudioManager.selectOutputDevice(device)
        syncSystemAudioState()
    }

    func selectSystemInputDevice(id: AudioDevice.ID?) {
        selectSystemInputDevice(availableInputDevices.first { $0.id == id })
    }

    func selectSystemOutputDevice(id: AudioDevice.ID?) {
        selectSystemOutputDevice(availableOutputDevices.first { $0.id == id })
    }

    func startSystemEQMode() {
        stop()
        systemAudioManager.startSystemEQ()
        syncSystemAudioState()
    }

    func stopSystemEQMode() {
        systemAudioManager.stopSystemEQ()
        syncSystemAudioState()
    }

    func startExternalLoopbackMode() {
        stop()
        systemAudioManager.startExternalLoopback(preset: currentLoopbackPreset())
        syncSystemAudioState()
    }

    func stopExternalLoopbackMode() {
        systemAudioManager.stopExternalLoopback()
        syncSystemAudioState()
    }

    func restartExternalLoopbackMode() {
        systemAudioManager.restartExternalLoopback(preset: currentLoopbackPreset())
        syncSystemAudioState()
    }

    func setSystemAudiBypassed(_ isBypassed: Bool) {
        systemAudioManager.setSystemAudiBypassed(isBypassed)
        syncSystemAudioState()
    }

    func setExternalLoopbackBypassed(_ isBypassed: Bool) {
        systemAudioManager.setExternalLoopbackBypassed(isBypassed)
        syncSystemAudioState()
    }

    // MARK: - EQ Controls

    func setEQMode(_ mode: EQMode) {
        guard mode != eqMode else { return }

        cacheActiveBands()
        eqMode = mode
        bands = bandsForMode(mode)
        selectedPreset = EQPreset(name: "Custom", mode: eqMode, bands: bands, preamp: preamp)
        audioEngineController.applyPreset(selectedPreset)
        updateExternalLoopbackEQIfNeeded()
        updateSystemEQIfNeeded()
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
        updateExternalLoopbackEQIfNeeded()
        updateSystemEQIfNeeded()
    }

    func updateBandGain(index: Int, gain: Float) {
        guard index >= 0 && index < bands.count else { return }
        bands[index].gain = gain
        commitActiveBandsAsCustom()
        audioEngineController.updateBand(bands[index])
        updateExternalLoopbackEQIfNeeded()
        updateSystemEQIfNeeded()
    }

    func updateBandFrequency(index: Int, frequency: Float) {
        guard index >= 0 && index < bands.count else { return }
        bands[index].frequency = frequency
        commitActiveBandsAsCustom()
        audioEngineController.updateBand(bands[index])
        updateExternalLoopbackEQIfNeeded()
        updateSystemEQIfNeeded()
    }

    func updateBandQ(index: Int, q: Float) {
        guard index >= 0 && index < bands.count else { return }
        bands[index].q = q
        commitActiveBandsAsCustom()
        audioEngineController.updateBand(bands[index])
        updateExternalLoopbackEQIfNeeded()
        updateSystemEQIfNeeded()
    }

    func updateBandFilterType(index: Int, filterType: EQFilterType) {
        guard index >= 0 && index < bands.count else { return }
        bands[index].filterType = filterType
        commitActiveBandsAsCustom()
        audioEngineController.updateBand(bands[index])
        updateExternalLoopbackEQIfNeeded()
        updateSystemEQIfNeeded()
    }

    func updateBandEnabled(index: Int, isEnabled: Bool) {
        guard index >= 0 && index < bands.count else { return }
        bands[index].isEnabled = isEnabled
        commitActiveBandsAsCustom()
        audioEngineController.updateBand(bands[index])
        updateExternalLoopbackEQIfNeeded()
        updateSystemEQIfNeeded()
    }

    func updatePreamp(gain: Float) {
        preamp = gain
        audioEngineController.setPreampGain(gain)
        selectedPreset = EQPreset(name: "Custom", mode: eqMode, bands: bands, preamp: preamp)
        updateExternalLoopbackEQIfNeeded()
        updateSystemEQIfNeeded()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        audioEngineController.setBypass(!enabled)
        updateExternalLoopbackEQIfNeeded()
        updateSystemEQIfNeeded()
    }

    func setGraphicBandCount(_ count: GraphicBandCount) {
        guard count != graphicBandCount, eqMode == .graphic else {
            graphicBandCount = count
            return
        }

        graphicBandCount = count
        audioEngineController.currentGraphicBandCount = count
        let newBands = EQBand.defaultBands(count: count)
        bands = newBands
        graphicBands = newBands
        selectedPreset = EQPreset(name: "Custom", mode: eqMode, bands: bands, preamp: preamp)
        audioEngineController.applyPreset(selectedPreset)
        updateExternalLoopbackEQIfNeeded()
        updateSystemEQIfNeeded()
    }

    func toggleVolumeBoost() {
        isVolumeBoostEnabled.toggle()
        let boostValue: Double = isVolumeBoostEnabled ? 2.0 : 1.0
        audioEngineController.setVolumeBoost(boostValue)
    }

    func resetEQ() {
        bands = EQBand.defaultBands(for: eqMode, graphicBandCount: graphicBandCount)
        preamp = 0.0
        cacheActiveBands()
        selectedPreset = EQPreset(name: "Flat", mode: eqMode, bands: bands, preamp: preamp)
        audioEngineController.applyPreset(selectedPreset)
        updateExternalLoopbackEQIfNeeded()
        updateSystemEQIfNeeded()
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
        updateExternalLoopbackEQIfNeeded()
        updateSystemEQIfNeeded()
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
            return graphicBands.isEmpty ? EQBand.defaultBands(count: graphicBandCount) : graphicBands
        case .parametric:
            return parametricBands.isEmpty ? EQBand.defaultParametricBands() : parametricBands
        }
    }

    private func commitActiveBandsAsCustom() {
        cacheActiveBands()
        selectedPreset = EQPreset(name: "Custom", mode: eqMode, bands: bands, preamp: preamp)
    }

    private func syncSystemAudioState() {
        systemAudioMode = systemAudioManager.mode
        systemAudioStatus = systemAudioManager.status
        selectedSystemInputDevice = systemAudioManager.selectedInputDevice
        selectedSystemOutputDevice = systemAudioManager.selectedOutputDevice
        availableInputDevices = systemAudioManager.availableInputDevices
        availableOutputDevices = systemAudioManager.availableOutputDevices
        detectedBlackHoleDevice = systemAudioManager.detectedBlackHoleDevice
        externalLoopbackLatency = systemAudioManager.externalLoopbackLatency
        isExternalLoopbackBypassed = systemAudioManager.isExternalLoopbackBypassed
        systemAudioLatency = systemAudioManager.systemAudioLatency
    }

    private func updateExternalLoopbackEQIfNeeded() {
        guard systemAudioMode == .externalLoopback, systemAudioStatus == .running else {
            return
        }

        systemAudioManager.updateExternalLoopbackEQ(currentLoopbackPreset())
        syncSystemAudioState()
    }

    func updateSystemEQIfNeeded() {
        guard systemAudioMode == .systemEQ, systemAudioStatus == .running else {
            return
        }

        systemAudioManager.updateSystemAudiEQ(currentLoopbackPreset())
        syncSystemAudioState()
    }

    private func currentLoopbackPreset() -> EQPreset {
        EQPreset(
            name: selectedPreset.name,
            mode: eqMode,
            bands: bands,
            preamp: min(preamp, 0.0)
        )
    }
}

// MARK: - UTType Extension
extension UTType {
    public static var coreAudioFormat: UTType {
        UTType("com.apple.coreaudio-format") ?? UTType.audio
    }
}
