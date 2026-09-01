//
//  MenuBarAudioHubView.swift
//  OpenEQ
//
//  Created by Ozan
//

import SwiftUI
import AppKit

struct MenuBarAudioHubView: View {
    @Bindable var viewModel: OpenEQViewModel
    @Environment(\.openWindow) private var openWindow
    
    @State private var activeRoutingPopoverChannelID: String?
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                headerBar
                
                // Input Devices Section
                if !viewModel.availableInputDevices.isEmpty {
                    inputSection
                    Divider()
                        .background(Color.white.opacity(0.1))
                }
                
                // Output Devices Section
                if !viewModel.availableOutputDevices.isEmpty {
                    outputSection
                    Divider()
                        .background(Color.white.opacity(0.1))
                }
                
                // Global Multi-Output Toggle
                globalMultiOutputToggle
                
                // Apps / Per-App Volume & EQ Section
                appsSection
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                footerActions
            }
            .padding(16)
        }
        .frame(width: 360, height: 520)
        .onReceive(NotificationCenter.default.publisher(for: .showMainWindow)) { _ in
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    
    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(Color.blue)
                .font(.system(size: 14))
            
            Text(viewModel.activePhysicalOutputName ?? viewModel.selectedSystemOutputDevice?.name ?? "Default Output")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            
            Button {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 2)
    }
    
    // MARK: - Input Section
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.availableInputDevices) { device in
                deviceRow(device: device, isInput: true)
            }
        }
    }
    
    // MARK: - Output Section
    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.availableOutputDevices) { device in
                deviceRow(device: device, isInput: false)
            }
        }
    }
    
    private func deviceRow(device: AudioDevice, isInput: Bool) -> some View {
        let isDefault = isInput ? device.isDefaultInput : (device.id == (viewModel.selectedSystemOutputDevice?.id ?? 0) || device.isDefaultOutput)
        let isMuted = device.isMuted ?? false
        let currentVol = device.volume ?? 0.75
        
        return HStack(spacing: 10) {
            // Device Icon
            Image(systemName: deviceIconName(device))
                .font(.system(size: 14))
                .foregroundStyle(isDefault ? Color.blue : Color.secondary)
                .frame(width: 20)
            
            // Device Name
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 12, weight: isDefault ? .semibold : .regular))
                    .foregroundStyle(isDefault ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 110, alignment: .leading)
            
            // Mute / Speaker Icon
            Button {
                viewModel.systemAudioManager.setDeviceMute(!isMuted, for: device)
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : (isInput ? "mic.fill" : "speaker.wave.2.fill"))
                    .font(.system(size: 11))
                    .foregroundStyle(isMuted ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            
            // Volume Slider
            Slider(
                value: Binding(
                    get: { Double(currentVol) },
                    set: { newVal in
                        viewModel.systemAudioManager.setDeviceVolume(Float(newVal), for: device)
                    }
                ),
                in: 0.0...1.0
            )
            .tint(Color.blue)
            
            // Percentage Label
            Text("\(Int(currentVol * 100))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 35, alignment: .trailing)
        }
    }
    
    // MARK: - Global Multi-Output Toggle
    private var globalMultiOutputToggle: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    .font(.system(size: 13))
                    .foregroundStyle(viewModel.isGlobalMultiOutputEnabled ? Color.blue : Color.secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Global Multi-Output")
                        .font(.system(size: 12, weight: .medium))
                    Text("Mirror all audio to multiple devices")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $viewModel.isGlobalMultiOutputEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Apps Section
    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("APPS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Toggle("Per-app Volume", isOn: $viewModel.isPerAppVolumeEnabled)
                    .font(.system(size: 11))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            
            if viewModel.isPerAppVolumeEnabled {
                VStack(spacing: 8) {
                    ForEach(viewModel.appAudioProcessManager.channels.prefix(6)) { channel in
                        appChannelCard(channel: channel)
                    }
                }
            }
        }
    }
    
    private func appChannelCard(channel: AppAudioChannel) -> some View {
        let isBoosted = channel.volume > 1.0
        let percent = Int(channel.volume * 100)
        
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                // App Icon
                if let icon = channel.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                        .cornerRadius(4)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                
                // App Name
                Text(channel.appName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .frame(width: 80, alignment: .leading)
                
                // Mute Button
                Button {
                    viewModel.appAudioProcessManager.toggleMute(for: channel.id)
                } label: {
                    Image(systemName: channel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(channel.isMuted ? Color.red : Color.secondary)
                }
                .buttonStyle(.plain)
                
                // Volume Slider (supports up to 200% boost)
                Slider(
                    value: Binding(
                        get: { channel.volume },
                        set: { val in viewModel.appAudioProcessManager.updateVolume(val, for: channel.id) }
                    ),
                    in: 0.0...2.0
                )
                .tint(isBoosted ? Color.orange : Color.blue)
                
                // Percentage Text with Boost Highlight
                Text("\(percent)%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(isBoosted ? Color.orange : Color.secondary)
                    .frame(width: 38, alignment: .trailing)
                
                // Routing Picker Popover Button
                Button {
                    activeRoutingPopoverChannelID = (activeRoutingPopoverChannelID == channel.id ? nil : channel.id)
                } label: {
                    Image(systemName: channel.isMultiOutputEnabled ? "headphones" : "speaker.wave.2")
                        .font(.system(size: 11))
                        .foregroundStyle(channel.isMultiOutputEnabled ? Color.blue : Color.secondary)
                }
                .buttonStyle(.plain)
                .popover(
                    isPresented: Binding(
                        get: { activeRoutingPopoverChannelID == channel.id },
                        set: { if !$0 { activeRoutingPopoverChannelID = nil } }
                    ),
                    arrowEdge: .trailing
                ) {
                    AppOutputRoutingPopover(
                        channel: Binding(
                            get: { channel },
                            set: { updated in viewModel.appAudioProcessManager.updateChannel(updated) }
                        ),
                        availableOutputs: viewModel.availableOutputDevices
                    )
                }
                
                // Inline EQ Toggle Button
                Button {
                    viewModel.appAudioProcessManager.toggleEQExpanded(for: channel.id)
                } label: {
                    Image(systemName: channel.isEQExpanded ? "xmark" : "slider.vertical.3")
                        .font(.system(size: 11))
                        .foregroundStyle(channel.isEQExpanded ? Color.primary : (channel.isEQEnabled ? Color.blue : Color.secondary))
                }
                .buttonStyle(.plain)
            }
            
            // Expanded Inline 10-Band EQ if opened
            if channel.isEQExpanded {
                AppInlineEQView(
                    channel: Binding(
                        get: { channel },
                        set: { updated in viewModel.appAudioProcessManager.updateChannel(updated) }
                    )
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(8)
        .background(Color.white.opacity(channel.isEQExpanded ? 0.08 : 0.03), in: RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Footer Actions
    private var footerActions: some View {
        HStack {
            Button("Settings") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            
            Spacer()
            
            Button("Quit") {
                viewModel.shutdown()
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
    
    private func deviceIconName(_ device: AudioDevice) -> String {
        let name = device.name.lowercased()
        if device.isInput { return "mic.fill" }
        if name.contains("airpod") { return "airpods" }
        if name.contains("headphone") || name.contains("wh-1000") || name.contains("acton") { return "headphones" }
        if name.contains("speaker") { return "laptopcomputer" }
        if name.contains("display") || name.contains("dell") || name.contains("kg272") { return "display" }
        if name.contains("blackhole") { return "waveform.badge.magnifyingglass" }
        return "speaker.wave.2.fill"
    }
}
