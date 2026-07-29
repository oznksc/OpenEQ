import AVFoundation
import CoreAudio
import Accelerate

let kOpenEQSysObj = AudioObjectID(kAudioObjectSystemObject)

final class SystemAudioEQEngine {
    private(set) var status: SystemAudioStatus = .stopped
    private(set) var latencyEstimate: TimeInterval?
    private(set) var physicalOutputUID: String?
    private(set) var physicalOutputName: String?
    private(set) var didTripFeedbackProtection = false

    var onAnalysis: ((SpectrumAnalysis) -> Void)?
    var onStatusChanged: ((SystemAudioStatus) -> Void)?
    var onSafetyTrip: (() -> Void)?
    var onPhysicalOutputChanged: ((String?, String?) -> Void)?

    private let analyzer = SpectrumAnalyzer()
    private let logger = AppLogger(category: "SystemAudioEQ")

    private let ioQueue = DispatchQueue(label: "com.openeq.system-audio-eq.io", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var aggIOProcID: AudioDeviceIOProcID?
    private var physicalOutputID = AudioObjectID(kAudioObjectUnknown)
    private var isRunning = false
    private var isRebuilding = false
    private var sampleRate: Double = 48000
    private var channelCount: UInt32 = 2
    private let dspState = SystemAudioDSPState()
    private var feedbackGuard = FeedbackGuard()
    private var safetyTripNotified = false
    private var feedbackProtectionEnabled = true
    private var isObservingDefaultOutput = false
    /// Scratch for interleaved ↔ non-interleaved conversion (audio thread only).
    private var deinterleaveScratch: [UnsafeMutablePointer<Float>?] = [nil, nil]
    private var deinterleaveCapacity: Int = 0
    private lazy var defaultOutputListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.handleDefaultOutputChanged()
    }

    deinit {
        stopObservingDefaultOutput()
        stop()
        freeScratch()
    }

