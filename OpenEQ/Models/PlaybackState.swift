//
//  PlaybackState.swift
//  OpenEQ
//
//  Created by Ozan
//

import Foundation

/// Represents the current operational state of the audio engine.
enum AudioEngineState: Equatable, Codable {
    case idle
    case preparing
    case ready
    case playing
    case paused
    case stopped
    case failed(String)

    /// Human-readable title mapping for interface components.
    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .preparing:
            return "Preparing"
        case .ready:
            return "Ready"
        case .playing:
            return "Playing"
        case .paused:
            return "Paused"
        case .stopped:
            return "Stopped"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }
}

typealias PlaybackState = AudioEngineState
