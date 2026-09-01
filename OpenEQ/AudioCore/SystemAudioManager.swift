import AppKit
import CoreAudio
import Foundation
import Observation

@MainActor
@Observable
final class SystemAudioManager {
    private(set) var mode: SystemAudioMode = .disabled
    private(set) var status: SystemAudioStatus = .stopped
    private(set) var selectedInputDevice: AudioDevice?
    private(set) var selectedOutputDevice: AudioDevice?
    private(set) var availableInputDevices: [AudioDevice] = []
    private(set) var availableOutputDevices: [AudioDevice] = []
    private(set) var detectedBlackHoleDevice: AudioDevice?
    private(set) var spectrumLevels = SpectrumLevels()
    private(set) var leftLevel: Float = 0.0
    private(set) var rightLevel: Float = 0.0
    private(set) var peakLevel: Float = 0.0
    private(set) var isClipping: Bool = false
    private(set) var externalLoopbackLatency: TimeInterval?
    private(set) var isExternalLoopbackBypassed = false
    private(set) var isSystemAudioBypassed = false
    private(set) var systemAudioLatency: TimeInterval?
    private(set) var activePhysicalOutputUID: String?
    private(set) var activePhysicalOutputName: String?
    private(set) var didTripFeedbackProtection = false
    /// True when system EQ should resume after wake / recovery.
    private(set) var prefersSystemEQRunning = false
    private(set) var isReceivingTapAudio = false
    private(set) var systemEQSetupDetail: String?
    /// Third-party HAL plugins that commonly break process taps / aggregates.
    private(set) var conflictingHALPluginNames: [String] = []

    var onPhysicalOutputChanged: ((String?, String?) -> Void)?
    var onSafetyTrip: (() -> Void)?
    var onAnalysis: ((SpectrumAnalysis) -> Void)?

    private let deviceManager: AudioDeviceManager
    private let systemAudioEQEngine: SystemAudioEQEngine
    private let externalLoopbackEngine: ExternalLoopbackEngine
    private let logger = AppLogger(category: "SystemAudio")
    private var rebuildWorkItem: DispatchWorkItem?
    private var lastSystemEQPreset: EQPreset = .flatPreset()
    private var loopbackFeedbackGuard = FeedbackGuard()
    private let workspaceObserverStore = WorkspaceObserverStore(
        center: NSWorkspace.shared.notificationCenter
    )

    convenience init() {
        self.init(
            deviceManager: AudioDeviceManager(),
            systemAudioEQEngine: SystemAudioEQEngine(),
            externalLoopbackEngine: ExternalLoopbackEngine()
        )
    }

    init(
        deviceManager: AudioDeviceManager,
        systemAudioEQEngine: SystemAudioEQEngine,
        externalLoopbackEngine: ExternalLoopbackEngine
    ) {
        self.deviceManager = deviceManager
        self.systemAudioEQEngine = systemAudioEQEngine
        self.externalLoopbackEngine = externalLoopbackEngine
        self.deviceManager.onDevicesChanged = { [weak self] in
            Task { @MainActor in self?.syncDeviceSnapshot() }
        }
        self.systemAudioEQEngine.onAnalysis = { [weak self] analysis in
            self?.applyAnalysis(analysis)
        }
        self.systemAudioEQEngine.onStatusChanged = { [weak self] status in
            self?.handleEngineStatus(status)
        }
        self.systemAudioEQEngine.onSafetyTrip = { [weak self] in
            self?.handleSafetyTrip()
        }
        self.systemAudioEQEngine.onPhysicalOutputChanged = { [weak self] uid, name in
            self?.activePhysicalOutputUID = uid
            self?.activePhysicalOutputName = name
            self?.onPhysicalOutputChanged?(uid, name)
        }
        self.externalLoopbackEngine.onAnalysis = { [weak self] analysis in
            self?.applyAnalysis(analysis)
            self?.evaluateLoopbackFeedback(analysis)
        }
        refreshDevices()
        startSleepWakeObservers()
        conflictingHALPluginNames = Self.detectConflictingHALPlugins()
    }

