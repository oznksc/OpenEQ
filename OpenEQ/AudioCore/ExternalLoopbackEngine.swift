//
//  ExternalLoopbackEngine.swift
//  OpenEQ
//
//  Created by Ozan
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
    private let analyzer = SpectrumAnalyzer()
    private var engine: AVAudioEngine?
    private var eq: AVAudioUnitEQ?
    private var limiter: AVAudioUnitEffect?

    private var selectedInputDevice: AudioDevice?
    private var selectedOutputDevice: AudioDevice?
    private var currentPreset: EQPreset = .flatPreset()
    private var isTapInstalled = false

    init() {}

    private func ensureGraphNodes() throws -> (
        engine: AVAudioEngine,
        eq: AVAudioUnitEQ,
        limiter: AVAudioUnitEffect
    ) {
        if let engine, let eq, let limiter {
            return (engine, eq, limiter)
        }

        let limiterDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        let engine = AVAudioEngine()
        let eq = AVAudioUnitEQ(numberOfBands: 31)
        let limiter = AVAudioUnitEffect(audioComponentDescription: limiterDescription)

        self.engine = engine
        self.eq = eq
        self.limiter = limiter

        PeakLimiterConfigurator.applyDefaults(to: limiter)
        applyPreset(currentPreset)
        setBypassed(isBypassed)

        return (engine, eq, limiter)
    }

    func configure(inputDevice: AudioDevice?, outputDevice: AudioDevice?) {
        selectedInputDevice = inputDevice
        selectedOutputDevice = outputDevice
    }

    func start(inputDevice: AudioDevice?, outputDevice: AudioDevice?, preset: EQPreset) {
        configure(inputDevice: inputDevice, outputDevice: outputDevice)
        currentPreset = preset
        stop()

        do {
            try validateRouting()
            let nodes = try configureGraph()
            updateEQ(preset)
            try installAnalyzerTap()
            try nodes.engine.start()
            latencyEstimate = estimateLatency()
            status = .running
            logger.info("External loopback engine started.")
        } catch let error as ExternalLoopbackError {
            cleanupAfterFailedStart()
            status = .failed(error.localizedDescription)
            logger.error(error.localizedDescription)
        } catch {
            cleanupAfterFailedStart()
            status = .failed(error.localizedDescription)
            logger.error(error.localizedDescription)
        }
    }

    func stop() {
        removeAnalyzerTap()
        engine?.stop()
        engine?.reset()
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
        eq?.bypass = isBypassed
        limiter?.bypass = false
    }

    private func configureGraph() throws -> (
        engine: AVAudioEngine,
        eq: AVAudioUnitEQ,
        limiter: AVAudioUnitEffect
    ) {
        let nodes = try ensureGraphNodes()
        let input = nodes.engine.inputNode
        let mixer = nodes.engine.mainMixerNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw ExternalLoopbackError.invalidAudioFormat
        }

        if nodes.eq.engine == nil {
            nodes.engine.attach(nodes.eq)
        }

        if nodes.limiter.engine == nil {
            nodes.engine.attach(nodes.limiter)
        }

        nodes.engine.disconnectNodeOutput(input)
        nodes.engine.disconnectNodeOutput(nodes.eq)
        nodes.engine.disconnectNodeOutput(nodes.limiter)

        nodes.engine.connect(input, to: nodes.eq, format: inputFormat)
        nodes.engine.connect(nodes.eq, to: nodes.limiter, format: inputFormat)
        nodes.engine.connect(nodes.limiter, to: mixer, format: inputFormat)

        return nodes
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
        guard let eq else { return }
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
            audioBand.bandwidth = modelBand.audioUnitBandwidth
            audioBand.filterType = modelBand.audioUnitFilterType(for: preset.mode)
            audioBand.bypass = !modelBand.isEnabled
        }
    }

    private func installAnalyzerTap() throws {
        guard !isTapInstalled else { return }
        guard let engine else { throw ExternalLoopbackError.invalidAudioFormat }

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw ExternalLoopbackError.invalidAudioFormat
        }

        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let analysis = self.analyzer.analyze(buffer: buffer) else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onAnalysis?(analysis)
            }
        }
        isTapInstalled = true
    }

    private func cleanupAfterFailedStart() {
        removeAnalyzerTap()
        engine?.stop()
        engine?.reset()
        latencyEstimate = nil
    }

    private func removeAnalyzerTap() {
        guard isTapInstalled else { return }
        engine?.mainMixerNode.removeTap(onBus: 0)
        isTapInstalled = false
    }

    private func estimateLatency() -> TimeInterval {
        guard let engine else { return 0 }
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
    case invalidAudioFormat

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
        case .invalidAudioFormat:
            return "The selected audio route does not expose a usable PCM format."
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
