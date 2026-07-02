//
//  SystemAudioMode.swift
//  OpenEQ
//
//  Created by Ozan
//

import Foundation

enum SystemAudioMode: String, CaseIterable, Codable, Identifiable {
    case disabled
    case monitorOnly
    case externalLoopback
    case nativeTapExperimental

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .monitorOnly:
            return "Monitor Only"
        case .externalLoopback:
            return "External Loopback"
        case .nativeTapExperimental:
            return "Native Tap Experimental"
        }
    }
}