    static func detectConflictingHALPlugins() -> [String] {
        let dir = "/Library/Audio/Plug-Ins/HAL"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
            return []
        }
        let suspects = ["Boom", "DeskFx", "Hear", "SoundSiphon", "Audio Hijack"]
        return contents.filter { name in
            suspects.contains { name.localizedCaseInsensitiveContains($0) }
        }
    }

    func setMode(_ mode: SystemAudioMode) {
        stopActive()
        self.mode = mode
        prefersSystemEQRunning = false
        updateStatusForCurrentMode()
        logger.info("System audio mode changed to \(mode.rawValue)")
    }

    func refreshDevices() {
        deviceManager.refreshDevices()
        syncDeviceSnapshot()
    }

    func selectInputDevice(_ device: AudioDevice?) {
        selectedInputDevice = device
        updateStatusForCurrentMode()
    }

    func selectOutputDevice(_ device: AudioDevice?) {
        selectedOutputDevice = device
        updateStatusForCurrentMode()
    }

    func start() {
        switch mode {
        case .disabled:
            status = .stopped
        case .systemEQ:
            startSystemEQ(preset: lastSystemEQPreset)
        case .externalLoopback:
            startExternalLoopback(preset: lastSystemEQPreset)
        }
    }

    func stop() {
        prefersSystemEQRunning = false
        stopActive()
        status = .stopped
    }

    /// Emergency stop: drop all system processing and restore routing immediately.
    func enterSafeMode() {
        logger.warning("Entering system audio safe mode")
        prefersSystemEQRunning = false
        rebuildWorkItem?.cancel()
        stopActive()
        mode = .disabled
        isSystemAudioBypassed = false
        isExternalLoopbackBypassed = false
        didTripFeedbackProtection = false
        loopbackFeedbackGuard.reset()
        resetAnalysis()
        status = .stopped
    }

    func startSystemEQ() {
        startSystemEQ(preset: EQPreset.flatPreset())
    }

    func startSystemEQ(preset: EQPreset) {
        startSystemEQ(preset: preset, target: .systemExcludingSelf, preferredOutputUID: nil)
    }

    /// Starts process-tap EQ for system-wide or a specific app target from the graph.
    func startSystemEQ(
        preset: EQPreset,
        target: ProcessTapTarget,
        preferredOutputUID: String? = nil
    ) {
        stopActive()
        mode = .systemEQ
        lastSystemEQPreset = preset
        prefersSystemEQRunning = true
        // Clear sticky error/permission UI so a retry can show the real new outcome.
        status = .ready
        systemEQSetupDetail = nil
        isReceivingTapAudio = false
        guard #available(macOS 14.2, *) else {
            status = .failed("System-wide EQ requires macOS 14.2 or later.")
            prefersSystemEQRunning = false
            return
        }

        systemAudioEQEngine.setFeedbackProtectionEnabled(AppPreferences.feedbackProtectionEnabled)
        systemAudioEQEngine.start(
            with: preset,
            target: target,
            preferredOutputUID: preferredOutputUID
        )
        systemAudioEQEngine.setBypassed(isSystemAudioBypassed)
        systemAudioLatency = systemAudioEQEngine.latencyEstimate
        activePhysicalOutputUID = systemAudioEQEngine.physicalOutputUID
        activePhysicalOutputName = systemAudioEQEngine.physicalOutputName
        isReceivingTapAudio = systemAudioEQEngine.isReceivingTapAudio
        systemEQSetupDetail = systemAudioEQEngine.lastSetupDetail
        didTripFeedbackProtection = false
        status = systemAudioEQEngine.status
        if status != .running {
            prefersSystemEQRunning = false
        }

        // Refresh health flags shortly after start (engine schedules its own probe).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { [weak self] in
            guard let self else { return }
            self.isReceivingTapAudio = self.systemAudioEQEngine.isReceivingTapAudio
            self.systemEQSetupDetail = self.systemAudioEQEngine.lastSetupDetail
        }
    }

    func stopSystemEQ() {
        prefersSystemEQRunning = false
        systemAudioEQEngine.stop()
        systemAudioLatency = nil
        activePhysicalOutputUID = nil
        activePhysicalOutputName = nil
        didTripFeedbackProtection = false
        resetAnalysis()
        if mode == .systemEQ { status = .stopped }
    }

    func updateSystemAudioEQ(_ preset: EQPreset) {
        guard mode == .systemEQ else { return }
        lastSystemEQPreset = preset
        systemAudioEQEngine.updateEQ(preset)
    }

    func setSystemAudioLevelMatch(enabled: Bool, gainDB: Float) {
        systemAudioEQEngine.setLevelMatched(enabled, gainDB: gainDB)
    }

    func setSystemAudioBypassed(_ bypassed: Bool) {
        isSystemAudioBypassed = bypassed
        guard mode == .systemEQ else { return }
        systemAudioEQEngine.setBypassed(bypassed)
    }

    func clearFeedbackProtectionTrip() {
        didTripFeedbackProtection = false
        loopbackFeedbackGuard.reset()
        systemAudioEQEngine.clearSafetyTripMute()
        if mode == .systemEQ, status == .running {
            // Resume processing after user acknowledges the trip.
            systemAudioEQEngine.setBypassed(isSystemAudioBypassed)
        }
    }

    func setFeedbackProtectionEnabled(_ enabled: Bool) {
        AppPreferences.feedbackProtectionEnabled = enabled
        systemAudioEQEngine.setFeedbackProtectionEnabled(enabled)
        if !enabled {
            clearFeedbackProtectionTrip()
        }
    }

    func startExternalLoopback(preset: EQPreset) {
        stopSystemEQ()
        mode = .externalLoopback
        lastSystemEQPreset = preset
        prefersSystemEQRunning = false
        loopbackFeedbackGuard.reset()
        updateStatusForCurrentMode()
        guard status == .ready else { return }

        // Prefer BlackHole as input when available and nothing valid selected.
        if selectedInputDevice?.isBlackHole != true, let blackHole = detectedBlackHoleDevice {
            selectedInputDevice = blackHole
        }

        externalLoopbackEngine.start(
            inputDevice: selectedInputDevice,
            outputDevice: selectedOutputDevice,
            preset: preset
        )
        externalLoopbackEngine.setBypassed(isExternalLoopbackBypassed)
        status = externalLoopbackEngine.status
        externalLoopbackLatency = externalLoopbackEngine.latencyEstimate
        isExternalLoopbackBypassed = externalLoopbackEngine.isBypassed
    }

    func stopExternalLoopback() {
        externalLoopbackEngine.stop()
        externalLoopbackLatency = nil
        loopbackFeedbackGuard.reset()
        resetAnalysis()
        if mode == .externalLoopback { status = .stopped }
    }

    func restartExternalLoopback(preset: EQPreset) {
        lastSystemEQPreset = preset
        externalLoopbackEngine.updateEQ(preset)
        externalLoopbackEngine.restart()
        externalLoopbackEngine.setBypassed(isExternalLoopbackBypassed)
        status = externalLoopbackEngine.status
        externalLoopbackLatency = externalLoopbackEngine.latencyEstimate
    }

    func updateExternalLoopbackEQ(_ preset: EQPreset) {
        guard mode == .externalLoopback else { return }
        lastSystemEQPreset = preset
        externalLoopbackEngine.updateEQ(preset)
    }

    func setExternalLoopbackBypassed(_ bypassed: Bool) {
        isExternalLoopbackBypassed = bypassed
        externalLoopbackEngine.setBypassed(bypassed)
        isExternalLoopbackBypassed = externalLoopbackEngine.isBypassed
    }

    func setDeviceVolume(_ volume: Float, for device: AudioDevice) {
        let scope: AudioObjectPropertyScope = device.isOutput ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput
        deviceManager.setVolume(volume, for: device.id, scope: scope)
        syncDeviceSnapshot()
    }

    func setDeviceMute(_ isMuted: Bool, for device: AudioDevice) {
        let scope: AudioObjectPropertyScope = device.isOutput ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput
        deviceManager.setMute(isMuted, for: device.id, scope: scope)
        syncDeviceSnapshot()
    }

    func openSystemAudioPrivacySettings() {
        // Prefer the modern Settings deep links used on Sonoma/Sequoia+.
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ]

        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }

        if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(fallback)
        }
    }

    /// Clears sticky permission/failed state so Start can be retried cleanly.
    func clearPermissionBlock() {
        if status == .permissionRequired || status.isTerminalFailure {
            status = mode == .disabled ? .stopped : .ready
        }
        systemEQSetupDetail = nil
    }

    func getInputDevices() -> [AudioDevice] { deviceManager.getInputDevices() }
    func getOutputDevices() -> [AudioDevice] { deviceManager.getOutputDevices() }
    func getDefaultInputDevice() -> AudioDevice? { deviceManager.getDefaultInputDevice() }
    func getDefaultOutputDevice() -> AudioDevice? { deviceManager.getDefaultOutputDevice() }
    func detectBlackHoleDevice() -> AudioDevice? { deviceManager.detectBlackHoleDevice() }

    // MARK: - Private

    private func handleEngineStatus(_ status: SystemAudioStatus) {
        self.status = status
        switch status {
        case .running:
            systemAudioLatency = systemAudioEQEngine.latencyEstimate
            activePhysicalOutputUID = systemAudioEQEngine.physicalOutputUID
            activePhysicalOutputName = systemAudioEQEngine.physicalOutputName
        case .stopped, .permissionRequired:
            systemAudioLatency = nil
        case .failed:
            systemAudioLatency = nil
            prefersSystemEQRunning = false
        case .ready, .unavailable:
            break
        }
    }

    private func handleSafetyTrip() {
        didTripFeedbackProtection = true
        logger.warning("Feedback protection tripped — muting system EQ output")
        // Keep processing graph alive but muted; do not force EQ bypass so the user
        // can resume with the same curve after acknowledging the warning.
        onSafetyTrip?()
    }

    private func evaluateLoopbackFeedback(_ analysis: SpectrumAnalysis) {
        guard mode == .externalLoopback, status == .running else { return }
        guard AppPreferences.feedbackProtectionEnabled else { return }

        // Peak meters are normalized ~0…1; require true clip-like peaks, not loud music.
        let peak = analysis.peakLevel
        let rms = max(analysis.leftPeak, analysis.rightPeak) * 0.55
        if loopbackFeedbackGuard.evaluate(peak: peak, rms: rms) {
            didTripFeedbackProtection = true
            logger.warning("Feedback protection tripped on external loopback")
            externalLoopbackEngine.setBypassed(true)
            isExternalLoopbackBypassed = true
            onSafetyTrip?()
        }
    }

    private func startSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter

        // Observers live for the process lifetime (manager is owned by the app ViewModel).
        let willSleepToken = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWillSleep()
            }
        }

        let didWakeToken = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDidWake()
            }
        }

        workspaceObserverStore.add(willSleepToken)
        workspaceObserverStore.add(didWakeToken)
    }

    private func handleWillSleep() {
        guard mode == .systemEQ, status == .running else { return }
        logger.info("System sleep detected — pausing aggregate IO safely")
        // Keep prefersSystemEQRunning true so wake can resume.
        systemAudioEQEngine.stop()
        systemAudioLatency = nil
        status = .stopped
    }

    private func handleDidWake() {
        guard prefersSystemEQRunning, mode == .systemEQ else { return }
        logger.info("System wake detected — recovering system EQ")
        // Brief delay lets Core Audio re-enumerate devices after wake.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.prefersSystemEQRunning, self.mode == .systemEQ else { return }
            self.refreshDevices()
            self.systemAudioEQEngine.setFeedbackProtectionEnabled(AppPreferences.feedbackProtectionEnabled)
            self.systemAudioEQEngine.start(with: self.lastSystemEQPreset)
            self.systemAudioEQEngine.setBypassed(self.isSystemAudioBypassed)
            self.systemAudioLatency = self.systemAudioEQEngine.latencyEstimate
            self.activePhysicalOutputUID = self.systemAudioEQEngine.physicalOutputUID
            self.activePhysicalOutputName = self.systemAudioEQEngine.physicalOutputName
            self.status = self.systemAudioEQEngine.status
            if self.status != .running {
                self.prefersSystemEQRunning = false
            }
        }
    }

    private func syncDeviceSnapshot() {
        let inputs = deviceManager.getInputDevices()
        let outputs = deviceManager.getOutputDevices()
        availableInputDevices = inputs
        availableOutputDevices = outputs
        detectedBlackHoleDevice = deviceManager.detectBlackHoleDevice()

        selectedInputDevice = selectedInputDevice.flatMap { cur in inputs.first { $0.id == cur.id } }
            ?? detectedBlackHoleDevice
            ?? inputs.first(where: \.isDefaultInput)
            ?? inputs.first
        selectedOutputDevice = selectedOutputDevice.flatMap { cur in outputs.first { $0.id == cur.id } }
            ?? outputs.first(where: \.isDefaultOutput)
            ?? outputs.first

        if mode == .systemEQ, status == .running || prefersSystemEQRunning {
            scheduleRebuild()
        }

        updateStatusForCurrentMode()
    }

    private func scheduleRebuild() {
        rebuildWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.systemAudioEQEngine.rebuildAggregateWithCurrentOutput()
            self.systemAudioLatency = self.systemAudioEQEngine.latencyEstimate
            self.activePhysicalOutputUID = self.systemAudioEQEngine.physicalOutputUID
            self.activePhysicalOutputName = self.systemAudioEQEngine.physicalOutputName
            self.status = self.systemAudioEQEngine.status
        }
        rebuildWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func updateStatusForCurrentMode() {
        // Never sticky-lock permission/failed forever — device refresh used to freeze the UI
        // on "Permission Required" even after TCC was granted.
        if status == .running, systemAudioEQEngine.status == .running, deviceManager.lastError == nil {
            return
        }
        if let err = deviceManager.lastError {
            status = .failed(err.localizedDescription)
            return
        }

        switch mode {
        case .disabled:
            status = .stopped
        case .systemEQ:
            guard #available(macOS 14.2, *) else {
                status = .failed("Requires macOS 14.2+")
                return
            }
            // Prefer live engine status so retries surface the real error.
            switch systemAudioEQEngine.status {
            case .running:
                status = .running
            case .failed(let message):
                status = .failed(message)
            case .permissionRequired:
                status = .permissionRequired
            case .stopped, .ready, .unavailable:
                status = .ready
            }
        case .externalLoopback:
            guard selectedInputDevice != nil else {
                status = .unavailable
                return
            }
            guard selectedOutputDevice != nil else {
                status = .failed("Select an output device")
                return
            }
            if detectedBlackHoleDevice == nil {
                status = .failed("Install BlackHole for loopback")
                return
            }
            if selectedOutputDevice?.isBlackHole == true {
                status = .failed("Output cannot be BlackHole")
                return
            }
            if selectedInputDevice?.id == selectedOutputDevice?.id {
                status = .failed("Input and output cannot match")
                return
            }
            if externalLoopbackEngine.status == .running {
                status = .running
            } else {
                status = .ready
            }
        }
    }

    private func applyAnalysis(_ analysis: SpectrumAnalysis) {
        spectrumLevels = analysis.levels
        leftLevel = analysis.leftPeak
        rightLevel = analysis.rightPeak
        peakLevel = analysis.peakLevel
        isClipping = analysis.isClipping
        onAnalysis?(analysis)
    }

    private func resetAnalysis() {
        let analysis = SpectrumAnalysis(
            levels: SpectrumLevels(),
            leftPeak: 0,
            rightPeak: 0,
            peakLevel: 0,
            isClipping: false
        )
        applyAnalysis(analysis)
    }

    private func stopActive() {
        rebuildWorkItem?.cancel()
        if mode == .systemEQ { stopSystemEQ() }
        if mode == .externalLoopback { stopExternalLoopback() }
    }
}

private final class WorkspaceObserverStore {
    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter) {
        self.center = center
    }

    func add(_ token: NSObjectProtocol) {
        tokens.append(token)
    }

    deinit {
        for token in tokens {
            center.removeObserver(token)
        }
    }
}
