import AppKit
import UniformTypeIdentifiers

extension OpenEQViewModel {
    // MARK: - Playback Controls

    func play() {
        errorMessage = nil
        audioEngineController.play()

        if case .failed(let message) = audioEngineController.playbackState {
            errorMessage = message
        }
    }

    func pause() {
        audioEngineController.pause()
    }

    func stop() {
        audioEngineController.stop()
    }

    func seek(to time: TimeInterval) {
        audioEngineController.seek(to: time)
    }

    func togglePlayback() {
        switch playbackState {
        case .playing:
            pause()
        case .paused, .stopped, .idle, .ready, .failed:
            play()
        case .preparing:
            break
        }
    }

    // MARK: - File Management

    func openAudioFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowsOtherFileTypes = true
        panel.allowedContentTypes = [
            .audio,
            .mp3,
            .wav,
            .mpeg4Audio,
            .coreAudioFormat,
            UTType(filenameExtension: "aiff")
        ].compactMap { $0 }

        if panel.runModal() == .OK, let url = panel.url {
            loadAudioFile(url: url)
        }
    }

    func loadAudioFile(url: URL) {
        do {
            errorMessage = nil
            try audioEngineController.prepare(url: url)
            selectedFileURL = url
            selectedFileName = url.lastPathComponent
        } catch {
            errorMessage = "Failed to load audio: \(error.localizedDescription)"
            selectedFileURL = nil
            selectedFileName = "No File Selected"
        }
    }
}
