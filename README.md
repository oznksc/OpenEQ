<p align="center">
  <img src="openeq-app-icon.png" alt="OpenEQ Logo" width="200" />
</p>

# OpenEQ

An open-source macOS audio equalizer application built with **SwiftUI**, **AVFoundation**, and **Accelerate (vDSP)**. OpenEQ provides a lightweight, performant desktop dashboard designed for audio adjustments, custom graphic equalization curves, and real-time audio analysis.

## Features

### Equalizer
- **10-Band & 31-Band Graphic Equalizer**: Switchable between standard 10-band and professional 31-band ISO frequency intervals.
- **5-Band Parametric EQ**: Configurable frequency, gain, Q factor, and filter types (parametric, low/high shelf, low/high pass).
- **Independent Preamp Control**: Fine-tune volume levels with standard decibel mapping limits (`-24.0` to `+24.0` dB).
- **EQ Bypass**: Instant toggle to compare processed vs unprocessed audio.
- **Real-Time FFT Spectrum Analyzer**: 64-band spectrum visualization using GPU-accelerated Canvas rendering and vDSP Fourier Transform.

### Audio Playback
- Local audio file playback (MP3, WAV, AAC, CAF, AIFF) with EQ applied.
- Playback controls: play, pause, stop, seek, volume, mute.
- **Volume Booster**: Boost volume up to 200% beyond system limits.

### Presets
- 5 built-in presets: Flat, Bass Boost, Vocal Clarity, Warm, Bright.
- Save/delete custom user presets.
- Import/export presets as JSON files.

### System Audio (Beta)
- **Monitor Only**: Inspect system audio without processing.
- **External Loopback**: Route system audio through EQ using a virtual audio device (e.g., BlackHole).
- Real-time spectrum analysis of system audio.

### Menu Bar Integration
- Quick EQ toggle from the menu bar.
- Preset switching and playback controls without opening the main window.

### Keyboard Shortcuts
| Shortcut | Action |
|----------|--------|
| `⌘O` | Open Audio File |
| `⌘R` | Reset EQ |
| `⌘B` | Toggle EQ Bypass |
| `⌘⇧V` | Toggle Volume Boost |
| `Space` | Play/Pause |

## Architecture Overview
OpenEQ is structured around clean, modular boundaries:
1. **SwiftUI Layer**: Responsive user interface including custom faders and GPU-buffered spectrum canvas drawing.
2. **ViewModel Layer (MVVM)**: Observes playback states and manages UI interactions, data bindings, and user preferences persistence.
3. **AudioCore Layer**: Interfaces with Apple's `AVAudioEngine`, establishing node graphs, parametric filters, volume multipliers, and output taps.
4. **vDSP Spectrum Analyzer**: Executes windowing and Forward Discrete Fourier Transforms on captured buffer frames.
5. **Services**: PresetStore (JSON-based preset persistence).

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
```bash
xcodebuild -scheme OpenEQ -destination 'platform=macOS' build
```

## Contributing
We welcome contributions! Please review our [CONTRIBUTING.md](CONTRIBUTING.md) guide to learn about coding guidelines, git workflows, and pull request procedures.

## License
OpenEQ is open-source and licensed under the permissive **MIT License**. See the [LICENSE](LICENSE) file for complete details.
