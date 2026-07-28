import XCTest
@testable import OpenEQ

@MainActor
final class OpenEQTests: XCTestCase {
    func testEQBandClampsEditableParameters() {
        var band = EQBand(frequency: 1, gain: 30, q: 20)

        XCTAssertEqual(band.frequency, EQBand.frequencyRange.lowerBound)
        XCTAssertEqual(band.gain, EQBand.gainRange.upperBound)
        XCTAssertEqual(band.q, EQBand.qRange.upperBound)

        band.frequency = 100_000
        band.gain = -100
        band.q = 0

        XCTAssertEqual(band.frequency, EQBand.frequencyRange.upperBound)
        XCTAssertEqual(band.gain, EQBand.gainRange.lowerBound)
        XCTAssertEqual(band.q, EQBand.qRange.lowerBound)
    }

    func testDefaultPresetsHaveExpectedShape() throws {
        let presets = EQPreset.defaultPresets()
        let bassBoost = try XCTUnwrap(presets.first { $0.name == "Bass Boost" })

        XCTAssertEqual(presets.count, 5)
        XCTAssertEqual(bassBoost.bands.count, GraphicBandCount.ten.bandCount)
        XCTAssertEqual(bassBoost.bands[0].gain, 6.0)
        XCTAssertEqual(bassBoost.bands[1].gain, 5.5)
    }

    func testSpectrumAnalyzerResetClearsAllLevels() {
        let analysis = SpectrumAnalyzer().reset()

        XCTAssertEqual(analysis.levels.count, SpectrumAnalyzer.barCount)
        XCTAssertTrue(analysis.levels.allSatisfy { $0 == 0 })
        XCTAssertEqual(analysis.leftPeak, 0)
        XCTAssertEqual(analysis.rightPeak, 0)
        XCTAssertEqual(analysis.peakLevel, 0)
        XCTAssertFalse(analysis.isClipping)
    }

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
}
