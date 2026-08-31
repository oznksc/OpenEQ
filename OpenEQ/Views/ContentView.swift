import SwiftUI

struct ContentView: View {
    let viewModel: OpenEQViewModel

    var body: some View {
        MainWindowView(viewModel: viewModel)
            .onReceive(NotificationCenter.default.publisher(for: .openAudioFile)) { _ in
                viewModel.openAudioFile()
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetEQ)) { _ in
                viewModel.resetEQ()
            }
            .frame(width: OpenEQTheme.minWindowWidth, height: OpenEQTheme.minWindowHeight)
    }
}

#Preview {
    ContentView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .frame(width: 1100, height: 700)
}
