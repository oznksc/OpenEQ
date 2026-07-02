//
//  CoreAudioTapManager.swift
//  OpenEQ
//
//  Created by Codex on 27.06.2026.
//

import CoreAudio
import Foundation

final class CoreAudioTapManager {
    var onAnalysis: ((SpectrumAnalysis) -> Void)?
    var onStatusChanged: ((SystemAudioStatus) -> Void)?

    private let analyzer = SpectrumAnalyzer()
    private let logger = AppLogger(category: "CoreAudioTap")
    private let ioQueue = DispatchQueue(label: "com.openeq.core-audio-tap.io")
    private let propertyQueue = DispatchQueue(label: "com.openeq.core-audio-tap.properties")

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var aggregateDeviceUID: String?
    private var sampleRate: Double = 48_000
    private var isRunning = false

    private lazy var runningListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.handleRunningStateChanged()
    }

    deinit {
        stop()
    }

    func start() {
        guard #available(macOS 14.2, *) else {
            onStatusChanged?(.failed("System audio capture requires macOS 14.2 or later."))
            return
        }

        do {
            stop()
            try createTapAndAggregateDevice()
            try startAggregateInputMonitoring()
            isRunning = true
            onStatusChanged?(.running)
        } catch let error as CoreAudioTapError {
            cleanupTapResources()
            logger.error(error.localizedDescription)
            onStatusChanged?(error.status)
        } catch {
            cleanupTapResources()
            logger.error(error.localizedDescription)
            onStatusChanged?(.failed(error.localizedDescription))
        }
    }

    func stop() {
        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown), let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }

        removeRunningListener()
        cleanupTapResources()
        isRunning = false
        onStatusChanged?(.stopped)
    }

    @available(macOS 14.2, *)
    private func createTapAndAggregateDevice() throws {
        // Core Audio Taps can capture outgoing system/process audio without changing system output routing.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "OpenEQ System Audio Monitor"
        description.isPrivate = true

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr else {
            throw CoreAudioTapError.tapCreationFailed(status)
        }

        tapID = newTapID
        sampleRate = try tapFormat(tapID: tapID).mSampleRate

        let tapUID = try tapUID(tapID: tapID)
        let aggregateUID = "com.openeq.system-audio-monitor.\(UUID().uuidString)"
        aggregateDeviceUID = aggregateUID

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "OpenEQ System Audio Monitor",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true
        ]

        var newAggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateDeviceID)
        guard status == noErr else {
            throw CoreAudioTapError.tapCreationFailed(status)
        }

        aggregateDeviceID = newAggregateDeviceID
        try setTapList(tapUID: tapUID, aggregateDeviceID: aggregateDeviceID)
    }

    private func startAggregateInputMonitoring() throws {
        guard aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) else {
            throw CoreAudioTapError.tapCreationFailed(kAudioHardwareBadObjectError)
        }

        addRunningListener()

        var createdIOProcID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &createdIOProcID,
            aggregateDeviceID,
            ioQueue
        ) { [weak self] _, inputData, _, _, _ in
            self?.handleInputBuffer(inputData)
        }

        guard status == noErr, let createdIOProcID else {
            throw CoreAudioTapError.tapCreationFailed(status)
        }

        ioProcID = createdIOProcID
        let startStatus = AudioDeviceStart(aggregateDeviceID, createdIOProcID)
        guard startStatus == noErr else {
            throw CoreAudioTapError.tapCreationFailed(startStatus)
        }
    }

    private func handleInputBuffer(_ inputData: UnsafePointer<AudioBufferList>) {
        guard isRunning else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        guard let firstBuffer = buffers.first, firstBuffer.mData != nil else {
            return
        }

        let channelCount = max(1, Int(firstBuffer.mNumberChannels))
        let frameLength = Int(firstBuffer.mDataByteSize) / (MemoryLayout<Float>.size * channelCount)
        guard frameLength > 0 else {
            return
        }

        guard let analysis = analyzer.analyze(
            bufferList: inputData,
            frameLength: frameLength,
            sampleRate: sampleRate
        ) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onAnalysis?(analysis)
        }
    }

    private func handleRunningStateChanged() {
        guard isRunning, aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) else {
            return
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isDeviceRunning: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            aggregateDeviceID,
            &address,
            0,
            nil,
            &dataSize,
            &isDeviceRunning
        )

        guard status == noErr, isDeviceRunning == 0 else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onStatusChanged?(.failed("System audio tap stopped unexpectedly."))
        }
    }

    @available(macOS 14.2, *)
    private func tapUID(tapID: AudioObjectID) throws -> CFString {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let value = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        value.initialize(to: nil)
        defer {
            value.deinitialize(count: 1)
            value.deallocate()
        }

        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &dataSize, value)
        guard status == noErr, let tapUID = value.pointee else {
            throw CoreAudioTapError.tapCreationFailed(status)
        }

        return tapUID
    }

    @available(macOS 14.2, *)
    private func tapFormat(tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &dataSize, &format)
        guard status == noErr else {
            throw CoreAudioTapError.tapCreationFailed(status)
        }

        return format
    }

    @available(macOS 14.2, *)
    private func setTapList(tapUID: CFString, aggregateDeviceID: AudioObjectID) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var tapList = [tapUID] as CFArray
        let dataSize = UInt32(MemoryLayout<CFArray>.size)
        let status = withUnsafePointer(to: &tapList) { pointer in
            AudioObjectSetPropertyData(
                aggregateDeviceID,
                &address,
                0,
                nil,
                dataSize,
                pointer
            )
        }

        guard status == noErr else {
            throw CoreAudioTapError.tapCreationFailed(status)
        }
    }

    private func addRunningListener() {
        guard aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) else {
            return
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            aggregateDeviceID,
            &address,
            propertyQueue,
            runningListener
        )
    }

    private func removeRunningListener() {
        guard aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) else {
            return
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            aggregateDeviceID,
            &address,
            propertyQueue,
            runningListener
        )
    }

    private func cleanupTapResources() {
        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }

        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }

        aggregateDeviceUID = nil
    }
}

enum CoreAudioTapError: LocalizedError {
    case unsupportedOS
    case permissionDenied
    case tapCreationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "System audio capture requires macOS 14.2 or later."
        case .permissionDenied:
            return "System audio capture permission was denied."
        case .tapCreationFailed(let status):
            return "System audio tap creation failed. OSStatus \(status)."
        }
    }

    var status: SystemAudioStatus {
        switch self {
        case .unsupportedOS:
            return .failed("System audio capture requires macOS 14.2 or later.")
        case .permissionDenied:
            return .permissionRequired
        case .tapCreationFailed(let status):
            return .failed("System audio tap creation failed. OSStatus \(status).")
        }
    }
}
