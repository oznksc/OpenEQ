# OpenEQ

An open-source macOS audio equalizer application built with **SwiftUI**, **AVFoundation**, and **Accelerate (vDSP)**. OpenEQ provides a lightweight, performant desktop dashboard designed for audio adjustments, custom graphic equalization curves, and real-time audio analysis.

## Key Features (MVP)
* **10-Band Graphic Equalizer**: Precise audio frequency controls at standard intervals: `32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16k` Hz.
* **Independent Preamp Control**: Fine-tune volume levels with standard decibel mapping limits (`-24.0` to `+24.0` dB).
* **Real-Time FFT Spectrum Analyzer**: Live visual feedback utilizing GPU-accelerated canvas rendering and vDSP Fourier Transform calculations (64 frequency bands).
* **Presets Management**: Load factory audio templates (*Flat, Bass Boost, Vocal Clarity, Warm, Bright*) or save/delete custom user profiles.
* **Import & Export**: Backup or share presets via native macOS JSON file handlers.
* **Mac App Polish**: Integrated menu bar bindings, Keyboard Shortcuts (⌘O: Open Audio, Space: Play/Pause, ⌘R: Reset EQ), dark-mode styling, and physical peak decay indicators.

## Architecture Overview
OpenEQ is structured around clean, modular boundaries:
1. **SwiftUI Layer**: Responsive user interface including custom metal-cap faders and GPU-buffered spectrum canvas drawing.
2. **ViewModel Layer (MVVM)**: Observes playback states and manages UI interactions, data bindings, and user preferences persistence.
3. **AudioCore Layer**: Interfaces with Apple's `AVAudioEngine`, establishing node graphs, parametric filters, volume multipliers, and output taps.
4. **vDSP Spectrum Analyzer**: Executes windowing and Forward Discrete Fourier Transforms on captured buffer frames.
5. **PresetStore Service**: Reads and writes configurations in JSON format under Application Support.

For detailed design specifications, see [docs/architecture.md](docs/architecture.md).

## Build Instructions
### Prerequisites
- macOS 14.0 or newer
- Xcode 15.0 or newer (or command line build utilities)

### Building via Xcode
1. Open the directory project file: `OpenEQ.xcodeproj` in Xcode.
2. Select target scheme **OpenEQ** and set build destination to **My Mac**.
3. Press `Cmd + B` to build or `Cmd + R` to run.

### Building via Terminal
Run the following build command from the repository root:
```bash
xcodebuild -scheme OpenEQ -destination 'platform=macOS' build
```

## Contributing
We welcome contributions! Please review our [CONTRIBUTING.md](CONTRIBUTING.md) guide to learn about coding guidelines, git workflows, and pull request procedures.

## License
OpenEQ is open-source and licensed under the permissive **MIT License**. See the [LICENSE](LICENSE) file for complete details.
