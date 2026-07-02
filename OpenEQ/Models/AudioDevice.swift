//
//  AudioDevice.swift
//  OpenEQ
//
//  Created by Codex on 27.06.2026.
//

import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
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
}
