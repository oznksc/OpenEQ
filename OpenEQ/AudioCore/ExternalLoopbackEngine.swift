//
//  ExternalLoopbackEngine.swift
//  OpenEQ
//
//  Created by Codex on 27.06.2026.
//

import AVFoundation
import AudioToolbox
import Foundation

@MainActor
@Observable
final class ExternalLoopbackEngine {
    private(set) var status: SystemAudioStatus = .stopped
    private(set) var latencyEstimate: TimeInterval?
    private(set) var isBypassed = false

    var onAnalysis: ((SpectrumAnalysis) -> Void)?

    private let logger = AppLogger(category: "ExternalLoopback")
    private let engine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: 31)
    private let limiter: AVAudioUnitEffect
    private let analyzer = SpectrumAnalyzer()

    private var selectedInputDevice: AudioDevice?
    private var selectedOutputDevice: AudioDevice?
    private var currentPreset: EQPreset = .flatPreset()
    private var isTapInstalled = false

    init() {
        let limiterDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        self.limiter = AVAudioUnitEffect(audioComponentDescription: limiterDescription)
    }

    func configure(inputDevice: AudioDevice?, outputDevice: AudioDevice?) {
        selectedInputDevice = inputDevice
        selectedOutputDevice = outputDevice
    }

    func start(inputDevice: AudioDevice?, outputDevice: AudioDevice?, preset: EQPreset) {
        configure(inputDevice: inputDevice, outputDevice: outputDevice)
        currentPreset = preset

        do {
            try validateRouting()
            stop()
            configureGraph()
            updateEQ(preset)
            installAnalyzerTap()
            try engine.start()
            latencyEstimate = estimateLatency()
            status = .running
            logger.info("External loopback engine started.")
        } catch let error as ExternalLoopbackError {
            status = .failed(error.localizedDescription)
            logger.error(error.localizedDescription)
        } catch {
            status = .failed(error.localizedDescription)
            logger.error(error.localizedDescription)
        }
    }

    func stop() {
        removeAnalyzerTap()
        engine.stop()
        engine.reset()
        status = .stopped
        latencyEstimate = nil
    }

    func restart() {
        start(
            inputDevice: selectedInputDevice,
            outputDevice: selectedOutputDevice,
            preset: currentPreset
        )
    }

    func updateEQ(_ preset: EQPreset) {
        currentPreset = preset
        applyPreset(preset)
    }

    func setBypassed(_ isBypassed: Bool) {
        self.isBypassed = isBypassed
        eq.bypass = isBypassed
        limiter.bypass = false
    }

    private func configureGraph() {
        let input = engine.inputNode
        let mixer = engine.mainMixerNode
        let inputFormat = input.outputFormat(forBus: 0)

        if eq.engine == nil {
            engine.attach(eq)
        }

        if limiter.engine == nil {
            engine.attach(limiter)
        }

        engine.disconnectNodeOutput(input)
        engine.disconnectNodeOutput(eq)
        engine.disconnectNodeOutput(limiter)

        // External loopback path: selected virtual input -> EQ -> limiter -> selected/default output.
        engine.connect(input, to: eq, format: inputFormat)
        engine.connect(eq, to: limiter, format: inputFormat)
        engine.connect(limiter, to: mixer, format: inputFormat)
    }

    private func validateRouting() throws {
        guard let inputDevice = selectedInputDevice else {
            throw ExternalLoopbackError.missingInput
        }

        guard let outputDevice = selectedOutputDevice else {
            throw ExternalLoopbackError.missingOutput
        }

        guard inputDevice.id != outputDevice.id else {
            throw ExternalLoopbackError.feedbackRisk("Input and output cannot be the same device.")
        }

        if outputDevice.isBlackHole {
            throw ExternalLoopbackError.feedbackRisk("Output device is also BlackHole. Select speakers or headphones to avoid a feedback loop.")
        }

        guard inputDevice.isDefaultInput, outputDevice.isDefaultOutput else {
            throw ExternalLoopbackError.deviceBindingUnavailable(
                "For this beta build, set macOS Sound Input to \(inputDevice.name) and Sound Output to \(outputDevice.name). Arbitrary device binding requires Core Audio HAL device selection."
            )
        }
    }

    private func applyPreset(_ preset: EQPreset) {
        let activeBandCount = min(preset.bands.count, eq.bands.count)
        eq.globalGain = preset.preamp

        for index in 0..<eq.bands.count {
            let audioBand = eq.bands[index]

            guard index < activeBandCount else {
                audioBand.bypass = true
                audioBand.gain = EQBand.neutralGain
                continue
            }

            let modelBand = preset.bands[index]
            audioBand.frequency = modelBand.frequency
            audioBand.gain = modelBand.gain
            audioBand.bandwidth = modelBand.q
            audioBand.filterType = modelBand.audioUnitFilterType(for: preset.mode)
            audioBand.bypass = !modelBand.isEnabled
        }
    }

    private func installAnalyzerTap() {
        guard !isTapInstalled else { return }

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let analysis = self.analyzer.analyze(buffer: buffer) else {
                return
            }

            DispatchQueue.main.async {
                self.onAnalysis?(analysis)
            }
        }
        isTapInstalled = true
    }

    private func removeAnalyzerTap() {
        guard isTapInstalled else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        isTapInstalled = false
    }

    private func estimateLatency() -> TimeInterval {
        let inputLatency = engine.inputNode.latency
        let outputLatency = engine.outputNode.latency
        let ioBufferLatency = Double(engine.inputNode.outputFormat(forBus: 0).sampleRate > 0 ? 1024.0 / engine.inputNode.outputFormat(forBus: 0).sampleRate : 0.0)
        return inputLatency + outputLatency + ioBufferLatency
    }
}

private enum ExternalLoopbackError: LocalizedError {
    case missingInput
    case missingOutput
    case feedbackRisk(String)
    case deviceBindingUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingInput:
            return "Select a loopback input device such as BlackHole."
        case .missingOutput:
            return "Select a physical output device such as speakers or headphones."
        case .feedbackRisk(let message):
            return message
        case .deviceBindingUnavailable(let message):
            return message
        }
    }
}

private extension EQBand {
    func audioUnitFilterType(for mode: EQMode) -> AVAudioUnitEQFilterType {
        if mode == .graphic {
            return .parametric
        }

        switch filterType {
        case .parametric:
            return .parametric
        case .lowShelf:
            return .lowShelf
        case .highShelf:
            return .highShelf
        case .highPass:
            return .highPass
        case .lowPass:
            return .lowPass
        }
    }
}
