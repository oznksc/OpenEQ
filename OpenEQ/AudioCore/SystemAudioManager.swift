//
//  SystemAudioManager.swift
//  OpenEQ
//
//  Created by Ozan
//

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

    private let deviceManager: AudioDeviceManager
    private let tapManager: CoreAudioTapManager
    private let externalLoopbackEngine: ExternalLoopbackEngine
    private let logger = AppLogger(category: "SystemAudio")

    convenience init() {
        self.init(
            deviceManager: AudioDeviceManager(),
            tapManager: CoreAudioTapManager(),
            externalLoopbackEngine: ExternalLoopbackEngine()
        )
    }

    init(
        deviceManager: AudioDeviceManager,
        tapManager: CoreAudioTapManager,
        externalLoopbackEngine: ExternalLoopbackEngine
    ) {
        self.deviceManager = deviceManager
        self.tapManager = tapManager
        self.externalLoopbackEngine = externalLoopbackEngine
        self.deviceManager.onDevicesChanged = { [weak self] in
            Task { @MainActor in
                self?.syncDeviceSnapshot()
            }
        }
        self.tapManager.onAnalysis = { [weak self] analysis in
            self?.applySystemAudioAnalysis(analysis)
        }
        self.tapManager.onStatusChanged = { [weak self] status in
            self?.status = status
        }
        self.externalLoopbackEngine.onAnalysis = { [weak self] analysis in
            self?.applySystemAudioAnalysis(analysis)
        }
        refreshDevices()
    }

    func setMode(_ mode: SystemAudioMode) {
        stopActiveSystemAudioEngine()
        self.mode = mode
        updateStatusForCurrentMode()
        logger.info("System audio mode changed to \(mode.rawValue)")
    }

    func refreshDevices() {
        deviceManager.refreshDevices()
        syncDeviceSnapshot()
    }

    func getInputDevices() -> [AudioDevice] {
        deviceManager.getInputDevices()
    }

    func getOutputDevices() -> [AudioDevice] {
        deviceManager.getOutputDevices()
    }

    func getDefaultInputDevice() -> AudioDevice? {
        deviceManager.getDefaultInputDevice()
    }

    func getDefaultOutputDevice() -> AudioDevice? {
        deviceManager.getDefaultOutputDevice()
    }

    func findDevice(named keyword: String) -> AudioDevice? {
        deviceManager.findDevice(named: keyword)
    }

    func detectBlackHoleDevice() -> AudioDevice? {
        deviceManager.detectBlackHoleDevice()
    }

    private func syncDeviceSnapshot() {
        let inputDevices = deviceManager.getInputDevices()
        let outputDevices = deviceManager.getOutputDevices()
        let previousInputDevice = selectedInputDevice
        let previousOutputDevice = selectedOutputDevice

        availableInputDevices = inputDevices
        availableOutputDevices = outputDevices
        detectedBlackHoleDevice = deviceManager.detectBlackHoleDevice()

        selectedInputDevice = selectedInputDevice.flatMap { current in
            inputDevices.first { $0.id == current.id }
        } ?? inputDevices.first(where: \.isDefaultInput) ?? inputDevices.first
        selectedOutputDevice = selectedOutputDevice.flatMap { current in
            outputDevices.first { $0.id == current.id }
        } ?? outputDevices.first(where: \.isDefaultOutput) ?? outputDevices.first

        if let previousInputDevice, selectedInputDevice == nil {
            status = .failed(AudioDeviceManagerError.deviceDisappeared(previousInputDevice.name).localizedDescription)
            return
        }

        if let previousOutputDevice, selectedOutputDevice == nil {
            status = .failed(AudioDeviceManagerError.deviceDisappeared(previousOutputDevice.name).localizedDescription)
            return
        }

        updateStatusForCurrentMode()
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
        case .monitorOnly:
            status = selectedInputDevice == nil ? .unavailable : .running
        case .externalLoopback:
            startExternalLoopback(preset: .flatPreset())
        case .nativeTapExperimental:
            // Native virtual audio driver work is out of scope for V1.
            status = .failed("Native tap capture is experimental and not enabled in V1.")
        }
    }

    func stop() {
        stopActiveSystemAudioEngine()
        status = .stopped
    }

    func startSystemAudioMonitor() {
        mode = .nativeTapExperimental
        guard #available(macOS 14.2, *) else {
            status = .failed("System audio capture requires macOS 14.2 or later.")
            return
        }

        status = .permissionRequired
        tapManager.start()
    }

    func stopSystemAudioMonitor() {
        tapManager.stop()
        resetSystemAudioAnalysis()
        if mode == .nativeTapExperimental {
            status = .stopped
        }
    }

    func startExternalLoopback(preset: EQPreset) {
        stopSystemAudioMonitor()
        mode = .externalLoopback
        updateStatusForCurrentMode()

        guard status == .ready else {
            return
        }

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
        resetSystemAudioAnalysis()
        if mode == .externalLoopback {
            status = .stopped
        }
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

    func setExternalLoopbackBypassed(_ isBypassed: Bool) {
        externalLoopbackEngine.setBypassed(isBypassed)
        isExternalLoopbackBypassed = externalLoopbackEngine.isBypassed
    }

    private func updateStatusForCurrentMode() {
        if let lastError = deviceManager.lastError {
            status = .failed(lastError.localizedDescription)
            return
        }

        switch mode {
        case .disabled:
            status = .stopped
        case .monitorOnly:
            status = selectedInputDevice == nil ? .unavailable : .ready
        case .externalLoopback:
            // System audio routing needs one device to receive loopback input and one output to monitor processed audio.
            guard selectedInputDevice != nil else {
                status = .unavailable
                return
            }

            guard selectedOutputDevice != nil else {
                status = .failed("Select an output device for processed monitoring.")
                return
            }

            if detectedBlackHoleDevice == nil {
                status = .failed("BlackHole was not found. Install BlackHole or select another virtual loopback input device.")
                logger.warning("BlackHole was not detected. External loopback can still use another virtual audio device.")
                return
            }

            if selectedOutputDevice?.isBlackHole == true {
                status = .failed("Output device is also BlackHole. Select speakers or headphones to avoid a feedback loop.")
                return
            }

            if selectedInputDevice?.id == selectedOutputDevice?.id {
                status = .failed("Input and output cannot be the same device.")
                return
            }

            status = .ready
        case .nativeTapExperimental:
            // Core Audio Tap can capture outgoing audio, but production routing is experimental.
            status = .permissionRequired
        }
    }

    private func applySystemAudioAnalysis(_ analysis: SpectrumAnalysis) {
        spectrumLevels = analysis.levels
        leftLevel = analysis.leftPeak
        rightLevel = analysis.rightPeak
        peakLevel = analysis.peakLevel
        isClipping = analysis.isClipping
    }

    private func resetSystemAudioAnalysis() {
        spectrumLevels = Array(repeating: 0.0, count: SpectrumAnalyzer.barCount)
        leftLevel = 0.0
        rightLevel = 0.0
        peakLevel = 0.0
        isClipping = false
    }

    private func stopActiveSystemAudioEngine() {
        if mode == .nativeTapExperimental {
            stopSystemAudioMonitor()
        }

        if mode == .externalLoopback {
            stopExternalLoopback()
        }
    }
}
