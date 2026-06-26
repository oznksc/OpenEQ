//
//  ContentView.swift
//  OpenEQ
//
//  Created by Gökmen on 26.06.2026.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = OpenEQViewModel(
        audioEngineController: AudioEngineController()
    )

    var body: some View {
        MainWindowView(viewModel: viewModel)
            .onReceive(NotificationCenter.default.publisher(for: .openAudioFile)) { _ in
                viewModel.openAudioFile()
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetEQ)) { _ in
                viewModel.resetEQ()
            }
    }
}

#Preview {
    ContentView()
        .frame(width: 1100, height: 720)
}
