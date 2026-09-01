//
//  AppAudioProcessManager.swift
//  OpenEQ
//
//  Created by Ozan
//

import AppKit
import CoreAudio
import Foundation
import Observation

/// Observes active audio-producing applications in macOS using Core Audio & NSWorkspace.
@MainActor
@Observable
final class AppAudioProcessManager {
    var channels: [AppAudioChannel] = []
    
    private var timer: Timer?
    private let logger = AppLogger(category: "AppAudioProcessManager")
    
    init() {
        refreshActiveAudioProcesses()
        startPeriodicPolling()
    }
    
    func startPeriodicPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshActiveAudioProcesses()
            }
        }
    }

    func stopPeriodicPolling() {
        timer?.invalidate()
        timer = nil
    }
    
    func refreshActiveAudioProcesses() {
        // Enumerate running applications with a bundle identifier (excluding OpenEQ itself)
        let myPID = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != myPID else { return false }
            // Filter standard GUI apps and background helpers
            return app.activationPolicy == .regular || app.bundleIdentifier != nil
        }
        
        var updatedChannels: [AppAudioChannel] = []
        
        for app in runningApps {
            let bundleID = app.bundleIdentifier
            let pid = app.processIdentifier
            let appName = app.localizedName ?? (bundleID ?? "App \(pid)")
            let icon = app.icon
            let channelID = bundleID ?? "pid:\(pid)"
            
            // Retain existing channel settings if already configured
            if let existing = channels.first(where: { $0.id == channelID || $0.pid == pid }) {
                updatedChannels.append(existing)
            } else {
                // Known common audio apps or newly launched apps
                let newChannel = AppAudioChannel(
                    id: channelID,
                    pid: pid,
                    bundleID: bundleID,
                    appName: appName,
                    appIcon: icon
                )
                updatedChannels.append(newChannel)
            }
        }
        
        // Prioritize common media & audio apps at top
        let priorityApps = ["spotify", "music", "chrome", "brave", "safari", "discord", "iina", "vlc", "zoom", "slack", "telegram", "arc"]
        updatedChannels.sort { lhs, rhs in
            let lName = lhs.appName.lowercased()
            let rName = rhs.appName.lowercased()
            let lMatch = priorityApps.firstIndex(where: { lName.contains($0) }) ?? 999
            let rMatch = priorityApps.firstIndex(where: { rName.contains($0) }) ?? 999
            if lMatch != rMatch {
                return lMatch < rMatch
            }
            return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
        }
        
        self.channels = updatedChannels
    }
    
    func updateVolume(_ volume: Double, for channelID: String) {
        if let idx = channels.firstIndex(where: { $0.id == channelID }) {
            channels[idx].volume = volume
        }
    }
    
    func toggleMute(for channelID: String) {
        if let idx = channels.firstIndex(where: { $0.id == channelID }) {
            channels[idx].isMuted.toggle()
        }
    }
    
    func toggleEQExpanded(for channelID: String) {
        if let idx = channels.firstIndex(where: { $0.id == channelID }) {
            channels[idx].isEQExpanded.toggle()
        }
    }
    
    func toggleEQEnabled(for channelID: String) {
        if let idx = channels.firstIndex(where: { $0.id == channelID }) {
            channels[idx].isEQEnabled.toggle()
        }
    }
    
    func setTargetOutputUIDs(_ uids: Set<String>, isMulti: Bool, for channelID: String) {
        if let idx = channels.firstIndex(where: { $0.id == channelID }) {
            channels[idx].targetOutputUIDs = uids
            channels[idx].isMultiOutputEnabled = isMulti
        }
    }
    
    func setBandGain(gain: Float, at bandIndex: Int, for channelID: String) {
        guard let idx = channels.firstIndex(where: { $0.id == channelID }),
              bandIndex >= 0, bandIndex < channels[idx].eqBands.count else { return }
        channels[idx].eqBands[bandIndex].gain = gain
    }
    
    func applyPreset(named presetName: String, bands: [EQBand], for channelID: String) {
        guard let idx = channels.firstIndex(where: { $0.id == channelID }) else { return }
        channels[idx].selectedPresetName = presetName
        channels[idx].eqBands = bands
    }
}
