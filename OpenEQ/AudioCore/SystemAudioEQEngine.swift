import AVFoundation
import CoreAudio
import Accelerate

let kOpenEQSysObj = AudioObjectID(kAudioObjectSystemObject)

@MainActor
final class SystemAudioEQEngine {
    private(set) var status: SystemAudioStatus = .stopped
    private(set) var latencyEstimate: TimeInterval?

    var onAnalysis: ((SpectrumAnalysis) -> Void)?
    var onStatusChanged: ((SystemAudioStatus) -> Void)?

    private let analyzer = SpectrumAnalyzer()
    private let logger = AppLogger(category: "SystemAudioEQ")

    private let ioQueue = DispatchQueue(label: "com.openeq.system-audio-eq.io", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var aggIOProcID: AudioDeviceIOProcID?
    private var isRunning = false
    private var sampleRate: Double = 48000
    private var lastEQPreset: EQPreset?
    private var ringBuffer: RingBuffer?

    func start(with preset: EQPreset) {
        guard #available(macOS 14.2, *) else {
            onStatusChanged?(.failed("Requires macOS 14.2+"))
            return
        }
        stop()
        lastEQPreset = preset
        do {
            try setupTap()
            try setupAggregateWithOutput()
            try startAggregateIO()
            isRunning = true
            latencyEstimate = Double(1024) / sampleRate * 3
            status = .running
            onStatusChanged?(.running)
            logger.info("System-wide EQ started")
        } catch {
            cleanup()
            let msg = (error as? SystemAudioEQError)?.localizedDescription ?? error.localizedDescription
            status = .failed(msg)
            onStatusChanged?(status)
            logger.error("Start failed: \(msg)")
        }
    }

    func stop() {
        guard isRunning else { return }
        stopAggregateIO()
        destroyAggregate()
        destroyTap()
        isRunning = false
        status = .stopped
        latencyEstimate = nil
        ringBuffer = nil
        onStatusChanged?(.stopped)
        logger.info("System-wide EQ stopped")
    }

    func updateEQ(_ preset: EQPreset) { lastEQPreset = preset }
    func setBypassed(_ bypassed: Bool) {}

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
        let tapUID = try getTapUID()
        let outputID = try getDefaultOutputDeviceID()
        let outputUID = try getDeviceUID(outputID)
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
        aggregateDeviceID = newAggID

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var list: CFArray? = [tapUID] as CFArray
        err = withUnsafeMutablePointer(to: &list) { ptr in
            AudioObjectSetPropertyData(aggregateDeviceID, &addr, UInt32(0), nil, UInt32(MemoryLayout<CFArray>.size), ptr)
        }
        guard err == noErr else { throw SystemAudioEQError.failed("Set tap list: \(err)") }

