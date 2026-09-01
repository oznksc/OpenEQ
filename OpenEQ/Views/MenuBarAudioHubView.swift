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
                
                if !viewModel.availableInputDevices.isEmpty {
                    inputSection
                    Divider()
                        .background(Color.white.opacity(0.1))
                }
                
                if !viewModel.availableOutputDevices.isEmpty {
                    outputSection
                    Divider()
                        .background(Color.white.opacity(0.1))
                }
                
                systemAudioSection

                globalMultiOutputToggle
                
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
            .help("Open main window")
            
            Button {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open settings")
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
            Image(systemName: deviceIconName(device))
                .font(.system(size: 14))
                .foregroundStyle(isDefault ? Color.blue : Color.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 12, weight: isDefault ? .semibold : .regular))
                    .foregroundStyle(isDefault ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 110, alignment: .leading)
            
            Button {
                viewModel.setMenuBarDeviceMute(!isMuted, for: device)
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : (isInput ? "mic.fill" : "speaker.wave.2.fill"))
                    .font(.system(size: 11))
                    .foregroundStyle(isMuted ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isMuted ? "Unmute \(device.name)" : "Mute \(device.name)")
            
            Slider(
                value: Binding(
                    get: { Double(currentVol) },
                    set: { newVal in
                        viewModel.setMenuBarDeviceVolume(Float(newVal), for: device)
                    }
                ),
                in: 0.0...1.0
            )
            .tint(Color.blue)
            
            Text("\(Int(currentVol * 100))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 35, alignment: .trailing)
        }
    }

    private var systemAudioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            compactSpectrumStrip

            HStack(spacing: 8) {
                Button {
                    viewModel.toggleSystemEQOneClick()
                } label: {
                    Label(viewModel.isSystemEQActive || viewModel.isExternalLoopbackActive ? "Stop" : "System EQ", systemImage: viewModel.isSystemEQActive || viewModel.isExternalLoopbackActive ? "stop.fill" : "waveform")
                        .font(.system(size: 11, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isSystemEQActive || viewModel.isExternalLoopbackActive ? .red : .blue)

                Button {
                    viewModel.setEnabled(!viewModel.isEnabled)
                } label: {
                    Image(systemName: viewModel.isEnabled ? "power.circle.fill" : "power.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.borderless)
                .help(viewModel.isEnabled ? "Bypass EQ" : "Enable EQ")

                Button {
                    viewModel.refreshSystemAudioDevices()
                    viewModel.refreshAudioProcesses()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Refresh devices and apps")
            }

            if viewModel.didTripFeedbackProtection {
                Button {
                    viewModel.clearFeedbackProtectionTrip()
                } label: {
                    Label("Resume Audio", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            if viewModel.systemAudioStatus == .permissionRequired {
                Button {
                    viewModel.retrySystemEQAfterPermission()
                } label: {
                    Label("Open Permission", systemImage: "lock.shield")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var compactSpectrumStrip: some View {
        MenuBarSpectrumStrip(
            levels: viewModel.spectrumLevels,
            isActive: viewModel.isSystemEQActive || viewModel.isExternalLoopbackActive,
            isClipping: viewModel.isClipping || viewModel.systemIsClipping
        )
        .frame(height: 38)
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
            Toggle("", isOn: Binding(
                get: { viewModel.isGlobalMultiOutputEnabled },
                set: { viewModel.setGlobalMultiOutputEnabled($0) }
            ))
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
                        appChannelCard(channel: channelBinding(for: channel))
                    }
                }
            } else {
                Text("Per-app controls are paused.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func channelBinding(for channel: AppAudioChannel) -> Binding<AppAudioChannel> {
        Binding(
            get: {
                viewModel.appAudioProcessManager.channels.first(where: { $0.id == channel.id }) ?? channel
            },
            set: { updated in
                viewModel.appAudioProcessManager.updateChannel(updated)
            }
        )
    }

    private func appChannelCard(channel: Binding<AppAudioChannel>) -> some View {
        let channelValue = channel.wrappedValue
        let isBoosted = channelValue.volume > 1.0
        let percent = Int(channelValue.volume * 100)
        
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                if let icon = channelValue.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                        .cornerRadius(4)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                
                Text(channelValue.appName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .frame(width: 80, alignment: .leading)
                
                Button {
                    viewModel.appAudioProcessManager.toggleMute(for: channelValue.id)
                } label: {
                    Image(systemName: channelValue.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(channelValue.isMuted ? Color.red : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(channelValue.isMuted ? "Unmute \(channelValue.appName)" : "Mute \(channelValue.appName)")
                
                Slider(
                    value: Binding(
                        get: { channel.wrappedValue.volume },
                        set: { val in viewModel.appAudioProcessManager.updateVolume(val, for: channelValue.id) }
                    ),
                    in: 0.0...2.0
                )
                .tint(isBoosted ? Color.orange : Color.blue)
                
                Text("\(percent)%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(isBoosted ? Color.orange : Color.secondary)
                    .frame(width: 38, alignment: .trailing)
                
                Button {
                    activeRoutingPopoverChannelID = (activeRoutingPopoverChannelID == channelValue.id ? nil : channelValue.id)
                } label: {
                    Image(systemName: channelValue.isMultiOutputEnabled ? "headphones" : "speaker.wave.2")
                        .font(.system(size: 11))
                        .foregroundStyle(channelValue.isMultiOutputEnabled ? Color.blue : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Output routing")
                .popover(
                    isPresented: Binding(
                        get: { activeRoutingPopoverChannelID == channelValue.id },
                        set: { if !$0 { activeRoutingPopoverChannelID = nil } }
                    ),
                    arrowEdge: .trailing
                ) {
                    AppOutputRoutingPopover(
                        channel: channel,
                        availableOutputs: viewModel.availableOutputDevices
                    )
                }
                
                Button {
                    viewModel.appAudioProcessManager.toggleEQExpanded(for: channelValue.id)
                } label: {
                    Image(systemName: channelValue.isEQExpanded ? "xmark" : "slider.vertical.3")
                        .font(.system(size: 11))
                        .foregroundStyle(channelValue.isEQExpanded ? Color.primary : (channelValue.isEQEnabled ? Color.blue : Color.secondary))
                }
                .buttonStyle(.plain)
                .help(channelValue.isEQExpanded ? "Close EQ" : "Open EQ")
            }
            
            if channelValue.isEQExpanded {
                AppInlineEQView(
                    channel: channel,
                    onGainChange: { index, gain in
                        viewModel.appAudioProcessManager.setBandGain(gain: gain, at: index, for: channelValue.id)
                    },
                    onPresetChange: { name, bands in
                        viewModel.appAudioProcessManager.applyPreset(named: name, bands: bands, for: channelValue.id)
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(8)
        .background(Color.white.opacity(channelValue.isEQExpanded ? 0.08 : 0.03), in: RoundedRectangle(cornerRadius: 8))
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

private struct MenuBarSpectrumStrip: View {
    let levels: SpectrumLevels
    let isActive: Bool
    let isClipping: Bool

    var body: some View {
        GeometryReader { geometry in
            let bars = Array(stride(from: 0, to: levels.count, by: 2))
            let spacing: CGFloat = 2
            let barWidth = max(2, (geometry.size.width - CGFloat(bars.count - 1) * spacing) / CGFloat(bars.count))

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, index in
                    let level = CGFloat(max(0.03, min(1, levels[index])))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(barColor(level: level))
                        .frame(width: barWidth, height: max(3, geometry.size.height * level))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .opacity(isActive ? 1 : 0.34)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.black.opacity(0.28))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isClipping ? Color.red.opacity(0.9) : Color.white.opacity(0.12), lineWidth: 1)
            }
        }
    }

    private func barColor(level: CGFloat) -> Color {
        if isClipping {
            return .red
        }
        if level > 0.78 {
            return .orange
        }
        return isActive ? OpenEQTheme.accentCyan : .secondary.opacity(0.7)
    }
}
