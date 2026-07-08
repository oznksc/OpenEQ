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

    private let logger = AppLogger(category: "AudioEngine")
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 31)
    private let analyzer = SpectrumAnalyzer()
    
    private var audioFile: AVAudioFile?
    private var currentFileURL: URL?
    private var isGraphConnected = false
    private var isTapInstalled = false
    private var lastProcessingFormat: AVAudioFormat?

    init() {
        configureEQ()
    }
    
    deinit {
        teardown()
    }

    var currentGraphicBandCount: GraphicBandCount = .ten

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

    private func attachNodesIfNeeded() {
        if player.engine == nil {
            engine.attach(player)
        }

        if eq.engine == nil {
            engine.attach(eq)
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
            isGraphConnected = false
        }

        // Signal chain: playerNode -> eqNode -> mainMixerNode.
        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        isGraphConnected = true
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
            logger.info("Format change: \(lastProcessingFormat!.sampleRate)ch/\(lastProcessingFormat!.channelCount) -> \(newFormat.sampleRate)ch/\(newFormat.channelCount)")
            engine.stop()
            engine.reset()
        }

        do {
            try connectGraph(format: newFormat)
        } catch {
            fail(error)
            throw error
        }

        if isFormatChange {
            do {
                try engine.start()
            } catch {
                logger.error("Engine restart after format change failed: \(error.localizedDescription)")
            }
        }

        lastProcessingFormat = newFormat
        audioFile = file
        currentFileURL = url
        player.scheduleFile(file, at: nil, completionHandler: nil)
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
        player.pause()
        playbackState = .paused
        removeTap()
        logger.info("Playback paused")
    }

    func stop() {
        stop(clearFile: false)
    }

    private func stop(clearFile: Bool) {
        removeTap()
        player.stop()
        engine.pause()
        
        if clearFile {
            audioFile = nil
            currentFileURL = nil
            playbackState = .idle
        } else if let file = audioFile {
            player.scheduleFile(file, at: nil, completionHandler: nil)
            playbackState = .stopped
        } else {
            playbackState = .idle
        }
        
        resetAnalysisState()
        logger.info("Playback stopped")
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

    func teardown() {
        logger.info("Tearing down audio engine")
        removeTap()
        player.stop()
        engine.stop()
        engine.reset()

        if isGraphConnected {
            engine.disconnectNodeOutput(player)
            engine.disconnectNodeOutput(eq)
            isGraphConnected = false
        }

        if player.engine != nil {
            engine.detach(player)
        }

        if eq.engine != nil {
            engine.detach(eq)
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
        eq.bypass = bypass
    }

    func setVolumeBoost(_ multiplier: Double) {
        volumeBoostMultiplier = Float(multiplier)
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
        player.volume = preampVolume * volumeBoostMultiplier
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

            guard let analysis = self.analyzer.analyze(buffer: buffer) else {
                return
            }

            DispatchQueue.main.async {
                self.spectrumLevels = analysis.levels
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
        let analysis = analyzer.reset()

        let update = {
            self.spectrumLevels = analysis.levels
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
