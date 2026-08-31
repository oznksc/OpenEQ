import CoreAudio
import Foundation

/// Describes which processes a Core Audio process tap should capture.
enum ProcessTapTarget: Equatable {
    /// All system audio except OpenEQ itself (classic System EQ).
    case systemExcludingSelf
    /// Explicit process object IDs (from `kAudioHardwarePropertyProcessObjectList`).
    case processes([AudioObjectID])
    /// Bundle identifiers — preferred on macOS 26+ with process restore.
    case bundleIDs([String])

    var shortDescription: String {
        switch self {
        case .systemExcludingSelf:
            return "system"
        case .processes(let ids):
            return "processes(\(ids.count))"
        case .bundleIDs(let ids):
            return ids.joined(separator: ",")
        }
    }
}
