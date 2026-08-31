import AppKit
import AudioToolbox
import Foundation
import Observation

struct AudioProcessInfo: Identifiable, Equatable {
    var id: UInt32 { objectID }
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    let name: String
    let icon: NSImage?
    let isRunningOutput: Bool
    let isRunningInput: Bool
}

@MainActor
@Observable
final class AudioProcessEnumerator {
    private(set) var processes: [AudioProcessInfo] = []
    private let logger = AppLogger(category: "AudioProcessEnumerator")
    private var timer: Timer?

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        do {
            processes = try enumerate().sorted {
                if $0.isRunningOutput != $1.isRunningOutput { return $0.isRunningOutput && !$1.isRunningOutput }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch {
            logger.warning("Process enumeration failed: \(error.localizedDescription)")
        }
    }

    private func enumerate() throws -> [AudioProcessInfo] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
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
        guard status == noErr, dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &ids
        )
        guard status == noErr else { return [] }

        let selfPID = getpid()
        return ids.compactMap { objectID -> AudioProcessInfo? in
            guard let pid = try? int32Property(objectID, kAudioProcessPropertyPID) else { return nil }
            if pid == selfPID { return nil }

            let bundleID = try? stringProperty(objectID, kAudioProcessPropertyBundleID)
            let runningOut = (try? uint32Property(objectID, kAudioProcessPropertyIsRunningOutput)) ?? 0
            let runningIn = (try? uint32Property(objectID, kAudioProcessPropertyIsRunningInput)) ?? 0

            let app = NSRunningApplication(processIdentifier: pid)
            let name = app?.localizedName
                ?? bundleID?.components(separatedBy: ".").last
                ?? "PID \(pid)"
            let icon = app?.icon

            return AudioProcessInfo(
                objectID: objectID,
                pid: pid,
                bundleID: bundleID,
                name: name,
                icon: icon,
                isRunningOutput: runningOut != 0,
                isRunningInput: runningIn != 0
            )
        }
    }

    private func int32Property(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> pid_t {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr else {
            throw EnumeratorError.propertyFailed(selector, status)
        }
        return value
    }

    private func uint32Property(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr else {
            throw EnumeratorError.propertyFailed(selector, status)
        }
        return value
    }

    private func stringProperty(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return nil }

        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<CFString?>.alignment)
        defer { raw.deallocate() }
        raw.initializeMemory(as: CFString?.self, repeating: nil, count: 1)
        status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, raw)
        guard status == noErr else { return nil }
        let cf = raw.load(as: CFString?.self)
        return cf as String?
    }

    private enum EnumeratorError: Error {
        case propertyFailed(AudioObjectPropertySelector, OSStatus)
    }
}