    func start(with preset: EQPreset) {
        guard #available(macOS 14.2, *) else {
            publishStatus(.failed("Requires macOS 14.2+"))
            return
        }
        stop()
        do {
            // Keep the user's physical device as system default.
            // Process-tap mute silences apps on that device; our aggregate IOProc
            // plays the processed tap audio back through the same speakers.
            // Setting default output to the aggregate is a common cause of total silence.
            physicalOutputID = try getDefaultOutputDeviceID()
            refreshPhysicalOutputMetadata()
            try setupTap()
            ioQueue.sync {
                dspState.configure(preset, sampleRate: sampleRate)
                feedbackGuard.reset()
                safetyTripNotified = false
                didTripFeedbackProtection = false
                dspState.isEmergencyMuted = false
            }
            try setupAggregateWithOutput()
            try startAggIO()
            startObservingDefaultOutput()
            isRunning = true
            latencyEstimate = estimateLatency()
            publishStatus(.running)
            logger.info(
                "System-wide EQ started (tap muted → aggregate IO → \(physicalOutputName ?? "output"), rate \(sampleRate))"
            )
        } catch {
            cleanup()
            let mapped = mapStartError(error)
            publishStatus(mapped)
            logger.error("Start failed: \(mapped.title)")
        }
    }

    func stop() {
        stopObservingDefaultOutput()
        cleanup()
        ioQueue.sync {
            dspState.reset()
            feedbackGuard.reset()
            safetyTripNotified = false
        }
        isRunning = false
        isRebuilding = false
        latencyEstimate = nil
        physicalOutputUID = nil
        physicalOutputName = nil
        didTripFeedbackProtection = false
        publishStatus(.stopped)
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

    func setFeedbackProtectionEnabled(_ enabled: Bool) {
        feedbackProtectionEnabled = enabled
        if !enabled {
            ioQueue.async { [weak self] in
                self?.feedbackGuard.reset()
                self?.dspState.isEmergencyMuted = false
                self?.safetyTripNotified = false
            }
            didTripFeedbackProtection = false
        }
    }

    func clearSafetyTripMute() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.feedbackGuard.reset()
            self.dspState.isEmergencyMuted = false
            self.safetyTripNotified = false
        }
        didTripFeedbackProtection = false
    }

    /// Rebuild when the user switches physical output (headphones, AirPods, etc.).
    func rebuildAggregateWithCurrentOutput() {
        guard isRunning, tapID != kAudioObjectUnknown, !isRebuilding else { return }

        let currentDefault: AudioDeviceID
        do {
            currentDefault = try getDefaultOutputDeviceID()
        } catch {
            logger.error("Could not read default output during rebuild: \(error.localizedDescription)")
            return
        }

        // Ignore our private aggregate if it somehow became default (legacy bug recovery).
        if currentDefault == aggDeviceID {
            if physicalOutputID != kAudioObjectUnknown {
                try? setDefaultOutput(physicalOutputID)
            }
            return
        }

        // Same physical device — nothing to rebuild.
        if currentDefault == physicalOutputID {
            return
        }

        isRebuilding = true
        logger.info("Rebuilding aggregate for new physical output \(currentDefault)")

        stopAggIO()
        destroyAggregate()

        do {
            physicalOutputID = currentDefault
            refreshPhysicalOutputMetadata()
            try setupAggregateWithOutput()
            try startAggIO()
            latencyEstimate = estimateLatency()
            isRebuilding = false
            publishStatus(.running)
            onPhysicalOutputChanged?(physicalOutputUID, physicalOutputName)
            logger.info("Aggregate device rebuilt with new output \(physicalOutputName ?? "?")")
        } catch {
            isRebuilding = false
            logger.error("Rebuild failed: \(error.localizedDescription)")
            cleanup()
            isRunning = false
            latencyEstimate = nil
            publishStatus(.failed("Device change failed: \(error.localizedDescription)"))
        }
    }

    // MARK: - Setup

    @available(macOS 14.2, *)
    private func setupTap() throws {
        // Mute tapped processes at their destination (physical default) so we do not
        // hear dry + wet. Processed audio is played via the aggregate IOProc instead.
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.name = "OpenEQ System Audio"
        desc.isPrivate = true
        desc.muteBehavior = .muted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let err = AudioHardwareCreateProcessTap(desc, &newTapID)
        guard err == noErr else {
            throw SystemAudioEQError.tapCreateFailed(err)
        }
        tapID = newTapID

        let tapFormat = try getTapFormat()
        sampleRate = tapFormat.mSampleRate > 0 ? tapFormat.mSampleRate : 48_000
        channelCount = max(1, tapFormat.mChannelsPerFrame)
        logger.info(
            "Tap created, rate: \(sampleRate), channels: \(channelCount), flags: \(tapFormat.mFormatFlags)"
        )
    }

    private func setupAggregateWithOutput() throws {
        guard physicalOutputID != kAudioObjectUnknown else {
            throw SystemAudioEQError.failed("No physical output device")
        }

        let outputUID = try getDeviceUID(physicalOutputID)
        let tapUID = try getTapUID()
        let aggUID = "com.openeq.agg.\(UUID().uuidString)"

        // Physical device is the only output subdevice and the clock master.
        // Process tap is attached as a tap source (input streams on the aggregate).
        let subDevices: [[String: Any]] = [
            [
                kAudioSubDeviceUIDKey: outputUID,
                kAudioSubDeviceInputChannelsKey: 0,
                // Prefer full duplex channel use from the physical device as output.
            ]
        ]

        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "OpenEQ Engine",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
        ]

        var newAggID = AudioObjectID(kAudioObjectUnknown)
        let err = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &newAggID)
        guard err == noErr else { throw SystemAudioEQError.failed("Create aggregate: \(err)") }
        aggDeviceID = newAggID
        // Attach process tap after create (array of tap UIDs) — most reliable path.
        try setTapList(tapUID)

        // Align aggregate sample rate with the tap / physical device when possible.
        try? setDeviceSampleRate(aggDeviceID, sampleRate)

        logger.info("Aggregate created with physical output \(outputUID) + tap")
    }

    private func setTapList(_ tapUID: CFString) throws {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var list: CFArray? = [tapUID] as CFArray
        let err = withUnsafeMutablePointer(to: &list) { ptr in
            AudioObjectSetPropertyData(
                aggDeviceID,
                &addr,
                UInt32(0),
                nil,
                UInt32(MemoryLayout<CFArray>.size),
                ptr
            )
        }
        guard err == noErr else { throw SystemAudioEQError.failed("Set tap list: \(err)") }
    }

    private func startAggIO() throws {
        var procID: AudioDeviceIOProcID?
        let err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggDeviceID, ioQueue) {
            [weak self] (_, inInputData, _, outOutputData, _) in
            guard let self else { return }
            self.handleIO(inData: inInputData, outData: outOutputData)
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

    private func handleIO(
        inData: UnsafePointer<AudioBufferList>,
        outData: UnsafeMutablePointer<AudioBufferList>
    ) {
        let inBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
        let outBuffers = UnsafeMutableAudioBufferListPointer(outData)

        for buffer in outBuffers {
            guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
            memset(data, 0, Int(buffer.mDataByteSize))
        }

        guard !inBuffers.isEmpty,
              let firstIn = inBuffers.first,
              firstIn.mData != nil,
              firstIn.mDataByteSize > 0 else {
            return
        }

        let inNonInterleaved = isNonInterleaved(inBuffers)
        let outNonInterleaved = isNonInterleaved(outBuffers)

        if inNonInterleaved && outNonInterleaved {
            processNonInterleaved(inBuffers: inBuffers, outBuffers: outBuffers)
        } else if !inNonInterleaved && !outNonInterleaved {
            processInterleaved(inBuffers: inBuffers, outBuffers: outBuffers)
        } else if inNonInterleaved && !outNonInterleaved {
            processNonInterleavedToInterleaved(inBuffers: inBuffers, outBuffers: outBuffers)
        } else {
            processInterleavedToNonInterleaved(inBuffers: inBuffers, outBuffers: outBuffers)
        }

        // Spectrum (best-effort, post-fill).
        if let outFirst = outBuffers.first,
           outFirst.mData != nil,
           outFirst.mDataByteSize > 0 {
            let channels = max(1, Int(outFirst.mNumberChannels))
            let frames = Int(outFirst.mDataByteSize) / (MemoryLayout<Float>.size * (outNonInterleaved ? 1 : channels))
            if frames > 0,
               let analysis = analyzer.analyze(bufferList: outData, frameLength: frames, sampleRate: sampleRate) {
                DispatchQueue.main.async { [weak self] in self?.onAnalysis?(analysis) }
            }
        }
    }

    private func isNonInterleaved(_ buffers: UnsafeMutableAudioBufferListPointer) -> Bool {
        if buffers.count > 1 { return true }
        guard let first = buffers.first else { return true }
        return first.mNumberChannels <= 1
    }

    private func processNonInterleaved(
        inBuffers: UnsafeMutableAudioBufferListPointer,
        outBuffers: UnsafeMutableAudioBufferListPointer
    ) {
        let channels = min(inBuffers.count, outBuffers.count, max(1, Int(channelCount)))
        var primaryFrames = 0

        for channel in 0..<channels {
            guard let inputData = inBuffers[channel].mData,
                  let outputData = outBuffers[channel].mData else { continue }
            let copyBytes = min(inBuffers[channel].mDataByteSize, outBuffers[channel].mDataByteSize)
            let frames = Int(copyBytes) / MemoryLayout<Float>.size
            guard frames > 0 else { continue }

            let source = inputData.assumingMemoryBound(to: Float.self)
            let destination = outputData.assumingMemoryBound(to: Float.self)
            memcpy(destination, source, Int(copyBytes))
            dspState.process(destination, frames: frames, channel: channel)
            if channel == 0 { primaryFrames = frames }
        }

        applyFeedbackGuard(outBuffers: outBuffers, nonInterleaved: true, frames: primaryFrames)
    }

    private func processInterleaved(
        inBuffers: UnsafeMutableAudioBufferListPointer,
        outBuffers: UnsafeMutableAudioBufferListPointer
    ) {
        guard let inData = inBuffers.first?.mData,
              let outData = outBuffers.first?.mData else { return }

        let inChannels = max(1, Int(inBuffers[0].mNumberChannels))
        let outChannels = max(1, Int(outBuffers[0].mNumberChannels))
        let channels = min(inChannels, outChannels, 2)
        let inFrames = Int(inBuffers[0].mDataByteSize) / (MemoryLayout<Float>.size * inChannels)
        let outFrames = Int(outBuffers[0].mDataByteSize) / (MemoryLayout<Float>.size * outChannels)
        let frames = min(inFrames, outFrames)
        guard frames > 0 else { return }

        ensureScratch(frames: frames, channels: channels)
        let source = inData.assumingMemoryBound(to: Float.self)
        let destination = outData.assumingMemoryBound(to: Float.self)

        for channel in 0..<channels {
            guard let scratch = deinterleaveScratch[channel] else { continue }
            for frame in 0..<frames {
                scratch[frame] = source[frame * inChannels + channel]
            }
            dspState.process(scratch, frames: frames, channel: channel)
        }

        for channel in 0..<channels {
            guard let scratch = deinterleaveScratch[channel] else { continue }
            for frame in 0..<frames {
                destination[frame * outChannels + channel] = scratch[frame]
            }
        }

        applyFeedbackGuard(outBuffers: outBuffers, nonInterleaved: false, frames: frames)
    }

    private func processNonInterleavedToInterleaved(
        inBuffers: UnsafeMutableAudioBufferListPointer,
        outBuffers: UnsafeMutableAudioBufferListPointer
    ) {
        guard let outData = outBuffers.first?.mData else { return }
        let outChannels = max(1, Int(outBuffers[0].mNumberChannels))
        let channels = min(inBuffers.count, outChannels, 2)
        let frames = Int(inBuffers[0].mDataByteSize) / MemoryLayout<Float>.size
        let outFrames = Int(outBuffers[0].mDataByteSize) / (MemoryLayout<Float>.size * outChannels)
        let n = min(frames, outFrames)
        guard n > 0 else { return }

        ensureScratch(frames: n, channels: channels)
        let destination = outData.assumingMemoryBound(to: Float.self)

        for channel in 0..<channels {
            guard let inputData = inBuffers[channel].mData,
                  let scratch = deinterleaveScratch[channel] else { continue }
            memcpy(scratch, inputData, n * MemoryLayout<Float>.size)
            dspState.process(scratch, frames: n, channel: channel)
        }

        for channel in 0..<channels {
            guard let scratch = deinterleaveScratch[channel] else { continue }
            for frame in 0..<n {
                destination[frame * outChannels + channel] = scratch[frame]
            }
        }

        applyFeedbackGuard(outBuffers: outBuffers, nonInterleaved: false, frames: n)
    }

    private func processInterleavedToNonInterleaved(
        inBuffers: UnsafeMutableAudioBufferListPointer,
        outBuffers: UnsafeMutableAudioBufferListPointer
    ) {
        guard let inData = inBuffers.first?.mData else { return }
        let inChannels = max(1, Int(inBuffers[0].mNumberChannels))
        let channels = min(outBuffers.count, inChannels, 2)
        let frames = Int(inBuffers[0].mDataByteSize) / (MemoryLayout<Float>.size * inChannels)
        guard frames > 0 else { return }

        let source = inData.assumingMemoryBound(to: Float.self)
        for channel in 0..<channels {
            guard let outputData = outBuffers[channel].mData else { continue }
            let outFrames = Int(outBuffers[channel].mDataByteSize) / MemoryLayout<Float>.size
            let n = min(frames, outFrames)
            let destination = outputData.assumingMemoryBound(to: Float.self)
            for frame in 0..<n {
                destination[frame] = source[frame * inChannels + channel]
            }
            dspState.process(destination, frames: n, channel: channel)
        }

        let primaryFrames = Int(outBuffers.first?.mDataByteSize ?? 0) / MemoryLayout<Float>.size
        applyFeedbackGuard(outBuffers: outBuffers, nonInterleaved: true, frames: primaryFrames)
    }

    private func applyFeedbackGuard(
        outBuffers: UnsafeMutableAudioBufferListPointer,
        nonInterleaved: Bool,
        frames: Int
    ) {
        guard feedbackProtectionEnabled, frames > 0 else {
            if dspState.isEmergencyMuted {
                silence(outBuffers)
            }
            return
        }

        if dspState.isEmergencyMuted {
            silence(outBuffers)
            return
        }

        guard let first = outBuffers.first?.mData else { return }
        let samples = first.assumingMemoryBound(to: Float.self)
        let evalFrames: Int
        if nonInterleaved {
            evalFrames = frames
        } else {
            let ch = max(1, Int(outBuffers[0].mNumberChannels))
            evalFrames = frames * ch
        }

        if feedbackGuard.evaluate(samples: samples, frames: min(evalFrames, frames)) {
            dspState.isEmergencyMuted = true
            silence(outBuffers)
            if !safetyTripNotified {
                safetyTripNotified = true
                DispatchQueue.main.async { [weak self] in
                    self?.didTripFeedbackProtection = true
                    self?.onSafetyTrip?()
                }
            }
        }
    }

    private func silence(_ outBuffers: UnsafeMutableAudioBufferListPointer) {
        for buffer in outBuffers {
            guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
            memset(data, 0, Int(buffer.mDataByteSize))
        }
    }

    private func ensureScratch(frames: Int, channels: Int) {
        if frames <= deinterleaveCapacity, deinterleaveScratch[0] != nil { return }
        freeScratch()
        deinterleaveCapacity = max(frames, 2048)
        for channel in 0..<min(channels, 2) {
            deinterleaveScratch[channel] = .allocate(capacity: deinterleaveCapacity)
        }
    }

    private func freeScratch() {
        for index in deinterleaveScratch.indices {
            deinterleaveScratch[index]?.deallocate()
            deinterleaveScratch[index] = nil
        }
        deinterleaveCapacity = 0
    }

    // MARK: - Default output observation

    private func handleDefaultOutputChanged() {
        guard isRunning, !isRebuilding else { return }
        ioQueue.async { [weak self] in
            DispatchQueue.main.async {
                self?.rebuildAggregateWithCurrentOutput()
            }
        }
    }

    private func startObservingDefaultOutput() {
        guard !isObservingDefaultOutput else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectAddPropertyListenerBlock(
            kOpenEQSysObj,
            &address,
            ioQueue,
            defaultOutputListener
        )
        if status == noErr {
            isObservingDefaultOutput = true
        } else {
            logger.warning("Could not observe default output changes: \(status)")
        }
    }

    private func stopObservingDefaultOutput() {
        guard isObservingDefaultOutput else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            kOpenEQSysObj,
            &address,
            ioQueue,
            defaultOutputListener
        )
        isObservingDefaultOutput = false
    }

    // MARK: - Helpers

    private func estimateLatency() -> TimeInterval {
        Double(1024) / max(sampleRate, 1) * 3
    }

    private func refreshPhysicalOutputMetadata() {
        physicalOutputUID = try? getDeviceUID(physicalOutputID)
        physicalOutputName = try? getDeviceName(physicalOutputID)
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) throws -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let ptr = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        ptr.initialize(to: nil)
        defer {
            ptr.deinitialize(count: 1)
            ptr.deallocate()
        }
        var size = UInt32(MemoryLayout<CFString?>.size)
        let err = AudioObjectGetPropertyData(deviceID, &addr, UInt32(0), nil, &size, ptr)
        guard err == noErr, let name = ptr.pointee as String? else {
            throw SystemAudioEQError.failed("Get device name: \(err)")
        }
        return name
    }

    private func publishStatus(_ newStatus: SystemAudioStatus) {
        status = newStatus
        onStatusChanged?(newStatus)
    }

    private func mapStartError(_ error: Error) -> SystemAudioStatus {
        if let eqError = error as? SystemAudioEQError {
            switch eqError {
            case .tapCreateFailed(let code):
                if code == -1 || code == kAudioHardwareIllegalOperationError || code == kAudioHardwareNotRunningError {
                    return .permissionRequired
                }
                return .failed(eqError.localizedDescription)
            case .failed(let message):
                if message.localizedCaseInsensitiveContains("permission")
                    || message.localizedCaseInsensitiveContains("denied") {
                    return .permissionRequired
                }
                return .failed(message)
            }
        }
        return .failed(error.localizedDescription)
    }

    private func getTapUID() throws -> CFString {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let ptr = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        ptr.initialize(to: nil)
        defer {
            ptr.deinitialize(count: 1)
            ptr.deallocate()
        }
        var size = UInt32(MemoryLayout<CFString?>.size)
        let err = AudioObjectGetPropertyData(tapID, &addr, UInt32(0), nil, &size, ptr)
        guard err == noErr, let uid = ptr.pointee else {
            throw SystemAudioEQError.failed("Get tap UID: \(err)")
        }
        return uid
    }

    private func getTapFormat() throws -> AudioStreamBasicDescription {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var fmt = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let err = AudioObjectGetPropertyData(tapID, &addr, UInt32(0), nil, &size, &fmt)
        guard err == noErr else { throw SystemAudioEQError.failed("Get tap format: \(err)") }
        return fmt
    }

    private func getDefaultOutputDeviceID() throws -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var outID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let err = AudioObjectGetPropertyData(kOpenEQSysObj, &addr, UInt32(0), nil, &size, &outID)
        guard err == noErr, outID != kAudioObjectUnknown else {
            throw SystemAudioEQError.failed("No output device")
        }
        return outID
    }

    private func getDeviceUID(_ deviceID: AudioDeviceID) throws -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let ptr = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        ptr.initialize(to: nil)
        defer {
            ptr.deinitialize(count: 1)
            ptr.deallocate()
        }
        var size = UInt32(MemoryLayout<CFString?>.size)
        let err = AudioObjectGetPropertyData(deviceID, &addr, UInt32(0), nil, &size, ptr)
        guard err == noErr, let uid = ptr.pointee else {
            throw SystemAudioEQError.failed("Get device UID: \(err)")
        }
        return uid as String
    }

    private func setDefaultOutput(_ deviceID: AudioDeviceID) throws {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = deviceID
        let err = AudioObjectSetPropertyData(
            kOpenEQSysObj,
            &addr,
            UInt32(0),
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &id
        )
        guard err == noErr else { throw SystemAudioEQError.failed("Set default output: \(err)") }
    }

    private func setDeviceSampleRate(_ deviceID: AudioDeviceID, _ rate: Double) throws {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = Float64(rate)
        let err = AudioObjectSetPropertyData(
            deviceID,
            &addr,
            0,
            nil,
            UInt32(MemoryLayout<Float64>.size),
            &value
        )
        if err != noErr {
            logger.warning("Could not set aggregate sample rate to \(rate): \(err)")
        }
    }

    // MARK: - Cleanup

    private func stopAggIO() {
        if let procID = aggIOProcID, aggDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggDeviceID, procID)
        }
        aggIOProcID = nil
    }

    private func destroyAggregate() {
        if aggDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggDeviceID)
            aggDeviceID = kAudioObjectUnknown
        }
    }

    private func destroyTap() {
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    private func cleanup() {
        // Recover if a previous buggy build left our aggregate as the system default.
        if let defaultID = try? getDefaultOutputDeviceID(),
           defaultID == aggDeviceID,
           physicalOutputID != kAudioObjectUnknown {
            try? setDefaultOutput(physicalOutputID)
        }
        stopAggIO()
        destroyAggregate()
        destroyTap()
        physicalOutputID = kAudioObjectUnknown
    }
}

