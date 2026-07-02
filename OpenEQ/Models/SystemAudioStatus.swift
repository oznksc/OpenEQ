//
//  SystemAudioStatus.swift
//  OpenEQ
//
//  Created by Ozan
//

import Foundation

enum SystemAudioStatus: Equatable, Codable {
    case unavailable
    case permissionRequired
    case ready
    case running
    case stopped
    case failed(String)

    var title: String {
        switch self {
        case .unavailable:
            return "Unavailable"
        case .permissionRequired:
            return "Permission Required"
        case .ready:
            return "Ready"
        case .running:
            return "Running"
        case .stopped:
            return "Stopped"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }
}
