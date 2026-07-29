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

        if isSystemEQActive {
            return "System-Wide EQ"
        }

        return "Real-Time FFT Spectrum"
    }

    var spectrumWarning: String? {
        if isExternalLoopbackActive {
            return "External loopback applies EQ to a user-installed virtual input and plays it to your selected output."
        }

        if isSystemEQActive {
            if let latency = systemAudioLatency {
                return String(format: "Processing all system audio · ~%.0f ms latency", latency * 1000)
            }
            return "Processing all system audio through OpenEQ."
        }

        return nil
    }

    var isSystemEQActive: Bool {
        systemAudioMode == .systemEQ && systemAudioStatus == .running
    }

    /// Legacy alias used by older call sites / previews.
    var isSystemAudioMonitorActive: Bool {
        isSystemEQActive
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
    var volume: Double {
        didSet { audioEngineController.setVolume(volume) }
    }
    var isMuted: Bool {
        didSet { audioEngineController.setMuted(isMuted) }
    }
    var systemAudioMode: SystemAudioMode
    var systemAudioStatus: SystemAudioStatus
    var selectedSystemInputDevice: AudioDevice?
    var selectedSystemOutputDevice: AudioDevice?
    var availableInputDevices: [AudioDevice]
    var availableOutputDevices: [AudioDevice]
    var detectedBlackHoleDevice: AudioDevice?
    var externalLoopbackLatency: TimeInterval?
    var isExternalLoopbackBypassed: Bool
    var isSystemAudioBypassed: Bool
    var systemAudioLatency: TimeInterval?
    /// Most recently used presets for menu-bar quick switching (newest first).
    var recentPresets: [EQPreset] = []
    var deviceProfiles: [DeviceEQProfile] = []
    var activePhysicalOutputName: String?
    var activePhysicalOutputUID: String?
    var didTripFeedbackProtection = false
    var showSystemEQOnboarding = false
    var autoApplyDeviceProfiles: Bool = AppPreferences.autoApplyDeviceProfiles
    var feedbackProtectionEnabled: Bool = AppPreferences.feedbackProtectionEnabled
    var preferSystemEQOnLaunch: Bool = AppPreferences.preferSystemEQOnLaunch
    var safetyBannerMessage: String?
    var selectedBandID: EQBand.ID?
    var dynamics: DynamicsSettings = .default
    var availableAUPlugins: [AUPluginDescriptor] = []
    var selectedAUPluginID: String?
    var loadedAUPluginName: String?
    var isLoadingAUPlugin = false
    var auPluginError: String?
    var headphoneProfiles: [HeadphoneProfile] = []
    var calibrationImportMessage: String?
    var channelLayout: ChannelLayout = .stereo
    var systemEQSetupDetail: String?
    var isReceivingTapAudio = false
    var conflictingHALPlugins: [String] = []

    var playbackDuration: TimeInterval {
        audioEngineController.playbackDuration
    }

    var playbackPosition: TimeInterval {
        audioEngineController.playbackPosition
    }

    private let audioEngineController: AudioEngineController
    private let systemAudioManager: SystemAudioManager
    private let presetStore = PresetStore()
    private let deviceProfileStore = DeviceProfileStore()
    private let auPluginHost = AUv3PluginHost()
    private let autoEQCatalog = AutoEQCatalog()
    private var graphicBands: [EQBand]
    private var parametricBands: [EQBand]
    private var isApplyingDeviceProfile = false

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
        self.isSystemAudioBypassed = systemAudioManager.isSystemAudioBypassed
        self.systemAudioLatency = systemAudioManager.systemAudioLatency
        self.recentPresets = [initialPreset]
        self.deviceProfiles = deviceProfileStore.loadProfiles()
        self.activePhysicalOutputName = systemAudioManager.activePhysicalOutputName
        self.activePhysicalOutputUID = systemAudioManager.activePhysicalOutputUID
        self.didTripFeedbackProtection = systemAudioManager.didTripFeedbackProtection
        self.showSystemEQOnboarding = !AppPreferences.hasCompletedSystemEQOnboarding

        self.audioEngineController.currentGraphicBandCount = .ten
        self.audioEngineController.applyPreset(initialPreset)
        self.audioEngineController.setVolume(volume)
        self.audioEngineController.setMuted(isMuted)
        self.audioEngineController.applyDynamics(self.dynamics)

        self.systemAudioManager.onPhysicalOutputChanged = { [weak self] uid, name in
            self?.handlePhysicalOutputChanged(uid: uid, name: name)
        }
        self.systemAudioManager.onSafetyTrip = { [weak self] in
            self?.handleSafetyTrip()
        }
        self.conflictingHALPlugins = systemAudioManager.conflictingHALPluginNames
    }

    /// Called once from the app root after the UI is ready.
    func handleAppLaunch() {
        if preferSystemEQOnLaunch {
            enableSystemEQOneClick()
        }
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

    func seek(to time: TimeInterval) {
        audioEngineController.seek(to: time)
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
        panel.allowsOtherFileTypes = true
        
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
        systemAudioManager.setSystemAudioBypassed(!isEnabled)
        systemAudioManager.setFeedbackProtectionEnabled(feedbackProtectionEnabled)
        systemAudioManager.startSystemEQ(preset: currentActivePreset())
        syncSystemAudioState()
        applyDeviceProfileIfNeeded(forUID: systemAudioManager.activePhysicalOutputUID)
        systemEQSetupDetail = systemAudioManager.systemEQSetupDetail
        isReceivingTapAudio = systemAudioManager.isReceivingTapAudio
        conflictingHALPlugins = systemAudioManager.conflictingHALPluginNames

        if case .failed(let message) = systemAudioStatus {
            errorMessage = message
            isShowingSystemAudio = true
        } else if systemAudioStatus == .permissionRequired {
            errorMessage = "Grant Screen & System Audio Recording permission, then try again."
            isShowingSystemAudio = true
        } else {
            errorMessage = nil
            completeSystemEQOnboardingIfNeeded()
            // Pull health probe result after engine settles.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                self?.syncSystemAudioState()
            }
        }
    }

    func stopSystemEQMode() {
        systemAudioManager.stopSystemEQ()
        syncSystemAudioState()
    }

    /// One-button path: switch to System-Wide EQ and start (driverless CATap).
    func enableSystemEQOneClick() {
        isShowingSystemAudio = true
        if systemAudioMode != .systemEQ {
            systemAudioManager.setMode(.systemEQ)
            syncSystemAudioState()
        }
        startSystemEQMode()
    }

    func toggleSystemEQOneClick() {
        if isSystemEQActive {
            stopSystemEQMode()
            systemAudioManager.setMode(.disabled)
            syncSystemAudioState()
        } else {
            enableSystemEQOneClick()
        }
    }

    func completeSystemEQOnboardingIfNeeded() {
        if !AppPreferences.hasCompletedSystemEQOnboarding {
            AppPreferences.hasCompletedSystemEQOnboarding = true
            showSystemEQOnboarding = false
        }
    }

    func dismissSystemEQOnboarding() {
        AppPreferences.hasCompletedSystemEQOnboarding = true
        showSystemEQOnboarding = false
    }

    func setPreferSystemEQOnLaunch(_ enabled: Bool) {
        preferSystemEQOnLaunch = enabled
        AppPreferences.preferSystemEQOnLaunch = enabled
    }

    func setAutoApplyDeviceProfiles(_ enabled: Bool) {
        autoApplyDeviceProfiles = enabled
        AppPreferences.autoApplyDeviceProfiles = enabled
    }

    func setFeedbackProtectionEnabled(_ enabled: Bool) {
        feedbackProtectionEnabled = enabled
        systemAudioManager.setFeedbackProtectionEnabled(enabled)
    }

    func rememberPresetForCurrentDevice() {
        guard let uid = activePhysicalOutputUID ?? systemAudioManager.activePhysicalOutputUID else {
            errorMessage = "No active output device to bind a profile."
            return
        }
        let name = activePhysicalOutputName
            ?? systemAudioManager.activePhysicalOutputName
            ?? "Output Device"
        deviceProfileStore.upsert(
            deviceUID: uid,
            deviceName: name,
            presetID: selectedPreset.id,
            presetName: selectedPreset.name,
            into: &deviceProfiles
        )
        safetyBannerMessage = "Saved “\(selectedPreset.name)” for \(name)."
    }

    func clearProfileForCurrentDevice() {
        guard let uid = activePhysicalOutputUID ?? systemAudioManager.activePhysicalOutputUID else { return }
        deviceProfileStore.remove(deviceUID: uid, from: &deviceProfiles)
        safetyBannerMessage = "Removed device profile."
    }

    func clearFeedbackProtectionTrip() {
        systemAudioManager.clearFeedbackProtectionTrip()
        didTripFeedbackProtection = false
        safetyBannerMessage = nil
        errorMessage = nil
        // Re-enable EQ after user acknowledges the trip.
        if !isEnabled {
            setEnabled(true)
        }
        syncSystemAudioState()
    }

    private func handlePhysicalOutputChanged(uid: String?, name: String?) {
        activePhysicalOutputUID = uid
        activePhysicalOutputName = name
        syncSystemAudioState()
        applyDeviceProfileIfNeeded(forUID: uid)
    }

    private func handleSafetyTrip() {
        didTripFeedbackProtection = true
        // Do not flip global EQ bypass — that made recovery confusing and looked like a total failure.
        safetyBannerMessage = "Feedback protection muted output after sustained clipping. Lower gain or check routing, then resume."
        errorMessage = nil
        syncSystemAudioState()
        isShowingSystemAudio = true
    }

    private func applyDeviceProfileIfNeeded(forUID uid: String?) {
        guard autoApplyDeviceProfiles, !isApplyingDeviceProfile else { return }
        guard let uid, let profile = deviceProfileStore.profile(forDeviceUID: uid, in: deviceProfiles) else {
            return
        }
        guard let presetID = profile.presetID else { return }

        let match = presets.first { $0.id == presetID }
            ?? presets.first { $0.name == profile.presetName }
        guard let preset = match else { return }
        guard preset.id != selectedPreset.id else { return }

        isApplyingDeviceProfile = true
        applyPreset(preset)
        isApplyingDeviceProfile = false
        safetyBannerMessage = "Loaded “\(preset.name)” for \(profile.deviceName)."
    }

    func startExternalLoopbackMode() {
        stop()
        systemAudioManager.setExternalLoopbackBypassed(!isEnabled)
        systemAudioManager.startExternalLoopback(preset: currentActivePreset())
        syncSystemAudioState()
        if case .failed(let message) = systemAudioStatus {
            errorMessage = message
        } else {
            errorMessage = nil
        }
    }

    func stopExternalLoopbackMode() {
        systemAudioManager.stopExternalLoopback()
        syncSystemAudioState()
    }

    func shutdown() {
        stop()
        systemAudioManager.stop()
        syncSystemAudioState()
    }

    /// Immediate passthrough: stop all system processing and restore device routing.
    func enterSafeMode() {
        systemAudioManager.enterSafeMode()
        isEnabled = true
        audioEngineController.setBypass(false)
        syncSystemAudioState()
        errorMessage = nil
    }

    func openSystemAudioPrivacySettings() {
        systemAudioManager.openSystemAudioPrivacySettings()
    }

    func restartExternalLoopbackMode() {
        systemAudioManager.restartExternalLoopback(preset: currentActivePreset())
        syncSystemAudioState()
    }

    func setSystemAudioBypassed(_ isBypassed: Bool) {
        systemAudioManager.setSystemAudioBypassed(isBypassed)
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
        selectedBandID = bands.first?.id
        selectedPreset = EQPreset(name: "Custom", mode: eqMode, bands: bands, preamp: preamp)
        audioEngineController.applyPreset(selectedPreset)
        updateExternalLoopbackEQIfNeeded()
        updateSystemEQIfNeeded()
    }

    func selectBand(id: EQBand.ID) {
        selectedBandID = id
    }

    func updateBandFromCurve(index: Int, band: EQBand) {
        guard index >= 0, index < bands.count else { return }
        bands[index] = band
        selectedBandID = band.id
        commitActiveBandsAsCustom()
        // Full mode apply keeps graphic/parametric band counts in sync with the engine.
        audioEngineController.applyMode(eqMode, bands: bands)
        audioEngineController.setPreampGain(preamp)
        updateExternalLoopbackEQIfNeeded()
        updateSystemEQIfNeeded()
    }

    // MARK: - Dynamics

    func setCompressorEnabled(_ enabled: Bool) {
        dynamics.isCompressorEnabled = enabled
        pushDynamics()
    }

    func setCompressorThreshold(_ value: Float) {
        dynamics.threshold = value
        dynamics.clamp()
        pushDynamics()
    }

    func setCompressorRatio(_ value: Float) {
        dynamics.ratio = value
        dynamics.clamp()
        pushDynamics()
    }

    func setCompressorAttack(_ value: Float) {
        dynamics.attack = value
        dynamics.clamp()
        pushDynamics()
    }

    func setCompressorRelease(_ value: Float) {
        dynamics.release = value
        dynamics.clamp()
        pushDynamics()
    }

    func setCompressorMakeup(_ value: Float) {
        dynamics.makeupGain = value
        dynamics.clamp()
        pushDynamics()
    }

    func setStereoBalance(_ value: Float) {
        dynamics.balance = value
        dynamics.clamp()
        pushDynamics()
    }

    private func pushDynamics() {
        audioEngineController.applyDynamics(dynamics)
    }

    // MARK: - AUv3

    func refreshAUPlugins() {
        auPluginHost.refreshAvailablePlugins()
        availableAUPlugins = auPluginHost.availablePlugins
        auPluginError = auPluginHost.lastError
    }

    func loadSelectedAUPlugin() {
        guard let id = selectedAUPluginID,
              let descriptor = availableAUPlugins.first(where: { $0.id == id }) else {
            return
        }
        isLoadingAUPlugin = true
        auPluginError = nil
        auPluginHost.loadPlugin(descriptor) { [weak self] result in
            guard let self else { return }
            self.isLoadingAUPlugin = false
            switch result {
            case .success(let unit):
                do {
                    try self.audioEngineController.insertAudioUnit(unit)
                    self.loadedAUPluginName = descriptor.displayName
                    self.auPluginError = nil
                } catch {
                    self.auPluginError = error.localizedDescription
                    self.loadedAUPluginName = nil
                }
            case .failure(let error):
                self.auPluginError = error.localizedDescription
                self.loadedAUPluginName = nil
            }
        }
    }

    func unloadAUPlugin() {
        audioEngineController.removeInsertedAudioUnit()
        auPluginHost.unloadPlugin()
        loadedAUPluginName = nil
        auPluginError = nil
    }

    // MARK: - AutoEQ / Calibration

    func loadHeadphoneCatalogIfNeeded() {
        guard headphoneProfiles.isEmpty else { return }
        headphoneProfiles = autoEQCatalog.loadBundledProfiles()
    }

    func filteredHeadphoneProfiles(query: String) -> [HeadphoneProfile] {
        loadHeadphoneCatalogIfNeeded()
        return autoEQCatalog.search(query, in: headphoneProfiles)
    }

    func applyHeadphoneProfile(_ profile: HeadphoneProfile) {
        let preset = profile.asPreset(graphicBandCount: graphicBandCount == .thirtyOne ? .thirtyOne : .ten)
        // Ensure graphic mode for headphone curves.
        if eqMode != .graphic {
            setEQMode(.graphic)
        }
        applyPreset(preset)
        // Keep as user-facing custom/applied name.
        calibrationImportMessage = "Applied \(profile.displayName) (\(profile.target))."
        errorMessage = nil
    }

    func importCalibrationFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .plainText,
            .text,
            .commaSeparatedText,
            UTType(filenameExtension: "txt") ?? .plainText,
            UTType(filenameExtension: "csv") ?? .commaSeparatedText
        ].compactMap { $0 }
        panel.title = "Import AutoEQ / REW Calibration"
        panel.message = "Select GraphicEQ.txt, ParametricEQ.txt, REW Equalizer APO export, or FR CSV."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let result = try CalibrationImporter.importFile(at: url)
            applyPreset(result.preset)
            if result.preset.mode == .graphic, eqMode != .graphic {
                // applyPreset already sets mode from preset
            }
            calibrationImportMessage = "Imported \(result.formatName): \(result.sourceName)"
            errorMessage = nil

            // Offer to keep as a user preset automatically under imported name.
            if !userPresets.contains(where: { $0.name == result.preset.name }) {
                saveCurrentPreset(name: result.preset.name, bands: bands, preamp: preamp)
            }
        } catch {
            calibrationImportMessage = nil
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func setChannelLayout(_ layout: ChannelLayout) {
        channelLayout = layout
        if layout == .multiChannel {
            calibrationImportMessage = "Multi-channel per-speaker EQ is a foundation only — stereo processing remains active."
        }
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
        // Unified bypass policy across local, system EQ, and external loopback.
        audioEngineController.setBypass(!enabled)
        systemAudioManager.setSystemAudioBypassed(!enabled)
        systemAudioManager.setExternalLoopbackBypassed(!enabled)
        syncSystemAudioState()
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
        rememberRecentPreset(preset)
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
        isSystemAudioBypassed = systemAudioManager.isSystemAudioBypassed
        systemAudioLatency = systemAudioManager.systemAudioLatency
        activePhysicalOutputUID = systemAudioManager.activePhysicalOutputUID
        activePhysicalOutputName = systemAudioManager.activePhysicalOutputName
        didTripFeedbackProtection = systemAudioManager.didTripFeedbackProtection
        isReceivingTapAudio = systemAudioManager.isReceivingTapAudio
        systemEQSetupDetail = systemAudioManager.systemEQSetupDetail
        conflictingHALPlugins = systemAudioManager.conflictingHALPluginNames
    }

    private func updateExternalLoopbackEQIfNeeded() {
        guard systemAudioMode == .externalLoopback, systemAudioStatus == .running else {
            return
        }

        systemAudioManager.updateExternalLoopbackEQ(currentActivePreset())
        syncSystemAudioState()
    }

    func updateSystemEQIfNeeded() {
        guard systemAudioMode == .systemEQ, systemAudioStatus == .running else {
            return
        }

        systemAudioManager.updateSystemAudioEQ(currentActivePreset())
        syncSystemAudioState()
    }

    /// Single DSP policy for every engine: same bands, mode, and preamp.
    private func currentActivePreset() -> EQPreset {
        EQPreset(
            name: selectedPreset.name,
            mode: eqMode,
            bands: bands,
            preamp: preamp
        )
    }

    private func rememberRecentPreset(_ preset: EQPreset) {
        // Skip ephemeral "Custom" fader edits for the quick-switch list.
        guard preset.name != "Custom" else { return }

        recentPresets.removeAll { $0.id == preset.id || $0.name == preset.name }
        recentPresets.insert(preset, at: 0)
        if recentPresets.count > 3 {
            recentPresets = Array(recentPresets.prefix(3))
        }
    }
}

// MARK: - UTType Extension
extension UTType {
    public static var coreAudioFormat: UTType {
        UTType("com.apple.coreaudio-format") ?? UTType.audio
    }
}
