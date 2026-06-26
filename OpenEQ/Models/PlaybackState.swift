//
//  PlaybackState.swift
//  OpenEQ
//
//  Created by Gökmen on 26.06.2026.
//

import Foundation

/// Represents the current operational state of the media playback or capturing pipeline.
enum PlaybackState: Equatable, Codable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case failed(message: String)

    /// Human-readable title mapping for interface components.
    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .loading:
            return "Loading"
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
