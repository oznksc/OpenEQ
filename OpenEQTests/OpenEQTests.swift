import XCTest
import AVFoundation
@testable import OpenEQ

@MainActor
final class OpenEQTests: XCTestCase {
    func testAppPresentationModesExposeExpectedSurfaces() {
        XCTAssertTrue(AppPresentationMode.dock.showsDockIcon)
        XCTAssertFalse(AppPresentationMode.dock.showsMenuBarExtra)
        XCTAssertFalse(AppPresentationMode.menuBar.showsDockIcon)
        XCTAssertTrue(AppPresentationMode.menuBar.showsMenuBarExtra)
        XCTAssertTrue(AppPresentationMode.both.showsDockIcon)
        XCTAssertTrue(AppPresentationMode.both.showsMenuBarExtra)
    }

    // MARK: - EQBand

    func testEQBandClampsInitialParameters() {
        let band = EQBand(frequency: 1, gain: 30, q: 20)

        XCTAssertEqual(band.frequency, EQBand.frequencyRange.lowerBound)
        XCTAssertEqual(band.gain, EQBand.gainRange.upperBound)
        XCTAssertEqual(band.q, EQBand.qRange.upperBound)
    }

    func testEQBandClampsUpdatedParameters() {
        var band = EQBand(frequency: 1000)

        band.frequency = 100_000
        band.gain = -100
        band.q = 0

        XCTAssertEqual(band.frequency, EQBand.frequencyRange.upperBound)
        XCTAssertEqual(band.gain, EQBand.gainRange.lowerBound)
        XCTAssertEqual(band.q, EQBand.qRange.lowerBound)
    }

    func testEQBandClampsBoundaryValues() {
        var band = EQBand(frequency: 1000)

        band.frequency = 20
        band.gain = -24
        band.q = 0.1
        XCTAssertEqual(band.frequency, 20)
        XCTAssertEqual(band.gain, -24)
        XCTAssertEqual(band.q, 0.1, accuracy: 0.001)

        band.frequency = 20000
        band.gain = 24
        band.q = 10
        XCTAssertEqual(band.frequency, 20000)
        XCTAssertEqual(band.gain, 24)
        XCTAssertEqual(band.q, 10, accuracy: 0.001)
    }

    func testEQBandFrequencyLabel() {
        XCTAssertEqual(EQBand(frequency: 32).label, "32")
        XCTAssertEqual(EQBand(frequency: 1000).label, "1k")
        XCTAssertEqual(EQBand(frequency: 16000).label, "16k")
        XCTAssertEqual(EQBand(frequency: 63).label, "63")
        XCTAssertEqual(EQBand(frequency: 20000).label, "20k")
    }

    func testEQBandDefaultBandsCount() {
        XCTAssertEqual(EQBand.defaultBands(count: .ten).count, 10)
        XCTAssertEqual(EQBand.defaultBands(count: .thirtyOne).count, 31)
    }

    func testEQBandDefaultParametricBands() {
        let bands = EQBand.defaultParametricBands()
        XCTAssertEqual(bands.count, 5)
        XCTAssertEqual(bands[0].filterType, .lowShelf)
        XCTAssertEqual(bands[4].filterType, .highShelf)
        XCTAssertEqual(bands[1].filterType, .parametric)
    }

    func testEQBandDefaultFrequenciesAreISOCorrect() {
        let tenBand = EQBand.tenBandFrequencies
        XCTAssertEqual(tenBand, [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000])

        let thirtyOneBand = EQBand.thirtyOneBandFrequencies
        XCTAssertEqual(thirtyOneBand.count, 31)
        XCTAssertEqual(thirtyOneBand.first, 20)
        XCTAssertEqual(thirtyOneBand.last, 20000)
    }

