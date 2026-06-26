//
//  AudioEngineController.swift
//  OpenEQ
//
//  Created by Gökmen on 26.06.2026.
//

import Foundation
import AVFoundation
import Observation

@Observable
final class AudioEngineController {
    private(set) var playbackState: PlaybackState = .stopped
    private(set) var currentPreset: EQPreset = .flatPreset()
    private(set) var spectrumLevels: [Double] = Array(repeating: 0.02, count: 64)

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 10)
    private let analyzer = SpectrumAnalyzer()
    
    private var audioFile: AVAudioFile?

    init() {
        setupAudioGraph()
    }
    
    private func setupAudioGraph() {
        engine.attach(player)
        engine.attach(eq)
        
        let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        for (i, freq) in frequencies.enumerated() {
            let band = eq.bands[i]
            band.frequency = freq
            band.filterType = .parametric
            band.bandwidth = 1.0
            band.gain = 0.0
            band.bypass = false
        }
        
        // Initial connection using standard format
        let format = engine.mainMixerNode.inputFormat(forBus: 0)
        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
    }

    func startEngineIfNeeded() throws {
        if !engine.isRunning {
            try engine.start()
        }
    }

    func loadFile(url: URL) throws {
        // Prevent tapping conflicts by stopping and resetting prior taps
        removeTap()
        player.stop()
        
        let file = try AVAudioFile(forReading: url)
        self.audioFile = file
        
        // Reconnect node graph using loaded file format to match channels and sample rate
        let format = file.processingFormat
        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        
        try startEngineIfNeeded()
        
        // Schedule audio file for playback
        player.scheduleFile(file, at: nil, completionHandler: nil)
        playbackState = .stopped
    }

    func play() {
        guard audioFile != nil else {
            playbackState = .failed(message: "No audio file loaded")
            return
        }
        
        do {
            try startEngineIfNeeded()
            player.play()
            playbackState = .playing
            
            // Hook up real-time audio sample capture
            installTap()
        } catch {
            playbackState = .failed(message: error.localizedDescription)
        }
    }

    func pause() {
        player.pause()
        playbackState = .paused
        removeTap()
    }

    func stop() {
        removeTap()
        player.stop()
        playbackState = .stopped
        
        // Re-schedule file so play starts from beginning
        if let file = audioFile {
            player.scheduleFile(file, at: nil, completionHandler: nil)
        }
        
        DispatchQueue.main.async {
            self.spectrumLevels = Array(repeating: 0.02, count: 64)
        }
    }

    func seekToStart() {
        let wasPlaying = player.isPlaying
        
        removeTap()
        player.stop()
        
        if let file = audioFile {
            player.scheduleFile(file, at: nil, completionHandler: nil)
        }
        
        if wasPlaying {
            player.play()
            installTap()
        }
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

    func setPreampGain(_ gain: Float) {
        let clampedGain = max(EQBand.gainRange.lowerBound, min(EQBand.gainRange.upperBound, gain))
        let volumeMultiplier = pow(10.0, clampedGain / 20.0)
        player.volume = volumeMultiplier
    }

    func applyPreset(_ preset: EQPreset) {
        currentPreset = preset
        setPreampGain(preset.preamp)
        for (i, band) in preset.bands.enumerated() {
            setBandGain(index: i, gain: band.gain)
            setBandEnabled(index: i, isEnabled: band.isEnabled)
        }
    }

    func updateBand(_ band: EQBand) {
        guard let index = currentPreset.bands.firstIndex(where: { $0.id == band.id }) else {
            return
        }

        currentPreset.bands[index] = band
        setBandGain(index: index, gain: band.gain)
        setBandEnabled(index: index, isEnabled: band.isEnabled)
    }

    // MARK: - Tap Installer and Callback
    
    private func installTap() {
        engine.mainMixerNode.removeTap(onBus: 0)
        
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        
        // Tap format should match the output bus format. Frame size 1024.
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            // Process the buffer through our Accelerate DFT analyzer
            let normalizedLevels = self.analyzer.analyze(buffer: buffer)
            
            let doubleLevels = normalizedLevels.map { Double($0) }
            
            if !doubleLevels.isEmpty {
                DispatchQueue.main.async {
                    self.spectrumLevels = doubleLevels
                }
            }
        }
    }
    
    private func removeTap() {
        engine.mainMixerNode.removeTap(onBus: 0)
    }
}
