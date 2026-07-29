import XCTest
import AVFoundation
@testable import OpenEQ

@MainActor
final class OpenEQTests: XCTestCase {
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

    // MARK: - Phase 2

    func testFeedbackGuardDoesNotTripOnShortPeaks() {
        var guardState = FeedbackGuard()
        for _ in 0..<5 {
            XCTAssertFalse(guardState.evaluate(peak: 1.0, rms: 0.9))
        }
        XCTAssertFalse(guardState.isTripped)
    }

    func testFeedbackGuardTripsOnSustainedHotSignal() {
        var guardState = FeedbackGuard()
        var tripped = false
        for _ in 0..<(FeedbackGuard.tripWindowCount + 2) {
            if guardState.evaluate(peak: 0.99, rms: 0.5) {
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
        for _ in 0..<10 {
            _ = guardState.evaluate(peak: 0.99, rms: 0.5)
        }
        XCTAssertGreaterThan(guardState.hotWindows, 0)
        for _ in 0..<20 {
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
}