    func testListeningComfortEngineStartsIdle() {
        let engine = ListeningComfortEngine()

        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.state.score, 100)
        XCTAssertEqual(engine.state.status, .comfortable)
    }

    func testListeningComfortEngineRespondsToSustainedLoudHarshAudio() {
        let engine = ListeningComfortEngine()
        let harshSpectrum = Array(repeating: Float(0.95), count: SpectrumAnalyzer.barCount)

        for _ in 0..<4_000 {
            _ = engine.update(
                peakLevel: 0.95,
                spectrumLevels: harshSpectrum,
                isActive: true,
                elapsed: 1
            )
        }

        XCTAssertLessThan(engine.state.score, 72)
        XCTAssertGreaterThan(engine.state.exposurePercent, 0.45)
        XCTAssertEqual(engine.state.status, .takeBreak)
        XCTAssertGreaterThan(engine.state.suggestedReliefDB, 0.2)
    }

    func testListeningComfortEngineRecoversWhileInactive() {
        let engine = ListeningComfortEngine()
        let spectrum = Array(repeating: Float(0.8), count: SpectrumAnalyzer.barCount)

        _ = engine.update(peakLevel: 0.9, spectrumLevels: spectrum, isActive: true, elapsed: 5)
        let activePressure = engine.state.loudnessPressure
        _ = engine.update(peakLevel: 0, spectrumLevels: [], isActive: false, elapsed: 5)

        XCTAssertGreaterThan(activePressure, 0.9)
        XCTAssertLessThan(engine.state.score, 100)
        XCTAssertEqual(engine.state.isActive, false)
    }

    func testEQBandDefaultBandsForMode() {
        let graphic = EQBand.defaultBands(for: .graphic, graphicBandCount: .ten)
        XCTAssertEqual(graphic.count, 10)
        XCTAssertTrue(graphic.allSatisfy { $0.filterType == .parametric })

        let parametric = EQBand.defaultBands(for: .parametric)
        XCTAssertEqual(parametric.count, 5)
    }

    // MARK: - EQPreset

    func testDefaultPresetsHaveExpectedShape() throws {
        let presets = EQPreset.defaultPresets()
        let bassBoost = try XCTUnwrap(presets.first { $0.name == "Bass Boost" })

        XCTAssertEqual(presets.count, 5)
        XCTAssertEqual(bassBoost.bands.count, GraphicBandCount.ten.bandCount)
        XCTAssertEqual(bassBoost.bands[0].gain, 6.0)
        XCTAssertEqual(bassBoost.bands[1].gain, 5.5)
    }

    func testFlatPresetIsNeutral() {
        let flat = EQPreset.flatPreset()
        XCTAssertEqual(flat.name, "Flat")
        XCTAssertEqual(flat.mode, .graphic)
        XCTAssertEqual(flat.preamp, 0)
        XCTAssertTrue(flat.bands.allSatisfy { $0.gain == 0 })
        XCTAssertTrue(flat.bands.allSatisfy { $0.isEnabled })
    }

    func testAllDefaultPresetsHaveValidGains() {
        for preset in EQPreset.defaultPresets() {
            for band in preset.bands {
                XCTAssertTrue(
                    band.gain >= EQBand.gainRange.lowerBound && band.gain <= EQBand.gainRange.upperBound,
                    "\(preset.name) band at \(band.frequency)Hz has out-of-range gain \(band.gain)"
                )
            }
        }
    }

    func testPresetJSONRoundTrip() throws {
        let original = EQPreset(name: "Test", bands: EQBand.defaultBands(count: .thirtyOne), preamp: -3.0)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EQPreset.self, from: data)

        XCTAssertEqual(original.name, decoded.name)
        XCTAssertEqual(original.mode, decoded.mode)
        XCTAssertEqual(original.preamp, decoded.preamp, accuracy: 0.001)
        XCTAssertEqual(original.bands.count, decoded.bands.count)
        for (originalBand, decodedBand) in zip(original.bands, decoded.bands) {
            XCTAssertEqual(originalBand.frequency, decodedBand.frequency)
            XCTAssertEqual(originalBand.gain, decodedBand.gain)
            XCTAssertEqual(originalBand.q, decodedBand.q, accuracy: 0.001)
            XCTAssertEqual(originalBand.filterType, decodedBand.filterType)
            XCTAssertEqual(originalBand.isEnabled, decodedBand.isEnabled)
        }
    }

    func testPresetJSONRoundTripBackwardCompatible() throws {
        let json = """
        {
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "name": "Legacy",
            "bands": [{"id": "A0A0A0A0-B0B0-4040-A0A0-B0B0C0C0D0D0", "frequency": 1000, "gain": 3.0}],
            "preamp": 0.0,
            "createdAt": 725328000,
            "updatedAt": 725328000
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoder = JSONDecoder()
        let preset = try decoder.decode(EQPreset.self, from: data)

        XCTAssertEqual(preset.name, "Legacy")
        XCTAssertEqual(preset.mode, .graphic)
        XCTAssertEqual(preset.preamp, 0)
        XCTAssertEqual(preset.bands.count, 1)
        XCTAssertEqual(preset.bands[0].q, EQBand.defaultQ, accuracy: 0.001)
        XCTAssertEqual(preset.bands[0].filterType, .parametric)
        XCTAssertTrue(preset.bands[0].isEnabled)
    }

    func testPresetJSONRoundTripWithMode() throws {
        let json = """
        {
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "name": "Parametric Test",
            "mode": "parametric",
            "bands": [{"id": "A0A0A0A0-B0B0-4040-A0A0-B0B0C0C0D0D0", "frequency": 80, "gain": 2.0, "q": 0.7, "filterType": "lowShelf", "isEnabled": true}],
            "preamp": -1.5,
            "createdAt": 725328000,
            "updatedAt": 725328000
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoder = JSONDecoder()
        let preset = try decoder.decode(EQPreset.self, from: data)

        XCTAssertEqual(preset.mode, .parametric)
        XCTAssertEqual(preset.preamp, -1.5, accuracy: 0.001)
        XCTAssertEqual(preset.bands[0].filterType, .lowShelf)
        XCTAssertEqual(preset.bands[0].q, 0.7, accuracy: 0.001)
    }

    // MARK: - SpectrumAnalyzer

    func testSpectrumAnalyzerResetClearsAllLevels() {
        let analysis = SpectrumAnalyzer().reset()

        XCTAssertEqual(analysis.levels.count, SpectrumAnalyzer.barCount)
        XCTAssertTrue(analysis.levels.allSatisfy { $0 == 0 })
        XCTAssertEqual(analysis.leftPeak, 0)
        XCTAssertEqual(analysis.rightPeak, 0)
        XCTAssertEqual(analysis.peakLevel, 0)
        XCTAssertFalse(analysis.isClipping)
    }

    func testSpectrumLevelsHaveFixedWidthValueSemantics() {
        var levels = SpectrumLevels(repeating: 0.25)

        XCTAssertEqual(levels.count, SpectrumAnalyzer.barCount)
        XCTAssertTrue(levels.allSatisfy { $0 == 0.25 })

        levels[3] = 0.9

        XCTAssertEqual(levels[3], 0.9, accuracy: 0.001)
        XCTAssertEqual(levels[2], 0.25, accuracy: 0.001)
    }

    func testSpectrumAnalyzerProcessesSineWave() {
        let analyzer = SpectrumAnalyzer()
        let sampleRate: Double = 44100
        let frequency: Float = 440
        let frameLength = 1024

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameLength)) else {
            XCTFail("Failed to create buffer")
            return
        }
        buffer.frameLength = AVAudioFrameCount(frameLength)

        guard let floatDataLeft = buffer.floatChannelData?[0],
              let floatDataRight = buffer.floatChannelData?[1] else {
            XCTFail("No channel data")
            return
        }

        for i in 0..<frameLength {
            let sample = sin(2 * Float.pi * frequency * Float(i) / Float(sampleRate))
            floatDataLeft[i] = sample
            floatDataRight[i] = sample
        }

        let analysis = analyzer.analyze(buffer: buffer)
        XCTAssertNotNil(analysis)
        XCTAssertEqual(analysis?.levels.count, SpectrumAnalyzer.barCount)
        XCTAssertGreaterThan(analysis?.leftPeak ?? 0, 0)
        XCTAssertGreaterThan(analysis?.rightPeak ?? 0, 0)
    }

    // MARK: - AudioEngineController

    func testAudioEngineRejectsNonFileURLWithoutCrashing() throws {
        let controller = AudioEngineController()
        let url = try XCTUnwrap(URL(string: "https://example.com/audio.mp3"))

        XCTAssertThrowsError(try controller.prepare(url: url))
        if case .failed = controller.playbackState {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected the controller to enter a failed state")
        }
    }

    func testAudioEnginePlayWithoutFileEntersFailedState() {
        let controller = AudioEngineController()

        controller.play()

        if case .failed = controller.playbackState {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected playback without a file to fail")
        }
    }

    func testAudioEnginePreparesAiffFile() throws {
        let controller = AudioEngineController()
        let url = URL(fileURLWithPath: "/System/Library/Sounds/Ping.aiff")

        try controller.prepare(url: url)

        XCTAssertEqual(controller.playbackState, .ready)
        XCTAssertGreaterThan(controller.playbackDuration, 0)
    }

    func testAudioEngineStartsAndStopsAiffPlayback() throws {
        let controller = AudioEngineController()
        let url = URL(fileURLWithPath: "/System/Library/Sounds/Ping.aiff")

        try controller.prepare(url: url)
        controller.play()

        if case .failed(let message) = controller.playbackState {
            XCTFail("Playback failed: \(message)")
        } else {
            XCTAssertEqual(controller.playbackState, .playing)
        }

        controller.stop()
        XCTAssertEqual(controller.playbackState, .stopped)
    }

    func testAudioEngineStopsWhenAiffPlaybackFinishes() async throws {
        let controller = AudioEngineController()
        let url = URL(fileURLWithPath: "/System/Library/Sounds/Tink.aiff")

        try controller.prepare(url: url)
        controller.play()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertEqual(controller.playbackState, .stopped)
    }

    // MARK: - GraphicBandCount

    func testGraphicBandCountValues() {
        XCTAssertEqual(GraphicBandCount.ten.bandCount, 10)
        XCTAssertEqual(GraphicBandCount.thirtyOne.bandCount, 31)
    }

    // MARK: - EQMode

    func testEQModeIdentifiers() {
        XCTAssertEqual(EQMode.graphic.id, "graphic")
        XCTAssertEqual(EQMode.parametric.id, "parametric")
    }

    // MARK: - EQFilterType

    func testEQFilterTypeAllCases() {
        let types = EQFilterType.allCases
        XCTAssertEqual(types.count, 5)
        XCTAssertTrue(types.contains(.parametric))
        XCTAssertTrue(types.contains(.lowShelf))
        XCTAssertTrue(types.contains(.highShelf))
        XCTAssertTrue(types.contains(.lowPass))
        XCTAssertTrue(types.contains(.highPass))
    }

    func testEQFilterTypeTitles() {
        XCTAssertEqual(EQFilterType.parametric.title, "Parametric")
        XCTAssertEqual(EQFilterType.lowShelf.title, "Low Shelf")
        XCTAssertEqual(EQFilterType.highShelf.title, "High Shelf")
        XCTAssertEqual(EQFilterType.lowPass.title, "Low Pass")
        XCTAssertEqual(EQFilterType.highPass.title, "High Pass")
    }

    // MARK: - Phase 1 Stability

    func testDecibelToLinearConversion() {
        let cases: [(Float, Float)] = [
            (0.0, 1.0),
            (6.0206, 2.0),
            (-6.0206, 0.5),
            (-24.0, 0.0630957)
        ]

        for (db, expected) in cases {
            let linear = pow(10.0, db / 20.0)
            XCTAssertEqual(linear, expected, accuracy: 1e-4, "Failed for \(db) dB")
        }
    }

    func testAudioEngineBypassKeepsEnginePlayable() throws {
        let controller = AudioEngineController()
        let url = URL(fileURLWithPath: "/System/Library/Sounds/Ping.aiff")

        try controller.prepare(url: url)
        controller.setBypass(true)
        controller.play()

        if case .failed(let message) = controller.playbackState {
            XCTFail("Bypassed playback failed: \(message)")
        } else {
            XCTAssertEqual(controller.playbackState, .playing)
        }

        controller.setBypass(false)
        controller.stop()
        XCTAssertEqual(controller.playbackState, .stopped)
    }

    func testAudioEngineSurvivesSampleRateStyleReload() throws {
        let controller = AudioEngineController()
        let first = URL(fileURLWithPath: "/System/Library/Sounds/Ping.aiff")
        let second = URL(fileURLWithPath: "/System/Library/Sounds/Tink.aiff")

        try controller.prepare(url: first)
        XCTAssertEqual(controller.playbackState, .ready)

        try controller.prepare(url: second)
        XCTAssertEqual(controller.playbackState, .ready)
        XCTAssertGreaterThan(controller.playbackDuration, 0)

        controller.play()
        if case .failed(let message) = controller.playbackState {
            XCTFail("Playback after reload failed: \(message)")
        }
        controller.stop()
    }

    func testSystemAudioStatusPermissionTitle() {
        XCTAssertEqual(SystemAudioStatus.permissionRequired.title, "Permission Required")
        XCTAssertTrue(SystemAudioStatus.permissionRequired.isTerminalFailure)
        XCTAssertTrue(SystemAudioStatus.failed("x").isTerminalFailure)
        XCTAssertFalse(SystemAudioStatus.running.isTerminalFailure)
        // Failed setup messages must remain readable (not collapsed into permission only).
        if case .failed(let message) = SystemAudioStatus.failed("Create aggregate failed") {
            XCTAssertTrue(message.contains("aggregate"))
        } else {
            XCTFail("Expected failed status")
        }
    }

    func testSystemAudioModesCoverProductPaths() {
        let modes = SystemAudioMode.allCases
        XCTAssertEqual(modes.count, 3)
        XCTAssertTrue(modes.contains(.disabled))
        XCTAssertTrue(modes.contains(.systemEQ))
        XCTAssertTrue(modes.contains(.externalLoopback))
    }

    func testPeakLimiterConfiguratorDoesNotThrow() {
        let limiterDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        let limiter = AVAudioUnitEffect(audioComponentDescription: limiterDescription)
        PeakLimiterConfigurator.applyDefaults(to: limiter)
        XCTAssertFalse(limiter.bypass)
    }

    func testSystemAudioLimiterRemainsActiveWhenEQIsBypassed() {
        let dsp = SystemAudioDSPState()
        dsp.configure(.flatPreset(), sampleRate: 48_000)
        dsp.isBypassed = true

        let frameCount = 128
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        samples.initialize(repeating: 1, count: frameCount)
        defer {
            samples.deinitialize(count: frameCount)
            samples.deallocate()
        }

        dsp.process(samples, frames: frameCount, channel: 0)

        var maximum: Float = 0
        for frame in 0..<frameCount { maximum = max(maximum, abs(samples[frame])) }
        XCTAssertLessThanOrEqual(maximum, 0.98)
        XCTAssertGreaterThan(maximum, 0)
    }

    func testAudioUnitBandwidthMatchesQDefinition() {
        XCTAssertEqual(EQBand(frequency: 1000, q: 1).audioUnitBandwidth, 1.388, accuracy: 0.001)
        XCTAssertGreaterThan(EQBand(frequency: 1000, q: 0.5).audioUnitBandwidth, EQBand(frequency: 1000, q: 2).audioUnitBandwidth)
    }

    func testSystemAudioDSPFlatPresetIsTransparent() {
        let frameCount = 8192
        let input = sineWave(frequency: 997, frameCount: frameCount, amplitude: 0.25)
        let output = processSystemDSP(input, preset: .flatPreset())
        let latency = SystemAudioDSPState.limiterLatencyFrames(for: 48_000)
        let maximumError = zip(input.dropLast(latency), output.dropFirst(latency))
            .map { abs($0 - $1) }
            .max() ?? 1

        XCTAssertLessThan(maximumError, 1e-6)
    }

    func testSystemAudioLimiterLookAheadCatchesFullScaleImpulse() {
        let sampleRate = 48_000.0
        let latency = SystemAudioDSPState.limiterLatencyFrames(for: sampleRate)
        var samples = [Float](repeating: 0, count: latency * 3)
        samples[0] = 2
        let dsp = SystemAudioDSPState()
        dsp.configure(.flatPreset(), sampleRate: sampleRate)
        dsp.isBypassed = true

        samples.withUnsafeMutableBufferPointer {
            dsp.process($0.baseAddress!, frames: $0.count, channel: 0)
        }

        XCTAssertEqual(samples[latency], 0.98, accuracy: 1e-6)
        XCTAssertEqual(samples.prefix(latency).map(abs).max(), 0)
        XCTAssertLessThanOrEqual(samples.map(abs).max() ?? 2, 0.98)
    }

    func testSystemAudioLimiterLatencyIsOneMillisecondAcrossSampleRates() {
        for sampleRate in [44_100.0, 48_000.0, 96_000.0, 192_000.0] {
            let frames = SystemAudioDSPState.limiterLatencyFrames(for: sampleRate)
            XCTAssertEqual(Double(frames) / sampleRate, 0.001, accuracy: 1 / sampleRate)
        }
    }

    func testSystemAudioLimiterReleaseTimingIsSampleRateIndependent() {
        let reference = limiterReleaseProbe(sampleRate: 48_000, elapsed: 0.020)
        for sampleRate in [44_100.0, 96_000.0, 192_000.0] {
            XCTAssertEqual(
                limiterReleaseProbe(sampleRate: sampleRate, elapsed: 0.020),
                reference,
                accuracy: 0.002,
                "Limiter release changed at \(sampleRate) Hz"
            )
        }
    }

    func testSystemAudioLimiterLinksStereoGainReduction() {
        let sampleRate = 48_000.0
        let latency = SystemAudioDSPState.limiterLatencyFrames(for: sampleRate)
        var left = [Float](repeating: 0.5, count: latency * 3)
        var right = [Float](repeating: 0.5, count: latency * 3)
        left[0] = 2
        let dsp = SystemAudioDSPState()
        dsp.configure(.flatPreset(), sampleRate: sampleRate)
        dsp.isBypassed = true

        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                dsp.processStereo(
                    left: leftBuffer.baseAddress!,
                    right: rightBuffer.baseAddress!,
                    frames: leftBuffer.count
                )
            }
        }

        XCTAssertEqual(left[latency], 0.98, accuracy: 1e-6)
        XCTAssertEqual(right[latency], 0.245, accuracy: 1e-6)
        XCTAssertEqual(left[latency + 1], right[latency + 1], accuracy: 1e-6)
    }

    func testSystemAudioDSPParametricBoostMatchesRequestedGain() {
        let band = EQBand(frequency: 1000, gain: 6, q: 1, filterType: .parametric)
        let preset = EQPreset(name: "1 kHz +6 dB", mode: .parametric, bands: [band])

        XCTAssertEqual(measuredSystemDSPGain(frequency: 1000, preset: preset), 6, accuracy: 0.2)
        XCTAssertLessThan(abs(measuredSystemDSPGain(frequency: 100, preset: preset)), 0.2)
    }

    func testSystemAudioDSPMatchesAVAudioUnitEQAtBandCenter() throws {
        let band = EQBand(frequency: 1000, gain: 6, q: 1, filterType: .parametric)
        let preset = EQPreset(name: "Engine parity", mode: .parametric, bands: [band])
        let systemGain = measuredSystemDSPGain(frequency: 1000, preset: preset)
        let audioUnitGain = try measuredAudioUnitGain(frequency: 1000, band: band)

        XCTAssertEqual(systemGain, audioUnitGain, accuracy: 0.25)
    }

    func testSystemAudioDSPPreampGainIsCalibrated() {
        let preset = EQPreset(name: "+6 dB preamp", bands: [], preamp: 6)

        XCTAssertEqual(measuredSystemDSPGain(frequency: 997, preset: preset), 6, accuracy: 0.15)
    }

    func testSystemAudioDSPHighPassAttenuatesLowFrequencies() {
        let band = EQBand(frequency: 1000, q: 0.707, filterType: .highPass)
        let preset = EQPreset(name: "1 kHz high-pass", mode: .parametric, bands: [band])

        XCTAssertLessThan(measuredSystemDSPGain(frequency: 100, preset: preset), -35)
        XCTAssertGreaterThan(measuredSystemDSPGain(frequency: 5000, preset: preset), -0.1)
    }

    func testSystemAudioDSPDoesNotAddMeasurableHarmonicDistortionBelowLimiter() {
        let frequency = 1000.0
        let input = sineWave(frequency: frequency, frameCount: 48_000, amplitude: 0.05)
        let band = EQBand(frequency: Float(frequency), gain: 12, q: 1, filterType: .parametric)
        let preset = EQPreset(name: "THD probe", mode: .parametric, bands: [band])
        let output = processSystemDSP(input, preset: preset)

        XCTAssertLessThan(measuredTHDDecibels(Array(output[4800..<48_000]), frequency: frequency), -70)
    }

    func testSystemAudioDSPExtremeBoostStaysFiniteAndLimited() {
        let bands = EQBand.defaultBands(count: .thirtyOne).map {
            EQBand(frequency: $0.frequency, gain: 12, q: $0.q)
        }
        let preset = EQPreset(name: "Stress", bands: bands, preamp: 12)
        let output = processSystemDSP(sineWave(frequency: 1000, frameCount: 8192, amplitude: 0.9), preset: preset)

        XCTAssertTrue(output.allSatisfy(\.isFinite))
        XCTAssertLessThanOrEqual(output.map(abs).max() ?? 2, 1)
    }

    func testSystemAudioDSPRealtimeDeadlineMargin() {
        let bands = EQBand.defaultBands(count: .thirtyOne).enumerated().map { index, band in
            EQBand(frequency: band.frequency, gain: index.isMultiple(of: 2) ? 6 : -6, q: 1)
        }
        let dsp = SystemAudioDSPState()
        dsp.configure(EQPreset(name: "Realtime benchmark", bands: bands), sampleRate: 48_000)
        let frameCount = 256
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        samples.initialize(repeating: 0.05, count: frameCount)
        defer {
            samples.deinitialize(count: frameCount)
            samples.deallocate()
        }
        for _ in 0..<8 {
            dsp.process(samples, frames: frameCount, channel: 0)
        }

        var durations = [UInt64]()
        durations.reserveCapacity(2000)
        for _ in 0..<2000 {
            let start = DispatchTime.now().uptimeNanoseconds
            dsp.process(samples, frames: frameCount, channel: 0)
            durations.append(DispatchTime.now().uptimeNanoseconds - start)
        }
        durations.sort()
        let percentile99 = durations[Int(Double(durations.count - 1) * 0.99)]
        let callbackBudget = UInt64(Double(frameCount) / 48_000 * 1_000_000_000)

        XCTAssertLessThan(percentile99, callbackBudget / 4)
    }

    func testSystemAudioIOCallbackContainsNoForbiddenRealtimeOperations() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent("OpenEQ/AudioCore/SystemAudioEQEngine.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let callbackMethods = [
            "handleIO", "enqueueAnalysis", "isNonInterleaved", "processNonInterleaved",
            "processInterleaved", "processNonInterleavedToInterleaved",
            "processInterleavedToNonInterleaved", "applyFeedbackGuard", "silence",
            "ensureScratch", "copyInterleaved", "copyNonInterleavedToInterleaved"
        ]
        let forbiddenOperations = [
            "DispatchQueue", ".async", ".sync", "logger.", ".allocate(",
            "DispatchSemaphore", ".wait(", ".append(", "reserveCapacity"
        ]

        for method in callbackMethods {
            let body = try swiftFunctionBody(named: method, in: source)
            for operation in forbiddenOperations {
                XCTAssertFalse(body.contains(operation), "\(method) contains realtime-forbidden operation \(operation)")
            }
        }
    }

    func testSystemAudioDSPIsIndependentOfHostBufferFragmentation() {
        let input = sineWave(frequency: 997, frameCount: 16_384, amplitude: 0.08)
        let bands = [
            EQBand(frequency: 120, gain: 5, q: 0.7, filterType: .lowShelf),
            EQBand(frequency: 1000, gain: -4, q: 1.4, filterType: .parametric),
            EQBand(frequency: 8000, gain: 3, q: 0.8, filterType: .highShelf)
        ]
        let preset = EQPreset(name: "Fragmentation", mode: .parametric, bands: bands, preamp: -2)
        let contiguous = processSystemDSP(input, preset: preset, chunkPattern: [input.count])
        let fixed = processSystemDSP(input, preset: preset, chunkPattern: [256])
        let irregular = processSystemDSP(input, preset: preset, chunkPattern: [7, 127, 509, 31, 1024, 3, 211])

        XCTAssertLessThan(maximumDifference(contiguous, fixed), 1e-6)
        XCTAssertLessThan(maximumDifference(contiguous, irregular), 5e-4)
    }

    func testSystemAudioDSPStereoChannelsRemainMatchedDuringSmoothing() {
        let input = sineWave(frequency: 1000, frameCount: 8192, amplitude: 0.08)
        let band = EQBand(frequency: 1000, gain: 12, q: 2, filterType: .parametric)
        let preset = EQPreset(name: "Stereo smoothing", mode: .parametric, bands: [band], preamp: -3)
        let dsp = SystemAudioDSPState()
        dsp.configure(preset, sampleRate: 48_000)
        let frameCount = input.count
        var left = input
        var right = input
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                var offset = 0
                while offset < frameCount {
                    let frames = min(256, frameCount - offset)
                    dsp.process(leftBuffer.baseAddress! + offset, frames: frames, channel: 0)
                    dsp.process(rightBuffer.baseAddress! + offset, frames: frames, channel: 1)
                    offset += frames
                }
            }
        }

        XCTAssertLessThan(maximumDifference(left, right), 1e-6)
    }

    func testSystemAudioDSPChannelStateDoesNotLeakAcrossStereoChannels() {
        var left = [Float](repeating: 0, count: 4096)
        var right = [Float](repeating: 0, count: 4096)
        left[1024] = 0.5
        let preset = EQPreset(
            name: "State isolation",
            mode: .parametric,
            bands: [EQBand(frequency: 500, gain: 12, q: 4)]
        )
        let dsp = SystemAudioDSPState()
        dsp.configure(preset, sampleRate: 48_000)
        let frameCount = left.count
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                dsp.process(leftBuffer.baseAddress!, frames: frameCount, channel: 0)
                dsp.process(rightBuffer.baseAddress!, frames: frameCount, channel: 1)
            }
        }

        XCTAssertEqual(right.map(abs).max(), 0)
        XCTAssertGreaterThan(left.dropFirst(1025).map(abs).max() ?? 0, 0)
    }

    func testSystemAudioDSPFrequencyResponseAcrossSupportedSampleRates() {
        let band = EQBand(frequency: 1000, gain: 6, q: 1, filterType: .parametric)
        let preset = EQPreset(name: "Sample-rate matrix", mode: .parametric, bands: [band])

        for sampleRate in [44_100.0, 48_000.0, 96_000.0, 192_000.0] {
            XCTAssertEqual(
                measuredSystemDSPGain(frequency: 1000, preset: preset, sampleRate: sampleRate),
                6,
                accuracy: 0.25,
                "Unexpected response at \(sampleRate) Hz"
            )
        }
    }

    func testSystemAudioDSPSmoothingDurationIsSampleRateIndependent() {
        let preset = EQPreset(name: "Timed preamp", bands: [], preamp: 12)
        let reference = preampEnvelopeValue(after: 0.004, sampleRate: 48_000, preset: preset)

        for sampleRate in [44_100.0, 96_000.0, 192_000.0] {
            XCTAssertEqual(
                preampEnvelopeValue(after: 0.004, sampleRate: sampleRate, preset: preset),
                reference,
                accuracy: 0.01,
                "Smoothing duration changed at \(sampleRate) Hz"
            )
        }
    }

    func testSystemAudioDSPRemainsFiniteNearNyquistAtEverySampleRate() {
        let band = EQBand(frequency: 20_000, gain: 24, q: 10, filterType: .parametric)
        let preset = EQPreset(name: "Nyquist stress", mode: .parametric, bands: [band], preamp: -12)

        for sampleRate in [44_100.0, 48_000.0, 96_000.0, 192_000.0] {
            let probeFrequency = min(20_000, sampleRate * 0.48)
            let input = sineWave(
                frequency: probeFrequency,
                frameCount: Int(sampleRate / 4),
                amplitude: 0.05,
                sampleRate: sampleRate
            )
            let output = processSystemDSP(input, preset: preset, sampleRate: sampleRate)

            XCTAssertTrue(output.allSatisfy(\.isFinite), "Non-finite output at \(sampleRate) Hz")
            XCTAssertLessThanOrEqual(output.map(abs).max() ?? 2, 1)
        }
    }

    func testSystemAudioDSPHandlesRuntimeSampleRateChangeWithoutInstability() {
        let band = EQBand(frequency: 8000, gain: 18, q: 8, filterType: .parametric)
        let preset = EQPreset(name: "Rate transition", mode: .parametric, bands: [band], preamp: -6)
        let dsp = SystemAudioDSPState()
        dsp.configure(preset, sampleRate: 48_000)
        var first = sineWave(frequency: 8000, frameCount: 4096, amplitude: 0.1, sampleRate: 48_000)
        first.withUnsafeMutableBufferPointer {
            dsp.process($0.baseAddress!, frames: $0.count, channel: 0)
        }

        dsp.configure(preset, sampleRate: 96_000)
        var second = sineWave(frequency: 8000, frameCount: 8192, amplitude: 0.1, sampleRate: 96_000)
        second.withUnsafeMutableBufferPointer {
            dsp.process($0.baseAddress!, frames: $0.count, channel: 0)
        }

        XCTAssertTrue(second.allSatisfy(\.isFinite))
        XCTAssertLessThanOrEqual(second.map(abs).max() ?? 2, 1)
        XCTAssertGreaterThan(second.map(abs).max() ?? 0, 0.01)
    }

    private func sineWave(
        frequency: Double,
        frameCount: Int,
        amplitude: Float,
        sampleRate: Double = 48_000
    ) -> [Float] {
        (0..<frameCount).map {
            amplitude * sin(2 * Float.pi * Float(frequency) * Float($0) / Float(sampleRate))
        }
    }

    private func limiterReleaseProbe(sampleRate: Double, elapsed: Double) -> Float {
        let latency = SystemAudioDSPState.limiterLatencyFrames(for: sampleRate)
        let hotFrames = latency + 1
        let releaseFrames = Int((elapsed * sampleRate).rounded())
        var samples = [Float](repeating: 0.5, count: latency + hotFrames + releaseFrames + 1)
        for frame in 0..<hotFrames { samples[frame] = 2 }
        let dsp = SystemAudioDSPState()
        dsp.configure(.flatPreset(), sampleRate: sampleRate)
        dsp.isBypassed = true
        samples.withUnsafeMutableBufferPointer {
            dsp.process($0.baseAddress!, frames: $0.count, channel: 0)
        }
        return samples[latency + hotFrames + releaseFrames]
    }

    private func processSystemDSP(
        _ input: [Float],
        preset: EQPreset,
        sampleRate: Double = 48_000,
        blockSize: Int = 256
    ) -> [Float] {
        let dsp = SystemAudioDSPState()
        dsp.configure(preset, sampleRate: sampleRate)
        var output = input
        output.withUnsafeMutableBufferPointer { buffer in
            var offset = 0
            while offset < buffer.count {
                let frames = min(blockSize, buffer.count - offset)
                dsp.process(buffer.baseAddress! + offset, frames: frames, channel: 0)
                offset += frames
            }
        }
        return output
    }

    private func processSystemDSP(
        _ input: [Float],
        preset: EQPreset,
        chunkPattern: [Int],
        sampleRate: Double = 48_000
    ) -> [Float] {
        let dsp = SystemAudioDSPState()
        dsp.configure(preset, sampleRate: sampleRate)
        var output = input
        output.withUnsafeMutableBufferPointer { buffer in
            var offset = 0
            var chunkIndex = 0
            while offset < buffer.count {
                let frames = min(chunkPattern[chunkIndex % chunkPattern.count], buffer.count - offset)
                dsp.process(buffer.baseAddress! + offset, frames: frames, channel: 0)
                offset += frames
                chunkIndex += 1
            }
        }
        return output
    }

    private func maximumDifference(_ lhs: [Float], _ rhs: [Float]) -> Float {
        zip(lhs, rhs).reduce(0) { max($0, abs($1.0 - $1.1)) }
    }

    private func measuredSystemDSPGain(
        frequency: Double,
        preset: EQPreset,
        sampleRate: Double = 48_000
    ) -> Double {
        let amplitude: Float = 0.05
        let input = sineWave(
            frequency: frequency,
            frameCount: Int(sampleRate),
            amplitude: amplitude,
            sampleRate: sampleRate
        )
        let output = processSystemDSP(input, preset: preset, sampleRate: sampleRate)
        let settled = output.dropFirst(Int(sampleRate * 0.1))
        let outputRMS = sqrt(settled.reduce(0.0) { $0 + Double($1 * $1) } / Double(settled.count))
        let inputRMS = Double(amplitude) / sqrt(2)
        return 20 * log10(outputRMS / inputRMS)
    }

    private func preampEnvelopeValue(after duration: Double, sampleRate: Double, preset: EQPreset) -> Float {
        let frameCount = Int((duration * sampleRate).rounded())
        var samples = [Float](repeating: 0.05, count: frameCount)
        let dsp = SystemAudioDSPState()
        dsp.configure(preset, sampleRate: sampleRate)
        samples.withUnsafeMutableBufferPointer {
            dsp.process($0.baseAddress!, frames: $0.count, channel: 0)
        }
        return samples.last! / 0.05
    }

    private func measuredAudioUnitGain(
        frequency: Double,
        band: EQBand,
        sampleRate: Double = 48_000
    ) throws -> Double {
        let frameCount = 48_000
        let amplitude: Float = 0.05
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        sourceBuffer.frameLength = AVAudioFrameCount(frameCount)
        let input = sineWave(frequency: frequency, frameCount: frameCount, amplitude: amplitude, sampleRate: sampleRate)
        input.withUnsafeBufferPointer {
            sourceBuffer.floatChannelData![0].update(from: $0.baseAddress!, count: frameCount)
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let equalizer = AVAudioUnitEQ(numberOfBands: 1)
        let audioBand = equalizer.bands[0]
        audioBand.filterType = .parametric
        audioBand.frequency = band.frequency
        audioBand.gain = band.gain
        audioBand.bandwidth = band.audioUnitBandwidth
        audioBand.bypass = false
        engine.attach(player)
        engine.attach(equalizer)
        engine.connect(player, to: equalizer, format: format)
        engine.connect(equalizer, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 256)
        player.scheduleBuffer(sourceBuffer)
        try engine.start()
        player.play()

        let renderBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256)!
        var output = [Float]()
        output.reserveCapacity(frameCount)
        while output.count < frameCount {
            let requested = AVAudioFrameCount(min(256, frameCount - output.count))
            let status = try engine.renderOffline(requested, to: renderBuffer)
            if status == .success {
                output.append(contentsOf: UnsafeBufferPointer(start: renderBuffer.floatChannelData![0], count: Int(renderBuffer.frameLength)))
            } else if status != .insufficientDataFromInputNode {
                XCTFail("Offline Audio Unit rendering failed with status \(status.rawValue)")
                break
            }
        }
        player.stop()
        engine.stop()

        let settled = output.dropFirst(4096)
        let outputRMS = sqrt(settled.reduce(0.0) { $0 + Double($1 * $1) } / Double(settled.count))
        return 20 * log10(outputRMS / (Double(amplitude) / sqrt(2)))
    }

    private func measuredTHDDecibels(_ samples: [Float], frequency: Double, sampleRate: Double = 48_000) -> Double {
        var sineProjection = 0.0
        var cosineProjection = 0.0
        var totalEnergy = 0.0
        for (index, sample) in samples.enumerated() {
            let phase = 2 * Double.pi * frequency * Double(index) / sampleRate
            let value = Double(sample)
            sineProjection += value * sin(phase)
            cosineProjection += value * cos(phase)
            totalEnergy += value * value
        }
        let scale = 2 / Double(samples.count)
        let sineAmplitude = sineProjection * scale
        let cosineAmplitude = cosineProjection * scale
        let fundamentalEnergy = Double(samples.count) * (sineAmplitude * sineAmplitude + cosineAmplitude * cosineAmplitude) / 2
        let residualEnergy = max(0, totalEnergy - fundamentalEnergy)
        return 10 * log10(max(residualEnergy, 1e-20) / max(fundamentalEnergy, 1e-20))
    }

    private func swiftFunctionBody(named name: String, in source: String) throws -> Substring {
        guard let signature = source.range(of: "func \(name)("),
              let openingBrace = source[signature.lowerBound...].firstIndex(of: "{") else {
            throw NSError(domain: "RealtimeAudit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing function \(name)"])
        }
        var depth = 0
        var cursor = openingBrace
        while cursor < source.endIndex {
            if source[cursor] == "{" {
                depth += 1
            } else if source[cursor] == "}" {
                depth -= 1
                if depth == 0 {
                    return source[openingBrace...cursor]
                }
            }
            cursor = source.index(after: cursor)
        }
        throw NSError(domain: "RealtimeAudit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unclosed function \(name)"])
    }

    // MARK: - Phase 2

    func testFeedbackGuardGracePeriodIgnoresHotSignal() {
        var guardState = FeedbackGuard()
        for _ in 0..<FeedbackGuard.graceWindowCount {
            XCTAssertFalse(guardState.evaluate(peak: 1.0, rms: 0.95))
        }
        XCTAssertFalse(guardState.isTripped)
    }

    func testFeedbackGuardDoesNotTripOnLoudButLimitedMusic() {
        var guardState = FeedbackGuard()
        // Peak limiter ceiling is 0.98 — this is normal loud program material.
        let total = FeedbackGuard.graceWindowCount + FeedbackGuard.tripWindowCount + 20
        for _ in 0..<total {
            XCTAssertFalse(guardState.evaluate(peak: 0.98, rms: 0.55))
        }
        XCTAssertFalse(guardState.isTripped)
    }

    func testFeedbackGuardTripsOnSustainedHardClip() {
        var guardState = FeedbackGuard()
        var tripped = false
        let total = FeedbackGuard.graceWindowCount + FeedbackGuard.tripWindowCount + 5
        for _ in 0..<total {
            if guardState.evaluate(peak: 1.0, rms: 0.85) {
                tripped = true
                break
            }
        }
        XCTAssertTrue(tripped)
        XCTAssertTrue(guardState.isTripped)
        // Remains tripped until reset.
        XCTAssertTrue(guardState.evaluate(peak: 0.1, rms: 0.05))
        guardState.reset()
        XCTAssertFalse(guardState.isTripped)
        XCTAssertFalse(guardState.evaluate(peak: 0.1, rms: 0.05))
    }

    func testFeedbackGuardCoolsDown() {
        var guardState = FeedbackGuard()
        // Exit grace, then heat up a bit without tripping.
        for _ in 0..<(FeedbackGuard.graceWindowCount + 30) {
            _ = guardState.evaluate(peak: 1.0, rms: 0.9)
        }
        XCTAssertGreaterThan(guardState.hotWindows, 0)
        XCTAssertFalse(guardState.isTripped)
        for _ in 0..<40 {
            _ = guardState.evaluate(peak: 0.2, rms: 0.05)
        }
        XCTAssertEqual(guardState.hotWindows, 0)
        XCTAssertFalse(guardState.isTripped)
    }

    func testDeviceProfileStoreUpsertAndLookup() {
        let store = DeviceProfileStore()
        var profiles: [DeviceEQProfile] = []
        let presetID = UUID()

        store.upsert(
            deviceUID: "test-uid-airpods",
            deviceName: "AirPods Pro",
            presetID: presetID,
            presetName: "Bass Boost",
            into: &profiles
        )

        XCTAssertEqual(profiles.count, 1)
        let found = store.profile(forDeviceUID: "test-uid-airpods", in: profiles)
        XCTAssertEqual(found?.presetName, "Bass Boost")
        XCTAssertEqual(found?.presetID, presetID)

        store.upsert(
            deviceUID: "test-uid-airpods",
            deviceName: "AirPods Pro",
            presetID: presetID,
            presetName: "Vocal Clarity",
            into: &profiles
        )
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].presetName, "Vocal Clarity")

        store.remove(deviceUID: "test-uid-airpods", from: &profiles)
        XCTAssertTrue(profiles.isEmpty)
    }

    func testAudioDeviceProfileKeyPrefersUID() {
        let withUID = AudioDevice(
            id: 1,
            uid: "BuiltInSpeakerDevice",
            name: "MacBook Speakers",
            manufacturer: "Apple",
            isInput: false,
            isOutput: true,
            isDefaultInput: false,
            isDefaultOutput: true,
            sampleRate: 48000,
            channelCount: 2
        )
        XCTAssertEqual(withUID.profileKey, "BuiltInSpeakerDevice")

        let withoutUID = AudioDevice(
            id: 42,
            uid: nil,
            name: "Unknown",
            manufacturer: nil,
            isInput: false,
            isOutput: true,
            isDefaultInput: false,
            isDefaultOutput: false,
            sampleRate: nil,
            channelCount: 2
        )
        XCTAssertEqual(withoutUID.profileKey, "id:42")
    }

    // MARK: - Phase 3

    func testDynamicsSettingsClamp() {
        var settings = DynamicsSettings.default
        settings.threshold = -100
        settings.ratio = 100
        settings.attack = 0
        settings.release = 50
        settings.makeupGain = 40
        settings.balance = 5
        settings.clamp()

        XCTAssertEqual(settings.threshold, DynamicsSettings.thresholdRange.lowerBound)
        XCTAssertEqual(settings.ratio, DynamicsSettings.ratioRange.upperBound)
        XCTAssertEqual(settings.attack, DynamicsSettings.attackRange.lowerBound)
        XCTAssertEqual(settings.release, DynamicsSettings.releaseRange.upperBound)
        XCTAssertEqual(settings.makeupGain, DynamicsSettings.makeupRange.upperBound)
        XCTAssertEqual(settings.balance, DynamicsSettings.balanceRange.upperBound)
    }

    func testDynamicsSettingsDefaultCompressorOff() {
        XCTAssertFalse(DynamicsSettings.default.isCompressorEnabled)
        XCTAssertEqual(DynamicsSettings.default.balance, 0, accuracy: 0.001)
    }

    func testAudioEngineAcceptsDynamicsWithoutCrash() throws {
        let controller = AudioEngineController()
        var settings = DynamicsSettings.default
        settings.isCompressorEnabled = true
        settings.threshold = -20
        settings.ratio = 4
        settings.balance = -0.25
        controller.applyDynamics(settings)

        let url = URL(fileURLWithPath: "/System/Library/Sounds/Ping.aiff")
        try controller.prepare(url: url)
        controller.play()
        if case .failed(let message) = controller.playbackState {
            XCTFail("Playback with dynamics failed: \(message)")
        }
        controller.stop()
    }

    func testFourCharCodeString() {
        let code: FourCharCode = 0x61756678 // 'aufx'
        XCTAssertEqual(code.fourCharString, "aufx")
    }

    // MARK: - Phase 4

    func testCalibrationImporterParsesGraphicEQ() throws {
        let text = """
        Preamp: -6.2 dB
        GraphicEQ: 20 2.0; 32 3.0; 64 2.5; 125 1.0; 250 0.5; 500 0.0; 1000 -0.5; 2000 1.0; 4000 2.0; 8000 1.5; 16000 1.0; 20000 0.5
        """
        let result = try CalibrationImporter.importText(text, sourceName: "Test HP")
        XCTAssertEqual(result.formatName, "GraphicEQ")
        XCTAssertEqual(result.preset.mode, .graphic)
        XCTAssertEqual(result.preset.bands.count, 10)
        XCTAssertEqual(result.preset.preamp, -6.2, accuracy: 0.01)
        XCTAssertGreaterThan(result.preset.bands[0].gain, 0)
    }

    func testCalibrationImporterParsesParametric() throws {
        let text = """
        Preamp: -4.0 dB
        Filter 1: ON LSC Fc 80 Hz Gain 3.5 dB Q 0.70
        Filter 2: ON PK Fc 1000 Hz Gain -2.0 dB Q 1.41
        Filter 3: ON HSC Fc 8000 Hz Gain 1.5 dB Q 0.70
        """
        let result = try CalibrationImporter.importText(text, sourceName: "Para Test")
        XCTAssertEqual(result.formatName, "Parametric EQ")
        XCTAssertEqual(result.preset.mode, .parametric)
        XCTAssertEqual(result.preset.bands.count, 3)
        XCTAssertEqual(result.preset.bands[0].filterType, .lowShelf)
        XCTAssertEqual(result.preset.bands[1].filterType, .parametric)
        XCTAssertEqual(result.preset.bands[2].filterType, .highShelf)
        XCTAssertEqual(result.preset.preamp, -4.0, accuracy: 0.01)
    }

    func testHeadphoneProfileAsPresetTenBand() {
        let profile = HeadphoneProfile(
            name: "Test",
            brand: "Brand",
            gains: [1, 2, 3, 0, 0, 0, -1, -2, -1, 0],
            preamp: -3
        )
        let preset = profile.asPreset(graphicBandCount: .ten)
        XCTAssertEqual(preset.bands.count, 10)
        XCTAssertEqual(preset.bands[1].gain, 2, accuracy: 0.01)
        XCTAssertEqual(preset.preamp, -3, accuracy: 0.01)
        XCTAssertEqual(preset.mode, .graphic)
    }

    func testAutoEQCatalogFallbackNotEmpty() {
        let catalog = AutoEQCatalog()
        let profiles = catalog.loadBundledProfiles()
        XCTAssertFalse(profiles.isEmpty)
        let search = catalog.search("Sennheiser", in: profiles)
        XCTAssertFalse(search.isEmpty)
    }

    func testChannelLayoutStereoSupported() {
        XCTAssertTrue(ChannelLayout.stereo.isFullySupported)
        XCTAssertFalse(ChannelLayout.multiChannel.isFullySupported)
    }

    // MARK: - Graph model

    func testGraphStarterTemplateHasRunnableSystemChain() {
        let doc = GraphDocument.starterTemplate()
        let chains = GraphValidation.compileChains(doc)
        XCTAssertFalse(chains.isEmpty)
        XCTAssertTrue(chains.contains { $0.sourceKind == .system })
        XCTAssertNotNil(chains.first?.equalizerID)
        XCTAssertNotNil(chains.first?.outputID)
    }

    func testGraphRejectsCycles() {
        var doc = GraphDocument.starterTemplate()
        let dyn = GraphNode(kind: .dynamics, position: CGPoint(x: 400, y: 300))
        doc.nodes.append(dyn)
        guard let eq = doc.nodes.first(where: { $0.kind == .equalizer }) else {
            return XCTFail("Missing equalizer")
        }
        // Remove existing eq→output so eq.out is free, wire eq→dyn
        doc.edges.removeAll { $0.from.nodeID == eq.id }
        doc.edges.append(GraphEdge(
            from: GraphPortID(nodeID: eq.id, name: "out"),
            to: GraphPortID(nodeID: dyn.id, name: "in")
        ))
        // Closing dyn→eq would form a cycle
        XCTAssertFalse(
            GraphValidation.canConnect(
                from: GraphPortID(nodeID: dyn.id, name: "out"),
                to: GraphPortID(nodeID: eq.id, name: "in"),
                in: doc
            )
        )
    }

    func testGraphDocumentCodableRoundTrip() throws {
        let original = GraphDocument.starterTemplate()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GraphDocument.self, from: data)
        XCTAssertEqual(decoded.nodes.count, original.nodes.count)
        XCTAssertEqual(decoded.edges.count, original.edges.count)
        XCTAssertEqual(decoded.schemaVersion, GraphDocument.currentSchemaVersion)
    }

    func testGraphCanConnectValidPorts() {
        let doc = GraphDocument.starterTemplate()
        guard let file = doc.nodes.first(where: { $0.kind == .fileSource }),
              let eq = doc.nodes.first(where: { $0.kind == .equalizer }) else {
            return XCTFail("Missing nodes")
        }
        // EQ already has an input — fan-in not allowed for second connection to same input
        XCTAssertFalse(
            GraphValidation.canConnect(
                from: file.portID(name: "out"),
                to: eq.portID(name: "in"),
                in: doc
            )
        )
    }

    func testGraphRuntimePrefersSystemChainFromStarter() {
        let doc = GraphDocument.starterTemplate()
        guard let run = GraphRuntime.preferredRun(from: doc) else {
            return XCTFail("Expected runnable system chain")
        }
        XCTAssertEqual(run.chain.sourceKind, .system)
        if case .process(let target, _, let label) = run.kind {
            XCTAssertEqual(target, .systemExcludingSelf)
            XCTAssertEqual(label, "System Audio")
        } else {
            XCTFail("Expected process kind")
        }
        let preset = GraphRuntime.equalizerPreset(
            for: run.chain,
            document: doc,
            fallback: .flatPreset()
        )
        XCTAssertEqual(preset.name, "Flat")
    }

    func testGraphRuntimeResolvesAppBundleTarget() {
        var doc = GraphDocument()
        let appID = UUID()
        let eqID = UUID()
        let outID = UUID()
        doc.nodes = [
            GraphNode(
                id: appID,
                kind: .appSource,
                title: "Chrome",
                position: .zero,
                config: .appSource(
                    .init(
                        bundleID: "com.google.Chrome",
                        processObjectID: nil,
                        displayName: "Chrome",
                        pid: nil
                    )
                )
            ),
            GraphNode(id: eqID, kind: .equalizer, position: CGPoint(x: 200, y: 0)),
            GraphNode(id: outID, kind: .output, position: CGPoint(x: 400, y: 0))
        ]
        doc.edges = [
            GraphEdge(
                from: GraphPortID(nodeID: appID, name: "out"),
                to: GraphPortID(nodeID: eqID, name: "in")
            ),
            GraphEdge(
                from: GraphPortID(nodeID: eqID, name: "out"),
                to: GraphPortID(nodeID: outID, name: "in")
            )
        ]
        guard let run = GraphRuntime.preferredRun(from: doc) else {
            return XCTFail("Expected app chain")
        }
        XCTAssertEqual(run.chain.sourceKind, .app)
        if case .process(let target, _, let label) = run.kind {
            XCTAssertEqual(target, .bundleIDs(["com.google.Chrome"]))
            XCTAssertEqual(label, "Chrome")
        } else {
            XCTFail("Expected process kind for app")
        }
    }

    func testGraphRuntimeResolvesInputMonitorChain() {
        var doc = GraphDocument()
        let micID = UUID()
        let eqID = UUID()
        let outID = UUID()
        doc.nodes = [
            GraphNode(
                id: micID,
                kind: .inputSource,
                position: .zero,
                config: .inputSource(.init(deviceUID: "BuiltInMicUID", deviceName: "MacBook Mic"))
            ),
            GraphNode(id: eqID, kind: .equalizer, position: CGPoint(x: 200, y: 0)),
            GraphNode(
                id: outID,
                kind: .output,
                position: CGPoint(x: 400, y: 0),
                config: .output(.init(deviceUID: "SpeakerUID", deviceName: "Speakers"))
            )
        ]
        doc.edges = [
            GraphEdge(from: GraphPortID(nodeID: micID, name: "out"), to: GraphPortID(nodeID: eqID, name: "in")),
            GraphEdge(from: GraphPortID(nodeID: eqID, name: "out"), to: GraphPortID(nodeID: outID, name: "in"))
        ]
        guard let run = GraphRuntime.preferredRun(from: doc) else {
            return XCTFail("Expected input chain")
        }
        XCTAssertEqual(run.chain.sourceKind, .input)
        if case .input(let inUID, let outUID, let label) = run.kind {
            XCTAssertEqual(inUID, "BuiltInMicUID")
            XCTAssertEqual(outUID, "SpeakerUID")
            XCTAssertEqual(label, "MacBook Mic")
        } else {
            XCTFail("Expected input kind")
        }
    }

    func testGraphRuntimePrefersProcessOverInput() {
        var doc = GraphDocument.starterTemplate()
        let micID = UUID()
        let eq2 = UUID()
        let out2 = UUID()
        doc.nodes.append(contentsOf: [
            GraphNode(id: micID, kind: .inputSource, position: CGPoint(x: 80, y: 400)),
            GraphNode(id: eq2, kind: .equalizer, position: CGPoint(x: 320, y: 400)),
            GraphNode(id: out2, kind: .output, position: CGPoint(x: 580, y: 400))
        ])
        doc.edges.append(contentsOf: [
            GraphEdge(from: GraphPortID(nodeID: micID, name: "out"), to: GraphPortID(nodeID: eq2, name: "in")),
            GraphEdge(from: GraphPortID(nodeID: eq2, name: "out"), to: GraphPortID(nodeID: out2, name: "in"))
        ])
        guard let run = GraphRuntime.preferredRun(from: doc) else {
            return XCTFail("Expected preferred run")
        }
        XCTAssertEqual(run.chain.sourceKind, .system)
    }

    func testProcessTapTargetDescriptions() {
        XCTAssertEqual(ProcessTapTarget.systemExcludingSelf.shortDescription, "system")
        XCTAssertEqual(ProcessTapTarget.bundleIDs(["a.b"]).shortDescription, "a.b")
        XCTAssertTrue(ProcessTapTarget.processes([1, 2]).shortDescription.contains("2"))
    }

    @MainActor
    func testGraphStoreTopologyCallbackOnConnect() {
        let store = GraphStore(document: .starterTemplate())
        var fired = 0
        store.onTopologyChanged = { fired += 1 }
        guard let file = store.document.nodes.first(where: { $0.kind == .fileSource }),
              let eq = store.document.nodes.first(where: { $0.kind == .equalizer }) else {
            return XCTFail("Missing nodes")
        }
        // Fan-in blocked — should not fire topology for failed connect
        let connected = store.connect(from: file.portID(name: "out"), to: eq.portID(name: "in"))
        XCTAssertFalse(connected)
        XCTAssertEqual(fired, 0)

        store.disconnect(edgeID: store.document.edges[0].id)
        XCTAssertEqual(fired, 1)
    }

    // MARK: - Level Match & True-Peak Tests

    func testLevelMatchEstimatorConvergence() {
        var estimator = LevelMatchEstimator()
        XCTAssertEqual(estimator.offsetDB, 0)
        XCTAssertFalse(estimator.isConverged)

        // Active path is 6 dB louder than bypass (active = 0.2, bypass = 0.1)
        for _ in 0..<12 {
            _ = estimator.update(activeRMS: 0.2, bypassRMS: 0.1)
        }

        XCTAssertTrue(estimator.isConverged)
        XCTAssertEqual(estimator.offsetDB, -6.02, accuracy: 0.5)
    }

    func testTruePeakOversamplingDetectsInterSamplePeak() {
        let analyzer = SpectrumAnalyzer()
        // Create an inter-sample peak signal: samples hit +0.8, -0.8 around nyquist/sub-sample
        var samples = [Float](repeating: 0, count: 1024)
        for i in stride(from: 0, to: 1024, by: 4) {
            samples[i] = 0.0
            samples[i + 1] = 0.90
            samples[i + 2] = 0.90
            samples[i + 3] = 0.0
        }

        let analysis = samples.withUnsafeBufferPointer { ptr in
            analyzer.analyze(left: ptr.baseAddress!, right: nil, frameLength: 1024, sampleRate: 48_000)
        }

        XCTAssertNotNil(analysis)
        if let analysis {
            XCTAssertGreaterThanOrEqual(analysis.truePeak, 0.90)
            XCTAssertGreaterThan(analysis.truePeakDBTP, -1.0)
        }
    }

    // MARK: - Layered EQ Tests

    func testLayeredEQSummation() {
        let calBand = EQBand(frequency: 1000, gain: -2, q: 1, filterType: .parametric)
        let targetBand = EQBand(frequency: 1000, gain: 3, q: 1, filterType: .parametric)
        let sessionBand = EQBand(frequency: 1000, gain: 1.5, q: 1, filterType: .parametric)

        var layers = EQLayer.defaultLayers()
        layers[.calibration] = EQLayer(kind: .calibration, isEnabled: true, preamp: -1.0, bands: [calBand])
        layers[.target] = EQLayer(kind: .target, isEnabled: true, preamp: 0.0, bands: [targetBand])
        layers[.session] = EQLayer(kind: .session, isEnabled: true, preamp: 0.5, bands: [sessionBand])

        let composite = EQLayerComposite.compositePreset(
            mode: .parametric,
            layers: layers,
            activeSessionBands: [sessionBand],
            sessionPreamp: 0.5
        )

        XCTAssertEqual(composite.bands.count, 3)
        XCTAssertEqual(composite.preamp, -0.5, accuracy: 0.001)
    }

    // MARK: - Undo/Redo & Snapshot Slots Tests

    func testEQHistoryManagerUndoRedo() {
        let history = EQHistoryManager()
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)

        let s1 = EQSnapshot(name: "S1", mode: .graphic, bands: [], preamp: 0)
        let s2 = EQSnapshot(name: "S2", mode: .graphic, bands: [], preamp: 2)
        let s3 = EQSnapshot(name: "S3", mode: .graphic, bands: [], preamp: 4)

        history.push(current: s1)
        history.push(current: s2)
        XCTAssertTrue(history.canUndo)

        let restored2 = history.undo(current: s3)
        XCTAssertEqual(restored2?.preamp, 2)
        XCTAssertTrue(history.canRedo)

        let restored3 = history.redo(current: s2)
        XCTAssertEqual(restored3?.preamp, 4)
    }

    func testEQSnapshotSlotStorage() {
        let history = EQHistoryManager()
        let snapA = EQSnapshot(name: "Vocal", mode: .parametric, bands: [], preamp: -1.5)
        history.saveSlot(.a, snapshot: snapA)

        let retrieved = history.getSlot(.a)
        XCTAssertEqual(retrieved?.name, "Vocal")
        if let preamp = retrieved?.preamp {
            XCTAssertEqual(preamp, -1.5, accuracy: 0.001)
        } else {
            XCTFail("Missing snapshot in slot A")
        }
        XCTAssertNil(history.getSlot(.b))
    }
}
