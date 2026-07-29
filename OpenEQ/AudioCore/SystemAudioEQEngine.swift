import AVFoundation
import CoreAudio
import Accelerate
import CoreGraphics
import Darwin

let kOpenEQSysObj = AudioObjectID(kAudioObjectSystemObject)
private let kOpenEQAggregateUID = "com.openeq.system-eq.aggregate"

final class SystemAudioEQEngine {
    private(set) var status: SystemAudioStatus = .stopped
    private(set) var latencyEstimate: TimeInterval?
    private(set) var physicalOutputUID: String?
    private(set) var physicalOutputName: String?
    private(set) var didTripFeedbackProtection = false
    /// True once IOProc has seen non-silent tap audio (for diagnostics/UI).
    private(set) var isReceivingTapAudio = false
    private(set) var lastSetupDetail: String?

    var onAnalysis: ((SpectrumAnalysis) -> Void)?
    var onStatusChanged: ((SystemAudioStatus) -> Void)?
    var onSafetyTrip: (() -> Void)?
    var onPhysicalOutputChanged: ((String?, String?) -> Void)?

    private let analyzer = SpectrumAnalyzer()
    private let logger = AppLogger(category: "SystemAudioEQ")

    private let ioQueue = DispatchQueue(label: "com.openeq.system-audio-eq.io", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var tapUUIDString: String?
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
    private var ioCallbackCount: UInt64 = 0
    private var ioFramesWithSignal: UInt64 = 0
    private var healthCheckWorkItem: DispatchWorkItem?
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
            // Ensure Screen/System Audio Recording is requested. Do NOT treat every
            // Core Audio "nope" as a permission failure — that blocks real diagnosis.
            try ensureScreenCaptureAccess()

            physicalOutputID = try getDefaultOutputDeviceID()
            // Never nest our own aggregate as the physical destination.
            if isOpenEQAggregate(physicalOutputID) {
                throw SystemAudioEQError.failed(
                    "System output is already OpenEQ. Stop System EQ or pick Speakers/Headphones in Sound settings."
                )
            }
            refreshPhysicalOutputMetadata()

            destroyStaleAggregateIfNeeded()
            try setupTap()
            ioQueue.sync {
                dspState.configure(preset, sampleRate: sampleRate)
                feedbackGuard.reset()
                safetyTripNotified = false
                didTripFeedbackProtection = false
                dspState.isEmergencyMuted = false
                ioCallbackCount = 0
                ioFramesWithSignal = 0
            }
            isReceivingTapAudio = false
            try setupAggregateWithOutput()
            try startAggIO()
            // Public aggregate can be the system default so other apps render into it.
            try setDefaultOutput(aggDeviceID)
            startObservingDefaultOutput()
            scheduleHealthCheck()
            isRunning = true
            latencyEstimate = estimateLatency()
            lastSetupDetail = "tap+aggregate → \(physicalOutputName ?? "output") @ \(Int(sampleRate)) Hz"
            publishStatus(.running)
            logger.info("System-wide EQ started: \(lastSetupDetail ?? "")")
        } catch {
            cleanup(restoreOutput: true)
            let mapped = mapStartError(error)
            publishStatus(mapped)
            lastSetupDetail = mapped.title
            logger.error("Start failed: \(mapped.title)")
        }
    }

    func stop() {
        healthCheckWorkItem?.cancel()
        healthCheckWorkItem = nil
        stopObservingDefaultOutput()
        cleanup(restoreOutput: true)
        ioQueue.sync {
            dspState.reset()
            feedbackGuard.reset()
            safetyTripNotified = false
            ioCallbackCount = 0
            ioFramesWithSignal = 0
        }
        isRunning = false
        isRebuilding = false
        isReceivingTapAudio = false
        latencyEstimate = nil
        physicalOutputUID = nil
        physicalOutputName = nil
        didTripFeedbackProtection = false
        lastSetupDetail = nil
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

    func rebuildAggregateWithCurrentOutput() {
        guard isRunning, tapID != kAudioObjectUnknown, !isRebuilding else { return }

        let currentDefault: AudioDeviceID
        do {
            currentDefault = try getDefaultOutputDeviceID()
        } catch {
            logger.error("Could not read default output during rebuild: \(error.localizedDescription)")
            return
        }

        if currentDefault == aggDeviceID {
            return
        }

        if currentDefault == physicalOutputID {
            try? setDefaultOutput(aggDeviceID)
            return
        }

        if isOpenEQAggregate(currentDefault) {
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
            try setDefaultOutput(aggDeviceID)
            latencyEstimate = estimateLatency()
            isRebuilding = false
            publishStatus(.running)
            onPhysicalOutputChanged?(physicalOutputUID, physicalOutputName)
            logger.info("Aggregate rebuilt → \(physicalOutputName ?? "?")")
        } catch {
            isRebuilding = false
            logger.error("Rebuild failed: \(error.localizedDescription)")
            cleanup(restoreOutput: true)
            isRunning = false
            latencyEstimate = nil
            publishStatus(.failed("Device change failed: \(error.localizedDescription)"))
        }
    }

    // MARK: - Setup

    @available(macOS 14.2, *)
    private func setupTap() throws {
        // Same constructor as the working CoreAudioTapManager monitor path.
        // Exclude OpenEQ only when we can resolve our process object reliably.
        var exclude: [AudioObjectID] = []
        if let selfProcess = try? processObjectID(forPID: getpid()),
           selfProcess != kAudioObjectUnknown {
            exclude.append(selfProcess)
        }

        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: exclude)
        desc.name = "OpenEQ System Audio"
        desc.isPrivate = true
        // Mute dry path only while the aggregate is reading the tap.
        desc.muteBehavior = .mutedWhenTapped

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let err = AudioHardwareCreateProcessTap(desc, &newTapID)
        guard err == noErr else {
            throw SystemAudioEQError.tapCreateFailed(err)
        }
        tapID = newTapID

        // Always use the live tap UID from HAL (not the description's pre-create UUID).
        let liveUID = try getTapUID() as String
        tapUUIDString = liveUID

        let tapFormat = try getTapFormat()
        sampleRate = tapFormat.mSampleRate > 0 ? tapFormat.mSampleRate : 48_000
        channelCount = max(1, tapFormat.mChannelsPerFrame)
        logger.info(
            "Tap ready uid=\(liveUID) rate=\(sampleRate) ch=\(channelCount) flags=\(tapFormat.mFormatFlags)"
        )
    }

    private func setupAggregateWithOutput() throws {
        guard physicalOutputID != kAudioObjectUnknown else {
            throw SystemAudioEQError.failed("No physical output device")
        }
        guard let tapUUIDString else {
            throw SystemAudioEQError.failed("Missing tap UUID")
        }

        let outputUID = try getDeviceUID(physicalOutputID)
        let subDevices: [[String: Any]] = [
            [kAudioSubDeviceUIDKey: outputUID]
        ]

        // Match the known-working monitor path: create aggregate first, then attach
        // the tap via kAudioAggregateDevicePropertyTapList as CFArray of UID strings.
        // (Create-time "taps" dictionaries are flaky across macOS builds.)
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "OpenEQ",
            kAudioAggregateDeviceUIDKey: kOpenEQAggregateUID,
            // Private aggregates can still be set as default by object ID and avoid
            // cluttering Sound prefs for other users of the machine.
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
        ]

        var newAggID = AudioObjectID(kAudioObjectUnknown)
        let err = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &newAggID)
        guard err == noErr else {
            throw SystemAudioEQError.failed(
                "Create aggregate failed (\(err) / \(fourCC(err)))."
            )
        }
        aggDeviceID = newAggID

        try setTapListProperty(tapUUIDString)

        // Optional create-time style dict attach if UID-string attach left no sub-taps.
        if !hasActiveSubTaps() {
            logger.warning("UID tap list produced no sub-taps; trying dictionary composition")
            try setTapListViaComposition(tapUUIDString, outputUID: outputUID)
        }

        try? setDeviceSampleRate(aggDeviceID, sampleRate)

        let inputCh = (try? streamChannelCount(device: aggDeviceID, scope: kAudioDevicePropertyScopeInput)) ?? 0
        let outputCh = (try? streamChannelCount(device: aggDeviceID, scope: kAudioDevicePropertyScopeOutput)) ?? 0
        let subTaps = activeSubTapCount()
        logger.info("Aggregate id=\(aggDeviceID) inCh=\(inputCh) outCh=\(outputCh) subTaps=\(subTaps)")

        // StreamConfiguration often reports 0 input channels for tap-backed aggregates
        // until IO is started — do NOT hard-fail on inCh. Fail only if sub-tap attach failed.
        if subTaps == 0 && inputCh == 0 {
            throw SystemAudioEQError.failed(
                "Could not attach process tap to aggregate (no sub-taps). Toggle Screen & System Audio Recording for OpenEQ off/on, then Retry Start."
            )
        }
        if outputCh == 0 {
            throw SystemAudioEQError.failed(
                "Aggregate has no output to \(physicalOutputName ?? "the selected device"). Pick Speakers/Headphones in Sound settings and retry."
            )
        }
    }

    private func setTapListProperty(_ tapUUID: String) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // Identical pattern to CoreAudioTapManager (known working for process taps).
        var tapList = [tapUUID as CFString] as CFArray
        let dataSize = UInt32(MemoryLayout<CFArray>.size)
        let status = withUnsafePointer(to: &tapList) { pointer in
            AudioObjectSetPropertyData(
                aggDeviceID,
                &address,
                0,
                nil,
                dataSize,
                pointer
            )
        }
        guard status == noErr else {
            throw SystemAudioEQError.failed("Set tap list failed (\(status) / \(fourCC(status)))")
        }
    }

    /// Rebuild composition with explicit subdevice + tap dictionaries.
    private func setTapListViaComposition(_ tapUUID: String, outputUID: String) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyComposition,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "OpenEQ",
            kAudioAggregateDeviceUIDKey: kOpenEQAggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUUID]
            ],
            kAudioAggregateDeviceTapAutoStartKey: 1,
        ]
        var dict = composition as CFDictionary
        let status = withUnsafePointer(to: &dict) { pointer in
            AudioObjectSetPropertyData(
                aggDeviceID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<CFDictionary>.size),
                pointer
            )
        }
        if status != noErr {
            logger.warning("Composition update failed (\(status) / \(fourCC(status)))")
        }
    }

    private func activeSubTapCount() -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertySubTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(aggDeviceID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return 0 }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(aggDeviceID, &address, 0, nil, &dataSize, &ids)
        guard status == noErr else { return 0 }
        return ids.filter { $0 != kAudioObjectUnknown }.count
    }

    private func hasActiveSubTaps() -> Bool {
        activeSubTapCount() > 0
    }

    private func startAggIO() throws {
        var procID: AudioDeviceIOProcID?
        let err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggDeviceID, ioQueue) {
            [weak self] _, inInputData, _, outOutputData, _ in
            self?.handleIO(inData: inInputData, outData: outOutputData)
        }
        guard err == noErr, let procID else {
            throw SystemAudioEQError.failed("Create IOProc: \(err) (\(fourCC(err)))")
        }
        aggIOProcID = procID

        let startStatus = AudioDeviceStart(aggDeviceID, procID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(aggDeviceID, procID)
            aggIOProcID = nil
            throw SystemAudioEQError.failed(
                "Start IOProc failed (\(startStatus) / \(fourCC(startStatus))). Another audio driver may be blocking the device (Boom/DeskFx). HAL also said: there already is a thread."
            )
        }
    }

    private func scheduleHealthCheck() {
        healthCheckWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            let callbacks = self.ioQueue.sync { self.ioCallbackCount }
            let signal = self.ioQueue.sync { self.ioFramesWithSignal }
            self.logger.info("Health: callbacks=\(callbacks) signalBuffers=\(signal)")
            if callbacks == 0 {
                self.lastSetupDetail = "IOProc never called — HAL plugin conflict likely (Boom/DeskFx)."
                self.logger.error(self.lastSetupDetail ?? "")
            } else if signal == 0 {
                self.lastSetupDetail = "IOProc running but tap is silent. Grant Screen & System Audio Recording, play audio from another app, or disable Boom."
                self.logger.error(self.lastSetupDetail ?? "")
            } else {
                self.isReceivingTapAudio = true
            }
        }
        healthCheckWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    // MARK: - IO

    private func handleIO(
        inData: UnsafePointer<AudioBufferList>,
        outData: UnsafeMutablePointer<AudioBufferList>
    ) {
        ioCallbackCount &+= 1
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

        // Quick energy probe for health diagnostics.
        if let data = firstIn.mData {
            let frames = Int(firstIn.mDataByteSize) / MemoryLayout<Float>.size
            let samples = data.assumingMemoryBound(to: Float.self)
            var energy: Float = 0
            let probe = min(frames, 64)
            for i in 0..<probe { energy += abs(samples[i]) }
            if energy > 0.0001 {
                ioFramesWithSignal &+= 1
                if !isReceivingTapAudio {
                    DispatchQueue.main.async { [weak self] in self?.isReceivingTapAudio = true }
                }
            }
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
            memcpy(outputData, inputData, Int(copyBytes))
            let destination = outputData.assumingMemoryBound(to: Float.self)
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
        if dspState.isEmergencyMuted {
            silence(outBuffers)
            return
        }
        guard feedbackProtectionEnabled, frames > 0 else { return }
        guard let first = outBuffers.first?.mData else { return }
        let samples = first.assumingMemoryBound(to: Float.self)
        let sampleCount = nonInterleaved ? frames : frames * max(1, Int(outBuffers[0].mNumberChannels))
        if feedbackGuard.evaluate(samples: samples, frames: sampleCount) {
            dspState.isEmergencyMuted = true
            silence(outBuffers)
            if !safetyTripNotified {
                safetyTripNotified = true
                logger.warning("Feedback protection tripped")
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
        isObservingDefaultOutput = (status == noErr)
        if status != noErr {
            logger.warning("Could not observe default output: \(status)")
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

    private func fourCC(_ status: OSStatus) -> String {
        let v = UInt32(bitPattern: status)
        let bytes = [
            UInt8((v >> 24) & 0xff),
            UInt8((v >> 16) & 0xff),
            UInt8((v >> 8) & 0xff),
            UInt8(v & 0xff)
        ]
        let s = String(bytes: bytes, encoding: .macOSRoman) ?? "\(status)"
        return s.unicodeScalars.allSatisfy { $0.isASCII && $0.value >= 32 } ? s : "\(status)"
    }

    private func publishStatus(_ newStatus: SystemAudioStatus) {
        status = newStatus
        onStatusChanged?(newStatus)
    }

    private func mapStartError(_ error: Error) -> SystemAudioStatus {
        if let eqError = error as? SystemAudioEQError {
            switch eqError {
            case .tapCreateFailed(let code):
                // Only map narrow cases. kAudioHardwareIllegalOperationError ('nope') is
                // returned for many non-permission failures (HAL conflicts, bad property sets).
                if code == Int32(tccDeniedHint) {
                    return .permissionRequired
                }
                return .failed(
                    "Process tap create failed (OSStatus \(code) / \(fourCC(code))). If permission is already on, check Sound output and remove conflicting HAL plugins."
                )
            case .failed(let message):
                // Explicit permission probe only — not every message that mentions the word.
                if message.hasPrefix("PERMISSION:") {
                    return .permissionRequired
                }
                return .failed(message)
            }
        }
        return .failed(error.localizedDescription)
    }

    /// TCC-style denial sometimes surfaces as this value on some systems.
    private var tccDeniedHint: Int32 { -6700 }

    private func ensureScreenCaptureAccess() throws {
        // Process taps share Screen & System Audio Recording TCC on modern macOS.
        if CGPreflightScreenCaptureAccess() {
            return
        }
        let requested = CGRequestScreenCaptureAccess()
        if requested || CGPreflightScreenCaptureAccess() {
            return
        }
        throw SystemAudioEQError.failed(
            "PERMISSION: Screen & System Audio Recording is off for OpenEQ. Enable it in System Settings → Privacy & Security, then click Start again."
        )
    }

    private func processObjectID(forPID pid: pid_t) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processID = AudioObjectID(kAudioObjectUnknown)
        var pidValue = pid
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let err = AudioObjectGetPropertyData(
            kOpenEQSysObj,
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pidValue,
            &size,
            &processID
        )
        guard err == noErr else {
            throw SystemAudioEQError.failed("Translate PID failed: \(err)")
        }
        return processID
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
        let err = AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, ptr)
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
        let err = AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &fmt)
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
        let err = AudioObjectGetPropertyData(kOpenEQSysObj, &addr, 0, nil, &size, &outID)
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
        let err = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, ptr)
        guard err == noErr, let uid = ptr.pointee else {
            throw SystemAudioEQError.failed("Get device UID: \(err)")
        }
        return uid as String
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
        let err = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, ptr)
        guard err == noErr, let name = ptr.pointee as String? else {
            throw SystemAudioEQError.failed("Get device name: \(err)")
        }
        return name
    }

    private func isOpenEQAggregate(_ deviceID: AudioDeviceID) -> Bool {
        (try? getDeviceUID(deviceID)) == kOpenEQAggregateUID
            || ((try? getDeviceName(deviceID))?.contains("OpenEQ") ?? false)
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
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &id
        )
        guard err == noErr else {
            throw SystemAudioEQError.failed(
                "Could not set default output (\(err) / \(fourCC(err))). Conflicting HAL plugins (Boom/DeskFx) often cause this."
            )
        }
    }

    private func setDeviceSampleRate(_ deviceID: AudioDeviceID, _ rate: Double) throws {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = Float64(rate)
        _ = AudioObjectSetPropertyData(
            deviceID,
            &addr,
            0,
            nil,
            UInt32(MemoryLayout<Float64>.size),
            &value
        )
    }

    private func streamChannelCount(device: AudioDeviceID, scope: AudioObjectPropertyScope) throws -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        status = AudioObjectGetPropertyData(device, &addr, 0, nil, &dataSize, raw)
        guard status == noErr else { return 0 }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func destroyStaleAggregateIfNeeded() {
        // Look up previous OpenEQ aggregate by stable UID and destroy it.
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var uid = kOpenEQAggregateUID as CFString
        let err = withUnsafeMutablePointer(to: &uid) { uidPtr in
            AudioObjectGetPropertyData(
                kOpenEQSysObj,
                &address,
                UInt32(MemoryLayout<CFString>.size),
                uidPtr,
                &size,
                &deviceID
            )
        }
        if err == noErr, deviceID != kAudioObjectUnknown {
            logger.info("Destroying stale OpenEQ aggregate \(deviceID)")
            AudioHardwareDestroyAggregateDevice(deviceID)
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
        tapUUIDString = nil
    }

    private func cleanup(restoreOutput: Bool = false) {
        if restoreOutput, physicalOutputID != kAudioObjectUnknown {
            try? setDefaultOutput(physicalOutputID)
        } else if let defaultID = try? getDefaultOutputDeviceID(),
                  (defaultID == aggDeviceID || isOpenEQAggregate(defaultID)),
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
            return "System EQ: Process tap create failed (OSStatus \(code))."
        }
    }
}

// MARK: - DSP (unchanged core)

private struct BiquadCoefficients {
    let b0: Float
    let b1: Float
    let b2: Float
    let a1: Float
    let a2: Float
    static let identity = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
    var isIdentity: Bool { b0 == 1 && b1 == 0 && b2 == 0 && a1 == 0 && a2 == 0 }

    static func normalized(b0: Float, b1: Float, b2: Float, a0: Float, a1: Float, a2: Float) -> BiquadCoefficients {
        let inv = 1 / a0
        return BiquadCoefficients(b0: b0 * inv, b1: b1 * inv, b2: b2 * inv, a1: a1 * inv, a2: a2 * inv)
    }
}

private struct SmoothingCoefficients {
    static let duration = 512
    private var current: BiquadCoefficients = .identity
    private var target: BiquadCoefficients = .identity
    private var remaining = 0

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

private enum SystemAudioLimiter {
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
                to: Self.makeCoefficients(for: preset.bands[index], sampleRate: Float(sampleRate))
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
