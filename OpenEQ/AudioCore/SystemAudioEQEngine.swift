import AVFoundation
import CoreAudio
import Accelerate

let kOpenEQSysObj = AudioObjectID(kAudioObjectSystemObject)

final class SystemAudioEQEngine {
    private(set) var status: SystemAudioStatus = .stopped
    private(set) var latencyEstimate: TimeInterval?

    var onAnalysis: ((SpectrumAnalysis) -> Void)?
    var onStatusChanged: ((SystemAudioStatus) -> Void)?

    private let analyzer = SpectrumAnalyzer()
    private let logger = AppLogger(category: "SystemAudioEQ")

    private let ioQueue = DispatchQueue(label: "com.openeq.system-audio-eq.io", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var aggIOProcID: AudioDeviceIOProcID?
    private var origOutputID = AudioObjectID(kAudioObjectUnknown)
    private var isRunning = false
    private var sampleRate: Double = 48000
    private let dspState = SystemAudioDSPState()

    deinit {
        stop()
    }

    func start(with preset: EQPreset) {
        guard #available(macOS 14.2, *) else {
            onStatusChanged?(.failed("Requires macOS 14.2+"))
            return
        }
        stop()
        do {
            origOutputID = try getDefaultOutputDeviceID()
            try setupTap()
            ioQueue.sync {
                dspState.configure(preset, sampleRate: sampleRate)
            }
            try setupAggregateWithOutput()
            try setDefaultOutput(aggDeviceID)
            try startAggIO()
            isRunning = true
            latencyEstimate = Double(1024) / sampleRate * 3
            status = .running
            onStatusChanged?(.running)
            logger.info("System-wide EQ started on aggregate device")
        } catch {
            cleanup(restoreOutput: true)
            let msg = (error as? SystemAudioEQError)?.localizedDescription ?? error.localizedDescription
            status = .failed(msg)
            onStatusChanged?(status)
            logger.error("Start failed: \(msg)")
        }
    }

    func stop() {
        cleanup(restoreOutput: true)
        ioQueue.sync {
            dspState.reset()
        }
        isRunning = false
        status = .stopped
        latencyEstimate = nil
        onStatusChanged?(.stopped)
        logger.info("System-wide EQ stopped")
    }

    func updateEQ(_ preset: EQPreset) {
        let rate = sampleRate
        ioQueue.async { [weak self] in
            self?.dspState.configure(preset, sampleRate: rate)
        }
    }

    func setBypassed(_ bypassed: Bool) {
        ioQueue.async { [weak self] in
            self?.dspState.isBypassed = bypassed
        }
    }

    func rebuildAggregateWithCurrentOutput() {
        guard isRunning, tapID != kAudioObjectUnknown else { return }

        logger.info("Rebuilding aggregate device for output change")

        let savedPreset = EQPreset(name: "rebuild", mode: .graphic, bands: [], preamp: 0)

        stopAggIO()
        destroyAggregate()

        do {
            let newOutputID = try getDefaultOutputDeviceID()
            origOutputID = newOutputID
            try setupAggregateWithOutput()
            try setDefaultOutput(aggDeviceID)
            try startAggIO()
            logger.info("Aggregate device rebuilt with new output")
        } catch {
            logger.error("Rebuild failed: \(error.localizedDescription)")
            status = .failed("Device change failed: \(error.localizedDescription)")
            onStatusChanged?(status)
        }
    }

    // MARK: - Setup

    @available(macOS 14.2, *)
    private func setupTap() throws {
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.name = "OpenEQ System Audio"
        desc.isPrivate = true
        desc.muteBehavior = .muted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let err = AudioHardwareCreateProcessTap(desc, &newTapID)
        guard err == noErr else { throw SystemAudioEQError.failed("Create tap: \(err)") }
        tapID = newTapID
        sampleRate = try getTapFormat().mSampleRate
        logger.info("Tap created, rate: \(sampleRate)")
    }

    private func setupAggregateWithOutput() throws {
        let outputUID = try getDeviceUID(origOutputID)
        let tapUID = try getTapUID()
        let aggUID = "com.openeq.agg.\(UUID().uuidString)"

        let subDevices = [[kAudioSubDeviceUIDKey: outputUID]]
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "OpenEQ Engine",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
        ]

