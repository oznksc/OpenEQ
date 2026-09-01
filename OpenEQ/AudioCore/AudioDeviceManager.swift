//
//  AudioDeviceManager.swift
//  OpenEQ
//
//  Created by Ozan
//

import AudioToolbox
import CoreAudio
import Foundation

final class AudioDeviceManager {
    private(set) var devices: [AudioDevice] = []
    private(set) var lastError: AudioDeviceManagerError?

    var onDevicesChanged: (() -> Void)?

    private let logger = AppLogger(category: "AudioDeviceManager")
    private let listenerQueue = DispatchQueue(label: "com.openeq.audio-device-listener")
    private var isObservingDeviceChanges = false
    private lazy var devicesChangedBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.refreshDevices()
        self?.onDevicesChanged?()
    }

    init() {
        refreshDevices()
        startObservingDeviceChanges()
    }

    deinit {
        stopObservingDeviceChanges()
    }

    func refreshDevices() {
        do {
            devices = try enumerateDevices()
            lastError = nil

            if getInputDevices().isEmpty {
                lastError = .noInputDevices
            } else if getOutputDevices().isEmpty {
                lastError = .noOutputDevices
            }
        } catch let error as AudioDeviceManagerError {
            lastError = error
            devices = []
            logger.error(error.localizedDescription)
        } catch {
            lastError = .propertyReadFailed("Unknown Core Audio error: \(error.localizedDescription)")
            devices = []
            logger.error(error.localizedDescription)
        }
    }

    func getInputDevices() -> [AudioDevice] {
        devices.filter(\.isInput)
    }

    func getOutputDevices() -> [AudioDevice] {
        devices.filter(\.isOutput)
    }

    func getDefaultInputDevice() -> AudioDevice? {
        devices.first(where: \.isDefaultInput)
    }

    func getDefaultOutputDevice() -> AudioDevice? {
        devices.first(where: \.isDefaultOutput)
    }

    func findDevice(named keyword: String) -> AudioDevice? {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty else {
            return nil
        }

        return devices.first { device in
            device.name.localizedCaseInsensitiveContains(trimmedKeyword)
        }
    }

    func detectBlackHoleDevice() -> AudioDevice? {
        let blackHoleNames = ["BlackHole", "BlackHole 2ch", "BlackHole 16ch"]

        return devices.first { device in
            blackHoleNames.contains { keyword in
                device.name.localizedCaseInsensitiveContains(keyword)
            }
        }
    }

    func isKnownDevice(_ device: AudioDevice?) -> Bool {
        guard let device else {
            return false
        }

        return devices.contains { $0.id == device.id }
    }

    private func enumerateDevices() throws -> [AudioDevice] {
        let defaultInputID = try defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
        let defaultOutputID = try defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)

        return try deviceIDs().compactMap { deviceID in
            let inputChannels = try channelCount(for: deviceID, scope: kAudioDevicePropertyScopeInput)
            let outputChannels = try channelCount(for: deviceID, scope: kAudioDevicePropertyScopeOutput)
            let isInput = inputChannels > 0
            let isOutput = outputChannels > 0

            guard isInput || isOutput else {
                return nil
            }

            let scope: AudioObjectPropertyScope = isOutput ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput
            let volume = getVolume(for: deviceID, scope: scope)
            let isMuted = getMute(for: deviceID, scope: scope)

            return AudioDevice(
                id: deviceID,
                uid: try stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID),
                name: try stringProperty(deviceID, selector: kAudioObjectPropertyName) ?? "Unknown Device",
                manufacturer: try stringProperty(deviceID, selector: kAudioObjectPropertyManufacturer),
                isInput: isInput,
                isOutput: isOutput,
                isDefaultInput: deviceID == defaultInputID,
                isDefaultOutput: deviceID == defaultOutputID,
                sampleRate: try nominalSampleRate(for: deviceID),
                channelCount: max(inputChannels, outputChannels),
                volume: volume,
                isMuted: isMuted
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDefaultInput != rhs.isDefaultInput {
                return lhs.isDefaultInput
            }

            if lhs.isDefaultOutput != rhs.isDefaultOutput {
                return lhs.isDefaultOutput
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func deviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            throw AudioDeviceManagerError.coreAudioPropertyReadFailed("device list size", status)
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &devices
        )

        guard status == noErr else {
            throw AudioDeviceManagerError.coreAudioPropertyReadFailed("device list", status)
        }

        return devices
    }

    private func defaultDeviceID(selector: AudioObjectPropertySelector) throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else {
            throw AudioDeviceManagerError.coreAudioPropertyReadFailed("default device", status)
        }

        return deviceID
    }

    private func stringProperty(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) throws -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
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
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, value)

        if status == kAudioHardwareUnknownPropertyError {
            return nil
        }

        guard status == noErr else {
            throw AudioDeviceManagerError.coreAudioPropertyReadFailed("string property \(selector)", status)
        }

        return value.pointee as String?
    }

    private func nominalSampleRate(for deviceID: AudioDeviceID) throws -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate = Float64(0)
        var dataSize = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &sampleRate)

        if status == kAudioHardwareUnknownPropertyError {
            return nil
        }

        guard status == noErr else {
            throw AudioDeviceManagerError.coreAudioPropertyReadFailed("nominal sample rate", status)
        }

        return sampleRate
    }

    func getVolume(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var volume: Float32 = 0.0
        var dataSize = UInt32(MemoryLayout<Float32>.size)
        var status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &volume)
        
        if status != noErr {
            // Try Master/Channel 1 if Main failed
            address.mElement = 1
            status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &volume)
        }
        
        return status == noErr ? Float(volume) : nil
    }

    func setVolume(_ volume: Float, for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var vol: Float32 = max(0.0, min(1.0, Float32(volume)))
        let dataSize = UInt32(MemoryLayout<Float32>.size)
        var status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, dataSize, &vol)
        
        if status != noErr {
            // Also try channel 1 and channel 2
            address.mElement = 1
            _ = AudioObjectSetPropertyData(deviceID, &address, 0, nil, dataSize, &vol)
            address.mElement = 2
            _ = AudioObjectSetPropertyData(deviceID, &address, 0, nil, dataSize, &vol)
        }
        
        refreshDevices()
    }

    func getMute(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var isMuted: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &isMuted)
        
        return status == noErr ? (isMuted == 1) : nil
    }

    func setMute(_ isMuted: Bool, for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var val: UInt32 = isMuted ? 1 : 0
        let dataSize = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectSetPropertyData(deviceID, &address, 0, nil, dataSize, &val)
        
        refreshDevices()
    }

    private func channelCount(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) throws -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)

        if status == kAudioHardwareUnknownPropertyError || dataSize == 0 {
            return 0
        }

        guard status == noErr else {
            throw AudioDeviceManagerError.coreAudioPropertyReadFailed("stream configuration size", status)
        }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            rawBuffer.deallocate()
        }

        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, rawBuffer)

        guard status == noErr else {
            throw AudioDeviceManagerError.coreAudioPropertyReadFailed("stream configuration", status)
        }

        let audioBufferList = rawBuffer.bindMemory(to: AudioBufferList.self, capacity: 1)
        return UnsafeMutableAudioBufferListPointer(audioBufferList).reduce(0) { total, buffer in
            total + Int(buffer.mNumberChannels)
        }
    }

    private func startObservingDeviceChanges() {
        guard !isObservingDeviceChanges else {
            return
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerQueue,
            devicesChangedBlock
        )

        if status == noErr {
            isObservingDeviceChanges = true
        } else {
            logger.warning("Could not listen for audio device changes: OSStatus \(status).")
        }
    }

    private func stopObservingDeviceChanges() {
        guard isObservingDeviceChanges else {
            return
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerQueue,
            devicesChangedBlock
        )
        isObservingDeviceChanges = false
    }
}

enum AudioDeviceManagerError: LocalizedError, Equatable {
    case coreAudioPropertyReadFailed(String, OSStatus)
    case noInputDevices
    case noOutputDevices
    case deviceDisappeared(String)
    case propertyReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .coreAudioPropertyReadFailed(let property, let status):
            return "Core Audio property read failed for \(property). OSStatus \(status)."
        case .noInputDevices:
            return "No audio input devices are available."
        case .noOutputDevices:
            return "No audio output devices are available."
        case .deviceDisappeared(let name):
            return "Audio device disappeared: \(name)."
        case .propertyReadFailed(let message):
            return message
        }
    }
}
