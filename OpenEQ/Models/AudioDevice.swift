//
//  AudioDevice.swift
//  OpenEQ
//
//  Created by Ozan
//

import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    /// Persistent Core Audio device UID (stable across reboots; preferred for profiles).
    let uid: String?
    let name: String
    let manufacturer: String?
    let isInput: Bool
    let isOutput: Bool
    let isDefaultInput: Bool
    let isDefaultOutput: Bool
    let sampleRate: Double?
    let channelCount: Int?

    var isBlackHole: Bool {
        name.localizedCaseInsensitiveContains("BlackHole")
    }

    /// Stable key for device-specific EQ profiles.
    var profileKey: String {
        uid ?? "id:\(id)"
    }
}
