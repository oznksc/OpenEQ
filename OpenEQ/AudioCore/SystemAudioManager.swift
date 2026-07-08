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
    private(set) var spectrumLevels: [Float] = Array(repeating: 0.0, count: SpectrumAnalyzer.barCount)
    private(set) var leftLevel: Float = 0.0
    private(set) var rightLevel: Float = 0.0
    private(set) var peakLevel: Float = 0.0
    private(set) var isClipping: Bool = false
    private(set) var externalLoopbackLatency: TimeInterval?
    private(set) var isExternalLoopbackBypassed = false
    private(set) var systemAudioLatency: TimeInterval?

    private let deviceManager: AudioDeviceManager
    private let systemAudioEQEngine: SystemAudioEQEngine
    private let externalLoopbackEngine: ExternalLoopbackEngine
    private let logger = AppLogger(category: "SystemAudio")

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
            self?.status = status
        }
        self.externalLoopbackEngine.onAnalysis = { [weak self] analysis in
            self?.applyAnalysis(analysis)
        }
        refreshDevices()
    }

    func setMode(_ mode: SystemAudioMode) {
        stopActive()
        self.mode = mode
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
            startSystemEQ()
        case .externalLoopback:
            startExternalLoopback(preset: .flatPreset())
        }
    }

    func stop() {
        stopActive()
        status = .stopped
    }

    func startSystemEQ() {
        stopActive()
        mode = .systemEQ
        guard #available(macOS 14.2, *) else {
            status = .failed("System-wide EQ requires macOS 14.2 or later.")
            return
        }

        let preset = EQPreset(name: "System EQ", mode: .graphic, bands: EQBand.defaultBands(count: .ten), preamp: 0)
        systemAudioEQEngine.start(with: preset)
        systemAudioLatency = systemAudioEQEngine.latencyEstimate
        status = systemAudioEQEngine.status
    }

    func stopSystemEQ() {
        systemAudioEQEngine.stop()
        systemAudioLatency = nil
        resetAnalysis()
        if mode == .systemEQ { status = .stopped }
    }

    func updateSystemAudiEQ(_ preset: EQPreset) {
        guard mode == .systemEQ else { return }
        systemAudioEQEngine.updateEQ(preset)
    }

    func setSystemAudiBypassed(_ bypassed: Bool) {
        guard mode == .systemEQ else { return }
        systemAudioEQEngine.setBypassed(bypassed)
    }

    func startExternalLoopback(preset: EQPreset) {
        stopSystemEQ()
        mode = .externalLoopback
        updateStatusForCurrentMode()
        guard status == .ready else { return }

        externalLoopbackEngine.start(
            inputDevice: selectedInputDevice,
            outputDevice: selectedOutputDevice,
            preset: preset
        )
        status = externalLoopbackEngine.status
        externalLoopbackLatency = externalLoopbackEngine.latencyEstimate
        isExternalLoopbackBypassed = externalLoopbackEngine.isBypassed
    }

    func stopExternalLoopback() {
        externalLoopbackEngine.stop()
        externalLoopbackLatency = nil
        isExternalLoopbackBypassed = false
        resetAnalysis()
        if mode == .externalLoopback { status = .stopped }
    }

    func restartExternalLoopback(preset: EQPreset) {
        externalLoopbackEngine.updateEQ(preset)
        externalLoopbackEngine.restart()
        status = externalLoopbackEngine.status
        externalLoopbackLatency = externalLoopbackEngine.latencyEstimate
    }

    func updateExternalLoopbackEQ(_ preset: EQPreset) {
        guard mode == .externalLoopback else { return }
        externalLoopbackEngine.updateEQ(preset)
    }

    func setExternalLoopbackBypassed(_ bypassed: Bool) {
        externalLoopbackEngine.setBypassed(bypassed)
        isExternalLoopbackBypassed = externalLoopbackEngine.isBypassed
    }

    func getInputDevices() -> [AudioDevice] { deviceManager.getInputDevices() }
    func getOutputDevices() -> [AudioDevice] { deviceManager.getOutputDevices() }
    func getDefaultInputDevice() -> AudioDevice? { deviceManager.getDefaultInputDevice() }
    func getDefaultOutputDevice() -> AudioDevice? { deviceManager.getDefaultOutputDevice() }
    func detectBlackHoleDevice() -> AudioDevice? { deviceManager.detectBlackHoleDevice() }

    private func syncDeviceSnapshot() {
        let inputs = deviceManager.getInputDevices()
        let outputs = deviceManager.getOutputDevices()
        availableInputDevices = inputs
        availableOutputDevices = outputs
        detectedBlackHoleDevice = deviceManager.detectBlackHoleDevice()

        selectedInputDevice = selectedInputDevice.flatMap { cur in inputs.first { $0.id == cur.id } }
            ?? inputs.first(where: \.isDefaultInput) ?? inputs.first
        selectedOutputDevice = selectedOutputDevice.flatMap { cur in outputs.first { $0.id == cur.id } }
            ?? outputs.first(where: \.isDefaultOutput) ?? outputs.first

        updateStatusForCurrentMode()
    }

    private func updateStatusForCurrentMode() {
        if status == .running, deviceManager.lastError == nil { return }
        if let err = deviceManager.lastError {
            status = .failed(err.localizedDescription); return
        }

        switch mode {
        case .disabled:
            status = .stopped
        case .systemEQ:
            guard #available(macOS 14.2, *) else {
                status = .failed("Requires macOS 14.2+"); return
            }
            status = .ready
        case .externalLoopback:
            guard selectedInputDevice != nil else { status = .unavailable; return }
            guard selectedOutputDevice != nil else { status = .failed("Select an output device"); return }
            if detectedBlackHoleDevice == nil {
                status = .failed("Install BlackHole for loopback"); return
            }
            if selectedOutputDevice?.isBlackHole == true {
                status = .failed("Output cannot be BlackHole"); return
            }
            if selectedInputDevice?.id == selectedOutputDevice?.id {
                status = .failed("Input and output cannot match"); return
            }
            status = .ready
        }
    }

    private func applyAnalysis(_ analysis: SpectrumAnalysis) {
        spectrumLevels = analysis.levels
        leftLevel = analysis.leftPeak
        rightLevel = analysis.rightPeak
        peakLevel = analysis.peakLevel
        isClipping = analysis.isClipping
    }

    private func resetAnalysis() {
        spectrumLevels = Array(repeating: 0.0, count: SpectrumAnalyzer.barCount)
        leftLevel = 0; rightLevel = 0; peakLevel = 0; isClipping = false
    }

    private func stopActive() {
        if mode == .systemEQ { stopSystemEQ() }
        if mode == .externalLoopback { stopExternalLoopback() }
    }
}
