import AVFoundation
import CoreAudio
import Accelerate
import CoreGraphics
import Darwin

let kOpenEQSysObj = AudioObjectID(kAudioObjectSystemObject)
private let kOpenEQAggregateUID = "com.openeq.system-eq.aggregate"

final class SystemAudioEQEngine {
    private static let defaultScratchCapacity = 16_384

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
    private let analysisQueue = DispatchQueue(label: "com.openeq.system-audio-eq.analysis", qos: .utility)
    private var analysisTimer: DispatchSourceTimer?
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
    private var ioCallbackCount: Int64 = 0
    private var ioFramesWithSignal: Int64 = 0
    private var healthCheckWorkItem: DispatchWorkItem?
    private var deinterleaveScratch: [UnsafeMutablePointer<Float>?] = [nil, nil]
    private var deinterleaveCapacity: Int = 0
    private var analysisBuffers: [[UnsafeMutablePointer<Float>]] = []
    private var analysisBufferCapacity = 0
    private var analysisReadySlot: Int32 = -1
    private var analysisSlot = 0
    private var analysisWorkChannels = 0
    private var analysisWorkFrames = 0
    private var analysisWorkSampleRate: Double = 48000
    private var analysisAccumulatedFrames = 0
    private var analysisAccumulationChannels = 0
    private var droppedAnalysisBuffers: Int64 = 0
    private var tapSignalPublicationPending: Int32 = 0
    private var safetyTripPublicationPending: Int32 = 0
    private var tapTarget: ProcessTapTarget = .systemExcludingSelf
    private var preferredPhysicalOutputUID: String?
    private lazy var defaultOutputListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.handleDefaultOutputChanged()
    }

    init() {
        prepareScratch(capacity: Self.defaultScratchCapacity)
        prepareAnalysisBuffers(capacity: 1024)

        let timer = DispatchSource.makeTimerSource(queue: analysisQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.drainRealtimePublications() }
        timer.resume()
        analysisTimer = timer
    }

    deinit {
        stopObservingDefaultOutput()
        stop()
        freeScratch()
        analysisTimer?.cancel()
        analysisTimer = nil
        analysisQueue.sync { }
        freeAnalysisBuffers()
    }

    func start(with preset: EQPreset) {
        start(with: preset, target: .systemExcludingSelf, preferredOutputUID: nil)
    }

    /// Starts process-tap EQ for a specific target (system-wide or per-app).
    func start(
        with preset: EQPreset,
        target: ProcessTapTarget,
        preferredOutputUID: String? = nil
    ) {
        guard #available(macOS 14.2, *) else {
            publishStatus(.failed("Requires macOS 14.2+"))
            return
        }
        stop()
        tapTarget = target
        preferredPhysicalOutputUID = preferredOutputUID
        do {
            // Ensure Screen/System Audio Recording is requested. Do NOT treat every
            // Core Audio "nope" as a permission failure — that blocks real diagnosis.
            try ensureScreenCaptureAccess()

            physicalOutputID = try resolvePhysicalOutputID(preferredUID: preferredOutputUID)
            // Never nest our own aggregate as the physical destination.
            if isOpenEQAggregate(physicalOutputID) {
                throw SystemAudioEQError.failed(
                    "System output is already OpenEQ. Stop System EQ or pick Speakers/Headphones in Sound settings."
                )
            }
            refreshPhysicalOutputMetadata()

            destroyStaleAggregateIfNeeded()
            try setupTap(target: target)
            ioQueue.sync {
                dspState.configure(preset, sampleRate: sampleRate)
                feedbackGuard.reset()
                safetyTripNotified = false
                didTripFeedbackProtection = false
                dspState.isEmergencyMuted = false
                ioCallbackCount = 0
                ioFramesWithSignal = 0
                droppedAnalysisBuffers = 0
                analysisReadySlot = -1
                tapSignalPublicationPending = 0
                safetyTripPublicationPending = 0
                analysisAccumulatedFrames = 0
                analysisAccumulationChannels = 0
            }
            isReceivingTapAudio = false
            try setupAggregateWithOutput()
            try startAggIO()
            // Aggregate becomes system default so tapped apps render into it.
            try setDefaultOutput(aggDeviceID)
            startObservingDefaultOutput()
            scheduleHealthCheck()
            isRunning = true
            latencyEstimate = estimateLatency()
            lastSetupDetail = "\(target.shortDescription) → \(physicalOutputName ?? "output") @ \(Int(sampleRate)) Hz"
            publishStatus(.running)
            logger.info("Process EQ started: \(lastSetupDetail ?? "")")
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
            droppedAnalysisBuffers = 0
            analysisReadySlot = -1
            tapSignalPublicationPending = 0
            safetyTripPublicationPending = 0
            analysisAccumulatedFrames = 0
            analysisAccumulationChannels = 0
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
    private func setupTap(target: ProcessTapTarget) throws {
        let desc: CATapDescription
        switch target {
        case .systemExcludingSelf:
            var exclude: [AudioObjectID] = []
            if let selfProcess = try? processObjectID(forPID: getpid()),
               selfProcess != kAudioObjectUnknown {
                exclude.append(selfProcess)
            }
            desc = CATapDescription(stereoGlobalTapButExcludeProcesses: exclude)
            desc.name = "OpenEQ System Audio"

        case .processes(let objectIDs):
            let valid = objectIDs.filter { $0 != kAudioObjectUnknown }
            guard !valid.isEmpty else {
                throw SystemAudioEQError.failed("No running app process to tap. Launch the app and try again.")
            }
            desc = CATapDescription(stereoMixdownOfProcesses: valid)
            desc.name = "OpenEQ App Tap"

        case .bundleIDs(let ids):
            let cleaned = ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !cleaned.isEmpty else {
                throw SystemAudioEQError.failed("No app bundle ID selected for the App source node.")
            }
            if #available(macOS 26.0, *) {
                // Prefer bundle IDs so taps survive app relaunch.
                desc = CATapDescription()
                desc.name = "OpenEQ App Tap"
                desc.bundleIDs = cleaned
                desc.isExclusive = false
                desc.isMixdown = true
                desc.isMono = false
                desc.isProcessRestoreEnabled = true
            } else {
                // Fall back to currently running process objects for those bundles.
                let resolved = cleaned.compactMap { bundleID -> AudioObjectID? in
                    resolveProcessObjectID(bundleID: bundleID)
                }
                guard !resolved.isEmpty else {
                    throw SystemAudioEQError.failed(
                        "App not running (or not audible yet). Open it and play audio, then Run again."
                    )
                }
                desc = CATapDescription(stereoMixdownOfProcesses: resolved)
                desc.name = "OpenEQ App Tap"
            }
        }

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
            "Tap ready target=\(target.shortDescription) uid=\(liveUID) rate=\(sampleRate) ch=\(channelCount)"
        )
    }

    private func resolvePhysicalOutputID(preferredUID: String?) throws -> AudioDeviceID {
        if let preferredUID, !preferredUID.isEmpty,
           let deviceID = try? deviceID(forUID: preferredUID),
           deviceID != kAudioObjectUnknown,
           !isOpenEQAggregate(deviceID) {
            return deviceID
        }
        return try getDefaultOutputDeviceID()
    }

    private func resolveProcessObjectID(bundleID: String) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else {
            return nil
        }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &ids
        ) == noErr else {
            return nil
        }

        for objectID in ids {
            guard let bid = try? processBundleID(objectID), bid == bundleID else { continue }
            return objectID
        }
        return nil
    }

    private func processBundleID(_ objectID: AudioObjectID) throws -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return nil }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<CFString?>.alignment
        )
        defer { raw.deallocate() }
        raw.initializeMemory(as: CFString?.self, repeating: nil, count: 1)
        status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, raw)
        guard status == noErr else { return nil }
        return raw.load(as: CFString?.self) as String?
    }

    private func deviceID(forUID uid: String) throws -> AudioDeviceID {
        guard let deviceID = existingDeviceID(forUID: uid) else {
            throw SystemAudioEQError.failed("Unknown output device UID")
        }
        return deviceID
    }

    private func existingDeviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var cfUID = uid as CFString
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPtr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                uidPtr,
                &size,
                &deviceID
            )
        }
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
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
        var err = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &newAggID)
        if err == kAudioHardwareIllegalOperationError {
            // Aggregate destruction is asynchronous. A fast stop/start can therefore
            // briefly leave the old UID reserved and make the next create return 'nope'.
            logger.warning("Aggregate create returned nope; cleaning the stable UID and retrying")
            destroyStaleAggregateIfNeeded()
            newAggID = AudioObjectID(kAudioObjectUnknown)
            err = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &newAggID)
        }
        guard err == noErr else {
            throw SystemAudioEQError.failed(
                "Create aggregate failed (\(err) / \(fourCC(err))). Select a physical output and retry."
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
        prepareScratch(capacity: max(Self.defaultScratchCapacity, bufferFrameSize(for: aggDeviceID)))
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
            let callbacks = OSAtomicAdd64Barrier(0, &self.ioCallbackCount)
            let signal = OSAtomicAdd64Barrier(0, &self.ioFramesWithSignal)
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
        OSAtomicIncrement64Barrier(&ioCallbackCount)
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
                OSAtomicIncrement64Barrier(&ioFramesWithSignal)
                OSAtomicCompareAndSwap32Barrier(0, 1, &tapSignalPublicationPending)
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

        enqueueAnalysis(outBuffers: outBuffers, nonInterleaved: outNonInterleaved)
    }

    private func enqueueAnalysis(
        outBuffers: UnsafeMutableAudioBufferListPointer,
        nonInterleaved: Bool
    ) {
        guard OSAtomicAdd32Barrier(0, &analysisReadySlot) == -1,
              let first = outBuffers.first,
              first.mData != nil else {
            OSAtomicIncrement64Barrier(&droppedAnalysisBuffers)
            return
        }
        let channels = min(2, nonInterleaved ? outBuffers.count : max(1, Int(first.mNumberChannels)))
        let frames = min(analysisBufferCapacity, Int(first.mDataByteSize) / (MemoryLayout<Float>.size * (nonInterleaved ? 1 : max(1, Int(first.mNumberChannels)))))
        guard frames > 0, analysisBufferCapacity > 0 else { return }

        if analysisAccumulationChannels != channels {
            analysisAccumulatedFrames = 0
            analysisAccumulationChannels = channels
        }

        let slot = analysisSlot
        let copyFrames = min(frames, analysisBufferCapacity - analysisAccumulatedFrames)
        guard copyFrames > 0 else { return }
        let offset = analysisAccumulatedFrames
        let buffers = analysisBuffers[slot]
        for channel in 0..<channels {
            guard let source = outBuffers[nonInterleaved ? channel : 0].mData else { continue }
            let destination = buffers[channel].advanced(by: offset)
            let input = source.assumingMemoryBound(to: Float.self)
            if nonInterleaved {
                memcpy(destination, input, copyFrames * MemoryLayout<Float>.size)
            } else {
                for frame in 0..<copyFrames { destination[frame] = input[frame * max(1, Int(first.mNumberChannels)) + channel] }
            }
        }

        analysisAccumulatedFrames += copyFrames
        guard analysisAccumulatedFrames >= analysisBufferCapacity else { return }

        analysisWorkChannels = channels
        analysisWorkFrames = analysisBufferCapacity
        analysisWorkSampleRate = sampleRate
        analysisSlot = (analysisSlot + 1) % 2
        analysisAccumulatedFrames = 0
        OSAtomicCompareAndSwap32Barrier(-1, Int32(slot), &analysisReadySlot)
    }

    private func drainRealtimePublications() {
        if OSAtomicCompareAndSwap32Barrier(1, 0, &tapSignalPublicationPending) {
            DispatchQueue.main.async { [weak self] in self?.isReceivingTapAudio = true }
        }
        if OSAtomicCompareAndSwap32Barrier(1, 0, &safetyTripPublicationPending) {
            logger.warning("Feedback protection tripped")
            DispatchQueue.main.async { [weak self] in
                self?.didTripFeedbackProtection = true
                self?.onSafetyTrip?()
            }
        }
        let readySlot = OSAtomicAdd32Barrier(0, &analysisReadySlot)
        let slot = OSAtomicCompareAndSwap32Barrier(readySlot, -1, &analysisReadySlot) ? Int(readySlot) : -1
        guard slot >= 0 else { return }
        processPendingAnalysis(slot: slot)
    }

    private func processPendingAnalysis(slot: Int) {
        let buffers = analysisBuffers[slot]
        let channels = analysisWorkChannels
        let frames = analysisWorkFrames
        let rate = analysisWorkSampleRate
        let result = analyzer.analyze(
            left: buffers[0],
            right: channels > 1 ? buffers[1] : nil,
            frameLength: frames,
            sampleRate: rate
        )
        if let result {
            DispatchQueue.main.async { [weak self] in self?.onAnalysis?(result) }
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

        guard ensureScratch(frames: frames, channels: channels) else {
            copyInterleaved(
                inData: inData,
                outData: outData,
                inChannels: inChannels,
                outChannels: outChannels,
                channels: channels,
                frames: frames
            )
            applyFeedbackGuard(outBuffers: outBuffers, nonInterleaved: false, frames: frames)
            return
        }
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

        guard ensureScratch(frames: n, channels: channels) else {
            copyNonInterleavedToInterleaved(
                inBuffers: inBuffers,
                outData: outData,
                outChannels: outChannels,
                channels: channels,
                frames: n
            )
            applyFeedbackGuard(outBuffers: outBuffers, nonInterleaved: false, frames: n)
            return
        }
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
                OSAtomicCompareAndSwap32Barrier(0, 1, &safetyTripPublicationPending)
            }
        }
    }

    private func silence(_ outBuffers: UnsafeMutableAudioBufferListPointer) {
        for buffer in outBuffers {
            guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
            memset(data, 0, Int(buffer.mDataByteSize))
        }
    }

    private func ensureScratch(frames: Int, channels: Int) -> Bool {
        guard frames > 0, frames <= deinterleaveCapacity else { return false }
        return (0..<min(channels, 2)).allSatisfy { deinterleaveScratch[$0] != nil }
    }

    private func prepareScratch(capacity: Int) {
        guard capacity > deinterleaveCapacity else { return }
        freeScratch()
        deinterleaveCapacity = capacity
        for channel in deinterleaveScratch.indices {
            deinterleaveScratch[channel] = .allocate(capacity: capacity)
        }
    }

    private func prepareAnalysisBuffers(capacity: Int) {
        analysisBufferCapacity = capacity
        analysisBuffers = (0..<2).map { _ in
            (0..<2).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: capacity) }
        }
    }

    private func freeAnalysisBuffers() {
        for slot in analysisBuffers { for buffer in slot { buffer.deallocate() } }
        analysisBuffers.removeAll()
        analysisBufferCapacity = 0
        analysisAccumulatedFrames = 0
        analysisAccumulationChannels = 0
    }

    private func bufferFrameSize(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var frameSize: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &frameSize
        )
        return status == noErr ? Int(frameSize) : 0
    }

    private func copyInterleaved(
        inData: UnsafeMutableRawPointer,
        outData: UnsafeMutableRawPointer,
        inChannels: Int,
        outChannels: Int,
        channels: Int,
        frames: Int
    ) {
        let source = inData.assumingMemoryBound(to: Float.self)
        let destination = outData.assumingMemoryBound(to: Float.self)
        for frame in 0..<frames {
            for channel in 0..<channels {
                destination[frame * outChannels + channel] = source[frame * inChannels + channel]
            }
        }
    }

    private func copyNonInterleavedToInterleaved(
        inBuffers: UnsafeMutableAudioBufferListPointer,
        outData: UnsafeMutableRawPointer,
        outChannels: Int,
        channels: Int,
        frames: Int
    ) {
        let destination = outData.assumingMemoryBound(to: Float.self)
        for channel in 0..<channels {
            guard let inputData = inBuffers[channel].mData else { continue }
            let source = inputData.assumingMemoryBound(to: Float.self)
            for frame in 0..<frames {
                destination[frame * outChannels + channel] = source[frame]
            }
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
        if let deviceID = existingDeviceID(forUID: kOpenEQAggregateUID) {
            if let defaultID = try? getDefaultOutputDeviceID(),
               defaultID == deviceID,
               physicalOutputID != kAudioObjectUnknown,
               physicalOutputID != deviceID {
                try? setDefaultOutput(physicalOutputID)
            }
            logger.info("Destroying stale OpenEQ aggregate \(deviceID)")
            destroyAggregateDeviceAndWait(deviceID)
        }
    }

    private func destroyAggregateDeviceAndWait(_ deviceID: AudioDeviceID) {
        guard deviceID != kAudioObjectUnknown else { return }
        let status = AudioHardwareDestroyAggregateDevice(deviceID)
        guard status == noErr else {
            logger.warning("Destroy aggregate \(deviceID) failed (\(status) / \(fourCC(status)))")
            return
        }

        // Core Audio documents destruction as asynchronous. Wait briefly for the
        // stable UID to disappear before allowing another aggregate to be created.
        for _ in 0..<20 {
            guard let currentID = existingDeviceID(forUID: kOpenEQAggregateUID), currentID == deviceID else {
                return
            }
            usleep(25_000)
        }
        logger.warning("Aggregate \(deviceID) is still being removed by Core Audio")
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
            destroyAggregateDeviceAndWait(aggDeviceID)
            aggDeviceID = kAudioObjectUnknown
        }
    }

    private func destroyTap() {
        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
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