        var newAggID = AudioObjectID(kAudioObjectUnknown)
        var err = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &newAggID)
        guard err == noErr else { throw SystemAudioEQError.failed("Create aggregate: \(err)") }
        aggDeviceID = newAggID

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var list: CFArray? = [tapUID] as CFArray
        err = withUnsafeMutablePointer(to: &list) { ptr in
            AudioObjectSetPropertyData(aggDeviceID, &addr, UInt32(0), nil, UInt32(MemoryLayout<CFArray>.size), ptr)
        }
        guard err == noErr else { throw SystemAudioEQError.failed("Set tap list: \(err)") }

        logger.info("Aggregate device created with output + tap")
    }

    private func startAggIO() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        var procID: AudioDeviceIOProcID?
        let err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggDeviceID, ioQueue) {
            [weak self] (_, inInputData, _, outOutputData, _) in
            guard let self else { return }
            self.handleIO(inData: inInputData, outData: outOutputData, format: format)
        }
        guard err == noErr, let procID else {
            throw SystemAudioEQError.failed("Create IOProc: \(err)")
        }
        aggIOProcID = procID
        let startStatus = AudioDeviceStart(aggDeviceID, procID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(aggDeviceID, procID)
            aggIOProcID = nil
            throw SystemAudioEQError.failed("Start IOProc: \(startStatus)")
        }
    }

    // MARK: - IO

    private func handleIO(inData: UnsafePointer<AudioBufferList>, outData: UnsafeMutablePointer<AudioBufferList>, format: AVAudioFormat) {
        let inBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
        let outBuffers = UnsafeMutableAudioBufferListPointer(outData)
        let channelCount = Int(format.channelCount)

        for buffer in outBuffers {
            guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
            memset(data, 0, Int(buffer.mDataByteSize))
        }

        guard let firstInput = inBuffers.first,
              firstInput.mData != nil,
              firstInput.mDataByteSize > 0 else {
            return
        }

        let activeChannels = min(inBuffers.count, outBuffers.count, channelCount)
        for channel in 0..<activeChannels {
            guard let inputData = inBuffers[channel].mData,
                  let outputData = outBuffers[channel].mData else { continue }
            let copyBytes = min(inBuffers[channel].mDataByteSize, outBuffers[channel].mDataByteSize)
            let frames = Int(copyBytes) / MemoryLayout<Float>.size
            guard frames > 0 else { continue }

            let source = inputData.assumingMemoryBound(to: Float.self)
            let destination = outputData.assumingMemoryBound(to: Float.self)
            memcpy(destination, source, Int(copyBytes))
            dspState.process(destination, frames: frames, channel: channel)
        }

        let analysisFrames = Int(firstInput.mDataByteSize) / MemoryLayout<Float>.size
        if analysisFrames > 0,
           let analysis = analyzer.analyze(bufferList: inData, frameLength: analysisFrames, sampleRate: sampleRate) {
            DispatchQueue.main.async { [weak self] in self?.onAnalysis?(analysis) }
        }
    }

    // MARK: - Helpers

    private func getTapUID() throws -> CFString {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let ptr = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        ptr.initialize(to: nil); defer { ptr.deinitialize(count: 1); ptr.deallocate() }
        var size = UInt32(MemoryLayout<CFString?>.size)
        let err = AudioObjectGetPropertyData(tapID, &addr, UInt32(0), nil, &size, ptr)
        guard err == noErr, let uid = ptr.pointee else { throw SystemAudioEQError.failed("Get tap UID: \(err)") }
        return uid
    }

    private func getTapFormat() throws -> AudioStreamBasicDescription {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var fmt = AudioStreamBasicDescription(); var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let err = AudioObjectGetPropertyData(tapID, &addr, UInt32(0), nil, &size, &fmt)
        guard err == noErr else { throw SystemAudioEQError.failed("Get tap format: \(err)") }
        return fmt
    }

    private func getDefaultOutputDeviceID() throws -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var outID = AudioObjectID(kAudioObjectUnknown); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let err = AudioObjectGetPropertyData(kOpenEQSysObj, &addr, UInt32(0), nil, &size, &outID)
        guard err == noErr, outID != kAudioObjectUnknown else { throw SystemAudioEQError.failed("No output device") }
        return outID
    }

    private func getDeviceUID(_ deviceID: AudioDeviceID) throws -> String {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let ptr = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        ptr.initialize(to: nil); defer { ptr.deinitialize(count: 1); ptr.deallocate() }
        var size = UInt32(MemoryLayout<CFString?>.size)
        let err = AudioObjectGetPropertyData(deviceID, &addr, UInt32(0), nil, &size, ptr)
        guard err == noErr, let uid = ptr.pointee else { throw SystemAudioEQError.failed("Get device UID: \(err)") }
        return uid as String
    }

    private func setDefaultOutput(_ deviceID: AudioDeviceID) throws {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = deviceID
        let err = AudioObjectSetPropertyData(kOpenEQSysObj, &addr, UInt32(0), nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        guard err == noErr else { throw SystemAudioEQError.failed("Set default output: \(err)") }
    }

    // MARK: - Cleanup

    private func stopAggIO() {
        if let p = aggIOProcID, aggDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggDeviceID, p); AudioDeviceDestroyIOProcID(aggDeviceID, p)
        }
        aggIOProcID = nil
    }

    private func destroyAggregate() {
        if aggDeviceID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggDeviceID); aggDeviceID = kAudioObjectUnknown }
    }

    private func destroyTap() {
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = kAudioObjectUnknown }
    }

    private func cleanup(restoreOutput: Bool = false) {
        if restoreOutput, origOutputID != kAudioObjectUnknown {
            try? setDefaultOutput(origOutputID)
        }
        stopAggIO()
        destroyAggregate()
        destroyTap()
        origOutputID = kAudioObjectUnknown
    }
}

