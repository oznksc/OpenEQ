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
            .frame(minWidth: 800, minHeight: 520)
    }
}

#Preview {
    ContentView(
        viewModel: OpenEQViewModel(audioEngineController: AudioEngineController())
    )
    .frame(width: 1100, height: 700)
}
