import Foundation
import CoreGraphics

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
        if !isExternalLoopbackActive {
            clearGraphRuntimeState()
        }
        syncSystemAudioState()
    }

    func enableSystemEQOneClick() {
        ensureSystemChainInGraph()
        runGraph(preferProcess: true)
    }

    func toggleSystemEQOneClick() {
        if isSystemEQActive || isExternalLoopbackActive {
            stopGraph()
        } else {
            enableSystemEQOneClick()
        }
    }

    // MARK: - Graph runtime

    /// Starts the preferred graph chain (app/system process tap, or input monitor).
    func runGraph(preferProcess: Bool = false) {
        refreshAudioProcesses()
        graphStore.revalidate()

        let document = graphStore.document
        let selection: (GraphChain, GraphRuntime.RunKind)?
        if preferProcess,
           let process = GraphValidation.compileChains(document).first(where: {
               $0.sourceKind == .system || $0.sourceKind == .app
           }),
           let kind = GraphRuntime.resolveProcessKind(chain: process, document: document) {
            selection = (process, kind)
        } else {
            selection = GraphRuntime.preferredRun(from: document)
        }

        guard let (chain, kind) = selection else {
            errorMessage = storeFriendlyGraphError()
            safetyBannerMessage = errorMessage
            return
        }

        let preset = GraphRuntime.equalizerPreset(
            for: chain,
            document: document,
            fallback: currentActivePreset()
        )
        applyPresetFromGraph(preset)
        let eqEnabled = GraphRuntime.isEqualizerEnabled(for: chain, document: document)
        setEnabled(eqEnabled)

        switch kind {
        case .process(let target, let outputUID, let label):
            stop()
            systemAudioManager.clearPermissionBlock()
            systemAudioManager.setSystemAudioBypassed(!isEnabled)
            systemAudioManager.setFeedbackProtectionEnabled(feedbackProtectionEnabled)
            systemAudioManager.startSystemEQ(
                preset: currentActivePreset(),
                target: target,
                preferredOutputUID: outputUID
            )
            syncSystemAudioState()
            applyDeviceProfileIfNeeded(forUID: systemAudioManager.activePhysicalOutputUID)
            updateGraphRuntimeState(chain: chain, label: label)

            if case .failed(let message) = systemAudioStatus {
                errorMessage = message
                safetyBannerMessage = message
                isShowingSystemAudio = true
                clearGraphRuntimeState()
            } else if systemAudioStatus == .permissionRequired {
                errorMessage = nil
                safetyBannerMessage = "Enable Screen & System Audio Recording for this OpenEQ build, then press Run again."
                isShowingSystemAudio = true
                clearGraphRuntimeState()
            } else {
                errorMessage = nil
                safetyBannerMessage = nil
                completeSystemEQOnboardingIfNeeded()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                    self?.syncSystemAudioState()
                }
            }

        case .input(let inputUID, let outputUID, let label):
            stop()
            let inputDevice = resolveInputDevice(uid: inputUID)
            let outputDevice = resolveOutputDevice(uid: outputUID)
            systemAudioManager.selectInputDevice(inputDevice)
            systemAudioManager.selectOutputDevice(outputDevice)
            systemAudioManager.setExternalLoopbackBypassed(!isEnabled)
            systemAudioManager.setFeedbackProtectionEnabled(feedbackProtectionEnabled)
            systemAudioManager.startExternalLoopback(preset: currentActivePreset())
            syncSystemAudioState()
            updateGraphRuntimeState(chain: chain, label: "Mic monitor · \(label)")

            if case .failed(let message) = systemAudioStatus {
                errorMessage = message
                safetyBannerMessage = message
                clearGraphRuntimeState()
            } else {
                errorMessage = nil
                safetyBannerMessage = "Microphone monitor path — not injected into other apps."
            }
        }
    }

    func stopGraph() {
        stopSystemEQMode()
        stopExternalLoopbackMode()
        systemAudioManager.setMode(.disabled)
        clearGraphRuntimeState()
        syncSystemAudioState()
    }

    func toggleGraph() {
        if isSystemEQActive || isExternalLoopbackActive {
            stopGraph()
        } else {
            runGraph()
        }
    }

    /// Ensures a System Audio → EQ → Output chain exists for one-click / toolbar.
    func ensureSystemChainInGraph() {
        let chains = graphStore.runnableChains
        if chains.contains(where: { $0.sourceKind == .system || $0.sourceKind == .app }) {
            return
        }
        // Promote starter or add a system chain.
        if graphStore.document.nodes.isEmpty {
            graphStore.resetToStarter()
            return
        }
        let hasSystem = graphStore.document.nodes.contains { $0.kind == .systemSource }
        let hasEQ = graphStore.document.nodes.contains { $0.kind == .equalizer }
        let hasOut = graphStore.document.nodes.contains { $0.kind == .output }
        if !hasSystem {
            _ = graphStore.addNode(kind: .systemSource, at: CGPoint(x: 80, y: 180))
        }
        if !hasEQ {
            _ = graphStore.addNode(kind: .equalizer, at: CGPoint(x: 320, y: 160))
        }
        if !hasOut {
            _ = graphStore.addNode(kind: .output, at: CGPoint(x: 580, y: 180))
        }
        if let system = graphStore.document.nodes.first(where: { $0.kind == .systemSource }),
           let eq = graphStore.document.nodes.first(where: { $0.kind == .equalizer }),
           let output = graphStore.document.nodes.first(where: { $0.kind == .output }) {
            if graphStore.document.edges(from: system.id).isEmpty {
                _ = graphStore.connect(from: system.portID(name: "out"), to: eq.portID(name: "in"))
            }
            if graphStore.document.edges(from: eq.id).isEmpty {
                _ = graphStore.connect(from: eq.portID(name: "out"), to: output.portID(name: "in"))
            }
        }
    }

    private func applyPresetFromGraph(_ preset: EQPreset) {
        isApplyingGraphEQ = true
        defer { isApplyingGraphEQ = false }
        selectedPreset = preset
        eqMode = preset.mode
        bands = preset.bands
        preamp = preset.preamp
        cacheActiveBands()
        audioEngineController.applyPreset(preset)
    }

    private func updateGraphRuntimeState(chain: GraphChain, label: String) {
        runningGraphNodeIDsOverride = Set(chain.nodeIDs)
        graphRuntimeLabel = label
    }

    private func clearGraphRuntimeState() {
        runningGraphNodeIDsOverride = []
        graphRuntimeLabel = nil
    }

    private func storeFriendlyGraphError() -> String {
        if let issue = graphStore.lastValidationIssues.first {
            return issue.message
        }
        return "Connect App/System or Microphone → Equalizer → Output, then Run."
    }

    private func resolveInputDevice(uid: String?) -> AudioDevice? {
        guard let uid, !uid.isEmpty else {
            return systemAudioManager.getDefaultInputDevice()
        }
        return availableInputDevices.first { ($0.uid ?? $0.profileKey) == uid }
            ?? systemAudioManager.getDefaultInputDevice()
    }

    private func resolveOutputDevice(uid: String?) -> AudioDevice? {
        guard let uid, !uid.isEmpty else {
            return systemAudioManager.getDefaultOutputDevice()
        }
        return availableOutputDevices.first { ($0.uid ?? $0.profileKey) == uid }
            ?? systemAudioManager.getDefaultOutputDevice()
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
        if !isSystemEQActive {
            clearGraphRuntimeState()
        }
        syncSystemAudioState()
    }

    func shutdown() {
        stop()
        systemAudioManager.stop()
        processEnumerator.stop()
        clearGraphRuntimeState()
        graphStore.saveToDisk()
        syncSystemAudioState()
    }

    func enterSafeMode() {
        systemAudioManager.enterSafeMode()
        isEnabled = true
        audioEngineController.setBypass(false)
        clearGraphRuntimeState()
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