enum SystemAudioEQError: LocalizedError {
    case failed(String)
    case tapCreateFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return "System EQ: \(message)"
        case .tapCreateFailed(let code):
            return "System EQ: Could not create process tap (OSStatus \(code)). Grant Screen & System Audio Recording permission in System Settings."
        }
    }
}

// MARK: - DSP

private struct BiquadCoefficients {
    let b0: Float
    let b1: Float
    let b2: Float
    let a1: Float
    let a2: Float

    static let identity = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    var isIdentity: Bool {
        b0 == 1 && b1 == 0 && b2 == 0 && a1 == 0 && a2 == 0
    }

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

enum SystemAudioLimiter {
    static let ceiling: Float = 0.98
    static let attack: Float = 0.35
    static let release: Float = 0.0025
}

private final class SystemAudioDSPState {
    private var smoothingCoeffs = Array(repeating: SmoothingCoefficients(), count: 31)
    private var leftStates = Array(repeating: BiquadState(), count: 31)
    private var rightStates = Array(repeating: BiquadState(), count: 31)
    private var currentInterpolated: [BiquadCoefficients] = Array(repeating: .identity, count: 31)
    private var preampLinear: Float = 1
    private var targetPreampLinear: Float = 1
    private var leftLimiterGain: Float = 1
    private var rightLimiterGain: Float = 1
    var isBypassed = false
    var isEmergencyMuted = false