enum SystemAudioEQError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self { case .failed(let m): return "System EQ: \(m)" }
    }
}

private struct BiquadCoefficients {
    let b0: Float
    let b1: Float
    let b2: Float
    let a1: Float
    let a2: Float

    static let identity = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    static func normalized(
        b0: Float,
        b1: Float,
        b2: Float,
        a0: Float,
        a1: Float,
        a2: Float
    ) -> BiquadCoefficients {
        let inverseA0 = 1 / a0
        return BiquadCoefficients(
            b0: b0 * inverseA0,
            b1: b1 * inverseA0,
            b2: b2 * inverseA0,
            a1: a1 * inverseA0,
            a2: a2 * inverseA0
        )
    }
}

private struct SmoothingCoefficients {
    static let duration = 512

    private var current: BiquadCoefficients
    private var target: BiquadCoefficients
    private var remaining: Int

    init() {
        current = .identity
        target = .identity
        remaining = 0
    }

    mutating func startTransition(to newTarget: BiquadCoefficients) {
        if remaining > 0 {
            let t = 1 - Float(remaining) / Float(Self.duration)
            current = lerp(current, target, t)
        }
        target = newTarget
        remaining = Self.duration
    }

    func interpolatedCoeffs() -> BiquadCoefficients {
        guard remaining > 0 else { return current }
        let t = 1 - Float(remaining) / Float(Self.duration)
        return lerp(current, target, t)
    }

    mutating func advance(frames: Int) {
        guard remaining > 0 else { return }

        if frames >= remaining {
            current = target
            remaining = 0
        } else {
            let t = 1 - Float(remaining - frames) / Float(Self.duration)
            current = lerp(current, target, t)
            remaining -= frames
        }
    }

    mutating func reset() {
        current = .identity
        target = .identity
        remaining = 0
    }

    private func lerp(_ a: BiquadCoefficients, _ b: BiquadCoefficients, _ t: Float) -> BiquadCoefficients {
        BiquadCoefficients(
            b0: a.b0 + (b.b0 - a.b0) * t,
            b1: a.b1 + (b.b1 - a.b1) * t,
            b2: a.b2 + (b.b2 - a.b2) * t,
            a1: a.a1 + (b.a1 - a.a1) * t,
            a2: a.a2 + (b.a2 - a.a2) * t
        )
    }
}

private struct BiquadState {
    var x1: Float = 0
    var x2: Float = 0
    var y1: Float = 0
    var y2: Float = 0
}

private final class SystemAudioDSPState {
    private var smoothingCoeffs = Array(repeating: SmoothingCoefficients(), count: 31)
    private var leftStates = Array(repeating: BiquadState(), count: 31)
    private var rightStates = Array(repeating: BiquadState(), count: 31)
    private var preampLinear: Float = 1
    var isBypassed = false

    func configure(_ preset: EQPreset, sampleRate: Double) {
        preampLinear = pow(10, preset.preamp / 20)

        for index in smoothingCoeffs.indices {
            guard index < preset.bands.count else {
                smoothingCoeffs[index].startTransition(to: .identity)
                continue
            }

            smoothingCoeffs[index].startTransition(
                to: Self.makeCoefficients(
                    for: preset.bands[index],
                    sampleRate: Float(sampleRate)
                )
            )
        }
    }

    func reset() {
        preampLinear = 1
        smoothingCoeffs = Array(repeating: SmoothingCoefficients(), count: 31)
        currentInterpolated = Array(repeating: .identity, count: 31)
        leftStates = Array(repeating: BiquadState(), count: 31)
        rightStates = Array(repeating: BiquadState(), count: 31)
    }

