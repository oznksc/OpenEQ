//
//  AppOutputRoutingPopover.swift
//  OpenEQ
//
//  Created by Ozan
//

import SwiftUI

struct AppOutputRoutingPopover: View {
    @Binding var channel: AppAudioChannel
    let availableOutputs: [AudioDevice]
    var onRoutingChanged: (() -> Void)?
    
    @State private var routingTab: RoutingTab = .single
    
    enum RoutingTab: String, CaseIterable {
        case single = "Single"
        case multi = "Multi"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Segmented Picker
            Picker("", selection: $routingTab) {
                ForEach(RoutingTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)
            
            // Devices List
            VStack(alignment: .leading, spacing: 4) {
                ForEach(availableOutputs) { device in
                    let deviceKey = device.uid ?? "id:\(device.id)"
                    let isSelected = channel.targetOutputUIDs.contains(deviceKey)
                    
                    Button {
                        handleDeviceSelection(deviceKey: deviceKey)
                    } label: {
                        HStack(spacing: 8) {
                            if routingTab == .multi {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                            } else {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                            }
                            
                            Image(systemName: deviceIconName(device))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            
                            Text(device.name)
                                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .lineLimit(1)
                            
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(
                            isSelected ? Color.blue.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .frame(width: 220)
        .onAppear {
            if channel.isMultiOutputEnabled {
                routingTab = .multi
            }
        }
        .onChange(of: routingTab) { _, newTab in
            channel.isMultiOutputEnabled = (newTab == .multi)
            if newTab == .single && channel.targetOutputUIDs.count > 1 {
                if let first = channel.targetOutputUIDs.first {
                    channel.targetOutputUIDs = [first]
                }
            }
            onRoutingChanged?()
        }
    }
    
    private func handleDeviceSelection(deviceKey: String) {
        if routingTab == .single {
            channel.targetOutputUIDs = [deviceKey]
        } else {
            if channel.targetOutputUIDs.contains(deviceKey) {
                channel.targetOutputUIDs.remove(deviceKey)
            } else {
                channel.targetOutputUIDs.insert(deviceKey)
            }
        }
        onRoutingChanged?()
    }
    
    private func deviceIconName(_ device: AudioDevice) -> String {
        let name = device.name.lowercased()
        if name.contains("airpod") { return "airpods" }
        if name.contains("headphone") || name.contains("wh-1000") || name.contains("acton") { return "headphones" }
        if name.contains("speaker") { return "hifispeaker.fill" }
        if name.contains("blackhole") { return "waveform.badge.magnifyingglass" }
        return "speaker.wave.2.fill"
    }
}