    func configure(_ preset: EQPreset, sampleRate: Double) {
        targetPreampLinear = pow(10, preset.preamp / 20)

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
        targetPreampLinear = 1
        leftLimiterGain = 1
        rightLimiterGain = 1
        isBypassed = false
        isEmergencyMuted = false
        smoothingCoeffs = Array(repeating: SmoothingCoefficients(), count: 31)
        currentInterpolated = Array(repeating: .identity, count: 31)
        leftStates = Array(repeating: BiquadState(), count: 31)
        rightStates = Array(repeating: BiquadState(), count: 31)
    }

    func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channel: Int) {
        if isEmergencyMuted {
            memset(samples, 0, frames * MemoryLayout<Float>.size)
            return
        }
        guard !isBypassed else { return }

        if channel == 0 {
            let preampDelta = targetPreampLinear - preampLinear
            if abs(preampDelta) > 0.00001 {
                preampLinear += preampDelta * min(1, Float(frames) / 256)
            } else {
                preampLinear = targetPreampLinear
            }

            currentInterpolated = smoothingCoeffs.indices.map { smoothingCoeffs[$0].interpolatedCoeffs() }
            for i in smoothingCoeffs.indices {
                smoothingCoeffs[i].advance(frames: frames)
            }
        }

        if abs(preampLinear - 1) > 0.0001 {
            var gain = preampLinear
            vDSP_vsmul(samples, 1, &gain, samples, 1, vDSP_Length(frames))
        }

        if channel == 0 {
            processFilters(samples, frames: frames, states: &leftStates)
            applyPeakLimiter(samples, frames: frames, gain: &leftLimiterGain)
        } else {
            processFilters(samples, frames: frames, states: &rightStates)
            applyPeakLimiter(samples, frames: frames, gain: &rightLimiterGain)
        }
    }

    private func processFilters(
        _ samples: UnsafeMutablePointer<Float>,
        frames: Int,
        states: inout [BiquadState]
    ) {
        for band in currentInterpolated.indices {
            let coeff = currentInterpolated[band]
            if coeff.isIdentity { continue }

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

    private func applyPeakLimiter(
        _ samples: UnsafeMutablePointer<Float>,
        frames: Int,
        gain: inout Float
    ) {
        let ceiling = SystemAudioLimiter.ceiling
        for index in 0..<frames {
            let absSample = abs(samples[index])
            let needed = absSample > ceiling ? ceiling / absSample : 1
            if needed < gain {
                gain += (needed - gain) * SystemAudioLimiter.attack
            } else {
                gain += (1 - gain) * SystemAudioLimiter.release
            }
            var out = samples[index] * gain
            if out > 1 { out = 1 }
            if out < -1 { out = -1 }
            samples[index] = out
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
                a1: 2 * ((amplitude - 1) + (amplitude + 1) * cosine),
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
