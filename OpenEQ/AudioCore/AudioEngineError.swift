//
//  AudioEngineError.swift
//  OpenEQ
//
//  Created by Codex on 26.06.2026.
//

import Foundation

enum AudioEngineError: LocalizedError {
    case unsupportedFile(URL)
    case engineFailedToStart(String)
    case fileCouldNotBeRead(URL)
    case audioGraphConnectionFailed(String)
    case playbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile(let url):
            return "Unsupported audio file: \(url.lastPathComponent)"
        case .engineFailedToStart(let reason):
            return "Audio engine failed to start: \(reason)"
        case .fileCouldNotBeRead(let url):
            return "Audio file could not be read: \(url.lastPathComponent)"
        case .audioGraphConnectionFailed(let reason):
            return "Audio graph connection failed: \(reason)"
        case .playbackFailed(let reason):
            return "Playback failed: \(reason)"
        }
    }
}