        logger.info("Aggregate device created with output + tap")
    }

    private func startAggregateIO() throws {
        let ringCapacity = Int(sampleRate * 0.3) * 2
        ringBuffer = RingBuffer(capacity: ringCapacity)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        var procID: AudioDeviceIOProcID?
        let err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, ioQueue) {
            [weak self] (inNow: UnsafePointer<AudioTimeStamp>,
                         inInputData: UnsafePointer<AudioBufferList>?,
                         inInputTime: UnsafePointer<AudioTimeStamp>?,
                         outOutputData: UnsafeMutablePointer<AudioBufferList>?,
                         inOutputTime: UnsafePointer<AudioTimeStamp>?) in
            guard let inData = inInputData, let outData = outOutputData else { return }
            self?.handleIO(inData: inData, outData: outData, format: format)
        }
        guard err == noErr, let procID else {
            throw SystemAudioEQError.failed("Create IOProc: \(err)")
        }
        aggIOProcID = procID
        AudioDeviceStart(aggregateDeviceID, procID)
    }

    // MARK: - IO

    private func handleIO(inData: UnsafePointer<AudioBufferList>, outData: UnsafeMutablePointer<AudioBufferList>, format: AVAudioFormat) {
        let inBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
        let outBuffers = UnsafeMutableAudioBufferListPointer(outData)

        guard let inFirst = inBuffers.first, let inBufData = inFirst.mData else { return }
        let frameLength = Int(inFirst.mDataByteSize) / MemoryLayout<Float>.size
        guard frameLength > 0 else { return }

        let preset = lastEQPreset ?? EQPreset.flatPreset()
        let channelCount = Int(format.channelCount)

        var processedData = Data(count: Int(inFirst.mDataByteSize))
        processedData.withUnsafeMutableBytes { destPtr in
            guard let dest = destPtr.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
            let src = inBufData.assumingMemoryBound(to: Float.self)
            memcpy(dest, src, Int(inFirst.mDataByteSize))
            applyEQ(dest, frames: frameLength / channelCount, channels: channelCount, preset: preset)
            if let outFirst = outBuffers.first, let outDataPtr = outFirst.mData {
                memcpy(outDataPtr, dest, Int(inFirst.mDataByteSize))
            }
        }

        if let analysis = analyzer.analyze(bufferList: inData, frameLength: frameLength, sampleRate: sampleRate) {
            DispatchQueue.main.async { [weak self] in self?.onAnalysis?(analysis) }
        }
    }

    // MARK: - EQ

    private func applyEQ(_ s: UnsafeMutablePointer<Float>, frames: Int, channels: Int, preset: EQPreset) {
        let gGain = dbToLinear(preset.preamp)
        let gains: [Float] = preset.bands.map { dbToLinear($0.gain) }
        let sr = Float(sampleRate)
        let bc = min(gains.count, 31)
        for ch in 0..<channels {
            let cd = s.advanced(by: ch * frames)
            if abs(gGain - 1.0) > 0.01 { var g = gGain; vDSP_vsmul(cd, 1, &g, cd, 1, vDSP_Length(frames)) }
            for b in 0..<bc {
                let gl = gains[b]
                guard abs(gl - 1.0) > 0.01 else { continue }
                let w0 = 2 * Float.pi * kOpenEQBands[b] / sr
                guard w0 < Float.pi else { continue }
                let Q: Float = 1.414; let a = sin(w0) / (2 * Q); let A = sqrt(gl)
                let (b0,b1,b2,a0,a1,a2): (Float,Float,Float,Float,Float,Float)
                if gl >= 1.0 { b0=1+a*A; b1 = -2*cos(w0); b2=1-a*A; a0=1+a/A; a1 = -2*cos(w0); a2=1-a/A }
                else { b0=1+a/A; b1 = -2*cos(w0); b2=1-a/A; a0=1+a*A; a1 = -2*cos(w0); a2=1-a/A }
                let ai=1/a0; let f0=b0*ai,f1=b1*ai,f2=b2*ai; let g0=a1*ai,g1=a2*ai
                var x1:Float=0,x2:Float=0,y1:Float=0,y2:Float=0
                for i in 0..<frames { let x0=cd[i]; let y0=f0*x0+f1*x1+f2*x2-g0*y1-g1*y2; cd[i]=y0; x2=x1;x1=x0;y2=y1;y1=y0 }
            }
        }
    }

    private func dbToLinear(_ d: Float) -> Float { pow(10, d / 20) }

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

    // MARK: - Cleanup

    private func stopAggregateIO() {
        if let p = aggIOProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, p); AudioDeviceDestroyIOProcID(aggregateDeviceID, p)
        }
        aggIOProcID = nil
    }

    private func destroyAggregate() {
        if aggregateDeviceID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateDeviceID); aggregateDeviceID = kAudioObjectUnknown }
    }

    private func destroyTap() {
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = kAudioObjectUnknown }
    }

    private func cleanup() { stopAggregateIO(); destroyAggregate(); destroyTap(); ringBuffer = nil }
}

private class RingBuffer {
    private var buf: Data
    private let cap: Int
    private var w = 0, r = 0
    private let lock = NSLock()
    init(capacity: Int) { cap = max(capacity, 4096); buf = Data(count: cap) }
    func write(data: Data, frameLength: Int) {
        lock.lock(); defer { lock.unlock() }
        let bytes = min(data.count, cap)
        data.withUnsafeBytes { src in guard let s=src.baseAddress else { return }
            buf.withUnsafeMutableBytes { dst in guard let d=dst.baseAddress else { return }
                let sp = cap - w
                if bytes <= sp { memcpy(d+w, s, bytes) } else { memcpy(d+w, s, sp); memcpy(d, s+sp, bytes-sp) }
            }
        }
        w = (w + bytes) % cap; if w == r { r = (r + bytes) % cap }
    }
    func read(into dest: UnsafeMutableRawPointer, maxBytes: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        let avail = (w - r + cap) % cap; let toR = min(maxBytes, avail)
        guard toR > 0 else { return 0 }
        buf.withUnsafeBytes { src in guard let s=src.baseAddress else { return }
            let sp = cap - r
            if toR <= sp { memcpy(dest, s+r, toR) } else { memcpy(dest, s+r, sp); memcpy(dest+sp, s, toR-sp) }
        }
        r = (r + toR) % cap; return toR
    }
}

enum SystemAudioEQError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self { case .failed(let m): return "System EQ: \(m)" }
    }
}

private let kOpenEQBands: [Float] = [20,25,31.5,40,50,63,80,100,125,160,200,250,315,400,500,630,800,1000,1250,1600,2000,2500,3150,4000,5000,6300,8000,10000,12500,16000,20000]
