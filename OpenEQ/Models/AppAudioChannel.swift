//
//  AppAudioChannel.swift
//  OpenEQ
//
//  Created by Ozan
//

import AppKit
import Foundation

/// Represents a running application's audio stream channel in OpenEQ's mixer.
struct AppAudioChannel: Identifiable, Equatable {
    let id: String // Bundle ID or PID String
    let pid: pid_t
    let bundleID: String?
    let appName: String
    let appIcon: NSImage?
    
    var volume: Double = 1.0 // 0.0 ... 2.0 (up to 200% boost)
    var isMuted: Bool = false
    var pan: Float = 0.0 // -1.0 (Left) ... 1.0 (Right)
    
    var targetOutputUIDs: Set<String> = []
    var isMultiOutputEnabled: Bool = false
    
    var isEQExpanded: Bool = false
    var isEQEnabled: Bool = false
    var selectedPresetName: String = "Flat"
    var eqBands: [EQBand] = EQBand.defaultBands()
    
    var leftVU: Float = 0.0
    var rightVU: Float = 0.0
    
    static func == (lhs: AppAudioChannel, rhs: AppAudioChannel) -> Bool {
        lhs.id == rhs.id &&
        lhs.volume == rhs.volume &&
        lhs.isMuted == rhs.isMuted &&
        lhs.pan == rhs.pan &&
        lhs.targetOutputUIDs == rhs.targetOutputUIDs &&
        lhs.isMultiOutputEnabled == rhs.isMultiOutputEnabled &&
        lhs.isEQExpanded == rhs.isEQExpanded &&
        lhs.isEQEnabled == rhs.isEQEnabled &&
        lhs.selectedPresetName == rhs.selectedPresetName &&
        lhs.eqBands == rhs.eqBands &&
        lhs.leftVU == rhs.leftVU &&
        lhs.rightVU == rhs.rightVU
    }
}
