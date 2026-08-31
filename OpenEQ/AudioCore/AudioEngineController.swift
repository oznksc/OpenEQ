//
//  AudioEngineController.swift
//  OpenEQ
//
//  Created by Ozan
//

import Foundation
import AVFoundation
import Observation

@Observable
final class AudioEngineController {
    private(set) var playbackState: AudioEngineState = .idle
    private(set) var currentPreset: EQPreset = .flatPreset()
    private(set) var spectrumLevels: [Float] = Array(repeating: 0.0, count: SpectrumAnalyzer.barCount)
    private(set) var leftLevel: Float = 0.0
    private(set) var rightLevel: Float = 0.0
    private(set) var peakLevel: Float = 0.0
    private(set) var isClipping: Bool = false

    private var volumeBoostMultiplier: Float = 1.0
    private var currentPreampGain: Float = 0.0
    private var outputVolume: Float = 1.0
    private var isMuted = false
    private var storedPlaybackPosition: TimeInterval = 0

    private let logger = AppLogger(category: "AudioEngine")
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 31)
    private let analyzer = SpectrumAnalyzer()
    private let compressor: AVAudioUnitEffect
    private let limiter: AVAudioUnitEffect
    private var insertedAU: AVAudioUnit?
    
    private var audioFile: AVAudioFile?
    private var currentFileURL: URL?
    private var isGraphConnected = false
    private var isTapInstalled = false
    private var lastProcessingFormat: AVAudioFormat?
    private var playbackGeneration: UInt64 = 0
    private var dynamics = DynamicsSettings.default
    private var stereoBalance: Float = 0
    private var analysisFramesSinceLast = 0

    init() {
        let compressorDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        compressor = AVAudioUnitEffect(audioComponentDescription: compressorDesc)

        let limiterDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        limiter = AVAudioUnitEffect(audioComponentDescription: limiterDesc)
        configureEQ()
        configureCompressor()
        configureLimiter()
        applyDynamics(dynamics)
        applyBalance(0)
    }
    
    deinit {
        teardown()
    }

    var currentGraphicBandCount: GraphicBandCount = .ten

    var playbackDuration: TimeInterval {
        guard let audioFile, audioFile.processingFormat.sampleRate > 0 else { return 0 }
        return Double(audioFile.length) / audioFile.processingFormat.sampleRate
    }

    var playbackPosition: TimeInterval {
        guard playbackState == .playing,
              let renderTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: renderTime),
              playerTime.sampleRate > 0 else {
            return storedPlaybackPosition
        }

        let position = max(0, Double(playerTime.sampleTime) / playerTime.sampleRate)
        return min(playbackDuration, position)
    }

    private func configureEQ() {
        let defaultBands = EQBand.defaultBands(count: .thirtyOne)
        for index in 0..<eq.bands.count {
            let audioBand = eq.bands[index]
            if index < defaultBands.count {
                audioBand.frequency = defaultBands[index].frequency
            }
            audioBand.filterType = .parametric
            audioBand.bandwidth = EQBand.defaultQ
            audioBand.gain = EQBand.neutralGain
            audioBand.bypass = false
        }
    }

    private func configureLimiter() {
        PeakLimiterConfigurator.applyDefaults(to: limiter)
    }

    private func configureCompressor() {
        // Defaults applied via applyDynamics; ensure unit is not bypassed by accident.
        compressor.bypass = true
    }

    private func attachNodesIfNeeded() {
        if player.engine == nil {
            engine.attach(player)
        }

        if eq.engine == nil {
            engine.attach(eq)
        }

        if compressor.engine == nil {
            engine.attach(compressor)
        }

        if let insertedAU, insertedAU.engine == nil {
            engine.attach(insertedAU)
        }

        if limiter.engine == nil {
            engine.attach(limiter)
        }
    }

    private func connectGraph(format: AVAudioFormat) throws {
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw AudioEngineError.audioGraphConnectionFailed("Invalid file format.")
        }

        attachNodesIfNeeded()

        if isGraphConnected {
            engine.disconnectNodeOutput(player)
            engine.disconnectNodeOutput(eq)
            engine.disconnectNodeOutput(compressor)
            if let insertedAU {
                engine.disconnectNodeOutput(insertedAU)
            }
            engine.disconnectNodeOutput(limiter)
            isGraphConnected = false
        }

        // player → EQ → compressor → [optional AU] → peak limiter → mixer
        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: compressor, format: format)
        if let insertedAU {
            engine.connect(compressor, to: insertedAU, format: format)
            engine.connect(insertedAU, to: limiter, format: format)
        } else {
            engine.connect(compressor, to: limiter, format: format)
        }
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
        isGraphConnected = true
        applyBalance(stereoBalance)
    }

    private func startEngineIfNeeded() throws {
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                throw AudioEngineError.engineFailedToStart(error.localizedDescription)
            }
        }
    }

    func prepare(url: URL) throws {
        logger.info("Preparing audio file: \(url.lastPathComponent)")
        playbackState = .preparing

        stop(clearFile: true)
        playbackState = .preparing

        guard url.isFileURL else {
            let error = AudioEngineError.unsupportedFile(url)
            fail(error)
            throw error
        }

        guard FileManager.default.isReadableFile(atPath: url.path) else {
            let error = AudioEngineError.fileCouldNotBeRead(url)
            fail(error)
            throw error
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            let engineError = AudioEngineError.unsupportedFile(url)
            fail(engineError)
            throw engineError
        }

        let newFormat = file.processingFormat
        let isFormatChange = lastProcessingFormat.map {
            $0.sampleRate != newFormat.sampleRate || $0.channelCount != newFormat.channelCount
        } ?? false

        if isFormatChange {
            logger.info(
                "Format change: \(lastProcessingFormat!.sampleRate)/\(lastProcessingFormat!.channelCount)ch -> \(newFormat.sampleRate)/\(newFormat.channelCount)ch"
            )
            removeTap()
            player.stop()
            engine.stop()
            engine.reset()
            isGraphConnected = false
        }

        do {
            try connectGraph(format: newFormat)
        } catch {
            fail(error)
            throw error
        }

        // Always ensure the engine is running after a successful prepare so
        // play()/seek() never race a half-rebuilt graph after sample-rate switches.
        do {
            try startEngineIfNeeded()
        } catch {
            logger.error("Engine start after prepare failed: \(error.localizedDescription)")
            fail(error)
            throw error
        }

        lastProcessingFormat = newFormat
        audioFile = file
        currentFileURL = url
        storedPlaybackPosition = 0
        scheduleCurrentFile()
        playbackState = .ready
        logger.info("Audio file ready: \(url.lastPathComponent)")
    }

    func loadFile(url: URL) throws {
        try prepare(url: url)
    }

    func play() {
        guard audioFile != nil else {
            fail(AudioEngineError.playbackFailed("No audio file loaded."))
            return
        }

        guard isGraphConnected else {
            fail(AudioEngineError.audioGraphConnectionFailed("Audio graph is not connected."))
            return
        }
        
        do {
            try startEngineIfNeeded()
            player.play()
            playbackState = .playing
            installTap()
            logger.info("Playback started")
        } catch {
            fail(error)
        }
    }

    func pause() {
        guard playbackState == .playing else { return }
        storedPlaybackPosition = playbackPosition
        player.pause()
        playbackState = .paused
        removeTap()
        logger.info("Playback paused")
    }

    func stop() {
        stop(clearFile: false)
    }

    private func stop(clearFile: Bool) {
        playbackGeneration &+= 1
        storedPlaybackPosition = 0
        removeTap()
        player.stop()
        engine.pause()
        
        if clearFile {
            audioFile = nil
            currentFileURL = nil
            playbackState = .idle
        } else if audioFile != nil {
            scheduleCurrentFile()
            playbackState = .stopped
        } else {
            playbackState = .idle
        }
        
        resetAnalysisState()
        logger.info("Playback stopped")
    }

    private func scheduleCurrentFile() {
        guard let audioFile else { return }
        let generation = playbackGeneration
        player.scheduleFile(audioFile, at: nil) { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.finishPlayback(generation: generation)
            }
        }
    }

    private func finishPlayback(generation: UInt64) {
        guard generation == playbackGeneration,
              playbackState == .playing else {
            return
        }

        removeTap()
        player.stop()
        engine.pause()
        playbackState = .stopped
        storedPlaybackPosition = playbackDuration
        resetAnalysisState()
        scheduleCurrentFile()
        logger.info("Playback finished")
    }

    func restart() {
        guard audioFile != nil else {
            fail(AudioEngineError.playbackFailed("No audio file loaded."))
            return
        }

        stop(clearFile: false)
        play()
    }

    func seekToStart() {
        restart()
    }

    func seek(to time: TimeInterval) {
        guard let audioFile,
              audioFile.processingFormat.sampleRate > 0 else {
            return
        }

        let duration = playbackDuration
        let clampedTime = max(0, min(duration, time))
        let startFrame = min(
            AVAudioFramePosition(clampedTime * audioFile.processingFormat.sampleRate),
            audioFile.length
        )
        let remainingFrames = AVAudioFrameCount(max(0, audioFile.length - startFrame))
        let wasPlaying = playbackState == .playing

        playbackGeneration &+= 1
        removeTap()
        player.stop()
        engine.pause()
        storedPlaybackPosition = clampedTime

        guard remainingFrames > 0 else {
            playbackState = .stopped
            storedPlaybackPosition = duration
            resetAnalysisState()
            return
        }

        let generation = playbackGeneration
        player.scheduleSegment(
            audioFile,
            startingFrame: startFrame,
            frameCount: remainingFrames,
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.finishPlayback(generation: generation)
            }
        }

        if wasPlaying {
            do {
                try startEngineIfNeeded()
                player.play()
                playbackState = .playing
                installTap()
            } catch {
                fail(error)
            }
        } else {
            playbackState = .paused
        }
    }

    func teardown() {
        logger.info("Tearing down audio engine")
        removeTap()
        player.stop()
        engine.stop()
        engine.reset()

        if isGraphConnected {
            engine.disconnectNodeOutput(player)
            engine.disconnectNodeOutput(eq)
            engine.disconnectNodeOutput(compressor)
            if let insertedAU {
                engine.disconnectNodeOutput(insertedAU)
            }
            engine.disconnectNodeOutput(limiter)
            isGraphConnected = false
        }

        if let insertedAU, insertedAU.engine != nil {
            engine.detach(insertedAU)
        }
        insertedAU = nil

        if player.engine != nil {
            engine.detach(player)
        }

        if eq.engine != nil {
            engine.detach(eq)
        }

        if compressor.engine != nil {
            engine.detach(compressor)
        }

        if limiter.engine != nil {
            engine.detach(limiter)
        }

        audioFile = nil
        currentFileURL = nil
        playbackState = .idle
        resetAnalysisState(dispatchToMain: false)
    }

    func setBandGain(index: Int, gain: Float) {
        guard index >= 0 && index < eq.bands.count else { return }
        let clampedGain = max(EQBand.gainRange.lowerBound, min(EQBand.gainRange.upperBound, gain))
        eq.bands[index].gain = clampedGain
    }

    func setBandEnabled(index: Int, isEnabled: Bool) {
        guard index >= 0 && index < eq.bands.count else { return }
        eq.bands[index].bypass = !isEnabled
    }

    func applyMode(_ mode: EQMode, bands: [EQBand]) {
        currentPreset = EQPreset(
            id: currentPreset.id,
            name: currentPreset.name,
            mode: mode,
            bands: bands,
            preamp: currentPreset.preamp,
            createdAt: currentPreset.createdAt,
            updatedAt: Date()
        )

        let activeBandCount = min(bands.count, eq.bands.count)

        for index in 0..<eq.bands.count {
            let audioBand = eq.bands[index]

            guard index < activeBandCount else {
                audioBand.bypass = true
                audioBand.gain = EQBand.neutralGain
                continue
            }

            let modelBand = bands[index]
            audioBand.frequency = modelBand.frequency
            audioBand.gain = modelBand.gain
            audioBand.bandwidth = modelBand.q
            audioBand.filterType = modelBand.audioUnitFilterType(for: mode)
            audioBand.bypass = !modelBand.isEnabled
        }
    }

    func setBypass(_ bypass: Bool) {
        // Keep the peak limiter engaged even when EQ is bypassed so volume
        // boost and preamp cannot hard-clip the output path.
        // Compressor enable is independent of EQ A/B bypass.
        eq.bypass = bypass
        compressor.bypass = !dynamics.isCompressorEnabled
        limiter.bypass = false
    }

    func applyDynamics(_ settings: DynamicsSettings) {
        var clamped = settings
        clamped.clamp()
        dynamics = clamped
        compressor.bypass = !clamped.isCompressorEnabled

        guard let tree = compressor.auAudioUnit.parameterTree else { return }
        for param in tree.allParameters {
            switch param.identifier {
            case "threshold", "Threshold":
                param.value = clamped.threshold
            case "headRoom", "HeadRoom":
                // Leave a little headroom relative to threshold.
                param.value = max(0.1, min(40, abs(clamped.threshold) * 0.35 + 3))
            case "expansionRatio", "ExpansionRatio":
                // Use expansion ratio slot as compression ratio on Apple's unit mapping.
                param.value = clamped.ratio
            case "attackTime", "AttackTime":
                param.value = clamped.attack
            case "releaseTime", "ReleaseTime":
                param.value = clamped.release
            case "masterGain", "MasterGain":
                param.value = clamped.makeupGain
            default:
                break
            }
        }

        applyBalance(clamped.balance)
    }

    func applyBalance(_ balance: Float) {
        stereoBalance = min(max(balance, -1), 1)
        engine.mainMixerNode.pan = stereoBalance
    }

    /// Inserts an already-instantiated AU effect into the local graph (after compressor).
    func insertAudioUnit(_ unit: AVAudioUnit) throws {
        if let existing = insertedAU, existing.engine != nil {
            engine.disconnectNodeOutput(existing)
            engine.detach(existing)
        }
        insertedAU = unit
        if let format = lastProcessingFormat {
            try connectGraph(format: format)
            try startEngineIfNeeded()
        } else {
            attachNodesIfNeeded()
        }
        logger.info("Inserted AU unit into local graph")
    }

    func removeInsertedAudioUnit() {
        guard let existing = insertedAU else { return }
        if isGraphConnected {
            engine.disconnectNodeOutput(existing)
        }
        if existing.engine != nil {
            engine.detach(existing)
        }
        insertedAU = nil
        if let format = lastProcessingFormat {
            try? connectGraph(format: format)
            try? startEngineIfNeeded()
        }
        logger.info("Removed AU unit from local graph")
    }

    func setVolumeBoost(_ multiplier: Double) {
        volumeBoostMultiplier = Float(multiplier)
        applyVolume()
    }

    func setVolume(_ volume: Double) {
        outputVolume = Float(max(0, min(2, volume)))
        applyVolume()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        applyVolume()
    }

    func setPreampGain(_ gain: Float) {
        let clampedGain = max(EQBand.gainRange.lowerBound, min(EQBand.gainRange.upperBound, gain))
        currentPreampGain = clampedGain
        applyVolume()
        currentPreset.preamp = clampedGain
    }

    private func applyVolume() {
        let preampVolume = pow(10.0, currentPreampGain / 20.0)
        player.volume = isMuted ? 0 : outputVolume * preampVolume * volumeBoostMultiplier
    }

    func applyPreset(_ preset: EQPreset) {
        currentPreset = preset
        setPreampGain(preset.preamp)
        applyMode(preset.mode, bands: preset.bands)
    }

    func updateBand(_ band: EQBand) {
        guard let index = currentPreset.bands.firstIndex(where: { $0.id == band.id }) else {
            return
        }

        currentPreset.bands[index] = band
        applyMode(currentPreset.mode, bands: currentPreset.bands)
    }

    // MARK: - Tap Installer and Callback
    
    private func installTap() {
        guard !isTapInstalled else { return }
        
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        
        // The mixer tap feeds post-EQ PCM into SpectrumAnalyzer; UI state is updated on main.
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }

            self.analysisFramesSinceLast += Int(buffer.frameLength)
            guard self.analysisFramesSinceLast >= max(1024, Int(format.sampleRate / 20)) else {
                return
            }
            self.analysisFramesSinceLast = 0

            guard let analysis = self.analyzer.analyze(buffer: buffer) else {
                return
            }

            DispatchQueue.main.async {
                self.spectrumLevels = Array(analysis.levels)
                self.leftLevel = analysis.leftPeak
                self.rightLevel = analysis.rightPeak
                self.peakLevel = analysis.peakLevel
                self.isClipping = analysis.isClipping
            }
        }

        isTapInstalled = true
    }
    
    private func removeTap() {
        guard isTapInstalled else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        isTapInstalled = false
    }

    private func fail(_ error: Error) {
        let message = error.localizedDescription
        logger.error(message)
        playbackState = .failed(message)
        removeTap()
    }

    private func resetAnalysisState(dispatchToMain: Bool = true) {
        analysisFramesSinceLast = 0
        let analysis = analyzer.reset()

        let update = {
            self.spectrumLevels = Array(analysis.levels)
            self.leftLevel = analysis.leftPeak
            self.rightLevel = analysis.rightPeak
            self.peakLevel = analysis.peakLevel
            self.isClipping = analysis.isClipping
        }

        if dispatchToMain {
            DispatchQueue.main.async(execute: update)
        } else {
            update()
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
