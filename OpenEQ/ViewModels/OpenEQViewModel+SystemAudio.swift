import Foundation

extension OpenEQViewModel {
    // MARK: - System Audio

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
        systemAudioManager.clearPermissionBlock()
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
            safetyBannerMessage = message
            isShowingSystemAudio = true
        } else if systemAudioStatus == .permissionRequired {
            errorMessage = nil
            safetyBannerMessage = "Enable Screen & System Audio Recording for this OpenEQ build, then press Start again."
            isShowingSystemAudio = true
        } else {
            errorMessage = nil
            safetyBannerMessage = nil
            completeSystemEQOnboardingIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                self?.syncSystemAudioState()
            }
        }
    }

    func retrySystemEQAfterPermission() {
        systemAudioManager.clearPermissionBlock()
        openSystemAudioPrivacySettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.startSystemEQMode()
        }
    }

    func stopSystemEQMode() {
        systemAudioManager.stopSystemEQ()
        syncSystemAudioState()
    }

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
        if !isEnabled {
            setEnabled(true)
        }
        syncSystemAudioState()
    }

    func handlePhysicalOutputChanged(uid: String?, name: String?) {
        activePhysicalOutputUID = uid
        activePhysicalOutputName = name
        syncSystemAudioState()
        applyDeviceProfileIfNeeded(forUID: uid)
    }

    func handleSafetyTrip() {
        didTripFeedbackProtection = true
        safetyBannerMessage = "Feedback protection muted output after sustained clipping. Lower gain or check routing, then resume."
        errorMessage = nil
        syncSystemAudioState()
        isShowingSystemAudio = true
    }

    func applyDeviceProfileIfNeeded(forUID uid: String?) {
        guard autoApplyDeviceProfiles, !isApplyingDeviceProfile else { return }
        guard let uid, let profile = deviceProfileStore.profile(forDeviceUID: uid, in: deviceProfiles) else {
            return
        }
        guard let presetID = profile.presetID else { return }

        let match = presets.first { $0.id == presetID }
            ?? presets.first { $0.name == profile.presetName }
        guard let preset = match, preset.id != selectedPreset.id else { return }

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
}