    func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channel: Int) {
        guard !isBypassed else { return }

        if abs(preampLinear - 1) > 0.0001 {
            var gain = preampLinear
            vDSP_vsmul(samples, 1, &gain, samples, 1, vDSP_Length(frames))
        }

        // Build interpolated coefficients for this buffer once (channel 0 also advances smoothing)
        if channel == 0 {
            currentInterpolated = smoothingCoeffs.indices.map { smoothingCoeffs[$0].interpolatedCoeffs() }
            for i in smoothingCoeffs.indices {
                smoothingCoeffs[i].advance(frames: frames)
            }
        }

        if channel == 0 {
            processFilters(samples, frames: frames, states: &leftStates)
        } else {
            processFilters(samples, frames: frames, states: &rightStates)
        }
    }

    private var currentInterpolated: [BiquadCoefficients] = []

    private func processFilters(
        _ samples: UnsafeMutablePointer<Float>,
        frames: Int,
        states: inout [BiquadState]
    ) {
        for band in currentInterpolated.indices {
            let coeff = currentInterpolated[band]
            if coeff.b0 == 1,
               coeff.b1 == 0,
               coeff.b2 == 0,
               coeff.a1 == 0,
               coeff.a2 == 0 {
                continue
            }

            var state = states[band]
            for index in 0..<frames {
                let input = samples[index]
                let output = coeff.b0 * input
                    + coeff.b1 * state.x1
                    + coeff.b2 * state.x2
                    - coeff.a1 * state.y1
                    - coeff.a2 * state.y2
                samples[index] = output
                state.x2 = state.x1
                state.x1 = input
                state.y2 = state.y1
                state.y1 = output
            }
            states[band] = state
        }
    }

    private static func makeCoefficients(for band: EQBand, sampleRate: Float) -> BiquadCoefficients {
        guard band.isEnabled, sampleRate > 0 else { return .identity }

        let frequency = max(20, min(band.frequency, sampleRate * 0.49))
        let omega = 2 * Float.pi * frequency / sampleRate
        let sine = sin(omega)
        let cosine = cos(omega)
        let q = max(0.1, min(10, band.q))
        let amplitude = pow(10, band.gain / 40)
        let alpha = sine / (2 * q)

        switch band.filterType {
        case .parametric:
            return .normalized(
                b0: 1 + alpha * amplitude,
                b1: -2 * cosine,
                b2: 1 - alpha * amplitude,
                a0: 1 + alpha / amplitude,
                a1: -2 * cosine,
                a2: 1 - alpha / amplitude
            )
        case .lowShelf, .highShelf:
            let shelfAlpha = sine / 2 * sqrt(max(0, (amplitude + 1 / amplitude) * (1 / q - 1) + 2))
            let beta = 2 * sqrt(amplitude) * shelfAlpha

            if band.filterType == .lowShelf {
                return .normalized(
                    b0: amplitude * ((amplitude + 1) - (amplitude - 1) * cosine + beta),
                    b1: 2 * amplitude * ((amplitude - 1) - (amplitude + 1) * cosine),
                    b2: amplitude * ((amplitude + 1) - (amplitude - 1) * cosine - beta),
                    a0: (amplitude + 1) + (amplitude - 1) * cosine + beta,
                    a1: -2 * ((amplitude - 1) + (amplitude + 1) * cosine),
                    a2: (amplitude + 1) + (amplitude - 1) * cosine - beta
                )
            }

            return .normalized(
                b0: amplitude * ((amplitude + 1) + (amplitude - 1) * cosine + beta),
                b1: -2 * amplitude * ((amplitude - 1) + (amplitude + 1) * cosine),
                b2: amplitude * ((amplitude + 1) + (amplitude - 1) * cosine - beta),
                a0: (amplitude + 1) - (amplitude - 1) * cosine + beta,
                a1: 2 * ((amplitude - 1) - (amplitude + 1) * cosine),
                a2: (amplitude + 1) - (amplitude - 1) * cosine - beta
            )
        case .lowPass:
            return .normalized(
                b0: (1 - cosine) / 2,
                b1: 1 - cosine,
                b2: (1 - cosine) / 2,
                a0: 1 + alpha,
                a1: -2 * cosine,
                a2: 1 - alpha
            )
        case .highPass:
            return .normalized(
                b0: (1 + cosine) / 2,
                b1: -(1 + cosine),
                b2: (1 + cosine) / 2,
                a0: 1 + alpha,
                a1: -2 * cosine,
                a2: 1 - alpha
            )
        }
    }
}
