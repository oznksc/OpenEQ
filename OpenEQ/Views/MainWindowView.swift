//
//  MainWindowView.swift
//  OpenEQ
//
//  Created by Gökmen on 26.06.2026.
//

import SwiftUI

struct MainWindowView: View {
    let viewModel: OpenEQViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Main Top Header Bar
            header
            
            Divider()

            // Center Content Split
            HStack(spacing: 0) {
                // Main Panel (Visualizer & Faders)
                VStack(spacing: 0) {
                    SpectrumView(levels: viewModel.spectrumLevels)
                    
                    Divider()
                    
                    EqualizerView(viewModel: viewModel)
                }
                
                Divider()

                // Sidebar Presets
                PresetPanelView(viewModel: viewModel)
                    .frame(width: 250)
            }

            Divider()

            // Bottom Player Dock
            PlayerControlsView(viewModel: viewModel)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 16) {
            // Logo Mark
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 38, height: 38)
                    .shadow(color: Color.blue.opacity(0.3), radius: 4)
                
                Image(systemName: "slider.vertical.3")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }
            
            // App Title and Subheading
            VStack(alignment: .leading, spacing: 2) {
                Text("OpenEQ")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)

                Text("Open-source macOS System-Wide Equalizer Core")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // State Pill Indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.5), radius: 3)
                
                Text(viewModel.playbackState.title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
    
    // MARK: - Dynamic Status Color Selection
    private var statusColor: Color {
        switch viewModel.playbackState {
        case .playing:
            return .green
        case .paused:
            return .orange
        case .stopped:
            return .gray
        case .idle:
            return .gray
        case .loading:
            return .blue
        case .failed:
            return .red
        }
    }
}

#Preview {
    MainWindowView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .frame(width: 1100, height: 720)
}
